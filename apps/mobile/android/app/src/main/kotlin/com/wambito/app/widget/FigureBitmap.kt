package com.wambito.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import kotlin.math.ceil
import kotlin.math.max

/**
 * The face of the widget's figure: home's hero (`LkText.amountXl`, Fredoka 700 with tabular figures).
 * Glance can only name the phone's fonts, so the figure is a picture drawn with the font file the
 * Flutter app already ships (no copy in `res/font`).
 */
object FigureFont {
    /** Where Flutter packs `assets/fonts/Fredoka-Variable.ttf` in the APK. */
    const val PATH = "flutter_assets/assets/fonts/Fredoka-Variable.ttf"

    /** The hero's weight, set on the variable font's `wght` axis. */
    private const val WEIGHT = 700

    @Volatile private var cached: Typeface? = null

    /** The face, loaded once per process. */
    fun typeface(context: Context): Typeface = cached ?: load(context, PATH).also { cached = it }

    /** The face at [path] in the APK's assets, or the phone's bold one when it cannot be read. */
    fun load(context: Context, path: String): Typeface = try {
        // A missing asset throws here, before build() (which would quietly fall back to the default).
        context.assets.open(path).close()
        Typeface.Builder(context.assets, path)
            .setFontVariationSettings("'wght' $WEIGHT")
            .setWeight(WEIGHT)
            .build() ?: Typeface.DEFAULT_BOLD
    } catch (_: Exception) {
        Typeface.DEFAULT_BOLD
    }
}

/** How small a figure may get to fit its room, against its size, before its end is cut. */
const val MIN_FIGURE_SCALE = 0.7f

/** A drawn figure: the picture, the size it was drawn at and the text it shows (cut, maybe). */
class Figure(val bitmap: Bitmap, val sizePx: Float, val text: String)

/**
 * [text] in white (Glance tints it by the theme), [sizePx] tall, at most [maxWidthPx] wide: a figure
 * too wide shrinks down to [MIN_FIGURE_SCALE] of its size, then loses its end to "…". The picture is
 * exactly as wide as the text and as tall as its line, so it sits like a text would.
 */
fun figureBitmap(text: String, sizePx: Float, maxWidthPx: Int, typeface: Typeface): Figure {
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        color = Color.WHITE
        this.typeface = typeface
        fontFeatureSettings = "'tnum'"
        textSize = sizePx
    }
    val room = max(maxWidthPx, 1).toFloat()
    val width = paint.measureText(text)
    var shown = text
    if (width > room) {
        paint.textSize = max(sizePx * MIN_FIGURE_SCALE, sizePx * room / width)
        if (paint.measureText(text) > room) {
            shown = TextUtils.ellipsize(text, paint, room, TextUtils.TruncateAt.END).toString()
        }
    }
    val metrics = paint.fontMetrics
    val w = ceil(paint.measureText(shown)).toInt().coerceIn(1, max(maxWidthPx, 1))
    val h = ceil(metrics.descent - metrics.ascent).toInt().coerceAtLeast(1)
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    Canvas(bitmap).drawText(shown, 0f, -metrics.ascent, paint)
    return Figure(bitmap, paint.textSize, shown)
}

/** The eye after the figure. */
val eyeSize = 36.dp

/** The ＋ and 🎤 of each layout: their faces, the ledge under them and the gap between them. */
data class ButtonSizes(val add: Dp, val mic: Dp, val gap: Dp)

/** The ledge under every button face, `brandEdge`, as the app's bottom bar draws it. */
val buttonLedge = 3.dp

fun buttonSizesFor(layout: WidgetSize): ButtonSizes = when (layout) {
    WidgetSize.SMALL -> ButtonSizes(add = 32.dp, mic = 28.dp, gap = 4.dp)
    WidgetSize.ROW -> ButtonSizes(add = 34.dp, mic = 28.dp, gap = 8.dp)
    WidgetSize.MEDIUM -> ButtonSizes(add = 40.dp, mic = 32.dp, gap = 3.dp)
}

/** How wide the figure may be in a box of [size] drawn as [layout]: what the rest leaves it. */
fun figureRoom(size: DpSize, layout: WidgetSize): Dp {
    val buttons = buttonSizesFor(layout)
    val rest = when (layout) {
        // Padding 8 each side, the gap before the buttons, ＋ and 🎤 side by side.
        WidgetSize.SMALL -> 16.dp + buttons.gap + buttons.add + buttons.gap + buttons.mic
        WidgetSize.ROW -> 28.dp + buttons.gap + buttons.add + buttons.gap + buttons.mic
        // Padding 8 each side, Wambi (64) with 10 on each side of the text, the ＋/🎤 column.
        WidgetSize.MEDIUM -> 16.dp + 64.dp + 20.dp + buttons.add
    }
    return (size.width - rest - eyeSize).coerceAtLeast(0.dp)
}
