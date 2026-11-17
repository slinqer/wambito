package com.wambito.app.notices

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

/**
 * The next days' due payments of a `preview` account, which the app (and the headless engine) read
 * from the vault and hand over (`wambito/notices` `scheduleDueList`): the names on each day, and the
 * account they were read for, the [owner]. [DueWorker] posts today's entry at 9:00 without asking
 * the server, and only while the owner is the account the app last told about
 * ([com.wambito.app.account.AccountMode.owner]).
 *
 * Replaced whole each time, never merged. It holds payment names, so its file is excluded from
 * backups (`wambito.notice.duelist.xml`, backup_rules.xml and data_extraction_rules.xml).
 */
object DueList {
    /** Persistent name: never renamed. */
    internal const val FILE = "wambito.notice.duelist"
    private const val OWNER = "owner"
    private const val DAYS = "days"

    private fun preferences(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Replaces the list with [days] (`YYYY-MM-DD` and the names on it), read for [owner]. */
    fun replace(context: Context, owner: String?, days: List<Pair<String, List<String>>>) {
        val doc = JSONObject()
        for ((date, names) in days) doc.put(date, JSONArray(names))
        // commit(): the job that starts a moment later must find what was just handed over.
        preferences(context).edit().apply {
            if (owner == null) remove(OWNER) else putString(OWNER, owner)
            putString(DAYS, doc.toString())
        }.commit()
    }

    /** The account the list was read for; null when none (or never handed over). */
    fun owner(context: Context): String? = preferences(context).getString(OWNER, null)

    /** The payments due on [date], in the order the app gave them; none when the day is not listed. */
    fun namesOn(context: Context, date: LocalDate): List<String> {
        val raw = preferences(context).getString(DAYS, null) ?: return emptyList()
        return try {
            val names = JSONObject(raw).optJSONArray(date.toString()) ?: return emptyList()
            (0 until names.length()).mapNotNull { names.optString(it).takeIf { name -> name.isNotBlank() } }
        } catch (_: org.json.JSONException) {
            emptyList()
        }
    }

    /** Forgets the list: a sign-out, the switch off, another account. */
    fun clear(context: Context) {
        preferences(context).edit().clear().commit()
    }
}
