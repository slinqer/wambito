package com.wambito.app.widget

import android.graphics.Typeface
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode

/** The widget's figure, drawn as a picture in the app's figure face (spec "Widget figure"). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FigureBitmapTest {
    private val face = Typeface.DEFAULT_BOLD

    @Test
    fun `a short figure is drawn at its size, as tall as its line`() {
        val figure = figureBitmap("$42.000", sizePx = 60f, maxWidthPx = 1000, typeface = face)
        assertEquals(60f, figure.sizePx)
        assertTrue(figure.bitmap.width in 1..1000)
        assertTrue("the line is about 1.2 times the size", figure.bitmap.height in 60..90)
    }

    @Test
    fun `a long figure shrinks to fit the room before it is cut`() {
        val wide = figureBitmap("$1.234.567", sizePx = 60f, maxWidthPx = 10_000, typeface = face)
        val room = (wide.bitmap.width * 0.8f).toInt()
        val fitted = figureBitmap("$1.234.567", sizePx = 60f, maxWidthPx = room, typeface = face)
        assertTrue(fitted.bitmap.width <= room)
        assertTrue(fitted.sizePx < 60f)
        assertEquals("$1.234.567", fitted.text)
    }

    @Test
    fun `past the smallest size it keeps the smallest and cuts the end`() {
        val figure = figureBitmap("$1.234.567.890.123", sizePx = 60f, maxWidthPx = 120, typeface = face)
        assertTrue(figure.bitmap.width <= 120)
        assertEquals(60f * MIN_FIGURE_SCALE, figure.sizePx)
        assertTrue(figure.text.endsWith("…"))
    }

    @Test
    fun `no room at all still gives a picture, one pixel wide`() {
        val figure = figureBitmap("$42.000", sizePx = 60f, maxWidthPx = 0, typeface = face)
        assertTrue(figure.bitmap.width >= 1)
    }

    @Test
    fun `the room the figure gets in each layout`() {
        // Small: 8 dp padding each side, the eye (36), a 4 dp gap and the buttons (＋ 32, 4, 🎤 28).
        assertEquals(170.dp - 16.dp - 36.dp - 4.dp - 64.dp, figureRoom(DpSize(170.dp, 60.dp), WidgetSize.SMALL))
        // Row: 14 dp padding each side, the eye, an 8 dp gap and the buttons (＋ 33, 8, 🎤 28).
        assertEquals(300.dp - 28.dp - 36.dp - 8.dp - 69.dp, figureRoom(DpSize(300.dp, 60.dp), WidgetSize.ROW))
        // Medium: 8 dp padding, Wambi (64) and 10 on each side of the text, the eye, the ＋ column (40).
        assertEquals(250.dp - 16.dp - 64.dp - 20.dp - 36.dp - 40.dp, figureRoom(DpSize(250.dp, 110.dp), WidgetSize.MEDIUM))
        assertEquals(0.dp, figureRoom(DpSize(60.dp, 40.dp), WidgetSize.SMALL))
    }

    @Test
    fun `the app's face from the Flutter assets, or the phone's bold one when the file is missing`() {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        assertEquals(Typeface.DEFAULT_BOLD, FigureFont.load(context, "flutter_assets/assets/fonts/missing.ttf"))
        assertTrue(FigureFont.load(context, FigureFont.PATH) !== Typeface.DEFAULT_BOLD)
    }
}
