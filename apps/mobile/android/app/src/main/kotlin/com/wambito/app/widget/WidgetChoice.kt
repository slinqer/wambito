package com.wambito.app.widget

import android.content.Context

/**
 * The widget's own "hide the amount" choice and the app's vibration switch, in the widget's
 * preferences (`HomeWidgetPreferences`), where the app (lib/home/widget_choice.dart) and the
 * widget's eye ([ToggleHideAmount]) both read and write them. Values `on` / `off`. Persistent names.
 */
object WidgetChoice {
    const val HIDE_AMOUNT_KEY = "wambito.widget.hideAmount"
    const val VIBRATION_KEY = "wambito.widget.vibration"

    /** The choice: its key, else the snapshot's (before the app copied it), else hidden. */
    fun hideAmount(context: Context): Boolean = hideAmount(context, WidgetSnapshot.read(context)?.hideAmount ?: true)

    /** The choice: its key, else [fallback] (the snapshot being drawn). */
    fun hideAmount(context: Context, fallback: Boolean): Boolean =
        when (WidgetSnapshot.preferences(context).getString(HIDE_AMOUNT_KEY, null)) {
            "on" -> true
            "off" -> false
            else -> fallback
        }

    /** Keeps [hidden] and puts it in the snapshot, the figures as they were. */
    fun setHideAmount(context: Context, hidden: Boolean) {
        val prefs = WidgetSnapshot.preferences(context)
        val edit = prefs.edit().putString(HIDE_AMOUNT_KEY, if (hidden) "on" else "off")
        WidgetSnapshot.read(context)?.let { edit.putString(WidgetSnapshot.KEY, it.copy(hideAmount = hidden).toJson()) }
        edit.commit()
    }

    /** Whether the widget may vibrate: on unless the app's switch said off. */
    fun vibrationOn(context: Context): Boolean =
        WidgetSnapshot.preferences(context).getString(VIBRATION_KEY, null) != "off"
}
