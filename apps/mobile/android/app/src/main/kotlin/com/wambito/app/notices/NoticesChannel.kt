package com.wambito.app.notices

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import com.wambito.app.account.AccountMode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's hand on the two notices (lib/notices): schedule or cancel each, and the notification
 * permission of Android 13+, which only the app asks, on screen, once.
 */
class NoticesChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleDue" -> {
                NoticeChannels.ensure(activity)
                NoticeScheduler.scheduleDue(activity, call.argument<String>("zone"), call.argument<String>("language"))
                result.success(null)
            }
            "cancelDue" -> {
                NoticeScheduler.cancelDue(activity)
                result.success(null)
            }
            "scheduleGuest" -> {
                NoticeChannels.ensure(activity)
                NoticeScheduler.scheduleGuest(activity, call.argument<String>("language"))
                result.success(null)
            }
            "cancelGuest" -> {
                NoticeScheduler.cancelGuest(activity)
                result.success(null)
            }
            // The account's mode for the background jobs (capture, widget, due notice): `plain`,
            // `preview`, `unknown`, or null when signed out. See account/AccountMode.kt.
            "setEncryptionMode" -> {
                AccountMode(activity).value = call.argument<String>("mode")
                result.success(null)
            }
            "permission" -> result.success(permission())
            "requestPermission" -> requestPermission(result)
            else -> result.notImplemented()
        }
    }

    /**
     * `granted` when notices can be posted; `askable` when they cannot because the Android 13+
     * permission is not given (the app may ask); `blocked` when they were switched off in the
     * phone's settings, which the app cannot change.
     */
    private fun permission(): String {
        val manager = activity.getSystemService(NotificationManager::class.java)
        return when {
            manager?.areNotificationsEnabled() == true -> "granted"
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> "askable"
            else -> "blocked"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(permission() == "granted")
            return
        }
        // The system prompt shows for an app that has a notification channel.
        NoticeChannels.ensure(activity)
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    /** From MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPermission = null
    }

    companion object {
        const val NAME = "wambito/notices"
        private const val PERMISSION_REQUEST = 4211
    }
}
