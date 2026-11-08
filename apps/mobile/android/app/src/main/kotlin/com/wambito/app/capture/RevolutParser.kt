package com.wambito.app.capture

import java.time.Instant

/**
 * Revolut, expenses only, in Portuguese, Italian, English and Spanish. The title is the merchant
 * (or "Revolut" and the like, then the merchant comes from the line); the text's first line is
 * "<emoji> <verb> <amount> [<preposition> <merchant>] <emoji>", then the balance line, which is
 * never read. Holds, adjustments, declines, transfers, exchanges and income match no line.
 */
object RevolutParser : BankParser {
    override val source = CaptureSource.REVOLUT

    /** A line: the words before the amount and the word before the merchant, if any. */
    private class Line(lead: String, preposition: String, merchantRequired: Boolean = false) {
        val regex = Regex(
            "^$EMOJI(?i:$lead)$SPACE${Money.PATTERN}" +
                "(?:$SPACE(?i:$preposition)$SPACE(\\S.*?))${if (merchantRequired) "" else "?"}$EMOJI$",
        )
    }

    private const val SPACE = "[${Money.SPACES}]+"

    // Emoji, symbols and spaces: anything but a letter or a digit.
    private const val EMOJI = "[^\\p{L}\\p{N}]*"

    // Where each line comes from: a phone of ours ("seen"), another project's capture or tests, or
    // nothing yet (to be checked on a phone). Merchants in the tests are invented.
    private val LINES = listOf(
        // pt-PT card payment, seen: "🛒 Gastou 12,50 €".
        Line("Gastou", "em"),
        // pt-PT Revolut Pay, seen: "💳 pagou €9.28 em <merchant>".
        Line("pagou", "em", merchantRequired = true),
        // Italian, from another project's capture: "Hai pagato 10 € presso <merchant> 🚗".
        Line("Hai pagato|Hai speso", "presso"),
        // English, from other projects' tests: "You spent €4.50 at <merchant>".
        Line("You spent|You paid", "at"),
        // Spanish, nothing yet: the same shape.
        Line("Has gastado|Has pagado", "en"),
    )

    // Titles that name Revolut, not the merchant.
    private val GENERIC_TITLES = setOf("revolut", "revolut pay", "revolut business")

    override fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture? {
        val firstLine = text?.lineSequence()?.firstOrNull()?.trim() ?: return null
        val match = LINES.firstNotNullOfOrNull { it.regex.matchEntire(firstLine) } ?: return null
        val (cents, currency) = Money.read(match, 1) ?: return null
        val named = title?.trim()?.takeIf { it.isNotEmpty() && it.lowercase() !in GENERIC_TITLES }
        val merchant = named ?: match.groups[1 + Money.GROUPS]?.value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return ParsedCapture(Kind.EXPENSE, cents, currency, merchant, postedAt, source)
    }
}
