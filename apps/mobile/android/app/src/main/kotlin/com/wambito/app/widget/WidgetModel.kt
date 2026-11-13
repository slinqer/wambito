package com.wambito.app.widget

import android.content.Context
import android.content.res.Configuration
import com.wambito.app.AppLanguages
import com.wambito.app.R
import java.time.Duration
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/** The app's theme choice: night (the default), day, or the phone's own mode. */
enum class WidgetTheme { NIGHT, DAY, SYSTEM }

/** The progress bar's colour: on track, a category near its limit, over the budgets. */
enum class Tone { GOOD, NEAR, OVER }

/** Wambi's face on the medium widget. */
enum class Mood { HAPPY, WORRIED }

/** What the widget says (spec section 7.1), worked out from a snapshot before anything is drawn. */
sealed interface WidgetModel {
    val theme: WidgetTheme

    /** Nobody signed in (or nothing to show yet): "Abre Wambito para empezar". */
    data class SignedOut(val message: String, override val theme: WidgetTheme) : WidgetModel

    data class Figures(
        /** "Te quedan", "Te pasaste" or "Gastado este mes" (or an earlier month's). */
        val label: String,
        /** The amount as the app writes it, or "••••" when hidden. */
        val amount: String,
        /** Spent over the budgets, 0 to 1; null without budgets. */
        val progress: Float?,
        val tone: Tone,
        /** The figures' month, by name ("Octubre"). */
        val month: String,
        val mood: Mood,
        /** "hace un rato" when the figures could not be refreshed for a while; null when fresh. */
        val stale: String?,
        override val theme: WidgetTheme,
        /** The ＋ and 🎤 read aloud, in the snapshot's language. */
        val addLabel: String,
        val captureLabel: String,
        /** What TalkBack reads for the amount when it is not what is shown ("Monto oculto"). */
        val amountDescription: String? = null,
        /** What TalkBack reads for the progress bar ("25 % del presupuesto gastado"). */
        val progressDescription: String? = null,
    ) : WidgetModel
}

/**
 * Figures this old are marked "hace un rato" even with no failed refresh: twice the refresh job's
 * period, so a run that is merely late (WorkManager's flex, Doze) never shows it. A failed refresh
 * after the figures shows it at once ([WidgetSnapshot.refreshFailedAt]).
 */
val STALE_AFTER: Duration = RefreshScheduler.INTERVAL.multipliedBy(2)

private fun themeOf(name: String?): WidgetTheme = when (name) {
    "light" -> WidgetTheme.DAY
    "system" -> WidgetTheme.SYSTEM
    else -> WidgetTheme.NIGHT
}

/** [context] with its resources in [language] ("es", "en", "it" or "pt"). */
private fun localized(context: Context, language: String): Context {
    val configuration = Configuration(context.resources.configuration)
    configuration.setLocale(Locale.forLanguageTag(language))
    return context.createConfigurationContext(configuration)
}

/** A month's name, capitalized ("Octubre", "October"), as the app writes it (formatMonthName). */
private fun monthName(month: YearMonth, language: String): String {
    val locale = Locale.forLanguageTag(language)
    return month.month.getDisplayName(TextStyle.FULL_STANDALONE, locale)
        .replaceFirstChar { it.titlecase(locale) }
}

/**
 * What the widget says for [snapshot] at [now]: "this month" is read in the profile's zone (the
 * snapshot's), else in [zone] (the phone's), so figures of an earlier month are labelled by their
 * month, never "este mes".
 */
fun widgetModel(context: Context, snapshot: WidgetSnapshot?, now: Instant, zone: ZoneId): WidgetModel {
    val theme = themeOf(snapshot?.theme)
    val strings = snapshot?.locale?.let { localized(context, it) } ?: context
    if (snapshot == null || !snapshot.signedIn) {
        return WidgetModel.SignedOut(snapshot?.line ?: strings.getString(R.string.widget_signed_out), theme)
    }
    val language = snapshot.locale ?: Locale.getDefault().language.takeIf { it in AppLanguages.ALL } ?: "es"
    val month = try {
        YearMonth.parse(snapshot.month)
    } catch (_: java.time.format.DateTimeParseException) {
        return WidgetModel.SignedOut(strings.getString(R.string.widget_signed_out), theme)
    }
    val name = monthName(month, language)
    // In the middle of a sentence the month is lowercase except in English, as the app writes it (monthInSentence).
    val inSentence = if (language == "en") name else name.lowercase(Locale.forLanguageTag(language))
    val current = month == YearMonth.from(now.atZone(snapshot.zone(zone)))
    val budgets = snapshot.budgetTotal > 0
    val over = budgets && snapshot.remaining < 0
    val hidden = snapshot.hideAmount
    val label = when {
        // Hidden, nothing tells how the month goes: not "Te pasaste", not even "Te quedan".
        hidden -> if (current) strings.getString(R.string.widget_hidden_label) else name
        !budgets -> if (current) {
            strings.getString(R.string.widget_spent)
        } else {
            strings.getString(R.string.widget_spent_past, inSentence)
        }
        over -> if (current) {
            strings.getString(R.string.widget_over)
        } else {
            strings.getString(R.string.widget_over_past, inSentence)
        }
        else -> if (current) {
            strings.getString(R.string.widget_remaining)
        } else {
            strings.getString(R.string.widget_remaining_past, inSentence)
        }
    }
    val cents = if (budgets) kotlin.math.abs(snapshot.remaining) else snapshot.spent
    val amount = if (hidden) {
        strings.getString(R.string.widget_hidden)
    } else {
        formatMoney(cents, snapshot.currency, language)
    }
    val worried = !hidden && snapshot.mood == "worried"
    val progress = if (budgets && !hidden) {
        (snapshot.spent.toDouble() / snapshot.budgetTotal).coerceIn(0.0, 1.0).toFloat()
    } else {
        null
    }
    val updatedAt = snapshot.updatedAt
    val failedAt = snapshot.refreshFailedAt
    val stale = updatedAt == null ||
        Duration.between(updatedAt, now) >= STALE_AFTER ||
        (failedAt != null && failedAt.isAfter(updatedAt))
    return WidgetModel.Figures(
        label = label,
        amount = amount,
        progress = progress,
        tone = when {
            hidden -> Tone.GOOD
            over -> Tone.OVER
            worried -> Tone.NEAR
            else -> Tone.GOOD
        },
        month = name,
        mood = if (worried) Mood.WORRIED else Mood.HAPPY,
        stale = if (stale) strings.getString(R.string.widget_stale) else null,
        theme = theme,
        addLabel = strings.getString(R.string.widget_add),
        captureLabel = strings.getString(R.string.widget_capture),
        amountDescription = if (hidden) strings.getString(R.string.widget_amount_hidden) else null,
        progressDescription = progress?.let {
            strings.getString(R.string.widget_progress, kotlin.math.round(it * 100).toInt())
        },
    )
}
