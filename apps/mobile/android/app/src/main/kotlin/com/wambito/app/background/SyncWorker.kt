package com.wambito.app.background

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.wambito.app.account.AccountMode
import com.wambito.app.capture.CaptureQueue
import com.wambito.app.capture.CaptureScheduler

/** The output key of what a sync did, for the logs and the tests. */
const val SYNC_OUTCOME = "outcome"

/**
 * Runs `syncMain` in a headless engine (D22) for a `preview` account.
 *
 *  * Not `preview`: nothing runs (`not preview`).
 *  * `done`, `changed`, `signedOut`, `locked`, `notPreview`: finished (retrying cannot change
 *    them). `changed` tells the app's engine, if it is alive, with `vaultChanged` (D7). After
 *    `done` or `changed`, captures still queued get a send ([CaptureScheduler.enqueueSend], D23).
 *  * `busy` (the app or another engine holds the lease), `failed`, `timeout`: retried with
 *    backoff, at most [MAX_RETRIES] times, then `gave up` (the next periodic run tries again).
 */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (!AccountMode(applicationContext).isPreview()) return done("not preview")
        val result = HeadlessHooks.run(applicationContext, "syncMain")
        // D23: a finished run means the engine works again; captures still queued get their send.
        if (result.outcome == "done" || result.outcome == "changed") sendQueued()
        return when (result.outcome) {
            "done", "signedOut", "locked", "notPreview" -> done(result.outcome)
            "changed" -> {
                BackgroundChannel.notifyVaultChanged()
                done("changed")
            }
            else -> if (runAttemptCount >= MAX_RETRIES) done("gave up") else Result.retry()
        }
    }

    private fun sendQueued() {
        if (CaptureQueue(applicationContext).all().isNotEmpty()) CaptureScheduler.enqueueSend(applicationContext)
    }

    private fun done(outcome: String): Result = Result.success(workDataOf(SYNC_OUTCOME to outcome))

    companion object {
        /** Retries of one run after a `busy`, `failed` or `timeout`. */
        const val MAX_RETRIES = 3
    }
}
