package com.wambito.app.capture

import android.content.Context
import androidx.annotation.VisibleForTesting
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.wambito.app.account.AccountMode
import com.wambito.app.notices.ApiResult
import com.wambito.app.notices.serverOf
import com.wambito.app.widget.SecureStorageSession
import com.wambito.app.widget.SessionSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/** What the capture jobs need from outside: the stored session, the API, the queue. */
class CaptureDependencies(
    val session: SessionSource,
    val api: CaptureApi = CaptureApi(),
)

/** Says what a capture did to the person (Task 9 posts the real notifications). */
interface CaptureNotifier {
    /** A capture was saved (or found already saved): ask "¿bien?". */
    fun show(context: Context, answer: CaptureAnswer)

    /** [count] captures wait for a session: "Inicia sesión para guardar 2 gastos detectados". */
    fun signInNeeded(context: Context, count: Int)

    /** [transactionId] needs no "¿bien?" any more: its notification, if still up, goes. */
    fun dismiss(context: Context, transactionId: String)
}

object CaptureHooks {
    /** Replaced in tests. */
    @VisibleForTesting
    var dependencies: ((Context) -> CaptureDependencies)? = null

    /** The real notifications; tests replace it. */
    @VisibleForTesting
    var notifier: CaptureNotifier = CapturePoster

    fun of(context: Context): CaptureDependencies =
        dependencies?.invoke(context) ?: CaptureDependencies(session = SecureStorageSession(context))
}

/** The output key of what a send did, for the logs and the tests. */
const val CAPTURE_OUTCOME = "outcome"

object CaptureScheduler {
    /** Persistent name: never renamed. */
    const val SEND = "wambito.capture.send"

    /**
     * The one shared name the first builds gave every "Bien" (persistent: kept only to be
     * cancelled). Appending made one job that kept failing hold every later Bien behind it, so each
     * confirm now has its own name ([confirmName]) and this chain is cancelled at the next Bien; a
     * notification it still held stays up for another tap.
     */
    const val CONFIRM = "wambito.capture.confirm"

    /** Persistent prefix: the unique name of the confirm of one transaction is [confirmName]. */
    private const val CONFIRM_PREFIX = "$CONFIRM."

    /** The unique work name of "Bien" on [id]: `wambito.capture.confirm.<id>`. */
    fun confirmName(id: String): String = CONFIRM_PREFIX + id

    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /**
     * Sends what is queued once there is a network. APPEND_OR_REPLACE: a capture queued while a
     * send runs gets its own run after it, and a failed send never blocks the ones behind it.
     */
    fun enqueueSend(context: Context) {
        val request = OneTimeWorkRequestBuilder<SendCapturesWorker>()
            .setConstraints(network)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(SEND, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    /**
     * After a sign-in of [userId] (`sendQueued` on the channel): the queue becomes theirs, dropping
     * what was captured for another account or for none, and what is left is sent.
     */
    fun sendQueued(context: Context, userId: String) {
        val queue = CaptureQueue(context)
        queue.adopt(userId, CaptureHooks.of(context).session.mark())
        if (queue.all().isNotEmpty()) enqueueSend(context)
    }

    /**
     * "Bien" on [id]'s notification: confirms it once there is a network. One unique job per id
     * (KEEP: a second tap while the first waits or runs adds nothing), so a confirm that keeps
     * failing never holds the confirm of another transaction.
     */
    fun enqueueConfirm(context: Context, id: String) {
        val request = OneTimeWorkRequestBuilder<ConfirmCaptureWorker>()
            .setConstraints(network)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setInputData(workDataOf(ConfirmCaptureWorker.ID to id))
            .build()
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork(CONFIRM)
        work.enqueueUniqueWork(confirmName(id), ExistingWorkPolicy.KEEP, request)
    }
}

/**
 * Confirms one transaction (`POST /v1/transactions/review`) and takes its notification away.
 *
 *  * Confirmed, or refused for good by the server (a 4xx other than 401, 408 and 429; a 404 is a
 *    transaction deleted meanwhile or another account's): the notification goes.
 *  * 401 or no session: the notification stays, no retry (opening the app signs in again).
 *  * A server error, 408 or 429: the notification stays and WorkManager retries with backoff, at
 *    most [MAX_ATTEMPTS] runs in all (the job waits for a network, so being offline uses none);
 *    then it gives up and the notification stays for another Bien, or the inbox.
 *  * A server setting that cannot be read sends nothing, as in [SendCapturesWorker].
 */
class ConfirmCaptureWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val id = inputData.getString(ID)?.takeIf { it.isNotEmpty() } ?: return done("no id")
        // A `preview` account's finances never leave the phone: nothing is confirmed with the server.
        val mode = AccountMode(context)
        if (mode.isPreview()) return done("encrypted account")
        if (!mode.allowsApi()) return if (runAttemptCount + 1 >= MAX_ATTEMPTS) done("gave up") else Result.retry()
        val dependencies = CaptureHooks.of(context)
        val token = dependencies.session.token()
        if (dependencies.session.mark() == null || token == null) return done("signed out")
        val server = serverOf(context, dependencies.session) ?: return done("server unreadable")
        return when (withContext(Dispatchers.IO) { dependencies.api.confirm(server, token, id) }) {
            is ApiResult.Ok -> {
                CapturePoster.dismiss(context, id)
                done("confirmed")
            }
            ApiResult.Rejected -> {
                CapturePoster.dismiss(context, id)
                done("rejected")
            }
            ApiResult.Unauthorized -> done("session refused")
            ApiResult.Failed -> if (runAttemptCount + 1 >= MAX_ATTEMPTS) done("gave up") else Result.retry()
        }
    }

    private fun done(outcome: String): Result = Result.success(workDataOf(CAPTURE_OUTCOME to outcome))

    companion object {
        /** The input data key of the transaction to confirm. */
        const val ID = "id"

        /**
         * Runs of one confirm before it gives up: with the 30 s exponential backoff, the 7 waits
         * between them come to about 1 h 4 min of a server that keeps failing.
         */
        const val MAX_ATTEMPTS = 8
    }
}

/**
 * Sends the queue to `POST /v1/captures`, oldest first (spec sections 2.2 and 5).
 *
 *  * An item leaves the queue only once the server answered it (created, merged) or refused it for
 *    good (a 4xx other than 401). The key travels with the item, so a retry after a crash or a lost
 *    answer saves nothing twice.
 *  * 401 or no session: the queue stays, one "sign in" notice with the count, no retry (the next
 *    capture, or the next sign-in through [CaptureScheduler.sendQueued], enqueues a send again).
 *  * Only the captures of the queue's owner are sent, and only while the session is the one
 *    `sendQueued` bound the queue to ([CaptureQueue.ownerMark]): one tagged for another account
 *    (or none), or a token written since, waits for the app to say whose the queue is now.
 *  * Offline or a server error: the queue stays and WorkManager retries with backoff.
 *  * A server setting that cannot be read sends nothing: the token never goes to the default server
 *    in place of the person's.
 *  * Nothing about a capture is logged.
 */
class SendCapturesWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val dependencies = CaptureHooks.of(context)
        val queue = CaptureQueue(context)
        if (mine(queue).isEmpty()) return done("empty")
        // A `preview` account's finances live only on the phone: nothing queued goes to the server
        // (the app clears the queue; until it does, it just stays). A mode the app has not learned
        // yet waits: the job runs again, and nothing is sent meanwhile.
        val mode = AccountMode(context)
        if (mode.isPreview()) return done("encrypted account")
        if (!mode.allowsApi()) return Result.retry()
        val mark = dependencies.session.mark()
        val token = dependencies.session.token()
        if (mark == null || token == null) {
            if (mark == null) CaptureHooks.notifier.signInNeeded(context, mine(queue).size)
            return done(if (mark == null) "signed out" else "token unreadable")
        }
        // A token written since the app last said whose the queue is (another account signing in,
        // before sendQueued): its owner may not be this session's, so nothing goes until it says.
        if (mark != queue.ownerMark()) return done("session not bound")
        val server = serverOf(context, dependencies.session) ?: return done("server unreadable")
        return withContext(Dispatchers.IO) { sendAll(context, dependencies, queue, server, token, mark) }
    }

    private fun sendAll(
        context: Context,
        dependencies: CaptureDependencies,
        queue: CaptureQueue,
        server: String,
        token: String,
        mark: String,
    ): Result {
        for (item in mine(queue)) {
            when (val answer = dependencies.api.send(server, token, item)) {
                is ApiResult.Ok -> {
                    // Signed out (or another account) while the request was on its way: the capture
                    // is saved, but what it says is not for whoever holds the phone now.
                    if (dependencies.session.mark() != mark) {
                        queue.remove(item.key)
                        return done("dropped")
                    }
                    queue.remove(item.key)
                    val saved = answer.value
                    // The other bank app's notice of a purchase already confirmed: nothing to ask.
                    if (saved.merged && !saved.needsReview) {
                        CaptureHooks.notifier.dismiss(context, saved.id)
                    } else {
                        CaptureHooks.notifier.show(context, saved)
                    }
                }
                // The server will never take this one: drop it, go on with the rest.
                ApiResult.Rejected -> queue.remove(item.key)
                ApiResult.Unauthorized -> {
                    CaptureHooks.notifier.signInNeeded(context, mine(queue).size)
                    return done("session refused")
                }
                ApiResult.Failed -> return Result.retry()
            }
        }
        return done("sent")
    }

    /** The queued captures of the account the queue belongs to. */
    private fun mine(queue: CaptureQueue): List<QueuedCapture> {
        val owner = queue.owner() ?: return emptyList()
        return queue.all().filter { it.userId == owner }
    }

    private fun done(outcome: String): Result = Result.success(workDataOf(CAPTURE_OUTCOME to outcome))
}
