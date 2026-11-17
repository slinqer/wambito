package com.wambito.app.scanner

import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.ChecksumException
import com.google.zxing.DecodeHintType
import com.google.zxing.FormatException
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader

private val hints = mapOf(
    DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
    DecodeHintType.TRY_HARDER to true,
)

/**
 * The text of the QR code in a camera frame's luminance plane (the Y plane of a YUV_420_888
 * [androidx.camera.core.ImageProxy]), or null when there is none or it cannot be read yet.
 *
 * [luminance] holds [height] rows of [rowStride] bytes, the first [width] of each being pixels (the
 * rest is padding, as the camera gives it). ZXing core only (plain Java, Apache-2.0): no ML Kit, no
 * Play Services. A QR is read at any quarter turn, so the frame's rotation does not matter.
 */
fun decodeQr(luminance: ByteArray, width: Int, height: Int, rowStride: Int): String? {
    if (width <= 0 || height <= 0 || rowStride < width) return null
    if (luminance.size < (height - 1) * rowStride + width) return null
    val source = PlanarYUVLuminanceSource(luminance, rowStride, height, 0, 0, width, height, false)
    return try {
        QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)), hints).text
    } catch (_: NotFoundException) {
        null
    } catch (_: ChecksumException) {
        null
    } catch (_: FormatException) {
        null
    }
}
