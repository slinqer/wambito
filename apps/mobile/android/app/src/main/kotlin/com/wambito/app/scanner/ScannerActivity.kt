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

    /**
     * CameraX's preview on [view], with no preview library: the surface comes from the texture, and the
     * picture is turned upright ([SurfaceRequest.setTransformationInfoListener]) and scaled to fill
     * the screen, cropping the overflow. The analysis does not depend on it.
     */
    private fun show(view: TextureView, request: SurfaceRequest) {
        val size = request.resolution
        val executor = ContextCompat.getMainExecutor(this)
        fun provide(texture: SurfaceTexture) {
            texture.setDefaultBufferSize(size.width, size.height)
            val surface = Surface(texture)
            request.provideSurface(surface, executor) { surface.release() }
        }
        request.setTransformationInfoListener(executor) { info ->
            val width = view.width.toFloat()
            val height = view.height.toFloat()
            if (width == 0f || height == 0f) return@setTransformationInfoListener
            val turned = info.rotationDegrees % 180 != 0
            val shownWidth = if (turned) size.height else size.width
            val shownHeight = if (turned) size.width else size.height
            val matrix = Matrix()
            // The texture fills the view stretched: undo that, turn it upright, then cover the view.
            matrix.postScale(size.width / width, size.height / height, width / 2, height / 2)
            matrix.postRotate(info.rotationDegrees.toFloat(), width / 2, height / 2)
            val cover = maxOf(width / shownWidth, height / shownHeight)
            matrix.postScale(cover, cover, width / 2, height / 2)
            view.setTransform(matrix)
        }
        val ready = view.surfaceTexture
        if (ready != null) {
            provide(ready)
        } else {
            view.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) = provide(texture)
                override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit
                // CameraX releases the Surface it was given; the texture is let go with the view.
                override fun onSurfaceTextureDestroyed(texture: SurfaceTexture) = true
                override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
            }
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
