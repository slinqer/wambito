package com.wambito.app.background

import android.content.Context
import androidx.annotation.VisibleForTesting
import com.wambito.app.capture.CaptureQueueChannel
import com.wambito.app.notices.NoticesChannel
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Duration

/**
 * How a headless run ended: the outcome's name (`done`, `changed`, `signedOut`, `notPreview`,
 * `locked`, `busy`, `failed`, as Dart says it, or `timeout`) and the answers of the local
 * `POST /v1/captures` as JSON text.
 */
data class HeadlessResult(val outcome: String, val captured: List<String>)

object HeadlessHooks {
    /** Replaces [HeadlessRunner.run] in tests. */
    @VisibleForTesting
    var runner: (suspend (Context, String) -> HeadlessResult)? = null

    suspend fun run(context: Context, entrypoint: String): HeadlessResult =
        runner?.invoke(context, entrypoint) ?: HeadlessRunner.run(context, entrypoint)
}

/**
 * A Flutter engine with no activity (D22), for work started by WorkManager: it runs [entrypoint]
 * (`syncMain` or `captureMain`, in lib/main.dart) and waits for `wambito/background` `finished`.
 * The engine registers the plugins itself, plus the channels Dart's background code calls:
 * `wambito/background`, `wambito/capture` (the queue) and `wambito/notices` (no activity).
 *
 * The engine is destroyed in every case: when the run ends, when it times out (`timeout`), when
 * the work is cancelled and when starting it throws (`failed`). Nothing is acknowledged here: the
 * queue only changes through Dart's `ackQueued`.
 */
object HeadlessRunner {
    /** WorkManager stops a job at 10 minutes; the engine gets 9. */
    val BUDGET: Duration = Duration.ofMinutes(9)

    suspend fun run(context: Context, entrypoint: String, timeout: Duration = BUDGET): HeadlessResult {
        val app = context.applicationContext
        val finished = CompletableDeferred<HeadlessResult>()
        var engine: FlutterEngine? = null
        try {
            // Engines are created and started on the main thread.
            withContext(Dispatchers.Main) {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
                val created = FlutterEngine(app)
                engine = created
                val messenger = created.dartExecutor.binaryMessenger
                BackgroundChannel(messenger) { outcome, captured ->
                    finished.complete(HeadlessResult(outcome, captured))
                }
                CaptureQueueChannel(app, messenger)
                NoticesChannel(app, null, messenger)
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint),
                )
            }
            return withTimeoutOrNull(timeout.toMillis()) { finished.await() }
                ?: HeadlessResult("timeout", emptyList())
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            return HeadlessResult("failed", emptyList())
        } finally {
            withContext(NonCancellable + Dispatchers.Main) { engine?.destroy() }
        }
    }
}
