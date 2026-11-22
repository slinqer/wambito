package com.wambito.app.account

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import com.wambito.app.background.SyncScheduler
import org.junit.Before
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

    @Before
    fun setUp() = WorkManagerTestInitHelper.initializeTestWorkManager(context)

    private fun live(name: String): Int = WorkManager.getInstance(context).getWorkInfosForUniqueWork(name).get()
        .count { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING }

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

    @Test
    fun `the owner is kept under wambito dot encryption dot owner and cleared with the mode`() {
        val mode = AccountMode(context)
        assertNull(mode.owner)
        mode.write("preview", "u1")
        assertEquals("u1", AccountMode(context).owner)
        assertEquals("preview", AccountMode(context).value)
        assertEquals(
            "u1",
            context.getSharedPreferences("wambito.encryption", Context.MODE_PRIVATE)
                .getString("wambito.encryption.owner", null),
        )
        mode.write(null, null)
        assertNull(AccountMode(context).owner)
        assertNull(AccountMode(context).value)
        mode.write("preview", "u1")
        mode.value = null
        assertNull(AccountMode(context).owner)
    }

    @Test
    fun `preview with an owner schedules the periodic sync, plain or none cancels both`() {
        val mode = AccountMode(context)
        mode.write("preview", "u1")
        assertEquals(1, live(SyncScheduler.PERIODIC))
        SyncScheduler.now(context)
        assertEquals(1, live(SyncScheduler.NOW))

        mode.write("plain", null)
        assertEquals(0, live(SyncScheduler.PERIODIC))
        assertEquals(0, live(SyncScheduler.NOW))

        mode.write("preview", "u1")
        SyncScheduler.now(context)
        mode.write(null, null)
        assertEquals(0, live(SyncScheduler.PERIODIC))
        assertEquals(0, live(SyncScheduler.NOW))
    }

    @Test
    fun `an unknown mode leaves the sync as it was and preview twice keeps one periodic work`() {
        val mode = AccountMode(context)
        mode.write("preview", "u1")
        mode.write("unknown", "u1")
        assertEquals(1, live(SyncScheduler.PERIODIC))
        mode.write("preview", "u1")
        assertEquals(1, live(SyncScheduler.PERIODIC))
    }
}
