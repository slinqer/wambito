package com.wambito.app.widget

import android.content.Context
import android.content.SharedPreferences
import com.wambito.app.AppLanguages
import org.json.JSONException
import org.json.JSONObject
import java.time.DateTimeException
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeParseException

/**
 * What the widget draws, as the app writes it (lib/home/widget_snapshot.dart, which documents the
 * shape) and the refresh job too ([RefreshWorker]): one JSON document, version 3, under [KEY] in
 * home_widget's SharedPreferences file [PREFS].
 *
 * Amounts are cents, as the API sends them. A snapshot that is missing, of another version, signed
 * out, or missing a figure reads as signed out: "Abre Wambito para empezar", never a stale figure.
 */
data class WidgetSnapshot(
    val signedIn: Boolean,
    val remaining: Long = 0,
    val spent: Long = 0,
    val budgetTotal: Long = 0,
    val currency: String = "",
    /** "es", "en", "it" or "pt": the widget's words and how amounts are written. Null: the phone's. */
    val locale: String? = null,
    /** `YYYY-MM`. */
    val month: String = "",
    /** "happy" or "worried". */
    val mood: String = "happy",
    val updatedAt: Instant? = null,
    val hideAmount: Boolean = false,
    /** "dark", "light" or "system": the theme picked in the app. */
    val theme: String = "dark",
    /**
     * When the refresh job last failed to reach the server (offline, a server error), if after
     * [updatedAt]: the figures are then marked "hace un rato". Written by [RefreshWorker] only; the
     * app's writes drop it (their figures are fresh) and its choice patches keep it.
     */
    val refreshFailedAt: Instant? = null,
    /**
     * The profile's IANA zone: "this month" and the midnight refresh are read in it, as the app
     * reads its own figures. Null (or not a zone): the phone's.
     */
    val timezone: String? = null,
    /**
     * Signed out only: the sentence the widget says in place of "Abre Wambito para empezar", in the
     * app's language (a `preview` account's "Próximamente con cifrado": its figures live only on
     * the phone). Written by the app; never by [RefreshWorker]. Null: the usual sentence.
     */
    val line: String? = null,
) {
    /** The profile's zone, or [fallback] (the phone's) without a valid one. */
    fun zone(fallback: ZoneId): ZoneId = timezone?.let {
        try {
            ZoneId.of(it)
        } catch (_: DateTimeException) {
            null
        }
    } ?: fallback

    fun toJson(): String {
        val doc = JSONObject()
            .put("v", VERSION)
            .put("signedIn", signedIn)
            .put("hideAmount", hideAmount)
            .put("theme", theme)
        if (locale != null) doc.put("locale", locale)
        if (!signedIn && line != null) doc.put("line", line)
        if (signedIn) {
            doc.put("remaining", remaining)
                .put("spent", spent)
                .put("budgetTotal", budgetTotal)
                .put("currency", currency)
                .put("month", month)
                .put("mood", mood)
                .put("updatedAt", updatedAt?.toString())
            if (refreshFailedAt != null) doc.put("refreshFailedAt", refreshFailedAt.toString())
            if (timezone != null) doc.put("timezone", timezone)
        }
        return doc.toString()
    }

    companion object {
        const val PREFS = "HomeWidgetPreferences"
        const val KEY = "wambito.widget.snapshot"
        const val VERSION = 3

        /** The snapshot in [json], or null when there is none of this version. */
        fun parse(json: String?): WidgetSnapshot? {
            if (json == null) return null
            val doc = try {
                JSONObject(json)
            } catch (_: JSONException) {
                return null
            }
            if (doc.optInt("v", -1) != VERSION) return null
            val hideAmount = doc.optBoolean("hideAmount", false)
            val theme = doc.optString("theme", "dark")
            val locale = doc.optString("locale", "").takeIf { it in AppLanguages.ALL }
            val signedOut = WidgetSnapshot(
                signedIn = false,
                locale = locale,
                hideAmount = hideAmount,
                theme = theme,
                line = doc.optString("line", "").takeIf { it.isNotEmpty() },
            )
            if (!doc.optBoolean("signedIn", false)) return signedOut
            val figures = listOf("remaining", "spent", "budgetTotal", "currency", "month")
            if (figures.any { !doc.has(it) || doc.isNull(it) }) return signedOut
            return try {
                WidgetSnapshot(
                    signedIn = true,
                    remaining = doc.getLong("remaining"),
                    spent = doc.getLong("spent"),
                    budgetTotal = doc.getLong("budgetTotal"),
                    currency = doc.getString("currency"),
                    locale = locale,
                    month = doc.getString("month"),
                    mood = doc.optString("mood", "happy"),
                    updatedAt = instant(doc.optString("updatedAt", "")),
                    refreshFailedAt = instant(doc.optString("refreshFailedAt", "")),
                    hideAmount = hideAmount,
                    theme = theme,
                    timezone = doc.optString("timezone", "").takeIf { it.isNotEmpty() },
                )
            } catch (_: JSONException) {
                signedOut
            }
        }

        private fun instant(text: String): Instant? = try {
            Instant.parse(text)
        } catch (_: DateTimeParseException) {
            null
        }

        fun preferences(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** What is stored now (null: nothing of this version). */
        fun read(context: Context): WidgetSnapshot? = parse(preferences(context).getString(KEY, null))
    }
}
