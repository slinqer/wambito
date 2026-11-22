package com.wambito.app.scanner

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import java.util.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QrDecodeTest {
    private val link =
        "wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"

    /** A [size]-pixel square QR of [text], as a camera's luminance plane: black 0, white 255, with
     *  [padding] bytes of garbage after each row (the row stride is larger than the width). */
    private fun frame(text: String, size: Int, padding: Int): ByteArray {
        val matrix = QRCodeWriter().encode(
            text,
            BarcodeFormat.QR_CODE,
            size,
            size,
            mapOf(EncodeHintType.MARGIN to 4),
        )
        val stride = size + padding
        val out = ByteArray(stride * size) { 0x7F }
        for (y in 0 until size) {
            for (x in 0 until size) {
                out[y * stride + x] = if (matrix.get(x, y)) 0 else 255.toByte()
            }
        }
        return out
    }

    @Test
    fun `a pairing qr in a frame with row padding decodes to its text`() {
        val size = 400
        assertEquals(link, decodeQr(frame(link, size, padding = 48), size, size, rowStride = size + 48))
    }

    @Test
    fun `a qr in a frame with no padding decodes too`() {
        val size = 360
        assertEquals(link, decodeQr(frame(link, size, padding = 0), size, size, rowStride = size))
    }

    @Test
    fun `noise decodes to null`() {
        val size = 320
        val noise = ByteArray((size + 16) * size).also { Random(7).nextBytes(it) }
        assertNull(decodeQr(noise, size, size, rowStride = size + 16))
    }

    @Test
    fun `a blank frame decodes to null`() {
        val size = 200
        assertNull(decodeQr(ByteArray(size * size) { 255.toByte() }, size, size, rowStride = size))
    }

    @Test
    fun `a buffer too short for its size decodes to null instead of throwing`() {
        assertNull(decodeQr(ByteArray(10), 100, 100, rowStride = 100))
        assertNull(decodeQr(ByteArray(100), 10, 10, rowStride = 5))
    }
}
