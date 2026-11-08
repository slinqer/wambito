package com.wambito.app.capture

import androidx.annotation.VisibleForTesting
import java.time.Instant

/** Reads one bank app's notification. Returns null when it is not a movement it understands. */
interface BankParser {
    val source: CaptureSource

    fun parse(title: String?, text: String?, postedAt: Instant): ParsedCapture?
}

/**
 * The parsers by source: Revolut and Google Wallet, expenses in pt, it, en and es for now. A parser
 * that throws drops the notification instead of crashing the listener. Nothing here logs: the
 * notification is never logged.
 */
object BankParsers {
    @VisibleForTesting
    var parsers: List<BankParser> = listOf(RevolutParser, GoogleWalletParser)

    fun parse(source: CaptureSource, title: String?, text: String?, postedAt: Instant): ParsedCapture? =
        try {
            parsers.firstOrNull { it.source == source }?.parse(title, text, postedAt)
        } catch (_: Exception) {
            null
        }
}
