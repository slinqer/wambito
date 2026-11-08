package com.wambito.app.capture

import java.time.Instant

/**
 * Google Wallet, expenses only, in Portuguese, English, Spanish and Italian: title = the merchant
 * (upper case, kept as it arrives: the server normalizes it), text = "<amount> <card words> <card>
 * ••<4 digits>". Income waits for samples.
 */
object GoogleWalletParser : BankParser {
    override val source = CaptureSource.GOOGLE_WALLET

    // The words before the card. pt-PT seen on a phone of ours ("12,50 € com o cartão <card> ••1234"),
    // English seen by another open-source project ("€10.60 with <card> ••1234"), Spanish and Italian
    // not seen yet: the same shape.
    private const val CARD_WORDS = "com o cartão|with|con la tarjeta|con la carta"

    private val EXPENSE = Regex("^${Money.PATTERN}[${Money.SPACES}]+(?:$CARD_WORDS) .+ ••\\d{4}$")

    override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? {
        val merchant = title?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val match = EXPENSE.matchEntire(text?.trim() ?: return null) ?: return null
        val (cents, currency) = Money.read(match, 1) ?: return null
        return ParsedCapture(Kind.EXPENSE, cents, currency, merchant, postedAt, source)
    }
}
