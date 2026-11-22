package com.wambito.app.background

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * `wambito/background` (lib/background/background_channel.dart), on both engines:
 *
 *  * the headless engine's Dart calls `finished {outcome, captured}` when its run ends: [onFinished]
 *    gets the outcome's name and the answers of the local `POST /v1/captures` as JSON text;
 *  * on the app's engine, native code calls `vaultChanged` (D7) through [notifyVaultChanged]: a
 *    headless run changed the vault file, so the open session refetches and syncs.
 */
class BackgroundChannel(
    messenger: BinaryMessenger,
    private val onFinished: ((outcome: String, captured: List<String>) -> Unit)? = null,
) {
    private val channel = MethodChannel(messenger, NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            when {
                call.method == "finished" && onFinished != null -> {
                    val outcome = call.argument<String>("outcome")
                    if (outcome == null) {
                        result.error("bad_args", "outcome is required", null)
                    } else {
                        val captured = (call.argument<List<Any?>>("captured") ?: emptyList())
                            .mapNotNull { (it as? Map<*, *>)?.let { map -> JSONObject(map).toString() } }
                        onFinished.invoke(outcome, captured)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Tells the app's Dart a headless run changed the vault (on the main thread, as channels need). */
    fun vaultChanged() {
        Handler(Looper.getMainLooper()).post { channel.invokeMethod("vaultChanged", null) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val NAME = "wambito/background"

        /** The app's own engine's channel while it is alive (MainActivity sets and clears it). */
        @Volatile
        var app: BackgroundChannel? = null

        /** D7: tells the app's engine, if one is alive. */
        fun notifyVaultChanged() {
            app?.vaultChanged()
        }
    }
}
