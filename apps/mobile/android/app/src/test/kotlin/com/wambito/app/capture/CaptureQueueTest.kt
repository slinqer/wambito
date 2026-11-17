package com.wambito.app.capture

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant

internal fun sampleCapture(
    merchant: String = "Mercadona",
    amountCents: Long = 1250,
    kind: Kind = Kind.EXPENSE,
    source: CaptureSource = CaptureSource.REVOLUT,
) = ParsedCapture(kind, amountCents, "EUR", merchant, Instant.parse("2026-11-04T12:30:15.123Z"), source)

@RunWith(RobolectricTestRunner::class)
class CaptureQueueTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @After
    fun tearDown() = CaptureQueue(context).clear()

    @Test
    fun `a new instance finds what an earlier one queued, in order`() {
        val first = CaptureQueue(context).add(sampleCapture("Mercadona"))
        val second = CaptureQueue(context).add(sampleCapture("Café", source = CaptureSource.GOOGLE_WALLET))

        val items = CaptureQueue(context).all()
        assertEquals(listOf(first, second), items)
        assertNotEquals(first.key, second.key)
    }

    @Test
    fun `remove takes one item out and keeps the others`() {
        val queue = CaptureQueue(context)
        val first = queue.add(sampleCapture("Mercadona"))
        val second = queue.add(sampleCapture("Café"))

        queue.remove(first.key)

        assertEquals(listOf(second), CaptureQueue(context).all())
    }

    @Test
    fun `an income and a wallet source round-trip`() {
        val item = CaptureQueue(context).add(
            sampleCapture("Nómina", 250000, Kind.INCOME, CaptureSource.GOOGLE_WALLET),
        )
        assertEquals(item, CaptureQueue(context).all().single())
    }

    @Test
    fun `only the capture's own fields and the key are stored`() {
        CaptureQueue(context).adopt("user-a")
        CaptureQueue(context).add(sampleCapture())
        val raw = context.getSharedPreferences("wambito.capture.queue", Context.MODE_PRIVATE).getString("items", null)!!
        val entry = org.json.JSONObject(org.json.JSONArray(raw).getJSONObject(0).toString())
        val keys = entry.keys().asSequence().toSet()
        assertEquals(setOf("key", "user", "kind", "amount", "currency", "merchant", "capturedAt", "source"), keys)
        assertTrue(raw.contains("\"kind\":\"expense\""))
    }

    @Test
    fun `an entry that cannot be read is skipped`() {
        context.getSharedPreferences("wambito.capture.queue", Context.MODE_PRIVATE).edit()
            .putString("items", """[{"key":"a","kind":"nope"}]""").commit()
        assertTrue(CaptureQueue(context).all().isEmpty())
    }

    @Test
    fun `a capture is tagged with the account the queue belongs to`() {
        val queue = CaptureQueue(context)
        assertEquals(null, queue.add(sampleCapture("Before")).userId)
        queue.adopt("user-a")
        val tagged = queue.add(sampleCapture("Mercadona"))
        assertEquals("user-a", tagged.userId)
        assertEquals("user-a", CaptureQueue(context).owner())
        assertEquals(tagged, CaptureQueue(context).all().last())
    }

    @Test
    fun `adopting another account drops the captures of the one before, and those of nobody`() {
        val queue = CaptureQueue(context)
        queue.add(sampleCapture("Nobody's"))
        queue.adopt("user-a")
        queue.add(sampleCapture("A's"))

        queue.adopt("user-b")

        assertTrue(queue.all().isEmpty())
        assertEquals("user-b", queue.owner())
    }

    @Test
    fun `adopting the same account again keeps its captures`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        val mine = queue.add(sampleCapture("A's"))
        queue.adopt("user-a")
        assertEquals(listOf(mine), queue.all())
    }

    @Test
    fun `an entry stored before captures were tagged is nobody's, and dropped at the next adopt`() {
        context.getSharedPreferences("wambito.capture.queue", Context.MODE_PRIVATE).edit()
            .putString(
                "items",
                """[{"key":"old","kind":"expense","amount":1250,"currency":"EUR","merchant":"Old",""" +
                    """"capturedAt":"2026-11-04T12:30:15.123Z","source":"revolut"}]""",
            ).commit()
        val queue = CaptureQueue(context)
        assertEquals(null, queue.all().single().userId)
        queue.adopt("user-a")
        assertTrue(queue.all().isEmpty())
    }

    @Test
    fun `clear forgets the captures and whose they were`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        queue.add(sampleCapture())
        queue.clear()
        assertTrue(queue.all().isEmpty())
        assertEquals(null, queue.owner())
        assertEquals(null, queue.add(sampleCapture()).userId)
    }

    @Test
    fun `sources are found by package and by wire name`() {
        assertEquals(CaptureSource.REVOLUT, CaptureSource.forPackage("com.revolut.revolut"))
        assertEquals(CaptureSource.GOOGLE_WALLET, CaptureSource.forPackage("com.google.android.apps.walletnfcrel"))
        assertEquals(null, CaptureSource.forPackage("com.example.other"))
    }

    @Test
    fun `confirms are kept without repeats, with their own store, and ack takes them out`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        val item = queue.add(sampleCapture())
        queue.addConfirm("t-1")
        queue.addConfirm("t-2")
        queue.addConfirm("t-1")
        assertEquals(listOf("t-1", "t-2"), CaptureQueue(context).confirms())

        queue.ack(listOf(item.key), listOf("t-1"))

        assertTrue(queue.all().isEmpty())
        assertEquals(listOf("t-2"), queue.confirms())
    }

    @Test
    fun `confirms of another account are dropped at adopt and all of them at clear`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        queue.addConfirm("t-1")
        queue.adopt("user-a")
        assertEquals(listOf("t-1"), queue.confirms())
        queue.adopt("user-b")
        assertTrue(queue.confirms().isEmpty())
        queue.addConfirm("t-2")
        queue.clear()
        assertTrue(queue.confirms().isEmpty())
    }

    @Test
    fun `refuse counts per item and drops one at the limit, leaving the others`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        val a = queue.add(sampleCapture("A"))
        val b = queue.add(sampleCapture("B"))
        repeat(2) { assertTrue(queue.refuse(listOf(a.key), 3).isEmpty()) }
        assertTrue(queue.refuse(listOf(b.key), 3).isEmpty())
        assertEquals(listOf(a.key), queue.refuse(listOf(a.key), 3))
        assertEquals(listOf(b.key), queue.all().map { it.key })
        // The count is stored apart: the item keeps only its own fields and the key.
        val raw = context.getSharedPreferences("wambito.capture.queue", Context.MODE_PRIVATE).getString("items", null)!!
        assertTrue(!raw.contains("refus"))
    }

    @Test
    fun `a key acked or removed forgets its refusals`() {
        val queue = CaptureQueue(context)
        queue.adopt("user-a")
        val a = queue.add(sampleCapture("A"))
        queue.refuse(listOf(a.key), 2)
        queue.ack(listOf(a.key), emptyList())
        val again = queue.add(sampleCapture("A"))
        assertTrue(queue.refuse(listOf(again.key), 2).isEmpty())
    }
}
