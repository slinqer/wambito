package com.wambito.app.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class RevolutParserTest {
    private val at = Instant.parse("2026-11-04T10:15:00Z")
    private val parser = RevolutParser

    private fun expense(cents: Long, merchant: String, currency: String = "EUR") = ParsedCapture(
        kind = Kind.EXPENSE,
        amountCents = cents,
        currency = currency,
        merchant = merchant,
        capturedAt = at,
        source = CaptureSource.REVOLUT,
    )

    private fun parse(title: String?, text: String?) = parser.parse(title, text, at)

    @Test
    fun `the source is revolut`() {
        assertEquals(CaptureSource.REVOLUT, parser.source)
    }

    @Test
    fun `reads a pt-PT expense`() {
        assertEquals(
            expense(1250, "Padaria Lua"),
            parse("Padaria Lua", "🛒 Gastou 12,50 €\nSaldo de EUR: 1 042,96 €"),
        )
    }

    @Test
    fun `reads a pt-PT Revolut Pay expense`() {
        // Revolut Pay: "pagou", the symbol first, a decimal point and "em <merchant>".
        assertEquals(
            expense(928, "Loja Sol"),
            parse("Loja Sol", "💳 pagou €9.28 em Loja Sol\nSaldo de EUR: €787.93"),
        )
        assertEquals(expense(928, "Loja Sol"), parse("Loja Sol", "pagou €9.28 em Loja Sol"))
        assertEquals(expense(928, "Loja Sol"), parse("Loja Sol", "💳 Pagou 9,28 € em Loja Sol"))
        assertEquals(expense(1200, "Loja Sol"), parse("Loja Sol", "💳 pagou €12 em Loja Sol"))
        assertEquals(expense(104296, "Loja Sol"), parse("Loja Sol", "💳 pagou €1 042.96 em Loja Sol"))
        assertEquals(expense(1250, "Loja Sol", "USD"), parse("Loja Sol", "💳 pagou US$12.50 em Loja Sol"))
    }

    @Test
    fun `a Revolut Pay line without the merchant or the currency is not read`() {
        assertNull(parse("Loja Sol", "💳 pagou €9.28"))
        assertNull(parse("Loja Sol", "💳 pagou 9.28 em Loja Sol"))
        assertNull(parse("Loja Sol", "💳 pagou €9.2 em Loja Sol"))
        assertNull(parse("Loja Sol", "💳 pagou €0.00 em Loja Sol"))
    }

    // Italian: the shape of a capture published by another open-source project (merchant invented here):
    // "Hai pagato 10 € presso <merchant> <emoji>" and the balance line.
    @Test
    fun `reads an Italian expense`() {
        assertEquals(
            expense(1000, "Vela Rossa"),
            parse("Vela Rossa", "Hai pagato 10 € presso Vela Rossa 🚗\n⚠️ Saldo: 24,53 €"),
        )
        assertEquals(expense(1250, "Vela Rossa"), parse("Vela Rossa", "Hai speso €12,50 presso Vela Rossa"))
        assertEquals(expense(123456, "Vela Rossa"), parse("Vela Rossa", "Hai speso €1.234,56 presso Vela Rossa"))
        assertEquals(expense(1250, "Vela Rossa"), parse("Vela Rossa", "🛒 Hai speso 12,50 €"))
    }

    // English: from other projects' tests, not yet seen on a phone.
    @Test
    fun `reads an English expense`() {
        assertEquals(expense(450, "Moon Cafe"), parse("Moon Cafe", "You spent €4.50 at Moon Cafe"))
        assertEquals(expense(123456, "Moon Cafe"), parse("Moon Cafe", "You paid €1,234.56 at Moon Cafe"))
        assertEquals(expense(1250, "Moon Cafe", "GBP"), parse("Moon Cafe", "🛒 You spent £12.50"))
    }

    // Spanish: no sample anywhere yet; the same shape as the others, to be checked on a phone.
    @Test
    fun `reads a Spanish expense`() {
        assertEquals(expense(1250, "Panadería Luna"), parse("Panadería Luna", "🛒 Has gastado 12,50 €"))
        assertEquals(
            expense(123456, "Panadería Luna"),
            parse("Panadería Luna", "Has pagado 1.234,56 € en Panadería Luna"),
        )
    }

    @Test
    fun `a generic title takes the merchant from the line`() {
        assertEquals(expense(450, "Moon Cafe"), parse("Revolut", "You spent €4.50 at Moon Cafe 🍔"))
        assertEquals(expense(1000, "Vela Rossa"), parse("Revolut Pay", "Hai pagato 10 € presso Vela Rossa"))
        assertNull(parse("Revolut", "You spent €4.50"))
    }

    @Test
    fun `a decimal point or comma is read only with two cents and one kind of separator`() {
        assertEquals(expense(1250, "Loja Sol"), parse("Loja Sol", "Gastou 12.50 €"))
        assertEquals(expense(123400, "Moon Cafe"), parse("Moon Cafe", "You spent €1,234 at Moon Cafe"))
        assertNull(parse("Moon Cafe", "You spent €1,234,56 at Moon Cafe"))
        assertNull(parse("Moon Cafe", "You spent €1.234.56 at Moon Cafe"))
        assertNull(parse("Moon Cafe", "You spent €12.5 at Moon Cafe"))
    }

    // One card payment can be pushed as a hold, an adjustment and the payment: only the payment counts.
    @Test
    fun `holds, adjustments and balance warnings are not expenses`() {
        assertNull(parse("34,53 € temporary hold ⛽", "Any unused balance will be returned to you once the transaction is settled. Tap for more"))
        assertNull(parse("Vela Rossa", "🚗 Pagamento aggiornato da 34,53 € a 10 €\nSaldo di EUR: 24,53 €"))
        assertNull(parse("Saldo inferiore a €30 👀", "Se puoi, ricarica subito il conto"))
    }

    @Test
    fun `the emoji can vary or be missing`() {
        val expected = expense(1250, "Padaria Lua")
        assertEquals(expected, parse("Padaria Lua", "☕ Gastou 12,50 €\nSaldo de EUR: 3,00 €"))
        assertEquals(expected, parse("Padaria Lua", "Gastou 12,50 €\nSaldo de EUR: 3,00 €"))
        assertEquals(expected, parse("Padaria Lua", "🧑‍🍳 Gastou 12,50 €"))
    }

    @Test
    fun `the balance is ignored`() {
        // A balance line that looks like an amount must not leak into any field.
        assertEquals(
            expense(500, "Padaria Lua"),
            parse("Padaria Lua", "🛒 Gastou 5 €\nSaldo de EUR: 9 999,99 €"),
        )
    }

    @Test
    fun `reads thousands separated by a space, a no-break space or a narrow no-break space`() {
        assertEquals(expense(104296, "Loja Sol"), parse("Loja Sol", "Gastou 1 042,96 €"))
        assertEquals(expense(104296, "Loja Sol"), parse("Loja Sol", "Gastou 1 042,96 €"))
        assertEquals(expense(104296, "Loja Sol"), parse("Loja Sol", "Gastou 1 042,96 €"))
        assertEquals(expense(123456789, "Loja Sol"), parse("Loja Sol", "Gastou 1 234 567,89 €"))
    }

    @Test
    fun `accepts a whole amount and reads cents without floats`() {
        assertEquals(expense(500, "Loja Sol"), parse("Loja Sol", "Gastou 5 €"))
        assertEquals(expense(1005, "Loja Sol"), parse("Loja Sol", "Gastou 10,05 €"))
        assertEquals(expense(1, "Loja Sol"), parse("Loja Sol", "Gastou 0,01 €"))
    }

    @Test
    fun `maps other currency symbols and codes, before or after the amount`() {
        assertEquals(expense(1250, "Loja Sol", "USD"), parse("Loja Sol", "Gastou US$ 12,50"))
        assertEquals(expense(1250, "Loja Sol", "USD"), parse("Loja Sol", "Gastou 12,50 USD"))
        assertEquals(expense(1250, "Loja Sol", "USD"), parse("Loja Sol", "Gastou 12,50 \$"))
        assertEquals(expense(1250, "Loja Sol", "GBP"), parse("Loja Sol", "Gastou £12,50"))
        assertEquals(expense(1250, "Loja Sol", "EUR"), parse("Loja Sol", "Gastou € 12,50"))
        assertEquals(expense(1250, "Loja Sol", "EUR"), parse("Loja Sol", "Gastou 12,50 EUR"))
    }

    @Test
    fun `never guesses a currency`() {
        assertNull(parse("Loja Sol", "Gastou 12,50"))
        assertNull(parse("Loja Sol", "Gastou 12,50 CHF"))
        assertNull(parse("Loja Sol", "Gastou 12,50 ¥"))
        assertNull(parse("Loja Sol", "Gastou € 12,50 USD"))
    }

    @Test
    fun `the merchant is the trimmed title`() {
        assertEquals(expense(1250, "Padaria Lua"), parse("  Padaria Lua \n", "Gastou 12,50 €"))
        assertNull(parse(null, "Gastou 12,50 €"))
        assertNull(parse("   ", "Gastou 12,50 €"))
    }

    @Test
    fun `captured at is the posted time`() {
        val other = Instant.parse("2026-01-02T03:04:05Z")
        assertEquals(other, parser.parse("Padaria Lua", "Gastou 12,50 €", other)?.capturedAt)
    }

    @Test
    fun `returns null for what is not an expense`() {
        assertNull(parse("Padaria Lua", null))
        assertNull(parse("Padaria Lua", ""))
        assertNull(parse("Revolut", "🎁 Ganhe 10 € por cada amigo que convidar!"))
        assertNull(parse("Padaria Lua", "Pagamento recusado"))
        assertNull(parse("Padaria Lua", "⚠️ Pagamento recusado de 12,50 €"))
        assertNull(parse("Conta Poupança", "Transferiu 50,00 € para Poupança"))
        assertNull(parse("Câmbio", "💱 Trocou 50,00 € por 54,00 US$"))
        assertNull(parse("Padaria Lua", "Gastou muito hoje"))
        assertNull(parse("Padaria Lua", "Gastou 12,5 €"))
        assertNull(parse("Padaria Lua", "Gastou 0,00 €"))
    }

    @Test
    fun `income waits for samples in every language`() {
        assertNull(parse("Ana Silva", "💸 Recebeu 20,00 €\nSaldo de EUR: 1 042,96 €"))
        assertNull(parse("Ana Silva", "Hai ricevuto €50,00 da Ana Silva"))
        assertNull(parse("Ana Silva", "€20.00 received from Ana Silva"))
        assertNull(parse("Ana Silva", "Has recibido 20,00 € de Ana Silva"))
    }
}
