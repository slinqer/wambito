package com.wambito.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class GoogleWalletParserTest {
    private val at = Instant.parse("2026-11-04T10:15:00Z")
    private val parser = GoogleWalletParser
    private val card = "com o cartão Revolut Mastercard ••1234"

    private fun expense(cents: Long, merchant: String, currency: String = "EUR") = ParsedCapture(
        kind = Kind.EXPENSE,
        amountCents = cents,
        currency = currency,
        merchant = merchant,
        capturedAt = at,
        source = CaptureSource.GOOGLE_WALLET,
    )

    private fun parse(title: String?, text: String?) = parser.parse(title, text, at)

    @Test
    fun `the source is google wallet`() {
        assertEquals(CaptureSource.GOOGLE_WALLET, parser.source)
    }

    @Test
    fun `reads a pt-PT expense and keeps the merchant as it arrives`() {
        assertEquals(expense(1250, "PADARIA LUA"), parse("PADARIA LUA", "12,50 € $card"))
    }

    @Test
    fun `reads thousands separated by a space, a no-break space or a narrow no-break space`() {
        assertEquals(expense(104296, "LOJA SOL"), parse("LOJA SOL", "1 042,96 € $card"))
        assertEquals(expense(104296, "LOJA SOL"), parse("LOJA SOL", "1 042,96 € $card"))
        assertEquals(expense(104296, "LOJA SOL"), parse("LOJA SOL", "1 042,96 € $card"))
    }

    @Test
    fun `accepts a whole amount`() {
        assertEquals(expense(500, "LOJA SOL"), parse("LOJA SOL", "5 € $card"))
    }

    @Test
    fun `maps other currency symbols and codes`() {
        assertEquals(expense(1250, "LOJA SOL", "USD"), parse("LOJA SOL", "12,50 US$ $card"))
        assertEquals(expense(1250, "LOJA SOL", "USD"), parse("LOJA SOL", "12,50 USD $card"))
        assertEquals(expense(1250, "LOJA SOL", "GBP"), parse("LOJA SOL", "£12,50 $card"))
    }

    @Test
    fun `never guesses a currency`() {
        assertNull(parse("LOJA SOL", "12,50 $card"))
        assertNull(parse("LOJA SOL", "12,50 CHF $card"))
    }

    @Test
    fun `a null or blank title gives null`() {
        assertNull(parse(null, "12,50 € $card"))
        assertNull(parse("  ", "12,50 € $card"))
        assertEquals(expense(1250, "PADARIA LUA"), parse(" PADARIA LUA ", "12,50 € $card"))
    }

    @Test
    fun `captured at is the posted time`() {
        val other = Instant.parse("2026-01-02T03:04:05Z")
        assertEquals(other, parser.parse("PADARIA LUA", "12,50 € $card", other)?.capturedAt)
    }

    @Test
    fun `returns null for what is not an expense`() {
        assertNull(parse("PADARIA LUA", null))
        assertNull(parse("PADARIA LUA", ""))
        assertNull(parse("Google Wallet", "Adicione o seu cartão e pague com o telemóvel"))
        assertNull(parse("PADARIA LUA", "Pagamento recusado"))
        assertNull(parse("PADARIA LUA", "Pagamento recusado: 12,50 € $card"))
        assertNull(parse("PADARIA LUA", card))
        assertNull(parse("PADARIA LUA", "12,50 € com o cartão Revolut Mastercard"))
        assertNull(parse("PADARIA LUA", "0,00 € $card"))
    }

    // English: the shape another open-source project saw on a phone ("€10.60 with <card> ••1234").
    @Test
    fun `reads an English expense`() {
        assertEquals(expense(1060, "MOON CAFE"), parse("MOON CAFE", "€10.60 with Example Bank Credit Card ••1234"))
        assertEquals(expense(104296, "MOON CAFE"), parse("MOON CAFE", "€1,042.96 with Revolut Mastercard ••1234"))
    }

    // Spanish and Italian: not seen anywhere yet; the Portuguese shape in each language.
    @Test
    fun `reads a Spanish or an Italian expense`() {
        assertEquals(
            expense(123456, "PANADERIA LUNA"),
            parse("PANADERIA LUNA", "1.234,56 € con la tarjeta Revolut Mastercard ••1234"),
        )
        assertEquals(
            expense(1250, "PANETTERIA LUNA"),
            parse("PANETTERIA LUNA", "12,50 € con la carta Revolut Mastercard ••1234"),
        )
    }

    @Test
    fun `the card words and the last digits are required in every language`() {
        assertNull(parse("MOON CAFE", "€10.60 with Example Bank Credit Card"))
        assertNull(parse("MOON CAFE", "€10.60 Example Bank Credit Card ••1234"))
        assertNull(parse("PANADERIA LUNA", "12,50 € con la tarjeta"))
    }
}
