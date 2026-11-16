package com.wambito.app.background

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import com.wambito.app.account.AccountMode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLooper
import java.nio.ByteBuffer

/** A messenger that records what the app's engine is sent. */
private class RecordingMessenger : BinaryMessenger {
    val sent = mutableListOf<Pair<String, String>>()

    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        message?.rewind()
        val call: MethodCall = StandardMethodCodec.INSTANCE.decodeMethodCall(message!!)
        sent += channel to call.method
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
}

@RunWith(RobolectricTestRunner::class)
class SyncWorkerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val calls = mutableListOf<String>()
    private var answer = HeadlessResult("done", emptyList())

    @Before
    fun setUp() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        HeadlessHooks.runner = { _, entrypoint ->
            calls += entrypoint
            answer
        }
    }

    @After
    fun tearDown() {
        HeadlessHooks.runner = null
        BackgroundChannel.app = null
        AccountMode(context).write(null, null)
    }

    private fun run(attempt: Int = 0): ListenableWorker.Result = runBlocking {
        TestListenableWorkerBuilder<SyncWorker>(context).setRunAttemptCount(attempt).build().doWork()
    }

    private fun outcomeOf(result: ListenableWorker.Result) =
        (result as ListenableWorker.Result.Success).outputData.getString(SYNC_OUTCOME)

    @Test
    fun `plain runs nothing and says not preview`() {
        AccountMode(context).write("plain", null)
        assertEquals("not preview", outcomeOf(run()))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun `nothing written yet runs nothing either`() {
        assertEquals("not preview", outcomeOf(run()))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun `preview starts syncMain`() {
        AccountMode(context).write("preview", "u1")
        answer = HeadlessResult("done", emptyList())
        assertEquals("done", outcomeOf(run()))
        assertEquals(listOf("syncMain"), calls)
    }

    @Test
    fun `failed retries until the third retry, then gives up with success`() {
        AccountMode(context).write("preview", "u1")
        answer = HeadlessResult("failed", emptyList())
        assertEquals(ListenableWorker.Result.retry(), run(0))
        assertEquals(ListenableWorker.Result.retry(), run(2))
        assertEquals("gave up", outcomeOf(run(3)))
    }

    @Test
    fun `busy and timeout are retried, signed out and locked are not`() {
        AccountMode(context).write("preview", "u1")
        for (outcome in listOf("busy", "timeout")) {
            answer = HeadlessResult(outcome, emptyList())
            assertEquals(ListenableWorker.Result.retry(), run(0))
        }
        for (outcome in listOf("signedOut", "locked", "notPreview")) {
            answer = HeadlessResult(outcome, emptyList())
            assertEquals(outcome, outcomeOf(run(0)))
        }
    }

    @Test
    fun `changed tells the app's engine when it is alive`() {
        AccountMode(context).write("preview", "u1")
        val messenger = RecordingMessenger()
        BackgroundChannel.app = BackgroundChannel(messenger)
        answer = HeadlessResult("changed", emptyList())
        assertEquals("changed", outcomeOf(run()))
        ShadowLooper.idleMainLooper()
        assertEquals(listOf("wambito/background" to "vaultChanged"), messenger.sent)
    }

    @Test
    fun `done tells nobody and changed with no app engine is fine`() {
        AccountMode(context).write("preview", "u1")
        val messenger = RecordingMessenger()
        BackgroundChannel.app = BackgroundChannel(messenger)
        answer = HeadlessResult("done", emptyList())
        run()
        ShadowLooper.idleMainLooper()
        assertTrue(messenger.sent.isEmpty())

        BackgroundChannel.app = null
        answer = HeadlessResult("changed", emptyList())
        assertEquals("changed", outcomeOf(run()))
    }
}
