package com.wambito.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class ActivoBankParserTest {
    private val at = Instant.parse("2026-11-26T12:11:00Z")
    private val parser = ActivoBankParser

    // The account number is invented.
    private val fromAccount = "Da conta 12345678901."

    private fun expense(cents: Long, currency: String = "EUR") = ParsedCapture(
        kind = Kind.EXPENSE,
        amountCents = cents,
        currency = currency,
        merchant = "ActivoBank",
        capturedAt = at,
        source = CaptureSource.ACTIVOBANK,
    )

    private fun parse(title: String?, text: String?) = parser.parse(title, text, at)

    @Test
    fun `the source is activobank, found by its package`() {
        assertEquals(CaptureSource.ACTIVOBANK, parser.source)
        assertEquals(CaptureSource.ACTIVOBANK, CaptureSource.forPackage("wit.android.bcpBankingApp.activoBank"))
        assertEquals(CaptureSource.ACTIVOBANK, CaptureSource.forWire("activobank"))
    }

    // pt-PT, seen on a phone of ours: title "💸 Enviou 4,10 EUR", text "Da conta <account>.".
    @Test
    fun `reads money sent, with or without the emoji`() {
        assertEquals(expense(410), parse("💸 Enviou 4,10 EUR", fromAccount))
        assertEquals(expense(410), parse("Enviou 4,10 EUR", fromAccount))
        assertEquals(expense(410), parse(" enviou 4,10 EUR ", fromAccount))
    }

    @Test
    fun `reads thousands, a whole amount and a symbol`() {
        assertEquals(expense(123456), parse("Enviou 1.234,56 EUR", fromAccount))
        assertEquals(expense(123456), parse("Enviou 1 234,56 EUR", fromAccount))
        assertEquals(expense(500), parse("Enviou 5 EUR", fromAccount))
        assertEquals(expense(410), parse("Enviou 4,10 €", fromAccount))
    }

    @Test
    fun `the text need not be there`() {
        assertEquals(expense(410), parse("Enviou 4,10 EUR", null))
    }

    @Test
    fun `captured at is the posted time`() {
        val other = Instant.parse("2026-01-02T03:04:05Z")
        assertEquals(other, parser.parse("Enviou 4,10 EUR", fromAccount, other)?.capturedAt)
    }

    @Test
    fun `returns null for what is not money sent`() {
        assertNull(parse(null, fromAccount))
        assertNull(parse("", fromAccount))
        assertNull(parse("ActivoBank", "Enviou 4,10 EUR"))
        assertNull(parse("Enviou 4,10", fromAccount))
        assertNull(parse("Enviou 0,00 EUR", fromAccount))
        assertNull(parse("Recebeu 4,10 EUR", fromAccount))
        assertNull(parse("Enviou 4,10 EUR para poupança? Saiba mais", fromAccount))
        assertNull(parse("Código de confirmação 123456", fromAccount))
    }
}
