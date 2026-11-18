package com.wambito.app.widget

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
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
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
 * lost the 🎤: SMALL (under 220 dp wide, 2×1), ROW (wide and short, 4×1) and MEDIUM (4×2).
 */
enum class WidgetSize { SMALL, ROW, MEDIUM }

/**
 * The smallest box the medium layout fits: a little under 4×2's 250×110 dp (a 4×2 is about 110 dp
 * tall, so the height stays at 100), for launchers that round down.
 */
private val mediumBox = DpSize(220.dp, 100.dp)

/** The smallest box the row layout fits: as wide as the medium one, but 4×1 short. */
private val rowBox = DpSize(220.dp, 40.dp)

/**
 * Both widgets draw the layout that fits the box they really have, not the one they were added
 * as: a 4×2 box once showed the small layout (no Wambi, no 🎤) until the app was opened.
 */
val widgetSizeMode = SizeMode.Responsive(setOf(DpSize(110.dp, 40.dp), DpSize(150.dp, 40.dp), rowBox, mediumBox))

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

/** A round button of [size]: ＋ (filled) or 🎤 (outlined in brand, as on home). */
@Composable
private fun RoundButton(
    icon: Int,
    label: String,
    filled: Boolean,
    theme: WidgetTheme,
    action: Action,
    size: Dp = 44.dp,
) {
    val brand = WidgetPalette.color("brand", theme)
    Box(
        modifier = GlanceModifier
            .size(size)
            .cornerRadius(size / 2)
            .background(if (filled) brand else WidgetPalette.color("stroke", theme))
            .semantics { contentDescription = label }
            .clickable(action),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            provider = ImageProvider(icon),
            contentDescription = null,
            modifier = GlanceModifier.size(size * 0.55f),
            colorFilter = ColorFilter.tint(if (filled) WidgetPalette.color("onBrand", theme) else brand),
        )
    }
}

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
    Text(
        text = model.amount,
        maxLines = 1,
        modifier = model.amountDescription?.let { description ->
            GlanceModifier.semantics { contentDescription = description }
        } ?: GlanceModifier,
        style = TextStyle(
            color = WidgetPalette.color("ink", theme),
            fontSize = amountSize.sp,
            fontWeight = FontWeight.Bold,
        ),
    )
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

/** The ＋ and 🎤 pair, side by side, [size] dp each and [gap] apart. */
@Composable
private fun ButtonsRow(model: WidgetModel.Figures, size: Dp, gap: Dp) {
    RoundButton(
        icon = R.drawable.ic_widget_add,
        label = model.addLabel,
        filled = true,
        theme = model.theme,
        action = linkAction(LaunchLinks.ADD),
        size = size,
    )
    Spacer(GlanceModifier.width(gap))
    RoundButton(
        icon = R.drawable.ic_widget_mic,
        label = model.captureLabel,
        filled = false,
        theme = model.theme,
        action = linkAction(LaunchLinks.CAPTURE),
        size = size,
    )
}

/**
 * The amount alone on one line, ellipsized: for the boxes too short for a label above it. With
 * [staleInDescription] (no room for the stale line) the stale text is read aloud with the amount.
 */
@Composable
private fun AmountLine(model: WidgetModel.Figures, size: Int, staleInDescription: Boolean, modifier: GlanceModifier) {
    val stale = model.stale.takeIf { staleInDescription }
    val description = if (stale == null) {
        model.amountDescription
    } else {
        listOf(model.amountDescription ?: model.amount, stale).joinToString(", ")
    }
    Text(
        text = model.amount,
        maxLines = 1,
        modifier = description?.let { modifier.semantics { contentDescription = it } } ?: modifier,
        style = TextStyle(
            color = WidgetPalette.color("ink", model.theme),
            fontSize = size.sp,
            fontWeight = FontWeight.Bold,
        ),
    )
}

/**
 * The shared one-line layout of small and row: the amount (when [showAmount]) with the stale line
 * under it (when [staleLine]), then ＋ and 🎤. Without the amount the buttons are centred.
 */
@Composable
private fun LineWidgetContent(
    model: WidgetModel.Figures,
    showAmount: Boolean,
    staleLine: Boolean,
    padding: Dp,
    amountSize: Int,
    buttonSize: Dp,
    gap: Dp,
) {
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
                AmountLine(model, amountSize, staleInDescription = !staleLine, modifier = GlanceModifier)
                if (staleLine) Stale(model)
            }
            Spacer(GlanceModifier.width(gap))
        }
        ButtonsRow(model, size = buttonSize, gap = gap)
    }
}

/**
 * Small (2×1): the amount on one line (stale text in its description), then ＋ and 🎤 at 36 dp;
 * no label, no room. Under 150 dp wide ([showAmount] false) only the two buttons.
 */
@Composable
fun SmallWidgetContent(model: WidgetModel, showAmount: Boolean = true) {
    if (model is WidgetModel.SignedOut) return SignedOutContent(model, face = false)
    LineWidgetContent(
        model as WidgetModel.Figures, showAmount, staleLine = false,
        padding = 8.dp, amountSize = 14, buttonSize = 36.dp, gap = 4.dp,
    )
}

/** Row (4×1): the amount on one line with the stale line under it, then ＋ and 🎤 at 40 dp. */
@Composable
fun RowWidgetContent(model: WidgetModel) {
    if (model is WidgetModel.SignedOut) return SignedOutContent(model, face = false)
    LineWidgetContent(
        model as WidgetModel.Figures, showAmount = true, staleLine = true,
        padding = 14.dp, amountSize = 20, buttonSize = 40.dp, gap = 8.dp,
    )
}

/** Medium (4×2): Wambi's face, the month, "Te quedan" with its progress bar, ＋ and 🎤 (40 dp, so they fit 100 dp). */
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
            .padding(8.dp)
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
        Column(verticalAlignment = Alignment.CenterVertically) {
            RoundButton(
                icon = R.drawable.ic_widget_add,
                label = model.addLabel,
                filled = true,
                theme = theme,
                action = linkAction(LaunchLinks.ADD),
                size = 40.dp,
            )
            Spacer(GlanceModifier.height(4.dp))
            RoundButton(
                icon = R.drawable.ic_widget_mic,
                label = model.captureLabel,
                filled = false,
                theme = theme,
                action = linkAction(LaunchLinks.CAPTURE),
                size = 40.dp,
            )
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
