package com.wambito.app.scanner

/** The pairing QR (lib/local/pairing.dart): what a scan takes when it is asked nothing. */
const val PAIR_QR_PREFIX = "wambito://pair?"

/** The web sign-in QR (lib/local/signin_approval.dart). */
const val SIGNIN_QR_PREFIX = "wambito://signin?"

/** The only QRs the app ever takes: any other prefix Dart may send is dropped. */
val KNOWN_QR_PREFIXES = listOf(PAIR_QR_PREFIX, SIGNIN_QR_PREFIX)

/**
 * The prefixes a `scan` call's `prefixes` argument asks for, kept to [KNOWN_QR_PREFIXES]; the
 * pairing QR alone when it asks none of them (or is missing), never "anything".
 */
fun qrPrefixesOf(argument: Any?): List<String> {
    val asked = (argument as? List<*>).orEmpty().filterIsInstance<String>()
        .filter { it in KNOWN_QR_PREFIXES }
        .distinct()
    return asked.ifEmpty { listOf(PAIR_QR_PREFIX) }
}

/** Whether a read QR's [text] is one the scan was asked for: one of [prefixes] the app knows. */
fun acceptsQr(text: String, prefixes: List<String>): Boolean =
    prefixes.any { it in KNOWN_QR_PREFIXES && text.startsWith(it) }
