package com.wambito.app.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import com.wambito.app.haptics.Blinds
import com.wambito.app.haptics.HapticSpec
import com.wambito.app.haptics.Haptics

/**
 * The widget's eye: hides or shows the widget's amount without opening the app (the app's eye on
 * home is another choice). Flips [WidgetChoice], plays the blinds unless the app's vibration
 * switch is off, and redraws both widget sizes.
 */
class ToggleHideAmount : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        toggle(context)
        WidgetUpdates.redrawAll(context)
    }

    companion object {
        /** Flips the choice and plays its blind with [play]; returns whether the amount is now hidden. */
        fun toggle(context: Context, play: (HapticSpec) -> Unit = { Haptics.play(context, it) }): Boolean {
            val hidden = !WidgetChoice.hideAmount(context)
            WidgetChoice.setHideAmount(context, hidden)
            if (WidgetChoice.vibrationOn(context)) play(if (hidden) Blinds.HIDDEN else Blinds.SHOWN)
            return hidden
        }
    }
}
