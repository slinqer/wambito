package com.wambito.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * The widget picker's previews (spec "Picker preview"): the real widget, drawn by Glance with
 * invented figures (octubre, "Te quedan 312,40 €", the eye open, night), into
 * `build/widget-previews/`. `scripts/gen-widget-previews.sh` runs it and copies them to
 * `res/drawable-nodpi`; never draw them by hand.
 */
@OptIn(ExperimentalGlanceRemoteViewsApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "es-w411dp-h891dp-xxhdpi")
class WidgetPreviewsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val now = Instant.parse("2026-10-22T20:00:00Z")
    private val out = File("build/widget-previews").apply { mkdirs() }

    private fun model(theme: String = "dark", remaining: Long = 31240, hide: Boolean = false) = widgetModel(
        context,
        WidgetSnapshot(
            signedIn = true,
            remaining = remaining,
            spent = 50000 - remaining,
            budgetTotal = 50000,
            currency = "EUR",
            locale = "es",
            month = "2026-10",
            mood = "happy",
            updatedAt = now,
            hideAmount = hide,
            theme = theme,
        ),
        now,
        ZoneId.of("Europe/Madrid"),
    )

    /** [content] in a [size] box, its corners rounded as a launcher clips them, as a PNG. */
    private fun render(name: String, size: DpSize, content: @Composable () -> Unit): File = runBlocking {
        val result = GlanceRemoteViews().compose(context, size) { content() }
        val view = result.remoteViews.apply(context, FrameLayout(context))
        val density = context.resources.displayMetrics.density
        val w = (size.width.value * density).toInt()
        val h = (size.height.value * density).toInt()
        view.measure(
            View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, w, h)
        val drawn = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(drawn))
        val rounded = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(drawn, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val radius = 20 * density
        Canvas(rounded).drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, paint)
        File(out, "$name.png").also { file -> file.outputStream().use { rounded.compress(Bitmap.CompressFormat.PNG, 100, it) } }
    }

    @Test
    fun `the picker previews, small and medium`() {
        val small = render("widget_preview_small", DpSize(180.dp, 60.dp)) { SmallWidgetContent(model()) }
        val medium = render("widget_preview_medium", DpSize(260.dp, 110.dp)) { MediumWidgetContent(model()) }
        assertTrue(small.length() > 0 && medium.length() > 0)
    }

    @Test
    fun `a look at the other states, for review only`() {
        render("check_row", DpSize(300.dp, 56.dp)) { RowWidgetContent(model()) }
        render("check_medium_day", DpSize(260.dp, 110.dp)) { MediumWidgetContent(model(theme = "light")) }
        render("check_small_hidden", DpSize(180.dp, 60.dp)) { SmallWidgetContent(model(hide = true)) }
        render("check_small_long", DpSize(150.dp, 40.dp)) { SmallWidgetContent(model(remaining = 123456789)) }
    }
}
