package com.wambito.app.capture

/**
 * The money of a bank notification in Portuguese, Spanish, Italian or English: "12,50 €", "€12.50",
 * "1 042,96 €", "1.234,56 €", "€1,234.56". The currency is a symbol or a code on either side of the
 * amount. A comma or a point is the decimal mark only when exactly two digits follow it; between
 * groups of three digits it separates thousands, as do a space, a no-break space and a narrow
 * no-break space. One kind of thousands separator per amount, never the decimal mark. Integer cents,
 * never a float.
 */
internal object Money {
    /** The spaces a notification puts between digits or before a currency, as a character class body. */
    const val SPACES = "   "
    private const val CURRENCY = "US\\$|[€$£]|[A-Z]{3}"

    /** The money fragment. Groups: currency before, whole, decimal mark, cents, currency after. */
    const val PATTERN =
        "(?:($CURRENCY)[$SPACES]?)?" +
            "(\\d{1,3}(?:[$SPACES.,]\\d{3})+|\\d+)(?:([.,])(\\d{2}))?" +
            "(?:[$SPACES]?($CURRENCY))?"

    /** How many groups [PATTERN] has: a parser's own groups come after them. */
    const val GROUPS = 5

    private val CURRENCIES = mapOf("€" to "EUR", "EUR" to "EUR", "US$" to "USD", "$" to "USD", "USD" to "USD", "£" to "GBP", "GBP" to "GBP")

    /** The amount and currency from the groups [first]..[first]+4 of a match, or null. */
    fun read(match: MatchResult, first: Int): Pair<Long, String>? {
        val groups = match.groups
        val before = groups[first]?.value
        val after = groups[first + 4]?.value
        // Exactly one currency: none is a guess, two is ambiguous.
        if ((before == null) == (after == null)) return null
        val currency = CURRENCIES[before ?: after] ?: return null
        val digits = groups[first + 1]!!.value
        // "1,234,56" or "1.234,567.00" are not amounts: one thousands separator, never the decimal mark.
        val separators = digits.filterNot { it.isDigit() }.toSet()
        if (separators.size > 1) return null
        val mark = groups[first + 2]?.value?.single()
        if (mark != null && mark in separators) return null
        val whole = digits.filter { it.isDigit() }.toLongOrNull() ?: return null
        val cents = groups[first + 3]?.value?.toLong() ?: 0L
        if (whole > (Long.MAX_VALUE - 99) / 100) return null
        val total = whole * 100 + cents
        return if (total > 0) total to currency else null
    }
}
