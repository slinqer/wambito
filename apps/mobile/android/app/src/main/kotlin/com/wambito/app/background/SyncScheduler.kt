package com.wambito.app.background

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * When the vault syncs with no app open (D7, D22): every 6 hours with a network, plus a one-off on
 * demand. Both run [SyncWorker]. Only a `preview` account has any ([com.wambito.app.account.AccountMode.write] schedules
 * and cancels them as the mode changes).
 */
object SyncScheduler {
    /** Persistent names: never renamed. */
    const val PERIODIC = "wambito.sync.periodic"
    const val NOW = "wambito.sync.now"

    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /** Every 6 hours, once there is a network; one already scheduled is kept. */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<SyncWorker>(6, TimeUnit.HOURS)
            .setConstraints(network)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /**
     * One sync now, with no constraint. One already waiting or running is kept and a second ask is
     * dropped (KEEP): the widget's refresh jobs ask every 3 hours and at midnight, and each ask must
     * not queue another engine behind the last. A run that finished leaves the name free.
     */
    fun now(context: Context) {
        val request = OneTimeWorkRequestBuilder<SyncWorker>()
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.KEEP, request)
    }

    /** Signed out, or the account is not a `preview` one: no sync of either kind. */
    fun cancel(context: Context) {
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork(PERIODIC)
        work.cancelUniqueWork(NOW)
    }
}
