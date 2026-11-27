package com.wambito.app.haptics

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Plays a [HapticSpec] on the phone's motor: for the app ([HapticsChannel]) and for the widget's
 * eye, which vibrates without the app. A composition on Android 11+ when the motor has every
 * primitive (or its fallback), else the waveform; no motor, or vibration off, plays nothing.
 */
object Haptics {
    /** Whether the phone has a motor and was asked to play. */
    fun play(context: Context, spec: HapticSpec): Boolean {
        val motor = vibratorOf(context)?.takeIf { it.hasVibrator() } ?: return false
        val effect = composition(motor, spec) ?: VibrationEffect.createWaveform(spec.timings(), -1)
        vibrate(motor, effect)
        return true
    }

    /** The composition for [spec], or null when this phone cannot play it (API below 30, say). */
    private fun composition(motor: Vibrator, spec: HapticSpec): VibrationEffect? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || spec.primitives.isEmpty()) return null
        // Each step as itself, or as its fallback (a `thud` as a `click`) where the motor lacks it.
        val ids = spec.primitives.map { step ->
            val own = primitiveId(step.name)
            when {
                motor.areAllPrimitivesSupported(own) -> own
                step.fallback != null -> primitiveId(step.fallback!!)
                else -> return null
            }
        }
        if (!motor.areAllPrimitivesSupported(*ids.toIntArray())) return null
        val composition = VibrationEffect.startComposition()
        spec.primitives.forEachIndexed { index, step ->
            composition.addPrimitive(ids[index], step.scale, step.delayMs)
        }
        return composition.compose()
    }

    // THUD and LOW_TICK are API 31 constants, inlined at compile time: on Android 11 the motor
    // simply reports them unsupported, and the fallback plays.
    private fun primitiveId(name: String): Int = when (name) {
        "click" -> VibrationEffect.Composition.PRIMITIVE_CLICK
        "thud" -> VibrationEffect.Composition.PRIMITIVE_THUD
        "lowTick" -> VibrationEffect.Composition.PRIMITIVE_LOW_TICK
        else -> VibrationEffect.Composition.PRIMITIVE_TICK
    }

    // A touch on Android 13+ (it follows the phone's "touch feedback" setting, as a keyboard's tick
    // does); below, the sonification usage, which that setting does not gate.
    @Suppress("DEPRECATION")
    private fun vibrate(motor: Vibrator, effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            motor.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            motor.vibrate(
                effect,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun vibratorOf(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
}
