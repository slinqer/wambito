package com.wambito.app.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WidgetChoiceTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val prefs get() = WidgetSnapshot.preferences(context)

    private fun store(snapshot: WidgetSnapshot) {
        prefs.edit().putString(WidgetSnapshot.KEY, snapshot.toJson()).commit()
    }

    @Before
    fun clean() {
        prefs.edit().clear().commit()
    }

    @Test
    fun `the keys are the app's`() {
        assertEquals("wambito.widget.hideAmount", WidgetChoice.HIDE_AMOUNT_KEY)
        assertEquals("wambito.widget.vibration", WidgetChoice.VIBRATION_KEY)
    }

    @Test
    fun `the widget's own key wins over the snapshot`() {
        store(WidgetSnapshot(signedIn = false, hideAmount = false))
        prefs.edit().putString(WidgetChoice.HIDE_AMOUNT_KEY, "on").commit()
        assertTrue(WidgetChoice.hideAmount(context))
        prefs.edit().putString(WidgetChoice.HIDE_AMOUNT_KEY, "off").commit()
        assertFalse(WidgetChoice.hideAmount(context))
    }

    @Test
    fun `with no key yet the snapshot says, and with nothing at all it hides`() {
        store(WidgetSnapshot(signedIn = false, hideAmount = false))
        assertFalse(WidgetChoice.hideAmount(context))
        prefs.edit().clear().commit()
        assertTrue(WidgetChoice.hideAmount(context))
    }

    @Test
    fun `setting it writes the key and the snapshot, figures untouched`() {
        store(WidgetSnapshot(signedIn = true, spent = 410, currency = "EUR", month = "2026-11", hideAmount = false))
        WidgetChoice.setHideAmount(context, true)
        assertEquals("on", prefs.getString(WidgetChoice.HIDE_AMOUNT_KEY, null))
        val after = WidgetSnapshot.read(context)!!
        assertTrue(after.hideAmount)
        assertEquals(410L, after.spent)
    }

    @Test
    fun `vibration is on unless the app said off`() {
        assertTrue(WidgetChoice.vibrationOn(context))
        prefs.edit().putString(WidgetChoice.VIBRATION_KEY, "off").commit()
        assertFalse(WidgetChoice.vibrationOn(context))
    }
}
