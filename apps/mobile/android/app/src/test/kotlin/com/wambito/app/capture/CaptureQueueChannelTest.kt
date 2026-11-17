package com.wambito.app.capture

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class CaptureQueueChannelTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After
    fun tearDown() = CaptureQueue(context).clear()

    private fun queueFor(userId: String, vararg merchants: String): List<QueuedCapture> {
        val queue = CaptureQueue(context)
        queue.adopt(userId)
        return merchants.map { queue.add(sampleCapture(it)) }
    }

    @Test
    fun `takeQueued answers the account's captures with their keys and removes nothing`() {
        val added = queueFor("u1", "Mercadona", "Café")
        val answer = CaptureQueueChannel.take(context, "u1")

        val captures = answer["captures"] as List<*>
        assertEquals(added.map { it.key }, captures.map { (it as Map<*, *>)["key"] })
        val first = captures[0] as Map<*, *>
        assertEquals("Mercadona", first["merchant"])
        assertEquals(added[0].capture.amountCents, first["amount"])
        assertEquals(emptyList<String>(), answer["confirms"])
        assertEquals(2, CaptureQueue(context).all().size)
    }

    @Test
    fun `takeQueued never hands over another account's captures`() {
        queueFor("u1", "Mercadona")
        val answer = CaptureQueueChannel.take(context, "u2")
        assertTrue((answer["captures"] as List<*>).isEmpty())
        assertEquals(1, CaptureQueue(context).all().size)
    }

    @Test
    fun `ackQueued removes the named captures only`() {
        val added = queueFor("u1", "Mercadona", "Café", "Taxi")
        CaptureQueueChannel.ack(context, listOf(added[0].key, added[2].key, "unknown"), emptyList())
        assertEquals(listOf(added[1].key), CaptureQueue(context).all().map { it.key })
    }

    @Test
    fun `a capture not acked stays queued, as after a failed run`() {
        val added = queueFor("u1", "Mercadona")
        CaptureQueueChannel.take(context, "u1")
        CaptureQueueChannel.ack(context, emptyList(), emptyList())
        assertEquals(added.map { it.key }, CaptureQueue(context).all().map { it.key })
    }

    @Test
    fun `takeQueued hands over the confirms and ackQueued removes the ones it names`() {
        queueFor("u1", "Mercadona")
        val queue = CaptureQueue(context)
        queue.addConfirm("t-1")
        queue.addConfirm("t-2")
        assertEquals(listOf("t-1", "t-2"), CaptureQueueChannel.take(context, "u1")["confirms"])

        CaptureQueueChannel.ack(context, emptyList(), listOf("t-1"))

        assertEquals(listOf("t-2"), queue.confirms())
        assertEquals(1, queue.all().size)
    }
}
