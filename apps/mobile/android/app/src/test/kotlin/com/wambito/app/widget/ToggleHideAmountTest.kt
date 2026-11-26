package com.wambito.app.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.wambito.app.haptics.Blinds
import com.wambito.app.haptics.HapticSpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The widget's eye: one tap flips its own hide choice, rewrites the snapshot, plays the blinds. */
@RunWith(RobolectricTestRunner::class)
class ToggleHideAmountTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val prefs get() = WidgetSnapshot.preferences(context)
    private val played = mutableListOf<HapticSpec>()

    @Before
    fun start() {
        prefs.edit().clear()
            .putString(
                WidgetSnapshot.KEY,
                WidgetSnapshot(signedIn = true, spent = 410, currency = "EUR", month = "2026-11").toJson(),
            )
            .putString(WidgetChoice.HIDE_AMOUNT_KEY, "off")
            .commit()
        played.clear()
    }

    @Test
    fun `a tap hides, with the blind coming down`() {
        assertTrue(ToggleHideAmount.toggle(context) { played += it })
        assertTrue(WidgetChoice.hideAmount(context))
        assertTrue(WidgetSnapshot.read(context)!!.hideAmount)
        assertEquals(listOf(Blinds.HIDDEN), played)
    }

    @Test
    fun `a second tap shows, with the blind going up`() {
        ToggleHideAmount.toggle(context) { played += it }
        assertFalse(ToggleHideAmount.toggle(context) { played += it })
        assertFalse(WidgetSnapshot.read(context)!!.hideAmount)
        assertEquals(listOf(Blinds.HIDDEN, Blinds.SHOWN), played)
    }

    @Test
    fun `with the app's vibration switch off it flips but plays nothing`() {
        prefs.edit().putString(WidgetChoice.VIBRATION_KEY, "off").commit()
        assertTrue(ToggleHideAmount.toggle(context) { played += it })
        assertTrue(played.isEmpty())
    }
}
