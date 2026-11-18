package com.wambito.app.scanner

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScannerPrefixTest {
    private val pair = "wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abc"
    private val signin = "wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abc"

    @Test
    fun `the default takes the pairing QR only`() {
        val prefixes = qrPrefixesOf(null)
        assertEquals(listOf(PAIR_QR_PREFIX), prefixes)
        assertTrue(acceptsQr(pair, prefixes))
        assertFalse(acceptsQr(signin, prefixes))
    }

    @Test
    fun `the sign-in QR when asked`() {
        val prefixes = qrPrefixesOf(listOf(SIGNIN_QR_PREFIX))
        assertTrue(acceptsQr(signin, prefixes))
        assertFalse(acceptsQr(pair, prefixes))
        assertTrue(acceptsQr(pair, qrPrefixesOf(listOf(PAIR_QR_PREFIX, SIGNIN_QR_PREFIX))))
    }

    @Test
    fun `a foreign text never, whatever is asked`() {
        val asked = qrPrefixesOf(listOf("https://", "", "wambito://", 7, SIGNIN_QR_PREFIX))
        assertEquals(listOf(SIGNIN_QR_PREFIX), asked)
        for (text in listOf("https://evil.example/x", "", "wambito://add", "WAMBITO://signin?id=1")) {
            assertFalse(acceptsQr(text, asked))
            assertFalse(acceptsQr(text, listOf("https://", "", "wambito://")))
        }
        // nothing usable asked: the default, never everything
        assertEquals(listOf(PAIR_QR_PREFIX), qrPrefixesOf(listOf("https://")))
        assertEquals(listOf(PAIR_QR_PREFIX), qrPrefixesOf("wambito://signin?"))
    }
}
