package com.wambito.app.notices

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
class NoticeSchedulerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val now = Instant.parse("2026-10-22T11:00:00Z") // 06:00 in Bogota

    @Before
    fun setUp() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
    }

    @After
    fun tearDown() {
        NoticeSettings(context).clear()
    }

    private fun active(name: String) = WorkManager.getInstance(context)
        .getWorkInfosForUniqueWork(name).get().filter { !it.state.isFinished }

    @Test
    fun `Hoy vence is scheduled for 9 in the profile's zone, on a network`() {
        NoticeScheduler.scheduleDue(context, "America/Bogota", "es", now)

        val job = active(NoticeScheduler.DUE).single()
        assertEquals(Duration.ofHours(3).toMillis(), job.initialDelayMillis)
        assertEquals(NetworkType.CONNECTED, job.constraints.requiredNetworkType)
        val settings = NoticeSettings(context)
        assertTrue(settings.dueEnabled)
        assertEquals("America/Bogota", settings.zone)
        assertEquals("es", settings.language)
    }

    @Test
    fun `scheduling again at every app open keeps the job, unless the zone changed`() {
        NoticeScheduler.scheduleDue(context, "America/Bogota", "es", now)
        val first = active(NoticeScheduler.DUE).single().id

        NoticeScheduler.scheduleDue(context, "America/Bogota", "en", now)
        assertEquals(first, active(NoticeScheduler.DUE).single().id)
        assertEquals("the language is kept up to date", "en", NoticeSettings(context).language)

        NoticeScheduler.scheduleDue(context, "Asia/Tokyo", "en", now)
        val moved = active(NoticeScheduler.DUE).single()
        assertNotEquals(first, moved.id)
        // 11:00 UTC is 20:00 in Tokyo: 9:00 is 13 hours away.
        assertEquals(Duration.ofHours(13).toMillis(), moved.initialDelayMillis)
    }

    @Test
    fun `no zone from the app keeps the one known, else the phone's`() {
        NoticeScheduler.scheduleDue(context, "America/Bogota", "es", now)
        NoticeScheduler.scheduleDue(context, null, "es", now)
        assertEquals("America/Bogota", NoticeSettings(context).zone)
        assertEquals(1, active(NoticeScheduler.DUE).size)

        NoticeSettings(context).clear()
        NoticeScheduler.scheduleDue(context, null, "es", now)
        assertNull(NoticeSettings(context).zone)
        assertEquals(1, active(NoticeScheduler.DUE).size)
    }

    @Test
    fun `the switch off cancels it`() {
        NoticeScheduler.scheduleDue(context, "America/Bogota", "es", now)
        NoticeScheduler.cancelDue(context)
        assertTrue(active(NoticeScheduler.DUE).isEmpty())
        assertFalse(NoticeSettings(context).dueEnabled)
    }

    @Test
    fun `cancelling it, a sign-out included, forgets a preview account's due list`() {
        DueList.replace(context, "u1", listOf("2026-10-23" to listOf("Arriendo")))
        NoticeScheduler.cancelDue(context)
        assertNull(DueList.owner(context))
        assertTrue(DueList.namesOn(context, java.time.LocalDate.parse("2026-10-23")).isEmpty())
    }

    @Test
    fun `the guest warning is a one-time job 44 days ahead, replaced at every app open`() {
        NoticeScheduler.scheduleGuest(context, "es")
        val first = active(NoticeScheduler.GUEST).single()
        // 44, not 45: the server counts activity to the day (a session slides at most once a day), so
        // the last accepted request may count a day early there. At 44 the deletion is still at least
        // 15 days away when "Tus datos se borrarán en 15 días" shows.
        assertEquals(Duration.ofDays(44).toMillis(), first.initialDelayMillis)
        // It asks the server nothing, so it waits for no network: a phone offline on day 44 is warned.
        assertEquals(NetworkType.NOT_REQUIRED, first.constraints.requiredNetworkType)
        assertTrue(NoticeSettings(context).guestEnabled)

        NoticeScheduler.scheduleGuest(context, "es")
        val second = active(NoticeScheduler.GUEST).single()
        assertNotEquals(first.id, second.id)
        // The first one is gone (WorkManager drops a replaced job), so only one can ever fire.
        val old = WorkManager.getInstance(context).getWorkInfoById(first.id).get()
        assertTrue(old == null || old.state == WorkInfo.State.CANCELLED)
    }

    @Test
    fun `signing out, claiming an email or the switch cancels the guest warning`() {
        NoticeScheduler.scheduleGuest(context, "es")
        NoticeScheduler.cancelGuest(context)
        assertTrue(active(NoticeScheduler.GUEST).isEmpty())
        assertFalse(NoticeSettings(context).guestEnabled)
    }

    private fun shade() = shadowOf(context.getSystemService(NotificationManager::class.java))

    /** Both notices on the shade, as the jobs post them. */
    private fun postBoth() {
        val poster = NoticePoster(context)
        assertTrue(poster.postDue(listOf("Arriendo", "Spotify"), "es"))
        assertTrue(poster.postGuestWarning("es"))
        assertEquals(2, shade().allNotifications.size)
    }

    @Test
    fun `cancelling Hoy vence also removes the one on the shade, and only that one`() {
        postBoth()
        NoticeScheduler.cancelDue(context)
        assertNull(shade().getNotification(NoticePoster.DUE_ID))
        assertTrue(shade().getNotification(NoticePoster.GUEST_ID) != null)
    }

    @Test
    fun `cancelling the guest warning also removes the one on the shade, and only that one`() {
        postBoth()
        NoticeScheduler.cancelGuest(context)
        assertNull(shade().getNotification(NoticePoster.GUEST_ID))
        assertTrue(shade().getNotification(NoticePoster.DUE_ID) != null)
    }

    @Test
    fun `signing out leaves no notice on the shade`() {
        postBoth()
        NoticeScheduler.cancelAll(context)
        assertTrue(shade().allNotifications.isEmpty())
    }

    @Test
    fun `cancelling both leaves nothing scheduled`() {
        NoticeScheduler.scheduleDue(context, "America/Bogota", "es", now)
        NoticeScheduler.scheduleGuest(context, "es")
        NoticeScheduler.cancelAll(context)
        assertTrue(active(NoticeScheduler.DUE).isEmpty())
        assertTrue(active(NoticeScheduler.GUEST).isEmpty())
    }
}
