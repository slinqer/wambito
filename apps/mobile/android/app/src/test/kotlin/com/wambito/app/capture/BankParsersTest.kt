package com.wambito.app.capture

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Test
import java.time.Instant

class BankParsersTest {
    private val at = Instant.parse("2026-11-04T10:15:00Z")
    private lateinit var original: List<BankParser>

    @Before
    fun save() {
        original = BankParsers.parsers
    }

    @After
    fun restore() {
        BankParsers.parsers = original
    }

    @Test
    fun `registers the revolut, google wallet and activobank parsers`() {
        assertEquals(
            setOf(CaptureSource.REVOLUT, CaptureSource.GOOGLE_WALLET, CaptureSource.ACTIVOBANK),
            BankParsers.parsers.map { it.source }.toSet(),
        )
        assertSame(RevolutParser, BankParsers.parsers.first { it.source == CaptureSource.REVOLUT })
        assertSame(GoogleWalletParser, BankParsers.parsers.first { it.source == CaptureSource.GOOGLE_WALLET })
        assertSame(ActivoBankParser, BankParsers.parsers.first { it.source == CaptureSource.ACTIVOBANK })
    }

    @Test
    fun `routes each source to its parser`() {
        val revolut = "🛒 Gastou 12,50 €\nSaldo de EUR: 1,00 €"
        val wallet = "12,50 € com o cartão Revolut Mastercard ••1234"
        assertNotNull(BankParsers.parse(CaptureSource.REVOLUT, "Padaria Lua", revolut, at))
        assertNotNull(BankParsers.parse(CaptureSource.GOOGLE_WALLET, "PADARIA LUA", wallet, at))
        // Each text belongs to the other source.
        assertNull(BankParsers.parse(CaptureSource.GOOGLE_WALLET, "Padaria Lua", revolut, at))
        assertNull(BankParsers.parse(CaptureSource.REVOLUT, "PADARIA LUA", wallet, at))
    }

    @Test
    fun `a parser that throws gives null instead of crashing`() {
        BankParsers.parsers = listOf(
            object : BankParser {
                override val source = CaptureSource.REVOLUT

                override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? =
                    error("boom")
            },
        )
        assertNull(BankParsers.parse(CaptureSource.REVOLUT, "x", "y", at))
    }
}
