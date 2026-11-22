package com.wambito.app.account

import android.content.Context
import com.wambito.app.background.SyncScheduler

/**
 * Whether the signed-in account's finances live on the server (`plain`) or only in the vault on the
 * phone, end-to-end encrypted (`preview`), kept where the background jobs can read it: the app
 * writes it (`wambito/notices` `setEncryptionMode`, from lib/vault/preview_sync.dart)
 * whenever it knows the mode, and clears it on sign-out. The jobs (capture, widget, due notice)
 * call the API on their own with the stored session, outside the app's finance guard, so each asks
 * here first: for a `preview` account none of them may send or fetch finance data.
 *
 * Values: `plain`, `preview`, `unknown` (signed in, the app has not learned the mode yet) and
 * absent (nobody told: an install from before the vault, or signed out). Nothing secret.
 */
class AccountMode(context: Context) {
    private val context = context.applicationContext
    private val preferences = this.context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** What the app last wrote, or null. */
    var value: String?
        get() = preferences.getString(KEY, null)
        // commit(): a job that starts a moment later must find what was just written. Clearing the
        // mode clears the owner too: nobody is signed in.
        set(value) {
            preferences.edit().apply {
                if (value == null) remove(KEY).remove(OWNER_KEY) else putString(KEY, value)
            }.commit()
        }

    /**
     * The id of the account the mode is for (the headless run checks it against the vault it
     * opens), or null: signed out, or the app has not told it.
     */
    val owner: String?
        get() = preferences.getString(OWNER_KEY, null)

    /**
     * What the app tells the background jobs (`wambito/notices` `setEncryptionMode`): the [mode] and
     * its [owner] are written together, and the background sync follows them: scheduled for a
     * `preview` account with a known owner, cancelled for `plain` or none (`unknown` leaves it
     * as it was: the app has not learned the mode yet).
     */
    fun write(mode: String?, owner: String?) {
        preferences.edit().apply {
            if (mode == null) remove(KEY) else putString(KEY, mode)
            if (mode == null || owner == null) remove(OWNER_KEY) else putString(OWNER_KEY, owner)
        }.commit()
        when {
            mode == PREVIEW && owner != null -> SyncScheduler.schedule(context)
            mode == null || mode == PLAIN -> SyncScheduler.cancel(context)
        }
    }

    /** May a job call the API with the person's finance data (see [allowsApi])? */
    fun allowsApi(): Boolean = allowsApi(value)

    /** Is the account known to keep its finances on the phone only? */
    fun isPreview(): Boolean = value == PREVIEW

    companion object {
        /** Persistent name: never renamed. */
        internal const val FILE = "wambito.encryption"

        /** The key the app and the jobs share (the name the iOS side uses too). */
        internal const val KEY = "wambito.encryption.mode"

        /** The account the mode is for (persistent: never renamed). */
        internal const val OWNER_KEY = "wambito.encryption.owner"
        const val PLAIN = "plain"
        const val PREVIEW = "preview"
        const val UNKNOWN = "unknown"

        /**
         * Only a `plain` account (or one from before the vault existed, which never wrote a mode)
         * lets a job touch the API. `preview` never does; `unknown` waits for the app to learn it.
         */
        fun allowsApi(mode: String?): Boolean = mode == null || mode == PLAIN
    }
}
