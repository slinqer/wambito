package com.wambito.app.launch

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.wambito.app.MainActivity
import com.wambito.app.widget.ServerSetting
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class LaunchLinksTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `the widget's buttons and the tile start this app on their link`() {
        val add = LaunchLinks.intent(context, LaunchLinks.ADD)
        assertEquals(Intent.ACTION_VIEW, add.action)
        assertEquals("wambito://add", add.dataString)
        // The app's own, not-exported entry for its links: no other app can start it.
        assertEquals("com.wambito.app.LaunchLinkAlias", add.component?.className)
        assertEquals("wambito://capture", LaunchLinks.intent(context, LaunchLinks.CAPTURE).dataString)
    }

    private fun viaAlias(link: String) =
        Intent(Intent.ACTION_VIEW, Uri.parse(link)).setClassName(context, "com.wambito.app.LaunchLinkAlias")

    @Test
    fun `only wambito add, capture and due links are taken, and only through the app's own entry`() {
        assertEquals("wambito://add", LaunchLinks.linkOf(LaunchLinks.intent(context, LaunchLinks.ADD)))
        assertEquals("wambito://capture", LaunchLinks.linkOf(viaAlias("wambito://capture")))
        // The "Hoy vence…" notice opens home through the same entry.
        assertEquals("wambito://due", LaunchLinks.linkOf(LaunchLinks.intent(context, LaunchLinks.DUE)))
        // And the guest warning opens "Guarda tu progreso".
        assertEquals("wambito://progress", LaunchLinks.linkOf(LaunchLinks.intent(context, LaunchLinks.PROGRESS)))
        assertNull(LaunchLinks.linkOf(viaAlias("wambito://settings")))
        assertNull(LaunchLinks.linkOf(viaAlias("https://app.wambito.com/auth/verify")))
        assertNull(LaunchLinks.linkOf(Intent(Intent.ACTION_MAIN)))
        assertNull(LaunchLinks.linkOf(null))
    }

    @Test
    fun `anotherSchemeIsIgnored, and the app builds only wambito`() {
        assertEquals("wambito", LaunchLinks.SCHEME)
        for (host in listOf("add", "capture", "due", "progress", "home")) {
            assertNull(LaunchLinks.linkOf(viaAlias("other://$host")))
            assertEquals("wambito://$host", LaunchLinks.linkOf(viaAlias("wambito://$host")))
        }
        for (link in listOf(LaunchLinks.ADD, LaunchLinks.CAPTURE, LaunchLinks.DUE, LaunchLinks.PROGRESS, LaunchLinks.HOME)) {
            assertEquals("wambito", link.scheme)
        }
        assertNull(LaunchLinks.linkOf(viaAlias("wambi://add")))
        // A wambito:// link is not a web link for the router.
        assertFalse(LaunchLinks.isWebLink(viaAlias("wambito://capture")))
    }

    @Test
    fun `another app starting the exported launcher activity with the link does not open capture`() {
        val explicit = Intent(Intent.ACTION_VIEW, Uri.parse("wambito://capture"))
            .setClass(context, MainActivity::class.java)
        assertNull(LaunchLinks.linkOf(explicit))
        assertNull(LaunchLinks.linkOf(Intent(Intent.ACTION_VIEW, Uri.parse("wambito://capture"))))
    }

    @Test
    fun `reopened from recents, the old link is not acted on again`() {
        val again = LaunchLinks.intent(context, LaunchLinks.CAPTURE)
            .addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        assertNull(LaunchLinks.linkOf(again))
    }

    // --- Web links (the magic link) --------------------------------------------------------------

    private fun view(link: String) = Intent(Intent.ACTION_VIEW, Uri.parse(link)).setClass(context, MainActivity::class.java)

    private val verify = "https://app.wambito.com/auth/verify?email=ana%40correo.com&code=123456"

    @Test
    fun `a web link to the configured server's host goes on to the app`() {
        assertFalse(LaunchLinks.isForeignWebLink(view(verify), "app.wambito.com"))
        // Hosts are not case-sensitive.
        assertFalse(LaunchLinks.isForeignWebLink(view(verify), "App.Wambito.com"))
        // The dev stack, from the emulator.
        assertFalse(LaunchLinks.isForeignWebLink(view("http://10.0.2.2:3000/auth/verify?code=1"), "10.0.2.2"))
    }

    @Test
    fun `a web link to any other host is dropped, so no app can sign the person into its account`() {
        assertTrue(LaunchLinks.isForeignWebLink(view("https://evil.example/auth/verify?email=x%40y.z&code=1"), "app.wambito.com"))
        assertTrue(LaunchLinks.isForeignWebLink(view(verify), "wambito.example.org"))
        // A server setting that cannot be read is no host at all: nothing goes on.
        assertTrue(LaunchLinks.isForeignWebLink(view(verify), null))
        assertTrue(LaunchLinks.isForeignWebLink(view("https:///auth/verify"), "app.wambito.com"))
    }

    @Test
    fun `what is not a web link is left to the other rules`() {
        assertFalse(LaunchLinks.isForeignWebLink(LaunchLinks.intent(context, LaunchLinks.ADD), null))
        assertFalse(LaunchLinks.isForeignWebLink(Intent(Intent.ACTION_MAIN), null))
        assertFalse(LaunchLinks.isForeignWebLink(null, null))
    }

    @Test
    fun `the configured server is the one chosen in Settings, else the build's default`() {
        val default = "https://app.wambito.com"
        assertEquals("app.wambito.com", LaunchLinks.serverHost(ServerSetting.Default, default))
        assertEquals("wambito.example.org", LaunchLinks.serverHost(ServerSetting.Chosen("https://wambito.example.org/"), default))
        assertNull(LaunchLinks.serverHost(ServerSetting.Unreadable, default))
    }

    // --- What Flutter's router may read ------------------------------------------------------------

    /** The intent Glance gives a tap on the widget itself, as the emulator's ActivityManager logged it. */
    private val glanceTap = Intent()
        .setClass(context, MainActivity::class.java)
        .setData(Uri.parse("glance-action:/CALLBACK?appWidgetId=5&viewId=2131296449&viewSize=110.09524.dp%20x%2040.0.dp&extraData=0"))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    @Test
    fun `the widget's body tap is a link home, through the app's own entry`() {
        assertEquals("wambito://home", LaunchLinks.intent(context, LaunchLinks.HOME).dataString)
        assertEquals("wambito://home", LaunchLinks.linkOf(LaunchLinks.intent(context, LaunchLinks.HOME)))
    }

    @Test
    fun `the router never reads the data Glance puts on a widget tap, with or without an action`() {
        // Read as a route it was "Page Not Found: no routes for location: glance-action:/CALLBACK?...".
        assertFalse(LaunchLinks.routerMayRead(glanceTap, "app.wambito.com"))
        assertFalse(LaunchLinks.routerMayRead(Intent(glanceTap).setAction(Intent.ACTION_VIEW), "app.wambito.com"))
    }

    @Test
    fun `the router reads only the magic link of the configured server`() {
        val host = "app.wambito.com"
        assertTrue(LaunchLinks.routerMayRead(view(verify), host))
        assertFalse(LaunchLinks.routerMayRead(view(verify), "wambito.example.org"))
        assertFalse(LaunchLinks.routerMayRead(view(verify), null))
        // Data on an intent that is not a view of a link is nobody's route.
        assertFalse(LaunchLinks.routerMayRead(Intent(Intent.ACTION_MAIN, Uri.parse(verify)), host))
        assertFalse(LaunchLinks.routerMayRead(Intent(Intent.ACTION_SEND, Uri.parse(verify)), host))
        assertFalse(LaunchLinks.routerMayRead(LaunchLinks.intent(context, LaunchLinks.ADD), host))
        // No data at all is not a route either, and null is not an intent.
        assertFalse(LaunchLinks.routerMayRead(Intent(Intent.ACTION_MAIN), host))
        assertFalse(LaunchLinks.routerMayRead(null, host))
    }

    // --- The page's "Abrir en Wambito" (apps/web/app/features/sign-in/open-in-app.ts) ----------------

    /** What the web page's button links to, character for character (open-in-app.test.ts). */
    private val intentLink =
        "intent://app.wambito.com/auth/verify" +
            "?email=ana%40example.com&code=424242&lang=es&next=%2Fapp%2Finsights&from=app" +
            "#Intent;scheme=https;package=com.wambito.app;" +
            "S.browser_fallback_url=https%3A%2F%2Fapp.wambito.com%2Fauth%2Fverify" +
            "%3Femail%3Dana%2540example.com%26code%3D424242%26lang%3Des%26next%3D%252Fapp%252Finsights;end"

    /** The intent Chrome starts for [intentLink]: it parses it, and may start only a browsable view. */
    private fun fromBrowser(): Intent =
        Intent.parseUri(intentLink, Intent.URI_INTENT_SCHEME).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            component = null
            selector = null
        }

    @Test
    fun `the page's intent link starts this app on the same https magic link`() {
        val intent = fromBrowser()
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals("com.wambito.app", intent.`package`)
        assertEquals(
            "https://app.wambito.com/auth/verify" +
                "?email=ana%40example.com&code=424242&lang=es&next=%2Fapp%2Finsights&from=app",
            intent.dataString,
        )
        assertEquals(
            "https://app.wambito.com/auth/verify?email=ana%40example.com&code=424242&lang=es&next=%2Fapp%2Finsights",
            intent.getStringExtra("browser_fallback_url"),
        )
    }

    @Test
    fun `MainActivity keeps that intent's link for the router, and takes no wambito link from it`() {
        val intent = fromBrowser()
        assertTrue(LaunchLinks.routerMayRead(intent, "app.wambito.com"))
        assertNull(LaunchLinks.linkOf(intent))
        // On another server the same link is dropped, as any web link is.
        assertFalse(LaunchLinks.routerMayRead(intent, "wambito.example.org"))
    }

    @Test
    fun `the review link carries the transaction id and only comes through the alias`() {
        assertEquals("wambito://review", LaunchLinks.REVIEW.toString())
        assertEquals(Uri.parse("wambito://review/t-1"), LaunchLinks.review("t-1"))
        assertEquals("wambito://review/t-1", LaunchLinks.linkOf(LaunchLinks.intent(context, LaunchLinks.review("t-1"))))
        // The other links take no path; review takes exactly one segment.
        assertNull(LaunchLinks.linkOf(viaAlias("wambito://review")))
        assertNull(LaunchLinks.linkOf(viaAlias("wambito://review/a/b")))
        assertNull(LaunchLinks.linkOf(viaAlias("wambito://add/t-1")))
        assertNull(LaunchLinks.linkOf(Intent(Intent.ACTION_VIEW, Uri.parse("wambito://review/t-1"))))
    }

    @Test
    fun `Android resolves that intent to MainActivity through the manifest's App Link filter`() {
        val resolved = context.packageManager.resolveActivity(fromBrowser(), 0)
        assertEquals(MainActivity::class.java.name, resolved?.activityInfo?.name)
    }

    // --- The web sign-in's QR (phone-first spec 8.1) ---------------------------------------------

    private val signin =
        "wambito://signin?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"

    @Test
    fun `the sign-in QR is taken from the exported activity, the system camera's way in`() {
        assertEquals(signin, LaunchLinks.linkOf(view(signin)))
        assertEquals(signin, LaunchLinks.linkOf(Intent(Intent.ACTION_VIEW, Uri.parse(signin))))
        // only with its query, never with a path, and not again from recents
        assertNull(LaunchLinks.linkOf(view("wambito://signin")))
        assertNull(LaunchLinks.linkOf(view("wambito://signin/x?id=1")))
        assertNull(LaunchLinks.linkOf(view(signin).addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)))
        // the other hosts still come through the alias only
        assertNull(LaunchLinks.linkOf(view("wambito://capture?id=1")))
    }

    @Test
    fun `Android resolves the sign-in QR to MainActivity`() {
        val camera = Intent(Intent.ACTION_VIEW, Uri.parse(signin)).addCategory(Intent.CATEGORY_BROWSABLE)
        val resolved = context.packageManager.resolveActivity(camera, 0)
        assertEquals(MainActivity::class.java.name, resolved?.activityInfo?.name)
    }
}
