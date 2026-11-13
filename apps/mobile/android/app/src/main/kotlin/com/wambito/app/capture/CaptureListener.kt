package com.wambito.app.capture

import android.app.Notification
import android.content.Context
import com.wambito.app.account.AccountMode
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.time.Instant

/**
 * Reads the notifications of the bank apps the person enabled. What a notification says never
 * leaves this class except as a [ParsedCapture]; its text is never stored or logged.
 */
class CaptureListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        if (notification.flags and (Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_ONGOING_EVENT) != 0) return
        // Unknown or disabled apps are dropped before any text is read.
        val source = CaptureSource.forPackage(sbn.packageName) ?: return
        if (!CaptureSettings(this).isEnabled(source)) return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString()
        handle(this, sbn.packageName, title, text, Instant.ofEpochMilli(sbn.postTime))
    }

    companion object {
        /** Queues what an enabled source's notification says and schedules sending. */
        fun handle(context: Context, packageName: String, title: String?, text: String?, postedAt: Instant) {
            val source = CaptureSource.forPackage(packageName) ?: return
            if (!CaptureSettings(context).isEnabled(source)) return
            // A `preview` account's finances never leave the phone: its notifications are not read.
            if (AccountMode(context).isPreview()) return
            val capture = BankParsers.parse(source, title, text, postedAt) ?: return
            CaptureQueue(context).add(capture)
            CaptureScheduler.enqueueSend(context)
        }
    }
}
