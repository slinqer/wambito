package com.wambito.app.widget

import android.content.Context
import androidx.glance.appwidget.testing.unit.assertHasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.isLinearProgressIndicator
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasContentDescription
import androidx.glance.testing.unit.hasText
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.wambito.app.launch.LaunchLinks
import es.antonborri.home_widget.HomeWidgetGlanceState
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId

/** Glance rendering tests for each state of both widgets (spec section 7.1). */
@RunWith(RobolectricTestRunner::class)
class WidgetContentTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val zone = ZoneId.of("America/Bogota")
    private val now = Instant.parse("2026-10-22T20:00:00Z")

    private fun snapshot(
        remaining: Long = 150000000,
        spent: Long = 50000000,
        budgetTotal: Long = 200000000,
        updatedAt: Instant = now.minusSeconds(60),
        hideAmount: Boolean = false,
        mood: String = "happy",
    ) = WidgetSnapshot(
        signedIn = true,
        remaining = remaining,
        spent = spent,
        budgetTotal = budgetTotal,
        currency = "COP",
        locale = "es",
        month = "2026-10",
        mood = mood,
        updatedAt = updatedAt,
        hideAmount = hideAmount,
        theme = "dark",
    )

    private fun model(snapshot: WidgetSnapshot?) = widgetModel(context, snapshot, now, zone)

    @Test
    fun `small, signed in with budgets - the amount, ＋ to the add sheet and 🎤 to capture`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            provideComposable { SmallWidgetContent(model(snapshot())) }
            onNode(hasText("Te quedan")).assertDoesNotExist()
            onNode(hasContentDescription("$1.500.000")).assertExists()
            // The figure is an image in the app's face, not a text in the phone's.
            onNode(hasText("$1.500.000")).assertDoesNotExist()
            onNode(hasContentDescription("Agregar gasto"))
                .assertHasStartActivityClickAction(LaunchLinks.intent(context, LaunchLinks.ADD))
            onNode(hasContentDescription("Decir o escribir un gasto"))
                .assertHasStartActivityClickAction(LaunchLinks.intent(context, LaunchLinks.CAPTURE))
            onNode(hasText("hace un rato")).assertDoesNotExist()
        }

    @Test
    fun `medium, signed in with budgets - Wambi, the month, the progress, ＋ and 🎤`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            provideComposable { MediumWidgetContent(model(snapshot())) }
            onNode(hasContentDescription("Wambito")).assertExists()
            onNode(hasText("Octubre")).assertExists()
            onNode(hasText("Te quedan")).assertExists()
            onNode(hasContentDescription("$1.500.000")).assertExists()
            onNode(isLinearProgressIndicator(0.25f)).assertExists()
            onNode(hasContentDescription("Agregar gasto"))
                .assertHasStartActivityClickAction(LaunchLinks.intent(context, LaunchLinks.ADD))
            onNode(hasContentDescription("Decir o escribir un gasto"))
                .assertHasStartActivityClickAction(LaunchLinks.intent(context, LaunchLinks.CAPTURE))
        }

    @Test
    fun `a 4×2 box draws the medium layout, whichever widget it is`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(DpSize(250.dp, 110.dp))
            provideComposable { SizedWidgetContent(model(snapshot())) }
            onNode(hasContentDescription("Wambito")).assertExists()
            onNode(hasContentDescription("Decir o escribir un gasto")).assertExists()
        }

    @Test
    fun `a 150 dp wide box draws the small layout with amount and both buttons, whichever widget it is`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(DpSize(150.dp, 40.dp))
            provideComposable { SizedWidgetContent(model(snapshot())) }
            onNode(hasContentDescription("$1.500.000")).assertExists()
            onNode(hasContentDescription("Agregar gasto")).assertExists()
            onNode(hasContentDescription("Decir o escribir un gasto")).assertExists()
            onNode(hasContentDescription("Wambito")).assertDoesNotExist()
        }

    @Test
    fun `a 4×1 box draws the row layout with both buttons and no Wambi`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(DpSize(250.dp, 50.dp))
            provideComposable { SizedWidgetContent(model(snapshot())) }
            onNode(hasContentDescription("$1.500.000")).assertExists()
            onNode(hasContentDescription("Agregar gasto")).assertExists()
            onNode(hasContentDescription("Decir o escribir un gasto")).assertExists()
            onNode(hasContentDescription("Wambito")).assertDoesNotExist()
        }

    @Test
    fun `the layout follows the box - a launcher's rounding still gets the medium one`() {
        assertEquals(WidgetSize.SMALL, widgetSizeFor(DpSize(110.dp, 40.dp)))
        assertEquals(WidgetSize.SMALL, widgetSizeFor(DpSize(180.dp, 110.dp)))
        assertEquals(WidgetSize.ROW, widgetSizeFor(DpSize(250.dp, 50.dp)))
        assertEquals(WidgetSize.ROW, widgetSizeFor(DpSize(320.dp, 70.dp)))
        assertEquals(WidgetSize.ROW, widgetSizeFor(DpSize(220.dp, 40.dp)))
        assertEquals(WidgetSize.MEDIUM, widgetSizeFor(DpSize(230.dp, 104.dp)))
        assertEquals(WidgetSize.MEDIUM, widgetSizeFor(DpSize(320.dp, 180.dp)))
    }

    @Test
    fun `both widgets are drawn for their exact box, so the figure gets all the room it has`() {
        // Responsive hands LocalSize its nearest bucket (a 330 dp medium got 220): the figure was cut.
        assertEquals(androidx.glance.appwidget.SizeMode.Exact, WambitoSmallWidget().sizeMode)
        assertEquals(androidx.glance.appwidget.SizeMode.Exact, WambitoMediumWidget().sizeMode)
    }

    @Test
    fun `a tap on the widget itself, on any of its figures, opens home`() {
        val home = LaunchLinks.intent(context, LaunchLinks.HOME)
        val states = listOf(snapshot(), WidgetSnapshot(signedIn = false, locale = "es"))
        for (draw in listOf<@androidx.compose.runtime.Composable (WidgetModel) -> Unit>(
            { SmallWidgetContent(it) },
            { RowWidgetContent(it) },
            { MediumWidgetContent(it) },
        )) {
            for (state in states) {
                runGlanceAppWidgetUnitTest {
                    setContext(context)
                    provideComposable { draw(model(state)) }
                    // The body: its outermost box is the one that takes the tap.
                    onNode(hasStartActivityClickAction(home)).assertExists()
                }
            }
        }
    }

    @Test
    fun `without budgets - Gastado este mes, what was spent, no progress`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            provideComposable {
                MediumWidgetContent(model(snapshot(remaining = -4200000, spent = 4200000, budgetTotal = 0)))
            }
            onNode(hasText("Gastado este mes")).assertExists()
            onNode(hasContentDescription("$42.000")).assertExists()
            onNode(hasText("Te quedan")).assertDoesNotExist()
        }

    @Test
    fun `small, without budgets - just the spent amount`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable {
            SmallWidgetContent(model(snapshot(remaining = -4200000, spent = 4200000, budgetTotal = 0)))
        }
        onNode(hasText("Gastado este mes")).assertDoesNotExist()
        onNode(hasContentDescription("$42.000")).assertExists()
    }

    @Test
    fun `signed out - Abre Wambito para empezar, and no amount at all`() {
        for (draw in listOf<@androidx.compose.runtime.Composable (WidgetModel) -> Unit>(
            { SmallWidgetContent(it) },
            { RowWidgetContent(it) },
            { MediumWidgetContent(it) },
        )) {
            runGlanceAppWidgetUnitTest {
                setContext(context)
                provideComposable { draw(model(WidgetSnapshot(signedIn = false, locale = "es"))) }
                onNode(hasText("Abre Wambito para empezar")).assertExists()
                onNode(hasContentDescription("$")).assertDoesNotExist()
                onNode(hasContentDescription("Agregar gasto")).assertDoesNotExist()
            }
        }
    }

    @Test
    fun `offline - the last figure, with a subtle hace un rato`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable {
            MediumWidgetContent(
                model(snapshot(updatedAt = now.minusSeconds(3600)).copy(refreshFailedAt = now.minusSeconds(60))),
            )
        }
        onNode(hasContentDescription("$1.500.000")).assertExists()
        onNode(hasText("hace un rato")).assertExists()
    }

    private fun offline() =
        model(snapshot(updatedAt = now.minusSeconds(3600)).copy(refreshFailedAt = now.minusSeconds(60)))

    @Test
    fun `offline, row - the stale text sits under the amount`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { RowWidgetContent(offline()) }
        onNode(hasContentDescription("$1.500.000")).assertExists()
        onNode(hasText("hace un rato")).assertExists()
    }

    @Test
    fun `offline, small - the stale text is in the amount's description`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { SmallWidgetContent(offline()) }
        onNode(hasContentDescription("$1.500.000, hace un rato")).assertExists()
        onNode(hasText("hace un rato")).assertDoesNotExist()
    }

    @Test
    fun `small below 150 dp wide - only the two buttons, and a tap elsewhere opens home`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(DpSize(110.dp, 40.dp))
            provideComposable { SizedWidgetContent(model(snapshot())) }
            onNode(hasContentDescription("$1.500.000")).assertDoesNotExist()
            onNode(hasContentDescription("Agregar gasto")).assertExists()
            onNode(hasContentDescription("Decir o escribir un gasto")).assertExists()
            onNode(hasStartActivityClickAction(LaunchLinks.intent(context, LaunchLinks.HOME))).assertExists()
        }

    @Test
    fun `small shows its amount from 150 dp wide`() {
        assertEquals(false, smallShowsAmount(DpSize(110.dp, 40.dp)))
        assertEquals(false, smallShowsAmount(DpSize(149.dp, 40.dp)))
        assertEquals(true, smallShowsAmount(DpSize(150.dp, 40.dp)))
        assertEquals(true, smallShowsAmount(DpSize(180.dp, 110.dp)))
    }

    @Test
    fun `amount hidden - nothing about the money on either size, read aloud as hidden`() {
        val over = snapshot(remaining = -50000000, spent = 250000000, hideAmount = true, mood = "worried")
        for ((hasLabel, draw) in listOf<Pair<Boolean, @androidx.compose.runtime.Composable (WidgetModel) -> Unit>>(
            // Only the medium layout has a label.
            false to { SmallWidgetContent(it) },
            false to { RowWidgetContent(it) },
            true to { MediumWidgetContent(it) },
        )) {
            runGlanceAppWidgetUnitTest {
                setContext(context)
                provideComposable { draw(model(over)) }
                onNode(hasText("••••")).assertDoesNotExist()
                onNode(hasContentDescription("Monto oculto")).assertExists()
                onNode(hasContentDescription("$")).assertDoesNotExist()
                onNode(hasText("Te pasaste")).assertDoesNotExist()
                onNode(hasText("Te quedan")).assertDoesNotExist()
                if (hasLabel) onNode(hasText("Este mes")).assertExists() else onNode(hasText("Este mes")).assertDoesNotExist()
                onNode(hasContentDescription("del presupuesto")).assertDoesNotExist()
                onNode(isLinearProgressIndicator(1f)).assertDoesNotExist()
            }
        }
    }

    @Test
    fun `the bar is read aloud with its percentage`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { MediumWidgetContent(model(snapshot())) }
        onNode(hasContentDescription("25 % del presupuesto gastado")).assertExists()
    }

    @Test
    fun `worried - Wambi's worried face`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        provideComposable { MediumWidgetContent(model(snapshot(mood = "worried"))) }
        onNode(hasContentDescription("Wambito")).assertExists()
    }

    /** Review Focus 4, as the widget reads its stored state: what Dart writes at a sign-out. */
    @Test
    @Config(qualifiers = "es")
    fun `after sign out the widget never shows the previous figure`() {
        val prefs = WidgetSnapshot.preferences(context)
        prefs.edit().putString(WidgetSnapshot.KEY, snapshot().copy(updatedAt = Instant.now()).toJson()).commit()
        for (box in listOf(DpSize(150.dp, 40.dp), DpSize(250.dp, 110.dp))) {
            runGlanceAppWidgetUnitTest {
                setContext(context)
                setAppWidgetSize(box)
                setState(HomeWidgetGlanceState(prefs))
                provideComposable { StoredWidgetContent() }
                onNode(hasContentDescription("$1.500.000")).assertExists()
            }
        }

        // lib/home/widget_snapshot.dart's signedOutSnapshot, as SessionController.signOut writes it.
        prefs.edit()
            .putString(WidgetSnapshot.KEY, """{"v":3,"signedIn":false,"hideAmount":false,"theme":"dark","locale":"es"}""")
            .commit()
        for (box in listOf(DpSize(150.dp, 40.dp), DpSize(250.dp, 110.dp))) {
            runGlanceAppWidgetUnitTest {
                setContext(context)
                setAppWidgetSize(box)
                setState(HomeWidgetGlanceState(prefs))
                provideComposable { StoredWidgetContent() }
                onNode(hasText("Abre Wambito para empezar")).assertExists()
                onNode(hasContentDescription("$1.500.000")).assertDoesNotExist()
                onNode(hasContentDescription("$")).assertDoesNotExist()
            }
        }

        // A phone still holding a version 1 snapshot (written before this version) shows no figure.
        prefs.edit()
            .putString(WidgetSnapshot.KEY, """{"v":1,"kind":"remaining","amount":"$1.500.000","month":"2026-10"}""")
            .commit()
        for (box in listOf(DpSize(110.dp, 40.dp), DpSize(250.dp, 110.dp))) {
            runGlanceAppWidgetUnitTest {
                setContext(context)
                setAppWidgetSize(box)
                setState(HomeWidgetGlanceState(prefs))
                provideComposable { StoredWidgetContent() }
                onNode(hasText("Abre Wambito para empezar")).assertExists()
                onNode(hasContentDescription("$1.500.000")).assertDoesNotExist()
            }
        }
    }
}
