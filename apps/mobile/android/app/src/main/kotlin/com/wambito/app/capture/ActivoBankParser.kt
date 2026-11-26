package com.wambito.app.capture

import java.time.Instant

/**
 * ActivoBank (Portugal), money sent only, in Portuguese. The title is "<emoji> Enviou <amount>" and
 * the text names the person's own account ("Da conta <number>."), never read: the notification names
 * no recipient, so the merchant is "ActivoBank" and the person changes it on review. Card payments,
 * income and other kinds wait for samples.
 */
object ActivoBankParser : BankParser {
    override val source = CaptureSource.ACTIVOBANK

    private const val MERCHANT = "ActivoBank"

    // Emoji, symbols and spaces: anything but a letter or a digit.
    private const val EMOJI = "[^\\p{L}\\p{N}]*"

    // pt-PT, seen on a phone of ours: "💸 Enviou 4,10 EUR".
    private val SENT = Regex("^$EMOJI(?i:Enviou)[${Money.SPACES}]+${Money.PATTERN}$")

    override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? {
        val match = SENT.matchEntire(title?.trim() ?: return null) ?: return null
        val (cents, currency) = Money.read(match, 1) ?: return null
        return ParsedCapture(Kind.EXPENSE, cents, currency, MERCHANT, postedAt, source)
    }
}
