package com.wambito.app.capture

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The headless engine's `wambito/capture` (lib/capture_auto/capture_platform.dart): what
 * `captureMain` reads and acknowledges. Only the two calls the background run makes; the app's own
 * [CaptureChannel] answers the rest on its engine. It needs no activity.
 *
 *  * `takeQueued {userId}` -> `{captures, confirms}`: the queued captures of [userId] (each its
 *    fields plus its stable `key`) and the notification ids confirmed with "Bien". Nothing leaves
 *    the queue here.
 *  * `ackQueued {keys, confirms}` -> null: the engine saved these captures; they leave the queue.
 *    A capture whose key is never acked (the run failed, timed out, was killed) stays queued, and
 *    is never sent anywhere in clear (D23).
 */
class CaptureQueueChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CaptureChannel.NAME)

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeQueued" -> {
                val userId = call.argument<String>("userId")?.takeIf { it.isNotEmpty() }
                if (userId == null) result.error("bad_args", "userId is required", null) else result.success(take(context, userId))
            }
            "ackQueued" -> {
                val keys = call.argument<List<String>>("keys")
                val confirms = call.argument<List<String>>("confirms")
                if (keys == null || confirms == null) {
                    result.error("bad_args", "keys and confirms are required", null)
                } else {
                    ack(context, keys, confirms)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        /** The queued captures of [userId], oldest first, and the "Bien" ids waiting for the vault. */
        fun take(context: Context, userId: String): Map<String, Any> {
            val captures = CaptureQueue(context).all().filter { it.userId == userId }.map { item ->
                val json: JSONObject = item.capture.toJson().put("key", item.key)
                json.keys().asSequence().associateWith { json.get(it) }
            }
            return mapOf("captures" to captures, "confirms" to CaptureQueue(context).confirms())
        }

        /** Removes the captures [keys] and the confirms [confirms] name. */
        fun ack(context: Context, keys: List<String>, confirms: List<String>) {
            CaptureQueue(context).ack(keys, confirms)
        }
    }
}
