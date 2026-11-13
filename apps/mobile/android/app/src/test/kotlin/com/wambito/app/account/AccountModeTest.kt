package com.wambito.app.account

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class AccountModeTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `only plain, or nothing written, lets a job reach the API`() {
        assertTrue(AccountMode.allowsApi(null))
        assertTrue(AccountMode.allowsApi("plain"))
        assertFalse(AccountMode.allowsApi("preview"))
        assertFalse(AccountMode.allowsApi("unknown"))
        assertFalse(AccountMode.allowsApi("anything else"))
    }

    @Test
    fun `the mode is kept under wambito dot encryption dot mode and cleared with null`() {
        val mode = AccountMode(context)
        assertNull(mode.value)
        assertTrue(mode.allowsApi())
        mode.value = "preview"
        assertEquals("preview", AccountMode(context).value)
        assertTrue(mode.isPreview())
        assertFalse(mode.allowsApi())
        assertEquals(
            "preview",
            context.getSharedPreferences("wambito.encryption", Context.MODE_PRIVATE)
                .getString("wambito.encryption.mode", null),
        )
        mode.value = null
        assertNull(AccountMode(context).value)
        assertFalse(mode.isPreview())
    }
}
