package com.wambito.app.notices

import android.app.NotificationManager
import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * When the two notices run (spec section 7.2), on AndroidX WorkManager: no Google, no exact
 * alarms.
 *
 *  * "Hoy vence…": a one-time job aimed at the next 9:00 in the profile's zone; it schedules the
 *    next one when it ends ([DueWorker]). WorkManager may run it a few minutes late.
 *  * The guest warning: a one-time job 44 days ahead, replaced each time the app opens on a guest
 *    account and the server accepts a request from it (lib/notices/notice_sync.dart), so it only
 *    ever fires after 44 days without that.
 *
 * "Hoy vence…" waits for a network, since it asks the server before saying anything. The guest
 * warning asks nothing, so it waits for none: a phone offline on day 44 is warned all the same.
 */
object NoticeScheduler {
    const val DUE = "wambito.notice.due"
    const val GUEST = "wambito.notice.guest"

    /**
     * The server deletes an inactive guest at 60 days (apps/api/src/services/guest-cleanup.ts), but
     * counts activity to the day: a session slides at most once a day, so the last accepted request
     * may count up to a day early there. 44 days keeps "en 15 días" from ever promising more than
     * is left.
     */
    val GUEST_AFTER: Duration = Duration.ofDays(44)

    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /**
     * Turns "Hoy vence…" on: the next 9:00 in [zone] (the profile's; null keeps the one known, else
     * the phone's). Called at every app open, so a job already waiting for that zone is kept.
     */
    fun scheduleDue(context: Context, zone: String?, language: String?, now: Instant = Instant.now()) {
        val settings = NoticeSettings(context)
        val known = settings.zone
        val kept = settings.dueEnabled && (zone == null || zone == known)
        val zoneId = NoticeTimes.zoneOr(zone ?: known, ZoneId.systemDefault())
        settings.dueEnabled = true
        settings.language = language
        if (zone != null) settings.zone = zoneId.id
        enqueueDue(context, zoneId, now, if (kept) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE)
    }

    /** The job after this one ([DueWorker] calls it as its last step), 9:00 in [zone]. */
    fun enqueueNextDue(context: Context, zone: ZoneId, now: Instant) =
        enqueueDue(context, zone, now, ExistingWorkPolicy.REPLACE)

    private fun enqueueDue(context: Context, zone: ZoneId, now: Instant, policy: ExistingWorkPolicy) =
        enqueueDueIn(context, Duration.between(now, NoticeTimes.nextDueRun(now, zone).toInstant()), policy)

    /** The "Hoy vence…" job [delay] from now, on a network. */
    internal fun enqueueDueIn(context: Context, delay: Duration, policy: ExistingWorkPolicy) {
        val request = OneTimeWorkRequestBuilder<DueWorker>()
            .setInitialDelay(delay)
            .setConstraints(network)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(DUE, policy, request)
    }

    fun cancelDue(context: Context) {
        val settings = NoticeSettings(context)
        settings.dueEnabled = false
        // Another person, or the switch on again later, starts with no day recorded.
        settings.lastDueDay = null
        // A preview account's list names its payments: it goes with the notice.
        DueList.clear(context)
        WorkManager.getInstance(context).cancelUniqueWork(DUE)
        // One already on the shade goes too: after a sign-out it names the previous person's
        // payments.
        removePosted(context, NoticePoster.DUE_ID)
    }

    /** Sets the guest warning 44 days from now, in place of any earlier one. */
    fun scheduleGuest(context: Context, language: String?) {
        val settings = NoticeSettings(context)
        settings.guestEnabled = true
        settings.language = language
        enqueueGuestIn(context, GUEST_AFTER, ExistingWorkPolicy.REPLACE)
    }

    /** The guest warning's job [delay] from now. */
    internal fun enqueueGuestIn(context: Context, delay: Duration, policy: ExistingWorkPolicy) {
        val request = OneTimeWorkRequestBuilder<GuestWorker>()
            .setInitialDelay(delay)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(GUEST, policy, request)
    }

    fun cancelGuest(context: Context) {
        NoticeSettings(context).guestEnabled = false
        WorkManager.getInstance(context).cancelUniqueWork(GUEST)
        // One already on the shade goes too: after a claim or a sign-out it is no longer true.
        removePosted(context, NoticePoster.GUEST_ID)
    }

    private fun removePosted(context: Context, id: Int) {
        context.getSystemService(NotificationManager::class.java)?.cancel(id)
    }

    fun cancelAll(context: Context) {
        cancelDue(context)
        cancelGuest(context)
    }
}
