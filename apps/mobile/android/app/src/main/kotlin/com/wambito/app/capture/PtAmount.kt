package com.wambito.app.capture

/**
 * The money of a European Portuguese notification: a decimal comma (or a point, where asked), thousands separated by a space,
 * a no-break space or a narrow no-break space, and the currency as a symbol or a code on either side
 * of the amount. Integer cents, never a float.
 */
internal object PtAmount {
    private const val SPACES = "   "
    private const val CURRENCY = "US\\$|[€$£]|[A-Z]{3}"

    /** The money fragment: the groups are the currency before, whole, cents and the currency after. */
    val PATTERN = pattern(decimals = ",")

    /**
     * The money fragment with the decimal separators in [decimals], a regex character class body:
     * Revolut Pay writes "€9.28" in a Portuguese notification, so its line takes ",." .
     */
    fun pattern(decimals: String) =
        "(?:($CURRENCY)[   ]?)?" +
            "(\\d{1,3}(?:[$SPACES]\\d{3})+|\\d+)(?:[$decimals](\\d{2}))?" +
            "(?:[$SPACES]?($CURRENCY))?"

    private val CURRENCIES = mapOf("€" to "EUR", "EUR" to "EUR", "US$" to "USD", "$" to "USD", "USD" to "USD", "£" to "GBP", "GBP" to "GBP")

    /** The amount and currency from the groups [first]..[first]+3 of a match, or null. */
    fun read(match: MatchResult, first: Int): Pair<Long, String>? {
        val groups = match.groups
        val before = groups[first]?.value
        val after = groups[first + 3]?.value
        // Exactly one currency: none is a guess, two is ambiguous.
        if ((before == null) == (after == null)) return null
        val currency = CURRENCIES[before ?: after] ?: return null
        val whole = groups[first + 1]!!.value.filter { it.isDigit() }.toLongOrNull() ?: return null
        val cents = groups[first + 2]?.value?.toLong() ?: 0L
        if (whole > (Long.MAX_VALUE - 99) / 100) return null
        val total = whole * 100 + cents
        return if (total > 0) total to currency else null
    }
}
