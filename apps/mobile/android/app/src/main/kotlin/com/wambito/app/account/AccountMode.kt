package com.wambito.app.account

import android.content.Context

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
    private val preferences = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** What the app last wrote, or null. */
    var value: String?
        get() = preferences.getString(KEY, null)
        // commit(): a job that starts a moment later must find what was just written.
        set(value) {
            preferences.edit().apply { if (value == null) remove(KEY) else putString(KEY, value) }.commit()
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
