package com.wambito.app.launch

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.wambito.app.widget.ServerSetting

/**
 * The app's own links (spec sections 7.1 and 7.2): `wambito://add` opens the add sheet with the
 * keypad ready (the widget's ＋), `wambito://capture` opens quick capture listening (the widget's 🎤
 * and the Quick Settings tile), `wambito://due` opens home with the payments due today (the "Hoy
 * vence…" notice), `wambito://progress` opens "Guarda tu progreso" (the guest warning),
 * `wambito://home` opens home (a tap on the widget itself). MainActivity keeps them from Flutter's router and hands them to Dart
 * (lib/launch/launch_links.dart), which opens them once the session has loaded.
 *
 * They reach the app only through [ALIAS], an activity-alias of `MainActivity` that is not exported
 * (AndroidManifest.xml): the widget and the tile start it as the app itself; no other app can,
 * so none can open the microphone. A link sent to the exported launcher activity is ignored.
 *
 * The one exception is [SIGNIN_HOST]: `wambito://signin?id=…&key=…` is the QR a browser shows to be
 * signed in by this phone (phone-first spec 8.1, ruling 14), and the system camera opens it, so
 * it comes to the exported `MainActivity` (its own intent filter). It only opens the approval
 * screen, where the person still has to approve, and only with the vault open (Dart).
 */
object LaunchLinks {
    /** The scheme of the links the app builds. */
    const val SCHEME = "wambito"

    val ADD: Uri = Uri.parse("wambito://add")
    val CAPTURE: Uri = Uri.parse("wambito://capture")

    /** The "Hoy vence…" notice (spec section 7.2): home, with the payments due today in view. */
    val DUE: Uri = Uri.parse("wambito://due")

    /** The guest warning (spec section 7.2): "Guarda tu progreso". */
    val PROGRESS: Uri = Uri.parse("wambito://progress")

    /** A tap on the widget itself (not its ＋ or 🎤): home, whatever the widget's area. */
    val HOME: Uri = Uri.parse("wambito://home")
    private val HOSTS = setOf("add", "capture", "due", "progress", "home", "review")

    /** A web sign-in's QR, opened by the system camera: the one link any app may send. */
    const val SIGNIN_HOST = "signin"

    /** `wambito://review/<id>` opens a detected transaction's review ("Cambiar" on its notification). */
    val REVIEW: Uri = Uri.parse("wambito://review")

    /** The link for transaction [id]'s review. */
    fun review(id: String): Uri = Uri.parse("$REVIEW/${Uri.encode(id)}")

    /** The not-exported entry the links come through (an alias of `MainActivity`). */
    const val ALIAS = "com.wambito.app.LaunchLinkAlias"

    /** What the widget's buttons and the tile start: this app's own link entry on [link]. */
    fun intent(context: Context, link: Uri): Intent =
        Intent(Intent.ACTION_VIEW, link)
            .setClassName(context, ALIAS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    /**
     * The `wambito://add`, `capture`, `due`, `progress`, `home` or `review/<id>` link [intent] carries
     * through [ALIAS], or a `wambito://signin?…` from anywhere ([SIGNIN_HOST]); else null. An
     * activity reopened from recents gets its first intent again: that one is not acted on twice.
     */
    fun linkOf(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val data = intent.data ?: return null
        if (data.scheme == SCHEME && data.host == SIGNIN_HOST) {
            // No path; Dart reads the id and key (lib/launch/launch_links.dart).
            return if (data.path.isNullOrEmpty() && !data.query.isNullOrEmpty()) data.toString() else null
        }
        if (intent.component?.className != ALIAS) return null
        if (data.scheme != SCHEME || data.host !in HOSTS) return null
        val path = data.path.orEmpty()
        if (data.host == "review") {
            // Exactly one segment: the transaction's id.
            if (data.pathSegments.size != 1 || data.pathSegments[0].isEmpty()) return null
        } else if (path.isNotEmpty() && path != "/") {
            return null
        }
        return data.toString()
    }

    /**
     * Whether [intent] is a web link (the sign-in email's magic link) for a host other than
     * [serverHost], the configured server's. `MainActivity` is exported, and Flutter routes an
     * opened link by its path alone, so without this any app could send `https://<any
     * host>/auth/verify?email=…&code=…` and sign the person into the sender's account. Such a link
     * is dropped and only opens the app. A null [serverHost] (the setting can't be read) matches
     * nothing.
     */
    fun isForeignWebLink(intent: Intent?, serverHost: String?): Boolean {
        if (!isWebLink(intent)) return false
        val host = intent?.data?.host
        return host.isNullOrEmpty() || serverHost == null || !host.equals(serverHost, ignoreCase = true)
    }

    /**
     * Whether Flutter's router may read [intent]'s data as a route: only the sign-in email's magic
     * link, an `ACTION_VIEW` of an http(s) address on [serverHost]'s host. With deep linking on,
     * Flutter hands any intent's data to the router, and Glance puts `glance-action:/CALLBACK?...`
     * on every tap on the widget itself: read as a route, it was "Page Not Found". Anything else
     * has its data stripped before Flutter sees it (MainActivity).
     */
    fun routerMayRead(intent: Intent?, serverHost: String?): Boolean {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return false
        val scheme = intent.data?.scheme
        if (scheme != "https" && scheme != "http") return false
        return !isForeignWebLink(intent, serverHost)
    }

    /** Whether [intent] opens a link in any scheme that is not `wambito://` (the app's own). */
    fun isWebLink(intent: Intent?): Boolean {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return false
        val data = intent.data ?: return false
        return data.scheme != SCHEME
    }

    /** The host of the server the app talks to: the one chosen in Settings, else [defaultServer]. */
    fun serverHost(setting: ServerSetting, defaultServer: String): String? = when (setting) {
        ServerSetting.Default -> Uri.parse(defaultServer).host
        is ServerSetting.Chosen -> Uri.parse(setting.url).host
        ServerSetting.Unreadable -> null
    }
}
