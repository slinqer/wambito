package com.wambito.app.capture

import android.content.Context
import android.util.Log
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
import com.wambito.app.background.BackgroundChannel
import com.wambito.app.background.HeadlessHooks
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
     * A `preview` account's capture is saved on the phone, in the vault: it waits for no network
     * (the engine's own sync tries the network afterwards and survives not having one).
     */
    private fun constraintsFor(context: Context): Constraints =
        if (AccountMode(context).isPreview()) Constraints.NONE else network

    /**
     * Sends what is queued: to the server once there is a network (`plain`), or into the vault
     * through the headless engine at once (`preview`). APPEND_OR_REPLACE: a capture queued while a
     * send runs gets its own run after it, and a failed send never blocks the ones behind it. A
     * run that finds the queue empty (the engine before it saved what the next one waits for)
     * returns at once without starting an engine, so a burst of captures never chains engines.
     */
    fun enqueueSend(context: Context) {
        val request = OneTimeWorkRequestBuilder<SendCapturesWorker>()
            .setConstraints(constraintsFor(context))
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
            .setConstraints(constraintsFor(context))
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
        // A `preview` account's finances never leave the phone: its "Bien" goes to the vault.
        val mode = AccountMode(context)
        if (mode.isPreview()) return confirmInVault(context, id)
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

    /**
     * D9: the id joins the queue's confirms and `captureMain` posts it to the local
     * `/v1/transactions/review`; a `changed` run tells the app's engine (D7). Only a run that finished (`done`, `changed`) can say it was
     * taken; any other outcome keeps the id (retried up to [MAX_ATTEMPTS], then it waits for the
     * next engine run, which reads it again). An id a finished run never acknowledged is dropped
     * at the last attempt.
     */
    private suspend fun confirmInVault(context: Context, id: String): Result {
        val queue = CaptureQueue(context)
        queue.addConfirm(id)
        val result = HeadlessHooks.run(context, CAPTURE_ENTRYPOINT)
        if (result.outcome == "changed") BackgroundChannel.notifyVaultChanged()
        announceCaptured(context, result.captured)
        val last = runAttemptCount + 1 >= MAX_ATTEMPTS
        if (!finished(result.outcome)) return if (last) done("kept") else Result.retry()
        if (id !in queue.confirms()) {
            CapturePoster.dismiss(context, id)
            return done("confirmed")
        }
        if (!last) return Result.retry()
        queue.ack(emptyList(), listOf(id))
        return done("gave up")
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
        // A `preview` account's finances live only on the phone: the headless engine saves what is
        // queued in the vault and nothing goes to the server. A mode the app has not learned yet
        // waits: the job runs again, and nothing is sent meanwhile.
        val mode = AccountMode(context)
        if (mode.isPreview()) return saveInVault(context, queue)
        if (!mode.allowsApi()) {
            return if (runAttemptCount + 1 >= MAX_ATTEMPTS) done("mode unknown") else Result.retry()
        }
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

    /**
     * D1, D8, D23: `captureMain` reads the queue (`takeQueued`), saves each capture in the vault
     * through the local `POST /v1/captures`, and acknowledges the ones it saved (`ackQueued`).
     * This worker never calls [CaptureApi] and never touches the queue itself, except to count.
     *
     *  * `changed` tells the app's engine, if it is alive, with `vaultChanged` (D7).
     *  * `done` or `changed`: the answers become notifications, once per transaction. A capture
     *    the run did not acknowledge is one the vault refuses: its count goes up and at
     *    [CaptureQueue.MAX_REFUSALS] it is dropped, logged with no finance field (R8). While some
     *    are left the job runs again, up to [MAX_ATTEMPTS].
     *  * Any other outcome, or `timeout`: the queue is as it was, nothing counts, and the job is
     *    retried up to [MAX_ATTEMPTS] runs, then `kept` (the next capture, app start or sync
     *    enqueues it again). Never dropped, never sent.
     */
    private suspend fun saveInVault(context: Context, queue: CaptureQueue): Result {
        val before = mine(queue).map { it.key }
        val result = HeadlessHooks.run(context, CAPTURE_ENTRYPOINT)
        if (result.outcome == "changed") BackgroundChannel.notifyVaultChanged()
        announceCaptured(context, result.captured)
        val last = runAttemptCount + 1 >= MAX_ATTEMPTS
        if (!finished(result.outcome)) return if (last) done("kept") else Result.retry()
        val left = queue.all().map { it.key }.toSet()
        val dropped = queue.refuse(before.filter { it in left }, CaptureQueue.MAX_REFUSALS)
        dropped.forEach { _ -> log("dropped a capture the vault refused") }
        if (mine(queue).isEmpty()) return done("saved")
        return if (last) done("kept") else Result.retry()
    }

    /** The queued captures of the account the queue belongs to. */
    private fun mine(queue: CaptureQueue): List<QueuedCapture> {
        val owner = queue.owner() ?: return emptyList()
        return queue.all().filter { it.userId == owner }
    }

    private fun done(outcome: String): Result = Result.success(workDataOf(CAPTURE_OUTCOME to outcome))

    companion object {
        /** Runs of one send before it gives up and leaves the queue for the next one (D23). */
        const val MAX_ATTEMPTS = ConfirmCaptureWorker.MAX_ATTEMPTS

        /** Where a dropped capture is reported; no capture field ever goes in it. Replaced in tests. */
        @VisibleForTesting
        var log: (String) -> Unit = { Log.w("WambitoCapture", it) }
    }
}

/** The headless entry point (lib/main.dart) that saves captures and confirms in the vault. */
private const val CAPTURE_ENTRYPOINT = "captureMain"

/** Whether a headless run ended with the vault worked on (`done`, `changed`): else the queue stays. */
private fun finished(outcome: String): Boolean = outcome == "done" || outcome == "changed"

/**
 * Tells the person what a headless run saved: one notification per transaction, even if the
 * answer comes twice (a re-run after a failure returns the same ones; the notification id is the
 * transaction's, so it replaces itself). The other bank app's notice of a purchase already
 * confirmed asks nothing.
 */
private fun announceCaptured(context: Context, captured: List<String>) {
    val seen = mutableSetOf<String>()
    for (json in captured) {
        val answer = parseCaptureAnswer(json) ?: continue
        if (!seen.add(answer.id)) continue
        if (answer.merged && !answer.needsReview) {
            CaptureHooks.notifier.dismiss(context, answer.id)
        } else {
            CaptureHooks.notifier.show(context, answer)
        }
    }
}
