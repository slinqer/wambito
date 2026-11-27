package com.wambito.app.widget

import android.util.TypedValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.wambito.app.R
import com.wambito.app.launch.LaunchLinks
import es.antonborri.home_widget.HomeWidgetGlanceState
import java.time.Instant
import java.time.ZoneId

/**
 * The layouts, by the box they get. Every one of them has both buttons, 🎤 and ＋, as a 4×1 once
 * lost the 🎤: SMALL (under 220 dp wide, 2×1), ROW (wide and short: a 4×1 on a grid of short rows)
 * and MEDIUM (4×2, and a 4×1 on a grid of tall rows, like One UI's 93 dp).
 */
enum class WidgetSize { SMALL, ROW, MEDIUM }

/**
 * The smallest box the medium layout fits: 4 dp of padding above and below its ＋ over 🎤 (81 dp
 * with their ledges). One UI's 4×1 is 401×93 dp: it gets Wambi and the full-size figure and buttons,
 * as its 4×2 does, instead of the row made for 40 dp.
 */
private val mediumBox = DpSize(220.dp, 88.dp)

/** The smallest box the row layout fits: as wide as the medium one, but 4×1 short. */
private val rowBox = DpSize(220.dp, 40.dp)

/**
 * Both widgets draw the layout that fits the box they really have, not the one they were added
 * as: a 4×2 box once showed the small layout (no Wambi, no 🎤) until the app was opened.
 *
 * Responsive hands `LocalSize` the largest of these boxes that fits, not the real one, and the
 * figure is a picture sized to the room that box leaves (`figureRoom`): with only the four layout
 * boxes a 330 dp medium got 220 and its figure was cut. So the wide boxes come every 35 dp, at the
 * row's and the medium's heights: the room is never more than 35 dp short. 15 boxes, under
 * Android's 16 sized layouts per widget. Exact fits the room to the dp, but Samsung's launcher drew
 * it narrower than its box.
 */
val widgetSizes: Set<DpSize> = buildSet {
    add(DpSize(110.dp, 40.dp))
    add(DpSize(150.dp, 40.dp))
    add(DpSize(180.dp, 40.dp))
    for (width in 220..395 step 35) {
        add(DpSize(width.dp, rowBox.height))
        add(DpSize(width.dp, mediumBox.height))
    }
}

val widgetSizeMode: SizeMode = SizeMode.Responsive(widgetSizes)

/** The layout for a box of [size]: medium when it is wide and tall, row when only wide, else small. */
fun widgetSizeFor(size: DpSize): WidgetSize = when {
    size.width >= mediumBox.width && size.height >= mediumBox.height -> WidgetSize.MEDIUM
    size.width >= rowBox.width -> WidgetSize.ROW
    else -> WidgetSize.SMALL
}

/** Whether the small layout has room for the amount: from 150 dp wide; below it, only the buttons. */
fun smallShowsAmount(size: DpSize): Boolean = size.width >= 150.dp

/**
 * The colours the widget uses, from the app's tokens (lib/theme/tokens.g.dart, generated from
 * docs/design/system/project/tokens.json): night, then day. test/tooling/widget_android_test.dart
 * checks every value against the tokens.
 */
object WidgetPalette {
    // name to (night, day), as ARGB.
    val tokens: Map<String, Pair<Long, Long>> = mapOf(
        "surface" to (0xFF241F48 to 0xFFFFFFFF),
        "ink" to (0xFFF3F0FF to 0xFF221A47),
        "inkMuted" to (0xFFB9B2E0 to 0xFF5B5285),
        "brand" to (0xFF7C4DFF to 0xFF7B3DF0),
        "brandEdge" to (0xFF3F22A3 to 0xFF4A2BBF),
        "onBrand" to (0xFFFFFFFF to 0xFFFFFFFF),
        "stroke" to (0xFF2D2660 to 0xFFE6DEFC),
        "good" to (0xFF7CFFB2 to 0xFF0B7A46),
        "near" to (0xFFFFB547 to 0xFFA85A00),
        "over" to (0xFFFF5C7A to 0xFFC2194A),
    )

    /** [name]'s colour in [theme]: fixed for night or day, following the phone for "system". */
    fun color(name: String, theme: WidgetTheme): ColorProvider {
        val (night, day) = tokens.getValue(name)
        return when (theme) {
            WidgetTheme.NIGHT -> ColorProvider(Color(night))
            WidgetTheme.DAY -> ColorProvider(Color(day))
            WidgetTheme.SYSTEM -> ColorProvider(day = Color(day), night = Color(night))
        }
    }
}

private fun toneColor(tone: Tone): String = when (tone) {
    Tone.GOOD -> "good"
    Tone.NEAR -> "near"
    Tone.OVER -> "over"
}

/**
 * Opens the app on home (a tap anywhere but the buttons: the figures, the face, the empty areas).
 * It is the app's own `wambito://home` link, like the buttons': a plain `actionStartActivity<MainActivity>()`
 * carries Glance's `glance-action:/CALLBACK?...` as data, which Flutter's router took for a route
 * ("Page Not Found") whenever the app was already running.
 */
@Composable
private fun openApp(): Action = linkAction(LaunchLinks.HOME)

@Composable
private fun linkAction(link: android.net.Uri): Action =
    actionStartActivity(LaunchLinks.intent(LocalContext.current, link))

/**
 * A ＋ or 🎤 as the app's bottom bar draws them (spec "Widget buttons"): a `brand` rounded square of
 * [size] with its white icon, standing on a [buttonLedge] of `brandEdge`. Glance has no shadows, so
 * the ledge is a second square under the face; both are the `widget_button` shape, tinted.
 */
@Composable
private fun LedgeButton(
    icon: Int,
    label: String,
    theme: WidgetTheme,
    action: Action,
    size: Dp,
    iconScale: Float,
) {
    val shape = ImageProvider(R.drawable.widget_button)
    Box(
        modifier = GlanceModifier
            .width(size)
            .height(size + buttonLedge)
            .background(shape, ContentScale.FillBounds, ColorFilter.tint(WidgetPalette.color("brandEdge", theme)))
            .semantics { contentDescription = label }
            .clickable(action),
        contentAlignment = Alignment.TopCenter,
    ) {
        Box(
            modifier = GlanceModifier
                .size(size)
                .background(shape, ContentScale.FillBounds, ColorFilter.tint(WidgetPalette.color("brand", theme))),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                provider = ImageProvider(icon),
                contentDescription = null,
                modifier = GlanceModifier.size(size * iconScale),
                colorFilter = ColorFilter.tint(WidgetPalette.color("onBrand", theme)),
            )
        }
    }
}

/** The ＋ of [buttons]: the larger one, its icon 26/58 of it as on the bar. */
@Composable
private fun AddButton(model: WidgetModel.Figures, buttons: ButtonSizes) = LedgeButton(
    icon = R.drawable.ic_widget_add,
    label = model.addLabel,
    theme = model.theme,
    action = linkAction(LaunchLinks.ADD),
    size = buttons.add,
    iconScale = 26f / 58f,
)

/** The 🎤 of [buttons]: the smaller one, its icon 22/44 of it as on the bar. */
@Composable
private fun MicButton(model: WidgetModel.Figures, buttons: ButtonSizes) = LedgeButton(
    icon = R.drawable.ic_widget_mic,
    label = model.captureLabel,
    theme = model.theme,
    action = linkAction(LaunchLinks.CAPTURE),
    size = buttons.mic,
    iconScale = 22f / 44f,
)

@Composable
private fun SignedOutContent(model: WidgetModel.SignedOut, face: Boolean) {
    val theme = model.theme
    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetPalette.color("surface", theme))
            .cornerRadius(20.dp)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .clickable(openApp()),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (face) {
            Image(
                provider = ImageProvider(R.drawable.wambi_happy),
                contentDescription = LocalContext.current.getString(R.string.widget_wambito),
                modifier = GlanceModifier.size(64.dp),
            )
            Spacer(GlanceModifier.width(12.dp))
        }
        Text(
            text = model.message,
            maxLines = 2,
            style = TextStyle(
                color = WidgetPalette.color("ink", theme),
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun Figure(model: WidgetModel.Figures, amountSize: Int, labelLines: Int = 1) {
    val theme = model.theme
    Text(
        text = model.label,
        maxLines = labelLines,
        style = TextStyle(color = WidgetPalette.color("inkMuted", theme), fontSize = 12.sp),
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        FigureImage(model, amountSize, WidgetSize.MEDIUM, model.amountDescription)
        EyeButton(model)
    }
}

/**
 * The amount (or ••••) in home's hero face, as a picture tinted `ink` (spec "Widget figure"): [sizeSp]
 * tall, at most as wide as [layout] leaves it in this box, read aloud as [description] or the amount.
 */
@Composable
private fun FigureImage(model: WidgetModel.Figures, sizeSp: Int, layout: WidgetSize, description: String?) {
    val context = LocalContext.current
    val metrics = context.resources.displayMetrics
    val sizePx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sizeSp.toFloat(), metrics)
    val room = figureRoom(LocalSize.current, layout)
    val figure = figureBitmap(
        model.amount,
        sizePx,
        (room.value * metrics.density).toInt(),
        FigureFont.typeface(context),
    )
    Image(
        provider = ImageProvider(figure.bitmap),
        contentDescription = description ?: model.amount,
        modifier = GlanceModifier.size(
            (figure.bitmap.width / metrics.density).dp,
            (figure.bitmap.height / metrics.density).dp,
        ),
        colorFilter = ColorFilter.tint(WidgetPalette.color("ink", model.theme)),
    )
}

/** The widget's eye, right after the amount: hides or shows it without opening the app. */
@Composable
private fun EyeButton(model: WidgetModel.Figures) {
    Box(
        modifier = GlanceModifier
            .size(eyeSize)
            .cornerRadius(eyeSize / 2)
            .semantics { contentDescription = model.eyeLabel }
            .clickable(actionRunCallback<ToggleHideAmount>()),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            provider = ImageProvider(if (model.hidden) R.drawable.ic_widget_eye_off else R.drawable.ic_widget_eye),
            contentDescription = null,
            modifier = GlanceModifier.size(20.dp),
            colorFilter = ColorFilter.tint(WidgetPalette.color("inkMuted", model.theme)),
        )
    }
}

@Composable
private fun Stale(model: WidgetModel.Figures) {
    val stale = model.stale ?: return
    Text(
        text = stale,
        maxLines = 1,
        style = TextStyle(color = WidgetPalette.color("inkMuted", model.theme), fontSize = 10.sp),
    )
}

/** The ＋ and 🎤 side by side, standing on one line as on the bar. */
@Composable
private fun ButtonsRow(model: WidgetModel.Figures, buttons: ButtonSizes) {
    Row(verticalAlignment = Alignment.Bottom) {
        AddButton(model, buttons)
        Spacer(GlanceModifier.width(buttons.gap))
        MicButton(model, buttons)
    }
}

/**
 * The amount alone on one line, ellipsized: for the boxes too short for a label above it. With
 * [staleInDescription] (no room for the stale line) the stale text is read aloud with the amount.
 */
@Composable
private fun AmountLine(
    model: WidgetModel.Figures,
    size: Int,
    layout: WidgetSize,
    staleInDescription: Boolean,
    modifier: GlanceModifier,
) {
    val stale = model.stale.takeIf { staleInDescription }
    val description = if (stale == null) {
        model.amountDescription
    } else {
        listOf(model.amountDescription ?: model.amount, stale).joinToString(", ")
    }
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        FigureImage(model, size, layout, description)
        EyeButton(model)
    }
}

/**
 * The shared one-line layout of small and row: the amount (when [showAmount]) with the stale line
 * under it (when [staleLine]), then ＋ and 🎤. Without the amount the buttons are centred.
 */
@Composable
private fun LineWidgetContent(
    model: WidgetModel.Figures,
    layout: WidgetSize,
    showAmount: Boolean,
    staleLine: Boolean,
    padding: Dp,
    amountSize: Int,
) {
    val buttons = buttonSizesFor(layout)
    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetPalette.color("surface", model.theme))
            .cornerRadius(20.dp)
            .padding(horizontal = padding, vertical = 2.dp)
            .clickable(openApp()),
        horizontalAlignment = if (showAmount) Alignment.Start else Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showAmount) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                AmountLine(model, amountSize, layout, staleInDescription = !staleLine, modifier = GlanceModifier)
                if (staleLine) Stale(model)
            }
            Spacer(GlanceModifier.width(buttons.gap))
        }
        ButtonsRow(model, buttons)
    }
}

/**
 * Small (2×1): the amount on one line (stale text in its description), then ＋ and 🎤 (32 and 28 dp);
 * no label, no room. Under 150 dp wide ([showAmount] false) only the two buttons.
 */
@Composable
fun SmallWidgetContent(model: WidgetModel, showAmount: Boolean = true) {
    if (model is WidgetModel.SignedOut) return SignedOutContent(model, face = false)
    LineWidgetContent(
        model as WidgetModel.Figures, WidgetSize.SMALL, showAmount, staleLine = false,
        padding = 8.dp, amountSize = 14,
    )
}

/** Row (4×1): the amount on one line with the stale line under it, then ＋ and 🎤 (33 and 28 dp). */
@Composable
fun RowWidgetContent(model: WidgetModel) {
    if (model is WidgetModel.SignedOut) return SignedOutContent(model, face = false)
    LineWidgetContent(
        model as WidgetModel.Figures, WidgetSize.ROW, showAmount = true, staleLine = true,
        padding = 14.dp, amountSize = 20,
    )
}

/** Medium (4×2): Wambi's face, the month, "Te quedan" with its progress bar, ＋ over 🎤 (40 and 32 dp with their ledges, so they fit 100 dp). */
@Composable
fun MediumWidgetContent(model: WidgetModel) {
    if (model is WidgetModel.SignedOut) return SignedOutContent(model, face = true)
    model as WidgetModel.Figures
    val context = LocalContext.current
    val theme = model.theme
    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetPalette.color("surface", theme))
            .cornerRadius(20.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .clickable(openApp()),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            provider = ImageProvider(
                if (model.mood == Mood.WORRIED) R.drawable.wambi_worried else R.drawable.wambi_happy,
            ),
            contentDescription = context.getString(R.string.widget_wambito),
            modifier = GlanceModifier.size(64.dp),
        )
        Spacer(GlanceModifier.width(10.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = model.month,
                maxLines = 1,
                style = TextStyle(
                    color = WidgetPalette.color("brand", theme),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
            )
            Figure(model, amountSize = 24)
            val progress = model.progress
            if (progress != null) {
                Spacer(GlanceModifier.height(6.dp))
                LinearProgressIndicator(
                    progress = progress,
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .cornerRadius(3.dp)
                        .semantics { contentDescription = model.progressDescription.orEmpty() },
                    color = WidgetPalette.color(toneColor(model.tone), theme),
                    backgroundColor = WidgetPalette.color("stroke", theme),
                )
            }
            Stale(model)
        }
        Spacer(GlanceModifier.width(10.dp))
        val buttons = buttonSizesFor(WidgetSize.MEDIUM)
        Column(
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AddButton(model, buttons)
            Spacer(GlanceModifier.height(buttons.gap))
            MicButton(model, buttons)
        }
    }
}

/** [model] in the layout that fits the widget's box. */
@Composable
fun SizedWidgetContent(model: WidgetModel) {
    when (widgetSizeFor(LocalSize.current)) {
        WidgetSize.SMALL -> SmallWidgetContent(model, showAmount = smallShowsAmount(LocalSize.current))
        WidgetSize.ROW -> RowWidgetContent(model)
        WidgetSize.MEDIUM -> MediumWidgetContent(model)
    }
}

/** The widget for what is stored now (home_widget's state: its SharedPreferences). */
@Composable
fun StoredWidgetContent() {
    val preferences = currentState<HomeWidgetGlanceState>().preferences
    val snapshot = WidgetSnapshot.parse(preferences.getString(WidgetSnapshot.KEY, null))
    SizedWidgetContent(widgetModel(LocalContext.current, snapshot, Instant.now(), ZoneId.systemDefault()))
}
