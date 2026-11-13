package com.wambito.app.notices

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class NoticeTextTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `at 9 the payments due today are joined naturally in Spanish`() {
        assertEquals("Hoy vence Arriendo", NoticeText.due(context, listOf("Arriendo"), "es"))
        assertEquals("Hoy vencen Arriendo y Spotify", NoticeText.due(context, listOf("Arriendo", "Spotify"), "es"))
        assertEquals(
            "Hoy vencen Arriendo, Netflix y Spotify",
            NoticeText.due(context, listOf("Arriendo", "Netflix", "Spotify"), "es"),
        )
    }

    @Test
    fun `and in English`() {
        assertEquals("Rent is due today", NoticeText.due(context, listOf("Rent"), "en"))
        assertEquals("Rent and Spotify are due today", NoticeText.due(context, listOf("Rent", "Spotify"), "en"))
        assertEquals(
            "Rent, Netflix and Spotify are due today",
            NoticeText.due(context, listOf("Rent", "Netflix", "Spotify"), "en"),
        )
    }

    @Test
    fun `Spanish says e before a word that starts with the sound i`() {
        assertEquals("Hoy vencen Arriendo e Internet", NoticeText.due(context, listOf("Arriendo", "Internet"), "es"))
        assertEquals("Hoy vencen Luz e Hipoteca", NoticeText.due(context, listOf("Luz", "Hipoteca"), "es"))
        // Not a vowel sound of i: Hielo, Iatrogenia.
        assertEquals("Hoy vencen Luz y Hielo", NoticeText.due(context, listOf("Luz", "Hielo"), "es"))
        assertEquals("Hoy vencen Luz y Spotify", NoticeText.due(context, listOf("Luz", "Spotify"), "es"))
    }

    @Test
    fun `and in Italian`() {
        assertEquals("Oggi scade Affitto", NoticeText.due(context, listOf("Affitto"), "it"))
        assertEquals("Oggi scadono Affitto e Spotify", NoticeText.due(context, listOf("Affitto", "Spotify"), "it"))
        assertEquals(
            "Oggi scadono Affitto, Netflix e Spotify",
            NoticeText.due(context, listOf("Affitto", "Netflix", "Spotify"), "it"),
        )
    }

    @Test
    fun `and in Portuguese from Portugal`() {
        assertEquals("Hoje vence Renda", NoticeText.due(context, listOf("Renda"), "pt"))
        assertEquals("Hoje vencem Renda e Spotify", NoticeText.due(context, listOf("Renda", "Spotify"), "pt"))
        // No "e" for "y" swap before the sound i, which only Spanish makes.
        assertEquals("Hoje vencem Luz e Internet", NoticeText.due(context, listOf("Luz", "Internet"), "pt"))
        assertEquals("Oggi scadono Luce e Internet", NoticeText.due(context, listOf("Luce", "Internet"), "it"))
    }

    @Test
    fun `blank and repeated names are left out`() {
        assertEquals(
            "Hoy vencen Arriendo y Spotify",
            NoticeText.due(context, listOf(" Arriendo ", "", "Spotify", "Arriendo"), "es"),
        )
    }

    @Test
    fun `the guest warning`() {
        assertEquals(
            "Tus datos se borrarán en 15 días si no agregas tu correo. Si borras la app, también los pierdes.",
            NoticeText.guestWarning(context, "es"),
        )
        assertEquals(
            "Your data will be deleted in 15 days if you don't add your email. If you delete the app, you lose them too.",
            NoticeText.guestWarning(context, "en"),
        )
    }

    @Test
    fun `the guest warning in Italian and Portuguese`() {
        assertEquals(
            "I tuoi dati verranno cancellati tra 15 giorni se non aggiungi la tua email. Se elimini l'app, li perdi comunque.",
            NoticeText.guestWarning(context, "it"),
        )
        assertEquals(
            "Os teus dados serão apagados dentro de 15 dias se não adicionares o teu email. Se apagares a app, perdes os dados na mesma.",
            NoticeText.guestWarning(context, "pt"),
        )
    }

    @Test
    @Config(qualifiers = "es")
    fun `no language chosen follows the phone, Spanish here, and a language the app lacks is Spanish`() {
        assertEquals("Hoy vence Arriendo", NoticeText.due(context, listOf("Arriendo"), null))
        assertEquals("Hoy vence Arriendo", NoticeText.due(context, listOf("Arriendo"), "fr"))
    }

    @Test
    @Config(qualifiers = "en")
    fun `no language chosen follows the phone, English here`() {
        assertEquals("Rent is due today", NoticeText.due(context, listOf("Rent"), null))
    }
}
