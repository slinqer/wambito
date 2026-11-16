package com.wambito.app.scanner

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The QR scanner, on the `wambito/scanner` channel (lib/scanner/qr_scanner.dart). The camera is
 * only ever opened by `scan`, and its permission only asked there.
 *
 *  * `isAvailable` → true when the phone has a camera.
 *  * `scan` → the text of the first `wambito://pair?` QR read ([ScannerActivity], full screen), or
 *    null when the person closed it or refused the camera permission (no error, no crash). Errors:
 *    `failed` (the camera could not start), `busy` (a scan is already open).
 *
 * One scan at a time: Android has one result slot per request code.
 */
class ScannerChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, NAME)
    private var pending: MethodChannel.Result? = null

    /** True while the permission prompt is up, so a second call is `busy` too. */
    private var asking = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
            )
            "scan" -> scan(result)
            else -> result.notImplemented()
        }
    }

    private fun scan(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A scan is already open", null)
            return
        }
        pending = result
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            open()
        } else {
            asking = true
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
        }
    }

    private fun open() {
        asking = false
        activity.startActivityForResult(Intent(activity, ScannerActivity::class.java), SCAN)
    }

    /** From MainActivity.onRequestPermissionsResult. A refusal answers null. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        if (!asking) return true
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            open()
        } else {
            asking = false
            finish { it.success(null) }
        }
        return true
    }

    /** From MainActivity.onActivityResult; false for a request that is not ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SCAN) return false
        finish { result ->
            when (resultCode) {
                Activity.RESULT_OK -> result.success(data?.getStringExtra(ScannerActivity.EXTRA_TEXT))
                ScannerActivity.RESULT_FAILED -> result.error("failed", "The camera could not start", null)
                else -> result.success(null)
            }
        }
        return true
    }

    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        answer(result)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending = null
        asking = false
    }

    companion object {
        const val NAME = "wambito/scanner"
        private const val PERMISSION_REQUEST = 4212
        private const val SCAN = 0x5153
    }
}
