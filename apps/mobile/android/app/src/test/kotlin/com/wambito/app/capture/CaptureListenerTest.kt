package com.wambito.app.capture

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant

private class RecordingParser(
    override val source: CaptureSource,
    private val result: ParsedCapture?,
) : BankParser {
    var calls = 0

    override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? {
        calls++
        return result
    }
}

@RunWith(RobolectricTestRunner::class)
class CaptureListenerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val postedAt = Instant.parse("2026-11-04T12:30:15Z")
    private val revolut = CaptureSource.REVOLUT.packageName

    @Before
    fun setUp() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context, Configuration.Builder().build())
        CaptureQueue(context).clear()
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, false)
        CaptureSettings(context).setEnabled(CaptureSource.GOOGLE_WALLET, false)
    }

    @After
    fun tearDown() {
        BankParsers.parsers = emptyList()
        CaptureQueue(context).clear()
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, false)
        CaptureSettings(context).setEnabled(CaptureSource.GOOGLE_WALLET, false)
    }

    @Test
    fun `ignores packages not enabled`() {
        val parser = RecordingParser(CaptureSource.REVOLUT, sampleCapture())
        BankParsers.parsers = listOf(parser)

        // Known package, source not enabled.
        CaptureListener.handle(context, revolut, "title", "text", postedAt)
        // Unknown package.
        CaptureListener.handle(context, "com.example.other", "title", "text", postedAt)

        assertEquals(0, parser.calls)
        assertTrue(CaptureQueue(context).all().isEmpty())
    }

    @Test
    fun `queues a parsed capture and schedules sending`() {
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, true)
        val capture = sampleCapture()
        val parser = RecordingParser(CaptureSource.REVOLUT, capture)
        BankParsers.parsers = listOf(parser)

        CaptureListener.handle(context, revolut, "title", "text", postedAt)

        assertEquals(1, parser.calls)
        assertEquals(listOf(capture), CaptureQueue(context).all().map { it.capture })
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get()
        assertEquals(1, work.size)
        assertEquals(WorkInfo.State.ENQUEUED, work[0].state)
    }

    @Test
    fun `a preview account queues nothing and reads no text`() {
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, true)
        val parser = RecordingParser(CaptureSource.REVOLUT, sampleCapture())
        BankParsers.parsers = listOf(parser)
        com.wambito.app.account.AccountMode(context).value = "preview"

        CaptureListener.handle(context, revolut, "title", "text", postedAt)

        assertEquals(0, parser.calls)
        assertTrue(CaptureQueue(context).all().isEmpty())
    }

    @Test
    fun `drops unparsed`() {
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, true)
        BankParsers.parsers = listOf(RecordingParser(CaptureSource.REVOLUT, null))

        CaptureListener.handle(context, revolut, "title", "text", postedAt)

        assertTrue(CaptureQueue(context).all().isEmpty())
        assertTrue(WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get().isEmpty())
    }

    @Test
    fun `drops everything while there are no parsers`() {
        CaptureSettings(context).setEnabled(CaptureSource.REVOLUT, true)
        BankParsers.parsers = emptyList()

        CaptureListener.handle(context, revolut, "title", "text", postedAt)

        assertTrue(CaptureQueue(context).all().isEmpty())
    }

    @Test
    fun `settings keep the enabled sources by wire name`() {
        CaptureSettings(context).setEnabled(CaptureSource.GOOGLE_WALLET, true)

        assertEquals(setOf(CaptureSource.GOOGLE_WALLET), CaptureSettings(context).enabled())
        assertEquals(
            setOf("google_wallet"),
            context.getSharedPreferences("wambito.capture.sources", Context.MODE_PRIVATE)
                .getStringSet("enabled", null),
        )
    }
}
