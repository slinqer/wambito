package com.wambito.app.capture

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The app's hand on automatic capture (lib/capture): access, enabled sources, the settings screens. */
class CaptureChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "setSource" -> {
                val source = call.argument<String>("source")?.let { CaptureSource.forWire(it) }
                val enabled = call.argument<Boolean>("enabled")
                if (source == null || enabled == null) {
                    result.error("bad_args", "source and enabled are required", null)
                } else {
                    CaptureSettings(activity).setEnabled(source, enabled)
                    result.success(null)
                }
            }
            "openAccessSettings" -> result.success(open(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)))
            "openAppInfo" -> result.success(
                open(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", activity.packageName, null)),
                ),
            )
            // After every sign-in: the queue becomes this account's, and what is left of it is sent.
            "sendQueued" -> {
                val userId = call.argument<String>("userId")?.takeIf { it.isNotEmpty() }
                if (userId == null) {
                    result.error("bad_args", "userId is required", null)
                } else {
                    // `from`: a merge's other account, whose captures are re-tagged, not dropped.
                    val from = call.argument<String>("from")?.takeIf { it.isNotEmpty() }
                    CaptureScheduler.sendQueued(activity, userId, from)
                    result.success(null)
                }
            }
            // On sign-out: captures of the account that left must not be sent for the next one.
            "clearQueue" -> {
                CaptureQueue(activity).clear()
                result.success(null)
            }
            // Confirmed in the app: their notifications have nothing left to ask.
            "dismiss" -> {
                val ids = call.argument<List<String>>("ids")
                if (ids == null) {
                    result.error("bad_args", "ids is required", null)
                } else {
                    CapturePoster.dismissAll(activity, ids)
                    result.success(null)
                }
            }
            // The review list as the app read it: notifications of anything not in it go.
            "keepOnly" -> {
                val ids = call.argument<List<String>>("ids")
                val before = call.argument<Number>("before")?.toLong()
                if (ids == null || before == null) {
                    result.error("bad_args", "ids and before are required", null)
                } else {
                    CapturePoster.keepOnly(activity, ids, before)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> {
        val granted = NotificationManagerCompat.getEnabledListenerPackages(activity).contains(activity.packageName)
        return mapOf(
            "access" to if (granted) "granted" else "missing",
            "sources" to CaptureSettings(activity).enabled().map { it.wire },
        )
    }

    private fun open(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val NAME = "wambito/capture"
    }
}
