package com.wambito.app.capture

import android.content.Context
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

/**
 * A capture waiting to be sent, with the idempotency key every attempt of it carries and the id of
 * the account it was captured for ([CaptureQueue.owner] then); null when no account was known
 * (signed out, or queued by a build before captures were tagged).
 */
data class QueuedCapture(val key: String, val capture: ParsedCapture, val userId: String? = null)

/**
 * The captures not yet saved on the server, in the order they were seen, in the SharedPreferences
 * file `wambito.capture.queue` (a persistent name: never renamed). It holds [ParsedCapture]'s
 * fields, the key and the account id, nothing else: no notification text ever reaches it.
 *
 * The queue belongs to one account, its [owner], which the app sets after every sign-in
 * ([adopt], through `sendQueued` on the `wambito/capture` channel). A capture is tagged with the
 * owner of the moment, so captures kept through a 401 go to their account when it signs in again,
 * and never to another one (R15).
 */
class CaptureQueue(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun add(capture: ParsedCapture): QueuedCapture = synchronized(LOCK) {
        val item = QueuedCapture(UUID.randomUUID().toString(), capture, owner())
        write(read() + item)
        item
    }

    fun all(): List<QueuedCapture> = synchronized(LOCK) { read() }

    /** The account the queue belongs to, or null when none is known (never signed in, signed out). */
    fun owner(): String? = preferences.getString(OWNER, null)

    /**
     * The session mark ([com.wambito.app.widget.SessionSource.mark]) the owner was set under. The
     * mark changes on every token write, so a token stored after the last [adopt] (another account
     * signing in, before the app says so) does not match it, and nothing is sent until it does.
     */
    fun ownerMark(): String? = preferences.getString(OWNER_MARK, null)

    /**
     * [userId] signed in, under the session [mark]: the queue is now theirs. Captures of another
     * account, and those of no known account (they could be anyone's), are dropped; theirs stay to
     * be sent. [from] is an account whose data [userId] takes over (a merge of this phone's account
     * into an email account, or that merge called off): its captures are re-tagged for [userId]
     * instead of dropped, and its confirms stay (transaction ids survive a merge).
     */
    fun adopt(userId: String, mark: String? = null, from: String? = null): Unit = synchronized(LOCK) {
        val items = read()
        val kept = items.mapNotNull {
            when {
                it.userId == userId -> it
                from != null && it.userId == from -> it.copy(userId = userId)
                else -> null
            }
        }
        val owner = owner()
        val edit = preferences.edit().putString(OWNER, userId)
        // The confirms of the account before are not for this one, unless this one takes it over.
        if (owner != userId && (from == null || owner != from)) edit.remove(CONFIRMS)
        if (mark == null) edit.remove(OWNER_MARK) else edit.putString(OWNER_MARK, mark)
        if (kept != items) edit.putString(ITEMS, encodeAll(kept))
        edit.commit()
    }

    fun remove(key: String) = synchronized(LOCK) {
        val items = read()
        if (items.any { it.key == key }) write(items.filterNot { it.key == key })
        forget(listOf(key))
    }

    /**
     * "Bien" taps on a `preview` account's notifications waiting for the vault (D9), oldest first:
     * transaction ids, which the headless run reads and acknowledges as it does the captures.
     */
    fun confirms(): List<String> = synchronized(LOCK) { readConfirms() }

    /** Adds [id] to [confirms] (once). */
    fun addConfirm(id: String): Unit = synchronized(LOCK) {
        val ids = readConfirms()
        if (id !in ids) preferences.edit().putString(CONFIRMS, JSONArray(ids + id).toString()).commit()
    }

    /** The headless run saved the captures [keys] and the confirms [confirms]: they leave. */
    fun ack(keys: List<String>, confirms: List<String>): Unit = synchronized(LOCK) {
        val items = read()
        if (items.any { it.key in keys }) write(items.filterNot { it.key in keys })
        val ids = readConfirms()
        if (ids.any { it in confirms }) {
            preferences.edit().putString(CONFIRMS, JSONArray(ids.filterNot { it in confirms }).toString()).commit()
        }
        forget(keys)
    }

    /**
     * A run that finished (`done` or `changed`) left the captures [keys] unacknowledged: the vault
     * refuses them. Each one's count goes up, and one that reaches [limit] is dropped. Engine
     * failures never come here, so a capture is never lost because the engine failed. Returns the
     * keys dropped.
     */
    fun refuse(keys: List<String>, limit: Int): List<String> = synchronized(LOCK) {
        val queued = read().map { it.key }.toSet()
        val counts = readRefusals()
        val dropped = mutableListOf<String>()
        for (key in keys.filter { it in queued }) {
            val count = (counts[key] ?: 0) + 1
            if (count >= limit) {
                dropped += key
                counts.remove(key)
            } else {
                counts[key] = count
            }
        }
        if (dropped.isNotEmpty()) write(read().filterNot { it.key in dropped })
        writeRefusals(counts)
        dropped
    }

    /** Signed out: the captures and whose they were are forgotten. */
    fun clear(): Unit = synchronized(LOCK) {
        preferences.edit().putString(ITEMS, encodeAll(emptyList())).remove(OWNER).remove(OWNER_MARK)
            .remove(CONFIRMS).remove(REFUSALS).commit()
    }

    private fun readConfirms(): List<String> {
        val raw = preferences.getString(CONFIRMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getString(it) }
        } catch (_: JSONException) {
            emptyList()
        }
    }

    /** Refusal counts by capture key, kept apart so the items keep only their own fields. */
    private fun readRefusals(): MutableMap<String, Int> {
        val raw = preferences.getString(REFUSALS, null) ?: return mutableMapOf()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { json.getInt(it) }.toMutableMap()
        } catch (_: JSONException) {
            mutableMapOf()
        }
    }

    private fun writeRefusals(counts: Map<String, Int>) {
        preferences.edit().putString(REFUSALS, JSONObject(counts).toString()).commit()
    }

    private fun forget(keys: List<String>) {
        val counts = readRefusals()
        if (keys.any { counts.remove(it) != null }) writeRefusals(counts)
    }

    private fun read(): List<QueuedCapture> {
        val raw = preferences.getString(ITEMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
        } catch (_: JSONException) {
            emptyList()
        }
    }

    // commit(): the notification listener may be killed right after it queues a capture.
    private fun write(items: List<QueuedCapture>) {
        preferences.edit().putString(ITEMS, encodeAll(items)).commit()
    }

    private fun encodeAll(items: List<QueuedCapture>): String {
        val array = JSONArray()
        items.forEach { array.put(encode(it)) }
        return array.toString()
    }

    private fun encode(item: QueuedCapture): JSONObject {
        val json = item.capture.toJson().put("key", item.key)
        if (item.userId != null) json.put(USER, item.userId)
        return json
    }

    /** An entry that cannot be read is skipped: it would only ever fail again. */
    private fun decode(json: JSONObject): QueuedCapture? {
        val key = json.optString("key").takeIf { it.isNotEmpty() } ?: return null
        val userId = json.optString(USER).takeIf { it.isNotEmpty() }
        return parsedCaptureFromJson(json)?.let { QueuedCapture(key, it, userId) }
    }

    companion object {
        /** The SharedPreferences file. */
        internal const val FILE = "wambito.capture.queue"
        private const val ITEMS = "items"
        private const val OWNER = "owner"
        private const val OWNER_MARK = "ownerMark"
        private const val USER = "user"
        private const val CONFIRMS = "confirms"
        private const val REFUSALS = "refusals"

        /** Finished runs that may leave a capture unacknowledged before it is dropped (R8). */
        const val MAX_REFUSALS = 8
        private val LOCK = Any()
    }
}
