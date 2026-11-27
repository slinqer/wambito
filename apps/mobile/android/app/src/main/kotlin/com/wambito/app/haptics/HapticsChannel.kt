package com.wambito.app.haptics

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's motor (lib/feedback/feedback_platform.dart), on the `wambito/haptics` method channel.
 *
 * `vibrate({waveform, primitives})` → Boolean (a motor played it) plays the feel of an event (see [HapticSpec]). On Android 11
 * (API 30) and up, when the motor supports every primitive asked for (or its fallback), it plays a
 * `VibrationEffect.Composition` (a crisp click or tick, or the deeper thud and low tick of
 * Android 12, played as a click and a tick by a motor without them); otherwise, and on older phones, the
 * waveform: the web's own pattern. A phone with no motor, or with vibration turned off, does
 * nothing, and no call fails because of it. The VIBRATE permission is a normal one, granted at
 * install.
 */
class HapticsChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val methods = MethodChannel(messenger, "wambito/haptics")
    private val context = context.applicationContext

    init {
        methods.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "vibrate" -> {
                val spec = HapticSpec.parse(call.arguments)
                if (spec == null) {
                    result.error("bad-pattern", "Nothing sound to play", null)
                    return
                }
                try {
                    result.success(Haptics.play(context, spec))
                } catch (e: RuntimeException) {
                    // A motor that refuses (a security exception, say) is no reason to fail a save.
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

}
