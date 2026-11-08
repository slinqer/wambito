package com.wambito.app.capture

import java.time.Instant

/**
 * Revolut, European Portuguese, expenses only: title = the merchant, text = "<emoji> Gastou <amount> €"
 * (a card payment) or "<emoji> pagou €<amount> em <merchant>" (Revolut Pay), and then the balance
 * line, which is never read. Income and the other languages wait for samples.
 */
object RevolutParser : BankParser {
    override val source = CaptureSource.REVOLUT

    // The first line only: an optional emoji (no letters), "Gastou" and the money (a card payment).
    private val EXPENSE = Regex("^[^\\p{L}\\p{N}]*Gastou[   ]+${PtAmount.PATTERN}$")

    // Revolut Pay: an optional emoji, "pagou" (lower case as it arrives), the money with a decimal
    // point or comma and "em <merchant>". The merchant is still read from the title.
    private val REVOLUT_PAY =
        Regex("^[^\\p{L}\\p{N}]*[Pp]agou[   ]+${PtAmount.pattern(decimals = ",.")}[   ]+em[   ]+\\S.*$")

    override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? {
        val merchant = title?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val firstLine = text?.lineSequence()?.firstOrNull()?.trim() ?: return null
        val match = (EXPENSE.matchEntire(firstLine) ?: REVOLUT_PAY.matchEntire(firstLine)) ?: return null
        val (cents, currency) = PtAmount.read(match, 1) ?: return null
        return ParsedCapture(Kind.EXPENSE, cents, currency, merchant, postedAt, source)
    }
}
