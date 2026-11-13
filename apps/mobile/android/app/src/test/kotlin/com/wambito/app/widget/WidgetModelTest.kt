package com.wambito.app.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId

/** What the widget says for each state (spec section 7.1), before it is drawn. */
@RunWith(RobolectricTestRunner::class)
class WidgetModelTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val zone = ZoneId.of("America/Bogota")
    private val now = Instant.parse("2026-10-22T20:00:00Z")
    private val nbsp = "\u00a0"

    private fun snapshot(
        remaining: Long = 150000000,
        spent: Long = 50000000,
        budgetTotal: Long = 200000000,
        currency: String = "COP",
        locale: String? = "es",
        month: String = "2026-10",
        mood: String = "happy",
        updatedAt: Instant = now.minusSeconds(60),
        hideAmount: Boolean = false,
        theme: String = "dark",
        timezone: String? = null,
    ) = WidgetSnapshot(
        signedIn = true,
        timezone = timezone,
        remaining = remaining,
        spent = spent,
        budgetTotal = budgetTotal,
        currency = currency,
        locale = locale,
        month = month,
        mood = mood,
        updatedAt = updatedAt,
        hideAmount = hideAmount,
        theme = theme,
    )

    private fun figures(snapshot: WidgetSnapshot?) =
        widgetModel(context, snapshot, now, zone) as WidgetModel.Figures

    @Test
    fun `signed in with budgets it says what is left, with the month and its progress`() {
        val model = figures(snapshot())
        assertEquals("Te quedan", model.label)
        assertEquals("$1.500.000", model.amount)
        assertEquals(0.25f, model.progress!!, 0.0001f)
        assertEquals(Tone.GOOD, model.tone)
        assertEquals("Octubre", model.month)
        assertEquals(Mood.HAPPY, model.mood)
        assertNull(model.stale)
    }

    @Test
    fun `over the budgets it says by how much, in the over colour`() {
        val model = figures(snapshot(remaining = -50000000, spent = 250000000))
        assertEquals("Te pasaste", model.label)
        assertEquals("$500.000", model.amount)
        assertEquals(1f, model.progress!!, 0.0001f)
        assertEquals(Tone.OVER, model.tone)
    }

    @Test
    fun `a category near its limit makes Wambi worried`() {
        val model = figures(snapshot(mood = "worried"))
        assertEquals(Mood.WORRIED, model.mood)
        assertEquals(Tone.NEAR, model.tone)
    }

    @Test
    fun `without budgets it says what was spent this month, with no progress`() {
        val model = figures(snapshot(remaining = -4200000, spent = 4200000, budgetTotal = 0))
        assertEquals("Gastado este mes", model.label)
        assertEquals("$42.000", model.amount)
        assertNull(model.progress)
    }

    @Test
    @Config(qualifiers = "es") // a Spanish phone: with no snapshot, the phone's language
    fun `signed out, or nothing written yet, or an older snapshot, it asks to open Wambito`() {
        val signedOut = WidgetSnapshot(signedIn = false, locale = "es")
        for (snapshot in listOf(signedOut, null, WidgetSnapshot.parse("""{"v":1,"amount":"$1"}"""))) {
            val model = widgetModel(context, snapshot, now, zone)
            assertTrue("$snapshot", model is WidgetModel.SignedOut)
            assertEquals("Abre Wambito para empezar", (model as WidgetModel.SignedOut).message)
        }
    }

    @Test
    fun `a signed-out snapshot with a line says that line, with no figure`() {
        val json = """{"v":3,"signedIn":false,"locale":"es","theme":"dark","hideAmount":false,"line":"Próximamente con cifrado"}"""
        val parsed = WidgetSnapshot.parse(json)!!
        assertEquals("Próximamente con cifrado", parsed.line)
        val model = widgetModel(context, parsed, now, zone)
        assertEquals("Próximamente con cifrado", (model as WidgetModel.SignedOut).message)
        // It survives a write and a read, and a signed-in snapshot never carries one.
        assertEquals("Próximamente con cifrado", WidgetSnapshot.parse(parsed.toJson())!!.line)
        assertNull(WidgetSnapshot.parse("""{"v":3,"signedIn":false,"line":""}""")!!.line)
        assertNull(snapshot().copy(line = "x").toJson().let { WidgetSnapshot.parse(it)!!.line })
    }

    @Test
    fun `hace un rato only after a refresh failed, or after twice the refresh period`() {
        // A late run on a working connection is not "a while ago".
        assertNull(figures(snapshot(updatedAt = now.minusSeconds(4 * 3600))).stale)
        assertEquals("hace un rato", figures(snapshot(updatedAt = now.minusSeconds(6 * 3600))).stale)
        // A refresh that failed after these figures were fetched: offline.
        val failed = snapshot(updatedAt = now.minusSeconds(3600)).copy(refreshFailedAt = now.minusSeconds(60))
        assertEquals("hace un rato", figures(failed).stale)
        // A failure before the figures came (the app wrote newer ones since) says nothing.
        val since = snapshot(updatedAt = now.minusSeconds(60)).copy(refreshFailedAt = now.minusSeconds(3600))
        assertNull(figures(since).stale)
    }

    @Test
    fun `the hidden amount tells nothing about the money - dots, a neutral label, no bar, no worry`() {
        for (hidden in listOf(
            snapshot(hideAmount = true),
            snapshot(hideAmount = true, remaining = -50000000, spent = 250000000),
            snapshot(hideAmount = true, mood = "worried"),
        )) {
            val model = figures(hidden)
            assertEquals("••••", model.amount)
            assertEquals("Este mes", model.label)
            assertNull(model.progress)
            assertEquals(Tone.GOOD, model.tone)
            assertEquals(Mood.HAPPY, model.mood)
            assertEquals("Monto oculto", model.amountDescription)
            assertNull(model.progressDescription)
        }
        assertEquals("Septiembre", figures(snapshot(hideAmount = true, month = "2026-09")).label)
        assertEquals("This month", figures(snapshot(hideAmount = true, locale = "en")).label)
        assertEquals("Amount hidden", figures(snapshot(hideAmount = true, locale = "en")).amountDescription)
    }

    @Test
    fun `TalkBack reads the amount as it is shown, and the bar as a percentage`() {
        val model = figures(snapshot())
        assertNull(model.amountDescription)
        assertEquals("25 % del presupuesto gastado", model.progressDescription)
        assertEquals("25% of the budget spent", figures(snapshot(locale = "en")).progressDescription)
        assertNull(figures(snapshot(budgetTotal = 0)).progressDescription)
    }

    @Test
    fun `in English, words and amounts follow the snapshot's language`() {
        val model = figures(snapshot(locale = "en"))
        assertEquals("Left", model.label)
        assertEquals("COP 1,500,000", model.amount)
        assertEquals("October", model.month)
        val signedOut = widgetModel(context, WidgetSnapshot(signedIn = false, locale = "en"), now, zone)
        assertEquals("Open Wambito to get started", (signedOut as WidgetModel.SignedOut).message)
    }

    @Test
    fun `in Italian and Portuguese, words, months and amounts follow the snapshot's language`() {
        val italian = figures(snapshot(locale = "it", currency = "EUR"))
        assertEquals("Ti restano", italian.label)
        assertEquals("Ottobre", italian.month)
        assertEquals("1.500.000,00${nbsp}€", italian.amount)
        val portuguese = figures(snapshot(locale = "pt", currency = "EUR"))
        assertEquals("Restam-te", portuguese.label)
        assertEquals("Outubro", portuguese.month)
        assertEquals("1${nbsp}500${nbsp}000,00${nbsp}€", portuguese.amount)
        assertEquals("25% del budget speso", figures(snapshot(locale = "it")).progressDescription)
        assertEquals("25% do orçamento gasto", figures(snapshot(locale = "pt")).progressDescription)
        val signedOut = widgetModel(context, WidgetSnapshot(signedIn = false, locale = "pt"), now, zone)
        assertEquals("Abre Wambito para começar", (signedOut as WidgetModel.SignedOut).message)
        assertEquals("Hai sforato in settembre", figures(snapshot(locale = "it", month = "2026-09", remaining = -1)).label)
    }

    @Test
    fun `an earlier month is lowercase mid-sentence, except in English, and capitalized as a label`() {
        assertEquals("Ti sono rimasti in settembre", figures(snapshot(locale = "it", month = "2026-09")).label)
        assertEquals("Passaste do limite em setembro", figures(snapshot(locale = "pt", month = "2026-09", remaining = -1)).label)
        assertEquals("Left in September", figures(snapshot(locale = "en", month = "2026-09")).label)
        assertEquals("Settembre", figures(snapshot(locale = "it", month = "2026-09")).month)
    }

    @Test
    fun `the snapshot keeps the four languages and drops any other`() {
        for (language in listOf("es", "en", "it", "pt")) {
            val json = """{"v":3,"signedIn":false,"locale":"$language"}"""
            assertEquals(language, WidgetSnapshot.parse(json)!!.locale)
        }
        assertNull(WidgetSnapshot.parse("""{"v":3,"signedIn":false,"locale":"fr"}""")!!.locale)
    }

    @Test
    fun `figures of an earlier month never say this month`() {
        assertEquals("Te quedaron en septiembre", figures(snapshot(month = "2026-09")).label)
        assertEquals("Te pasaste en septiembre", figures(snapshot(month = "2026-09", remaining = -1)).label)
        assertEquals(
            "Gastado en septiembre",
            figures(snapshot(month = "2026-09", budgetTotal = 0)).label,
        )
    }

    @Test
    fun `the month changes at midnight in the phone's zone`() {
        // 2026-11-01 03:00 UTC is still October 31 in Bogotá.
        val model = widgetModel(context, snapshot(), Instant.parse("2026-11-01T03:00:00Z"), zone)
        assertEquals("Te quedan", (model as WidgetModel.Figures).label)
    }

    @Test
    fun `this month is the profile's month, in its zone, whatever the phone's zone`() {
        // 2026-11-01 03:00 UTC: still October 31 in Bogotá, already November 1 in Madrid.
        val at = Instant.parse("2026-11-01T03:00:00Z")
        val madrid = ZoneId.of("Europe/Madrid")
        val bogotaProfile = widgetModel(context, snapshot(timezone = "America/Bogota"), at, madrid)
        assertEquals("Te quedan", (bogotaProfile as WidgetModel.Figures).label)
        val madridProfile = widgetModel(context, snapshot(timezone = "Europe/Madrid"), at, zone)
        assertEquals("Te quedaron en octubre", (madridProfile as WidgetModel.Figures).label)
        // A zone that is not one falls back to the phone's.
        val unknown = widgetModel(context, snapshot(timezone = "Not/AZone"), at, zone)
        assertEquals("Te quedan", (unknown as WidgetModel.Figures).label)
    }

    @Test
    fun `the snapshot's zone is the profile's, or the phone's without one`() {
        assertEquals(ZoneId.of("Asia/Tokyo"), snapshot(timezone = "Asia/Tokyo").zone(zone))
        assertEquals(zone, snapshot().zone(zone))
        assertEquals(zone, snapshot(timezone = "+05:00:00:00").zone(zone))
    }

    @Test
    fun `the theme is the app's choice, night when none`() {
        assertEquals(WidgetTheme.NIGHT, widgetModel(context, snapshot(theme = "dark"), now, zone).theme)
        assertEquals(WidgetTheme.DAY, widgetModel(context, snapshot(theme = "light"), now, zone).theme)
        assertEquals(WidgetTheme.SYSTEM, widgetModel(context, snapshot(theme = "system"), now, zone).theme)
        assertEquals(WidgetTheme.NIGHT, widgetModel(context, null, now, zone).theme)
        val signedOut = WidgetSnapshot(signedIn = false, theme = "light")
        assertEquals(WidgetTheme.DAY, widgetModel(context, signedOut, now, zone).theme)
    }

    @Test
    fun `the snapshot reads back what it wrote, and a signed-out one keeps no figure`() {
        val written = snapshot(updatedAt = Instant.parse("2026-10-22T15:30:00Z"), timezone = "America/Bogota")
        assertEquals(written, WidgetSnapshot.parse(written.toJson()))
        assertEquals("America/Bogota", org.json.JSONObject(written.toJson()).getString("timezone"))
        assertEquals(3, org.json.JSONObject(written.toJson()).getInt("v"))
        val signedOut = WidgetSnapshot.parse(
            """{"v":3,"signedIn":false,"hideAmount":true,"theme":"light","locale":"en"}""",
        )
        assertEquals(WidgetSnapshot(signedIn = false, hideAmount = true, theme = "light", locale = "en"), signedOut)
        // Signed in but missing a figure: never drawn as figures.
        assertEquals(false, WidgetSnapshot.parse("""{"v":3,"signedIn":true,"currency":"COP"}""")!!.signedIn)
        // A version 2 snapshot (no zone) is not read: the app writes a new one at its next start.
        assertNull(
            WidgetSnapshot.parse(
                """{"v":2,"signedIn":true,"remaining":1,"spent":1,"budgetTotal":2,"currency":"COP","month":"2026-10"}""",
            ),
        )
    }
}
