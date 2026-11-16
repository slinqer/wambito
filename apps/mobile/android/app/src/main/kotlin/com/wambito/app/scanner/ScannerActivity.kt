package com.wambito.app.scanner

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
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
    private val answered = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        analysisExecutor = Executors.newSingleThreadExecutor()
        val preview = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
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

    private fun start(preview: PreviewView) {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener(
            {
                try {
                    val provider = future.get()
                    val view = Preview.Builder().build().also { it.surfaceProvider = preview.surfaceProvider }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { it.setAnalyzer(analysisExecutor, ::analyze) }
                    provider.unbindAll()
                    provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, view, analysis)
                } catch (_: Exception) {
                    answer(RESULT_FAILED, null)
                }
            },
            ContextCompat.getMainExecutor(this),
        )
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
            setResult(code, text?.let { Intent().putExtra(EXTRA_TEXT, it) })
            finish()
        }
    }

    override fun onDestroy() {
        // Anything still pending is closed with the activity; the camera is released by the lifecycle.
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
