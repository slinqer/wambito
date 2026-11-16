package com.wambito.app.scanner

import org.junit.Assert.assertEquals
import org.junit.Test

class PreviewTransformTest {
    // A 640x480 sensor buffer (landscape, as a phone's sensor is) on a phone with the sensor turned 90.
    private val buffer = 640 to 480

    private fun assertMaps(t: Affine, from: Pair<Float, Float>, to: Pair<Float, Float>) {
        val (x, y) = t.map(from.first, from.second)
        assertEquals("x of $from", to.first, x, 0.01f)
        assertEquals("y of $from", to.second, y, 0.01f)
    }

    @Test
    fun `portrait, camera transform, the texture is already upright, so only the stretch is undone and the view covered`() {
        // Sensor 90, display 0: rotationDegrees 90. Content is 480x640 upright, no remaining turn.
        val t = previewTransform(1080f, 2400f, buffer.first, buffer.second, 90, true, 0)
        assertMaps(t, 540f to 1200f, 540f to 1200f)
        assertMaps(t, 0f to 0f, -360f to 0f)
        assertMaps(t, 1080f to 2400f, 1440f to 2400f)
    }

    @Test
    fun `landscape, camera transform, the upright content is turned back by the display rotation`() {
        // Sensor 90, display 90: rotationDegrees 0; the remaining turn is -90.
        val t = previewTransform(2400f, 1080f, buffer.first, buffer.second, 0, true, 90)
        assertMaps(t, 1200f to 540f, 1200f to 540f)
        assertMaps(t, 0f to 0f, 0f to 1440f)
    }

    @Test
    fun `portrait, no camera transform, the buffer is turned by rotationDegrees`() {
        val t = previewTransform(1080f, 2400f, buffer.first, buffer.second, 90, false, 0)
        assertMaps(t, 540f to 1200f, 540f to 1200f)
        assertMaps(t, 0f to 0f, 1440f to 0f)
    }

    @Test
    fun `landscape, no camera transform, no turn, the buffer is only scaled to cover`() {
        val t = previewTransform(2400f, 1080f, buffer.first, buffer.second, 0, false, 90)
        assertMaps(t, 1200f to 540f, 1200f to 540f)
        assertMaps(t, 0f to 0f, 0f to -360f)
    }
}
