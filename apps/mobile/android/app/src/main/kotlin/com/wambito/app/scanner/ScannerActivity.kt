package com.wambito.app.scanner

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.Camera
import androidx.camera.core.CameraState
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The camera, full screen, for one QR (`wambito/scanner` `scan`, [ScannerChannel]). CameraX shows the
 * preview and hands every frame's luminance plane to [decodeQr] (ZXing core), keeping only the
 * latest frame while one is being read. The first `wambito://pair?` text it reads goes back as
 * [RESULT_OK] with [EXTRA_TEXT]; any other QR is ignored, as the web's scanner ignores it. The close
 * button and Back answer [RESULT_CANCELED]; a camera that cannot start answers [RESULT_FAILED].
 * The stream stops when the activity does.
 *
 * Not exported: only the app's own [ScannerChannel] starts it. The camera permission is asked by
 * that channel before this opens, never at start.
 */
class ScannerActivity : ComponentActivity() {
    private lateinit var analysisExecutor: ExecutorService
    private var provider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private val answered = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        analysisExecutor = Executors.newSingleThreadExecutor()
        val preview = TextureView(this)
        val density = resources.displayMetrics.density
        val hint = TextView(this).apply {
            text = getString(com.wambito.app.R.string.scanner_hint)
            setTextColor(Color.WHITE)
            setBackgroundColor(0x99000000.toInt())
            textSize = 16f
            gravity = Gravity.CENTER
            val pad = (16 * density).toInt()
            setPadding(pad, pad, pad, pad)
        }
        val close = Button(this).apply {
            text = getString(com.wambito.app.R.string.scanner_close)
            setTypeface(typeface, Typeface.BOLD)
            setOnClickListener { cancel() }
        }
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(
                preview,
                FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
            )
            addView(
                hint,
                FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    .apply { gravity = Gravity.TOP },
            )
            val margin = (24 * density).toInt()
            addView(
                close,
                FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    .apply {
                        gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                        bottomMargin = margin
                    },
            )
        }
        watchTexture(preview)
        setContentView(root)
        // The bars' insets: the hint and the button stay clear of the status and navigation bars.
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }
        start(preview)
    }

    private fun start(preview: TextureView) {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener(
            {
                try {
                    val cameras = future.get()
                    provider = cameras
                    val view = Preview.Builder().build().also {
                        it.setSurfaceProvider(ContextCompat.getMainExecutor(this)) { request -> show(preview, request) }
                    }
                    val frames = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { it.setAnalyzer(analysisExecutor, ::analyze) }
                    analysis = frames
                    cameras.unbindAll()
                    val camera: Camera =
                        cameras.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, view, frames)
                    // A camera that cannot open or stops (in use by another app, disabled by policy):
                    // answered as failed, so Dart can say so and leave the typed code.
                    camera.cameraInfo.cameraState.observe(this) { state ->
                        if (state.error != null) answer(RESULT_FAILED, null)
                    }
                } catch (_: Exception) {
                    answer(RESULT_FAILED, null)
                }
            },
            ContextCompat.getMainExecutor(this),
        )
    }

    /** The last request's buffer and orientation, kept to apply again when the view's size changes. */
    private var bufferSize: android.util.Size? = null
    private var transformInfo: SurfaceRequest.TransformationInfo? = null

    /** What the person's screen is turned by, as 0, 90, 180 or 270. */
    @Suppress("DEPRECATION")
    private fun displayRotationDegrees(): Int = when (windowManager.defaultDisplay.rotation) {
        Surface.ROTATION_90 -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }

    /** Sets the preview's matrix from the last request, when the view has a size. */
    private fun applyTransform(view: TextureView) {
        val size = bufferSize ?: return
        val info = transformInfo ?: return
        if (view.width == 0 || view.height == 0) return
        val transform = previewTransform(
            view.width.toFloat(),
            view.height.toFloat(),
            size.width,
            size.height,
            info.rotationDegrees,
            info.hasCameraTransform(),
            displayRotationDegrees(),
        )
        view.setTransform(Matrix().apply { setValues(transform.values()) })
    }

    /** The surface CameraX is drawing on, and a texture the view let go while it still was. */
    private var surfaceInUse: Surface? = null
    private var textureLost: SurfaceTexture? = null

    /** A request waiting for the view's texture to exist. */
    private var waiting: ((SurfaceTexture) -> Unit)? = null

    /** The view's texture callbacks, set once: it is ours to release (see [onTextureDestroyed]). */
    private fun watchTexture(view: TextureView) {
        view.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                waiting?.invoke(texture)
                waiting = null
            }

            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit

            // False: the view does not release the texture, we do, once CameraX is done with its Surface.
            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                if (surfaceInUse == null) texture.release() else textureLost = texture
                return false
            }

            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
        }
        // The first layout comes after the first request: the matrix is applied again then.
        view.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyTransform(view) }
    }

    /**
     * CameraX's preview on [view], with no preview library: the surface comes from the texture, and the
     * picture is turned upright and scaled to fill the screen, cropping the overflow
     * ([previewTransform]). The analysis does not depend on it. A second request (CameraX asks again
     * after a rebind) lets go of the first one's Surface before the new one is given.
     */
    private fun show(view: TextureView, request: SurfaceRequest) {
        val executor = ContextCompat.getMainExecutor(this)
        bufferSize = request.resolution
        fun provide(texture: SurfaceTexture) {
            texture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
            surfaceInUse?.release()
            val surface = Surface(texture)
            surfaceInUse = surface
            request.provideSurface(surface, executor) {
                // The texture goes only after CameraX is done with this Surface.
                surface.release()
                if (surfaceInUse === surface) surfaceInUse = null
                textureLost?.let {
                    if (surfaceInUse == null) {
                        it.release()
                        textureLost = null
                    }
                }
            }
        }
        request.setTransformationInfoListener(executor) { info ->
            transformInfo = info
            applyTransform(view)
        }
        val ready = view.surfaceTexture
        if (ready != null) {
            provide(ready)
        } else {
            val pending: (SurfaceTexture) -> Unit = ::provide
            waiting = pending
            // A request CameraX withdraws before the texture exists is dropped, not answered later.
            request.addRequestCancellationListener(executor) { if (waiting === pending) waiting = null }
        }
    }

    /** One frame, on the analysis thread: its Y plane through ZXing. Always closes the frame. */
    private fun analyze(image: ImageProxy) {
        try {
            if (answered.get()) return
            val plane = image.planes[0]
            val buffer = plane.buffer
            val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
            val text = decodeQr(bytes, image.width, image.height, plane.rowStride)
            if (text != null && text.startsWith(PAIR_PREFIX)) answer(RESULT_OK, text)
        } catch (_: Exception) {
            // A frame that cannot be read: the next one.
        } finally {
            image.close()
        }
    }

    private fun cancel() = answer(RESULT_CANCELED, null)

    /** Answers once, from any thread, and closes. */
    private fun answer(code: Int, text: String?) {
        if (!answered.compareAndSet(false, true)) return
        runOnUiThread {
            // The camera stops with the answer, not when the activity is finally destroyed.
            analysis?.clearAnalyzer()
            provider?.unbindAll()
            setResult(code, text?.let { Intent().putExtra(EXTRA_TEXT, it) })
            finish()
        }
    }

    override fun onDestroy() {
        // The analyzer goes before its executor: no frame is handed to a thread that is gone.
        analysis?.clearAnalyzer()
        analysisExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_TEXT = "text"

        /** The camera could not start (no back camera, in use by another app). */
        const val RESULT_FAILED = Activity.RESULT_FIRST_USER

        /** The only QR the app wants: the pairing link (lib/local/pairing.dart). */
        const val PAIR_PREFIX = "wambito://pair?"
    }
}
