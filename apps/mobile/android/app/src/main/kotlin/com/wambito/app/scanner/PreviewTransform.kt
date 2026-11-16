package com.wambito.app.scanner

import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/** A 2D affine map: x' = a x + c y + tx, y' = b x + d y + ty (the layout of android.graphics.Matrix). */
data class Affine(
    val a: Float = 1f,
    val b: Float = 0f,
    val c: Float = 0f,
    val d: Float = 1f,
    val tx: Float = 0f,
    val ty: Float = 0f,
) {
    fun map(x: Float, y: Float): Pair<Float, Float> = (a * x + c * y + tx) to (b * x + d * y + ty)

    /** This map, then [next]. */
    fun then(next: Affine) = Affine(
        a = next.a * a + next.c * b,
        b = next.b * a + next.d * b,
        c = next.a * c + next.c * d,
        d = next.b * c + next.d * d,
        tx = next.a * tx + next.c * ty + next.tx,
        ty = next.b * tx + next.d * ty + next.ty,
    )

    /** Android's `Matrix.setValues` array. */
    fun values(): FloatArray = floatArrayOf(a, c, tx, b, d, ty, 0f, 0f, 1f)

    companion object {
        fun scale(sx: Float, sy: Float, px: Float, py: Float) =
            Affine(a = sx, d = sy, tx = px - sx * px, ty = py - sy * py)

        /** Clockwise on the screen (y down), as `Matrix.postRotate`. */
        fun rotate(degrees: Float, px: Float, py: Float): Affine {
            val r = Math.toRadians(degrees.toDouble())
            val cs = cos(r).toFloat()
            val sn = sin(r).toFloat()
            return Affine(
                a = cs, b = sn, c = -sn, d = cs,
                tx = px - cs * px + sn * py,
                ty = py - sn * px - cs * py,
            )
        }
    }
}

/**
 * The matrix to set on the preview's `TextureView`, which draws the camera buffer stretched over
 * the whole view: it undoes that stretch, turns the picture upright and scales it to cover the view
 * (the overflow is cropped). The twin of camera-view's `PreviewTransformation` for a fill-center
 * preview.
 *
 * [bufferWidth] x [bufferHeight] is the buffer CameraX asked for (sensor orientation).
 * [rotationDegrees] is `TransformationInfo.rotationDegrees` (clockwise degrees from the buffer to the
 * target rotation) and [hasCameraTransform] its `hasCameraTransform()`: when true the surface goes
 * straight to Camera2 and the SurfaceTexture's own transform has already turned the picture to the
 * device's natural orientation, so the only turn left is back by the display's rotation
 * ([displayRotationDegrees], 0, 90, 180, 270); when false the whole of [rotationDegrees] is left.
 */
fun previewTransform(
    viewWidth: Float,
    viewHeight: Float,
    bufferWidth: Int,
    bufferHeight: Int,
    rotationDegrees: Int,
    hasCameraTransform: Boolean,
    displayRotationDegrees: Int,
): Affine {
    val remaining: Int
    val contentTurned: Boolean
    if (hasCameraTransform) {
        remaining = -displayRotationDegrees
        // The sensor's own turn: what the target rotation asks plus the display's.
        contentTurned = Math.floorMod(rotationDegrees + displayRotationDegrees, 180) != 0
    } else {
        remaining = rotationDegrees
        contentTurned = false
    }
    val contentWidth = (if (contentTurned) bufferHeight else bufferWidth).toFloat()
    val contentHeight = (if (contentTurned) bufferWidth else bufferHeight).toFloat()
    val quarter = Math.floorMod(remaining, 180) != 0
    val shownWidth = if (quarter) contentHeight else contentWidth
    val shownHeight = if (quarter) contentWidth else contentHeight
    val cx = viewWidth / 2
    val cy = viewHeight / 2
    val cover = max(viewWidth / shownWidth, viewHeight / shownHeight)
    return Affine.scale(contentWidth / viewWidth, contentHeight / viewHeight, cx, cy)
        .then(Affine.rotate(remaining.toFloat(), cx, cy))
        .then(Affine.scale(cover, cover, cx, cy))
}
