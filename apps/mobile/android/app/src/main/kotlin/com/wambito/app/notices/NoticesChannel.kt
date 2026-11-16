package com.wambito.app.notices

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.wambito.app.account.AccountMode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's hand on the two notices (lib/notices): schedule or cancel each, and the notification
 * permission of Android 13+, which only the app asks, on screen, once. The headless engine has no
 * [activity] (null): it still answers everything but `requestPermission`, which says no.
 */
class NoticesChannel(private val context: Context, private val activity: Activity?, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, NAME)
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scheduleDue" -> {
                NoticeChannels.ensure(context)
                NoticeScheduler.scheduleDue(context, call.argument<String>("zone"), call.argument<String>("language"))
                result.success(null)
            }
            // A `preview` account's due list, read from the vault by Dart: the owner it was read for
            // and the days and names, replacing the whole list; the notice is scheduled as ever.
            "scheduleDueList" -> {
                DueList.replace(context, call.argument<String>("owner"), daysOf(call.argument<List<Map<String, Any?>>>("days")))
                NoticeChannels.ensure(context)
                NoticeScheduler.scheduleDue(context, call.argument<String>("zone"), call.argument<String>("language"))
                result.success(null)
            }
            "cancelDue" -> {
                NoticeScheduler.cancelDue(context)
                result.success(null)
            }
            "scheduleGuest" -> {
                NoticeChannels.ensure(context)
                NoticeScheduler.scheduleGuest(context, call.argument<String>("language"))
                result.success(null)
            }
            "cancelGuest" -> {
                NoticeScheduler.cancelGuest(context)
                result.success(null)
            }
            // The account's mode for the background jobs (capture, widget, due notice): `plain`,
            // `preview`, `unknown`, or null when signed out, and the account's user id. See
            // account/AccountMode.kt: it also schedules or cancels the background sync.
            "setEncryptionMode" -> {
                AccountMode(context).write(call.argument<String>("mode"), call.argument<String>("owner"))
                result.success(null)
            }
            "permission" -> result.success(permission())
            "requestPermission" -> requestPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun daysOf(days: List<Map<String, Any?>>?): List<Pair<String, List<String>>> =
        days.orEmpty().mapNotNull { day ->
            val date = day["date"] as? String ?: return@mapNotNull null
            date to (day["names"] as? List<*>).orEmpty().filterIsInstance<String>()
        }

    /**
     * `granted` when notices can be posted; `askable` when they cannot because the Android 13+
     * permission is not given (the app may ask); `blocked` when they were switched off in the
     * phone's settings, which the app cannot change.
     */
    private fun permission(): String {
        val manager = context.getSystemService(NotificationManager::class.java)
        return when {
            manager?.areNotificationsEnabled() == true -> "granted"
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> "askable"
            else -> "blocked"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (activity == null) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(permission() == "granted")
            return
        }
        // The system prompt shows for an app that has a notification channel.
        NoticeChannels.ensure(context)
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
