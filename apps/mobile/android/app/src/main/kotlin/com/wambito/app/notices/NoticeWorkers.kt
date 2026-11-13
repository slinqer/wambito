package com.wambito.app.notices

import android.content.Context
import androidx.annotation.VisibleForTesting
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.wambito.app.R
import com.wambito.app.account.AccountMode
import com.wambito.app.widget.SecureStorageSession
import com.wambito.app.widget.ServerSetting
import com.wambito.app.widget.SessionSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** What the notices' jobs need from outside: the stored session, the API, the clock. */
class NoticeDependencies(
    val session: SessionSource,
    val api: NoticeApi = NoticeApi(),
    val clock: () -> Instant = Instant::now,
)

object NoticeHooks {
    /** Replaced in tests. */
    @VisibleForTesting
    var dependencies: ((Context) -> NoticeDependencies)? = null

    /**
     * The real ones read the token where the app keeps it ([SecureStorageSession], read-only: never
     * a second copy of the token, never a write to the secure storage).
     */
    fun of(context: Context): NoticeDependencies =
        dependencies?.invoke(context) ?: NoticeDependencies(session = SecureStorageSession(context))
}

/**
 * The server a job asks: the one picked in Settings, else the app's default. A setting that is
 * stored but cannot be read is never replaced by the default (that would send the person's token to
 * our server instead of theirs): null, and the job does nothing.
 */
internal fun serverOf(context: Context, session: SessionSource): String? = when (val setting = session.server()) {
    ServerSetting.Default -> context.getString(R.string.default_server)
    is ServerSetting.Chosen -> setting.url
    ServerSetting.Unreadable -> null
}

/** Tries a job gets on a network that fails before it gives up on today. */
private const val DUE_TRIES = 3

/** The output key of what a job did, for the logs and the tests. */
const val NOTICE_OUTCOME = "outcome"

/**
 * "Hoy vence…" (spec section 7.2): at 9:00 in the profile's zone, one notice for the recurring
 * payments still pending today, joined naturally ("Arriendo y Spotify"); none when there are none.
 * Then it schedules tomorrow's 9:00, unless the switch is off or the session is gone.
 *
 *  * The app schedules it only for someone with an active recurring rule who allowed notifications;
 *    if the permission is gone by the time it runs, it asks the server nothing.
 *  * Its requests carry `x-wambito-background: 1`, so they never count as activity on the server.
 *  * One notice per local day: the day is recorded, and a run before 9:00 (a phone that was off
 *    overnight) posts nothing and aims at 9:00 instead.
 *  * It reads the session where the app keeps it and only reads the server; the notification
 *    permission is the app's to ask, in the app.
 */
class DueWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val dependencies = NoticeHooks.of(context)
        val settings = NoticeSettings(context)
        var zone = NoticeTimes.zoneOr(settings.zone, ZoneId.systemDefault())
        var outcome = "off"
        var keepGoing = true
        if (settings.dueEnabled) {
            val mark = dependencies.session.mark()
            if (mark == null) {
                outcome = "signed out"
            } else if (!AccountMode(context).allowsApi()) {
                // A `preview` account's payments live only on the phone: nothing is asked. While
                // the app has not learned the mode yet, tomorrow's run looks again.
                outcome = "encrypted account"
                keepGoing = !AccountMode(context).isPreview()
            } else if (!NoticePoster(context).canPost()) {
                // Nothing could be said: nothing is asked of the server either.
                outcome = "not allowed"
            } else {
                val attempt = withContext(Dispatchers.IO) { attempt(context, dependencies, settings, mark, zone) }
                if (attempt == null) {
                    if (runAttemptCount < DUE_TRIES) return Result.retry()
                    outcome = "gave up"
                } else {
                    outcome = attempt.outcome
                    zone = attempt.zone
                    keepGoing = attempt.keepGoing
                }
            }
        }
        // Tomorrow's 9:00 (or today's, when this run came before it), as the last step: only while
        // the switch is on and someone is signed in.
        if (keepGoing && settings.dueEnabled && dependencies.session.mark() != null) {
            NoticeScheduler.enqueueNextDue(context, zone, dependencies.clock())
        }
        return Result.success(workDataOf(NOTICE_OUTCOME to outcome))
    }

    private class Run(val outcome: String, val zone: ZoneId, val keepGoing: Boolean = true)

    /** A run's result; null when the network or the server failed (try again). */
    private fun attempt(
        context: Context,
        dependencies: NoticeDependencies,
        settings: NoticeSettings,
        mark: String,
        known: ZoneId,
    ): Run? {
        val server = serverOf(context, dependencies.session) ?: return Run("server unreadable", known)
        val token = dependencies.session.token() ?: return Run("token unreadable", known)
        val profile = when (val answer = dependencies.api.profile(server, token)) {
            is ApiResult.Ok -> answer.value
            ApiResult.Unauthorized -> return Run("session refused", known, keepGoing = false)
            ApiResult.Failed, ApiResult.Rejected -> return null
        }
        val zone = NoticeTimes.zoneOr(profile.timezone, known)
        if (settings.zone != zone.id) settings.zone = zone.id
        val now = dependencies.clock()
        // Before 9:00 there, never: the next run is aimed at 9:00 today.
        if (now.atZone(zone).toLocalTime().isBefore(NoticeTimes.DUE_AT)) return Run("before 9", zone)
        val today = LocalDate.ofInstant(now, zone)
        if (settings.lastDueDay == today.toString()) return Run("already today", zone)
        val names = when (val answer = dependencies.api.dueToday(server, token, today)) {
            is ApiResult.Ok -> answer.value
            ApiResult.Unauthorized -> return Run("session refused", zone, keepGoing = false)
            ApiResult.Failed, ApiResult.Rejected -> return null
        }
        // Signed out, or the switch turned off, while the request was on its way: nothing is said.
        if (dependencies.session.mark() != mark || !settings.dueEnabled) return Run("dropped", zone)
        if (names.isEmpty()) return Run("nothing due today", zone)
        if (!NoticePoster(context).postDue(names, settings.language)) return Run("not allowed", zone)
        settings.lastDueDay = today.toString()
        return Run("posted", zone)
    }
}

/**
 * The guest warning (spec section 7.2): it fires 44 days after the app was last opened on a guest
 * account (the app replaces the job at every open) and posts "Tus datos se borrarán en 15 días si
 * no agregas tu correo": the server deletes an inactive guest at 60 days.
 *
 * It makes **no call to the server**: any authenticated request is activity there and would move
 * the deletion 60 days on, making the warning false. It decides from what is on the phone: the
 * switch, a session that is still stored, and the guest flag the app keeps next to the token. The
 * app cancels the job when the account claims an email and when the person signs out.
 */
class GuestWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val dependencies = NoticeHooks.of(context)
        val settings = NoticeSettings(context)
        val outcome = when {
            !settings.guestEnabled -> "off"
            dependencies.session.mark() == null -> "signed out"
            // A flag that is missing reads as a guest, as in the app: the safe side is to warn.
            dependencies.session.guest() == false -> "has an email"
            NoticePoster(context).postGuestWarning(settings.language) -> "posted"
            else -> "not allowed"
        }
        return Result.success(workDataOf(NOTICE_OUTCOME to outcome))
    }
}
