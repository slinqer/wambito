package com.wambito.app.capture

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import androidx.work.workDataOf
import com.wambito.app.account.AccountMode
import com.wambito.app.background.HeadlessHooks
import com.wambito.app.background.HeadlessResult
import com.wambito.app.notices.ApiResult
import com.wambito.app.widget.ServerSetting
import com.wambito.app.widget.SessionSource
import com.wambito.app.widget.TinyHttpServer
import com.wambito.app.widget.TinyRequest
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

private class FakeSession(var stored: String?, var serverUrl: String?) : SessionSource {
    var serverUnreadable = false
    override fun guest(): Boolean? = null
    override fun token(): String? = stored
    override fun mark(): String? = stored?.let { "mark:$it" }
    override fun server(): ServerSetting = when {
        serverUnreadable -> ServerSetting.Unreadable
        serverUrl == null -> ServerSetting.Default
        else -> ServerSetting.Chosen(serverUrl!!)
    }
}

private class RecordingNotifier : CaptureNotifier {
    val shown = mutableListOf<CaptureAnswer>()
    val signIn = mutableListOf<Int>()
    val dismissed = mutableListOf<String>()
    override fun show(context: Context, answer: CaptureAnswer) {
        shown += answer
    }

    override fun dismiss(context: Context, transactionId: String) {
        dismissed += transactionId
    }

    override fun signInNeeded(context: Context, count: Int) {
        signIn += count
    }
}

@RunWith(RobolectricTestRunner::class)
class CaptureWorkersTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private lateinit var server: TinyHttpServer
    private lateinit var session: FakeSession
    private lateinit var queue: CaptureQueue
    private val notifier = RecordingNotifier()
    private val requests = mutableListOf<TinyRequest>()

    /** The status to answer a POST with, by merchant; 201 when absent. */
    private val statusFor = mutableMapOf<String, Int>()
    private var patchStatus = 200

    /** Merchants whose capture the server already holds as confirmed (`needsReview` false). */
    private val confirmed = mutableSetOf<String>()
    private var whileAnswering: (() -> Unit)? = null

    private fun answer(merged: Boolean, merchant: String, amount: Long) = """
        {"result":"${if (merged) "merged" else "created"}",
         "transaction":{"id":"t-$merchant","name":"$merchant","amount":-$amount,"currency":"EUR",
           "date":"2026-11-04","status":"posted","needsReview":${merchant !in confirmed}},
         "category":{"name":"Supermercado","fallback":false}}
    """.trimIndent()

    @Before
    fun setUp() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        server = TinyHttpServer { request ->
            requests += request
            whileAnswering?.invoke()
            when {
                request.method == "POST" && request.path.endsWith("/api/v1/captures") -> {
                    val body = JSONObject(request.body)
                    val merchant = body.getString("merchant")
                    val status = statusFor[merchant] ?: 201
                    when {
                        status == 201 || status == 200 -> status to answer(status == 200, merchant, body.getLong("amount"))
                        else -> status to "{}"
                    }
                }
                request.method == "POST" && request.path.endsWith("/api/v1/transactions/review") -> patchStatus to "{}"
                else -> 404 to "{}"
            }
        }
        session = FakeSession("token-1", "http://127.0.0.1:${server.port}")
        queue = CaptureQueue(context)
        queue.adopt("user-1", session.mark())
        CaptureHooks.dependencies = { CaptureDependencies(session = session) }
        CaptureHooks.notifier = notifier
    }

    @After
    fun tearDown() {
        HeadlessHooks.runner = null
        CaptureHooks.dependencies = null
        CaptureHooks.notifier = object : CaptureNotifier {
            override fun show(context: Context, answer: CaptureAnswer) = Unit
            override fun signInNeeded(context: Context, count: Int) = Unit
            override fun dismiss(context: Context, transactionId: String) = Unit
        }
        server.stop()
        queue.clear()
    }

    private fun runSend(): ListenableWorker.Result = runBlocking {
        TestListenableWorkerBuilder<SendCapturesWorker>(context).build().doWork()
    }

    private fun posts() = requests.filter { it.method == "POST" }

    /** What the fake headless run does to the queue, as Dart's `captureMain` would. */
    private class FakeRun(val outcome: String, val saves: (List<QueuedCapture>) -> List<QueuedCapture> = { emptyList() })

    private val entrypoints = mutableListOf<String>()

    private fun headless(run: FakeRun, context: Context = this.context) {
        HeadlessHooks.runner = { _, entry ->
            entrypoints += entry
            val saved = run.saves(CaptureQueue(context).all())
            CaptureQueueChannel.ack(context, saved.map { it.key }, emptyList())
            HeadlessResult(
                run.outcome,
                saved.map { answer(false, it.capture.merchant, it.capture.amountCents) },
            )
        }
    }

    private fun previewQueue(vararg merchants: String): List<QueuedCapture> {
        AccountMode(context).value = "preview"
        return merchants.map { queue.add(sampleCapture(it)) }
    }

    private fun runSendAt(attempt: Int): ListenableWorker.Result = runBlocking {
        TestListenableWorkerBuilder<SendCapturesWorker>(context).setRunAttemptCount(attempt).build().doWork()
    }

    @Test
    fun `preview capture never reaches the api`() {
        previewQueue("Mercadona", "Café")
        headless(FakeRun("changed") { it })

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertEquals(listOf("captureMain"), entrypoints)
        assertTrue(requests.isEmpty())
        assertEquals(listOf("t-Mercadona", "t-Café"), notifier.shown.map { it.id })
        assertTrue(queue.all().isEmpty())
        assertTrue(notifier.signIn.isEmpty())
    }

    @Test
    fun `the same transaction is announced once`() {
        previewQueue("Mercadona")
        HeadlessHooks.runner = { _, _ ->
            val twice = answer(false, "Mercadona", 1250)
            HeadlessResult("done", listOf(twice, twice))
        }
        runSend()
        assertEquals(listOf("t-Mercadona"), notifier.shown.map { it.id })
    }

    @Test
    fun `a merged capture already confirmed asks nothing`() {
        previewQueue("Mercadona")
        confirmed += "Mercadona"
        HeadlessHooks.runner = { _, _ -> HeadlessResult("changed", listOf(answer(true, "Mercadona", 1250))) }
        runSend()
        assertTrue(notifier.shown.isEmpty())
        assertEquals(listOf("t-Mercadona"), notifier.dismissed)
    }

    @Test
    fun `engine failure keeps the queue and never sends anything`() {
        previewQueue("Mercadona", "Café")
        headless(FakeRun("failed"))

        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(2, queue.all().size)
        assertTrue(requests.isEmpty())

        val last = runSendAt(SendCapturesWorker.MAX_ATTEMPTS - 1)
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "kept")), last)
        assertEquals(2, queue.all().size)
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `every outcome but done and changed keeps the queue`() {
        for (outcome in listOf("signedOut", "notPreview", "locked", "busy", "failed", "timeout")) {
            queue.clear()
            queue.adopt("user-1", session.mark())
            previewQueue("Mercadona")
            headless(FakeRun(outcome))
            assertEquals(outcome, ListenableWorker.Result.retry(), runSend())
            assertEquals(outcome, 1, queue.all().size)
        }
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `timeout keeps the queue`() {
        previewQueue("Mercadona", "Café")
        HeadlessHooks.runner = { _, _ -> HeadlessResult("timeout", emptyList()) }

        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(2, queue.all().size)
        val last = runSendAt(SendCapturesWorker.MAX_ATTEMPTS - 1)
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "kept")), last)
        assertEquals(2, queue.all().size)
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `a capture the vault refuses is dropped at the eighth finished run, engine failures never count`() {
        val items = previewQueue("Mercadona", "Café")
        // The vault takes the first and refuses the second, run after run.
        headless(FakeRun("done") { all -> all.filter { it.capture.merchant == "Mercadona" } })

        // Failed runs in between do not count.
        repeat(5) {
            HeadlessHooks.runner = { _, _ -> HeadlessResult("failed", emptyList()) }
            runSend()
        }
        headless(FakeRun("done") { all -> all.filter { it.capture.merchant == "Mercadona" } })
        for (run in 1 until CaptureQueue.MAX_REFUSALS) {
            assertEquals(ListenableWorker.Result.retry(), runSend())
            assertEquals("run $run", listOf(items[1].key), queue.all().map { it.key })
        }
        val last = runSendAt(SendCapturesWorker.MAX_ATTEMPTS - 1)
        assertEquals(ListenableWorker.Result.success().javaClass, last.javaClass)
        assertTrue(queue.all().isEmpty())
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `a refused capture is dropped without a trace of its finances in the log`() {
        previewQueue("Mercadona")
        headless(FakeRun("done"))
        val lines = mutableListOf<String>()
        SendCapturesWorker.log = { lines += it }
        try {
            repeat(CaptureQueue.MAX_REFUSALS) { runSend() }
        } finally {
            SendCapturesWorker.log = { }
        }
        assertTrue(queue.all().isEmpty())
        assertEquals(1, lines.size)
        assertTrue(lines.none { it.contains("Mercadona") || it.contains("1250") })
    }

    @Test
    fun `the send for a preview account waits for no network`() {
        previewQueue("Mercadona")
        CaptureScheduler.enqueueSend(context)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get()
        assertEquals(NetworkType.NOT_REQUIRED, work[0].constraints.requiredNetworkType)
    }

    @Test
    fun `a mode the app has not learned yet sends nothing and tries again later`() {
        AccountMode(context).value = "unknown"
        queue.add(sampleCapture("Mercadona"))

        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertTrue(requests.isEmpty())
        assertEquals(1, queue.all().size)

        AccountMode(context).value = "plain"
        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)
        assertTrue(queue.all().isEmpty())
    }

    @Test
    fun `a mode that stays unknown stops retrying after the last attempt`() {
        AccountMode(context).value = "unknown"
        queue.add(sampleCapture("Mercadona"))
        val last = runBlocking {
            TestListenableWorkerBuilder<SendCapturesWorker>(context)
                .setRunAttemptCount(ConfirmCaptureWorker.MAX_ATTEMPTS - 1).build().doWork()
        }
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "mode unknown")), last)
        assertTrue(requests.isEmpty())
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `Bien on preview goes to the vault, never to the api`() {
        previewQueue()
        var seen: List<String> = emptyList()
        HeadlessHooks.runner = { _, entry ->
            entrypoints += entry
            seen = queue.confirms()
            CaptureQueueChannel.ack(context, emptyList(), seen)
            HeadlessResult("changed", emptyList())
        }
        showOne()
        assertEquals(1, notifications().activeNotifications.size)

        val result = runBlocking {
            TestListenableWorkerBuilder<ConfirmCaptureWorker>(context)
                .setInputData(workDataOf(ConfirmCaptureWorker.ID to "t-1"))
                .build().doWork()
        }

        assertEquals(ListenableWorker.Result.success().javaClass, result.javaClass)
        assertEquals(listOf("t-1"), seen)
        assertEquals(listOf("captureMain"), entrypoints)
        assertTrue(requests.isEmpty())
        assertTrue(queue.confirms().isEmpty())
        assertTrue(notifications().activeNotifications.isEmpty())
    }

    @Test
    fun `Bien on preview keeps the confirm through an engine failure`() {
        previewQueue()
        HeadlessHooks.runner = { _, _ -> HeadlessResult("failed", emptyList()) }
        assertEquals(ListenableWorker.Result.retry(), runConfirm())
        assertEquals(listOf("t-1"), queue.confirms())
        val last = runConfirm(attempt = ConfirmCaptureWorker.MAX_ATTEMPTS - 1)
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "kept")), last)
        assertEquals(listOf("t-1"), queue.confirms())
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `Bien on preview that a finished run never acks is dropped at the last attempt`() {
        previewQueue()
        HeadlessHooks.runner = { _, _ -> HeadlessResult("done", emptyList()) }
        assertEquals(ListenableWorker.Result.retry(), runConfirm())
        assertEquals(listOf("t-1"), queue.confirms())
        runConfirm(attempt = ConfirmCaptureWorker.MAX_ATTEMPTS - 1)
        assertTrue(queue.confirms().isEmpty())
    }

    @Test
    fun `sends and removes on 201`() {
        queue.add(sampleCapture("Mercadona"))

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertTrue(queue.all().isEmpty())
        val answer = notifier.shown.single()
        assertEquals(false, answer.merged)
        assertEquals("t-Mercadona", answer.id)
        assertEquals(-1250L, answer.amountCents)
        assertEquals("Supermercado", answer.categoryName)
        assertEquals(false, answer.isFallback)
    }

    @Test
    fun `sends and removes on 200 merged`() {
        statusFor["Mercadona"] = 200
        queue.add(sampleCapture("Mercadona"))
        runSend()
        assertTrue(queue.all().isEmpty())
        assertEquals(true, notifier.shown.single().merged)
    }

    @Test
    fun `merged into a capture already confirmed asks nothing and takes its notification away`() {
        statusFor["Mercadona"] = 200
        confirmed += "Mercadona"
        queue.add(sampleCapture("Mercadona"))

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertTrue(queue.all().isEmpty())
        assertTrue(notifier.shown.isEmpty())
        assertEquals(listOf("t-Mercadona"), notifier.dismissed)
    }

    @Test
    fun `merged into a capture still to review asks again`() {
        statusFor["Mercadona"] = 200
        queue.add(sampleCapture("Mercadona"))
        runSend()
        val answer = notifier.shown.single()
        assertEquals(true, answer.merged)
        assertEquals(true, answer.needsReview)
        assertTrue(notifier.dismissed.isEmpty())
    }

    @Test
    fun `the poster removes the notification of a capture confirmed meanwhile`() {
        CapturePoster.show(context, CaptureAnswer(false, "t-1", -1250, "EUR", "Mercadona", "Supermercado", false))
        CapturePoster.show(context, CaptureAnswer(false, "t-2", -300, "EUR", "Café", "Café", false))
        assertEquals(3, notifications().activeNotifications.size) // two and the summary

        CapturePoster.dismiss(context, "t-1")

        assertEquals(1, notifications().activeNotifications.size)
    }

    @Test
    fun `the request is a bearer POST with the key, the background header and exactly six fields`() {
        val item = queue.add(sampleCapture("Mercadona"))
        runSend()

        val request = posts().single()
        assertEquals("/api/v1/captures", request.path)
        assertEquals(item.key, request.headers["idempotency-key"])
        assertEquals("Bearer token-1", request.headers["authorization"])
        assertEquals("1", request.headers["x-wambito-background"])
        val body = JSONObject(request.body)
        assertEquals(setOf("kind", "amount", "currency", "merchant", "capturedAt", "source"), body.keys().asSequence().toSet())
        assertEquals("expense", body.getString("kind"))
        assertEquals(1250L, body.getLong("amount"))
        assertEquals("EUR", body.getString("currency"))
        assertEquals("Mercadona", body.getString("merchant"))
        assertEquals("2026-11-04T12:30:15.123Z", body.getString("capturedAt"))
        assertEquals("revolut", body.getString("source"))
    }

    @Test
    fun `a resend after a crash keeps one item and the same key`() {
        queue.add(sampleCapture("Mercadona"))
        statusFor["Mercadona"] = 500
        assertEquals(ListenableWorker.Result.retry(), runSend())

        // The process died; a new queue instance finds the same single item.
        assertEquals(1, CaptureQueue(context).all().size)
        statusFor.clear()
        runSend()

        assertEquals(2, posts().size)
        assertEquals(posts()[0].headers["idempotency-key"], posts()[1].headers["idempotency-key"])
        assertTrue(queue.all().isEmpty())
    }

    @Test
    fun `unauthorized keeps the queue and asks for one sign-in notice with the count`() {
        statusFor["Mercadona"] = 401
        queue.add(sampleCapture("Mercadona"))
        queue.add(sampleCapture("Café"))

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertEquals(2, queue.all().size)
        assertEquals(listOf(2), notifier.signIn)
        assertEquals(1, posts().size)
        assertTrue(notifier.shown.isEmpty())
    }

    @Test
    fun `signed out sends nothing and asks for sign-in`() {
        session.stored = null
        queue.add(sampleCapture())
        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)
        assertTrue(requests.isEmpty())
        assertEquals(listOf(1), notifier.signIn)
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `sends only the captures of the account the queue belongs to`() {
        queue.add(sampleCapture("Mine"))
        // Queued for user-1, then another account's session is stored before the app says whose
        // the queue is now (sendQueued): nothing goes to it until then.
        val prefs = context.getSharedPreferences(CaptureQueue.FILE, Context.MODE_PRIVATE)
        prefs.edit().putString("owner", "user-2").commit()

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertTrue(posts().isEmpty())
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `a token written after the last sendQueued sends nothing until sendQueued`() {
        queue.add(sampleCapture("Kept through a 401"))
        // Another account's token is stored; the app has not said whose the queue is yet.
        session.stored = "token-2"

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)
        assertTrue(posts().isEmpty())
        assertEquals(1, queue.all().size)

        CaptureScheduler.sendQueued(context, "user-1")
        runSend()
        assertEquals(1, posts().size)
        assertEquals("Bearer token-2", posts().single().headers["authorization"])
        assertTrue(queue.all().isEmpty())
    }

    @Test
    fun `sendQueued binds the queue to the session of the moment`() {
        CaptureScheduler.sendQueued(context, "user-1")
        assertEquals("mark:token-1", queue.ownerMark())
        queue.clear()
        assertEquals(null, queue.ownerMark())
    }

    @Test
    fun `sendQueued for another account drops the old captures and sends nothing of them`() {
        queue.add(sampleCapture("Old account"))
        CaptureScheduler.sendQueued(context, "user-2")
        assertTrue(queue.all().isEmpty())
        assertEquals("user-2", queue.owner())
        val jobs = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get()
        assertTrue(jobs.isEmpty())
    }

    @Test
    fun `sendQueued for the same account keeps its captures and enqueues the send`() {
        queue.add(sampleCapture("Kept through a 401"))
        CaptureScheduler.sendQueued(context, "user-1")
        assertEquals(1, queue.all().size)
        val jobs = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get()
        assertEquals(1, jobs.size)
        runSend()
        assertTrue(queue.all().isEmpty())
        assertEquals(1, notifier.shown.size)
    }

    @Test
    fun `server error retries and keeps the item`() {
        statusFor["Mercadona"] = 503
        queue.add(sampleCapture("Mercadona"))
        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(1, queue.all().size)
        assertTrue(notifier.shown.isEmpty())
    }

    @Test
    fun `drops a rejected capture and goes on with the next`() {
        statusFor["Broken"] = 422
        queue.add(sampleCapture("Broken"))
        queue.add(sampleCapture("Mercadona"))

        assertEquals(ListenableWorker.Result.success().javaClass, runSend().javaClass)

        assertTrue(queue.all().isEmpty())
        assertEquals(listOf("t-Mercadona"), notifier.shown.map { it.id })
        assertEquals(2, posts().size)
    }

    @Test
    fun `too many requests is not a rejection, it is tried again`() {
        statusFor["Mercadona"] = 429
        queue.add(sampleCapture("Mercadona"))
        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `retries when the server lacks the endpoint (404)`() {
        statusFor["Mercadona"] = 404
        queue.add(sampleCapture("Mercadona"))
        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(1, queue.all().size)
        statusFor["Mercadona"] = 403
        assertEquals(ListenableWorker.Result.retry(), runSend())
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `an unreadable server setting sends nothing, never the token to the default server`() {
        session.serverUnreadable = true
        queue.add(sampleCapture())
        runSend()
        assertTrue(requests.isEmpty())
        assertEquals(1, queue.all().size)
    }

    @Test
    fun `a sign-out while the request is on its way saves nothing on the screen`() {
        queue.add(sampleCapture("Mercadona"))
        val rest = queue.add(sampleCapture("Café"))
        whileAnswering = { session.stored = null }
        runSend()
        assertTrue(notifier.shown.isEmpty())
        // The first was saved by the server, so it left the queue; the rest stayed for a sign-in.
        assertEquals(listOf(rest), queue.all())
        assertEquals(1, posts().size)
    }

    @Test
    fun `the server chosen in Settings is used with any path it has`() {
        session.serverUrl = "http://127.0.0.1:${server.port}/wambito/"
        queue.add(sampleCapture())
        runSend()
        assertEquals("/wambito/api/v1/captures", posts().single().path)
    }

    @Test
    fun `confirm posts the id to the review endpoint`() {
        val result = CaptureApi().confirm("http://127.0.0.1:${server.port}", "token-1", "t-1")
        assertEquals(ApiResult.Ok(Unit), result)
        val request = requests.single()
        assertEquals("POST", request.method)
        assertEquals("/api/v1/transactions/review", request.path)
        assertEquals("""{"ids":["t-1"]}""", request.body)
        assertEquals("1", request.headers["x-wambito-background"])
    }

    @Test
    fun `confirm tells a refused session apart`() {
        patchStatus = 401
        assertEquals(ApiResult.Unauthorized, CaptureApi().confirm("http://127.0.0.1:${server.port}", "t", "t-1"))
        patchStatus = 500
        assertEquals(ApiResult.Failed, CaptureApi().confirm("http://127.0.0.1:${server.port}", "t", "t-1"))
    }

    @Test
    fun `confirm takes a 4xx other than 401, 408 and 429 as refused for good`() {
        val url = "http://127.0.0.1:${server.port}"
        for (status in listOf(400, 403, 404, 409, 422)) {
            patchStatus = status
            assertEquals("status $status", ApiResult.Rejected, CaptureApi().confirm(url, "t", "t-1"))
        }
        for (status in listOf(408, 429)) {
            patchStatus = status
            assertEquals("status $status", ApiResult.Failed, CaptureApi().confirm(url, "t", "t-1"))
        }
    }

    private fun runConfirm(id: String = "t-1", attempt: Int = 0): ListenableWorker.Result = runBlocking {
        TestListenableWorkerBuilder<ConfirmCaptureWorker>(context)
            .setInputData(workDataOf(ConfirmCaptureWorker.ID to id))
            .setRunAttemptCount(attempt)
            .build()
            .doWork()
    }

    private fun notifications() = context.getSystemService(android.app.NotificationManager::class.java)

    private fun showOne() = CapturePoster.show(context, CaptureAnswer(false, "t-1", -1250, "EUR", "Mercadona", "Supermercado", false))

    @Test
    fun `confirm posts to the review endpoint and cancels the notification`() {
        showOne()
        assertEquals(1, notifications().activeNotifications.size)

        assertEquals(ListenableWorker.Result.success().javaClass, runConfirm().javaClass)

        assertEquals("""{"ids":["t-1"]}""", requests.single().body)
        assertEquals("Bearer token-1", requests.single().headers["authorization"])
        assertTrue(notifications().activeNotifications.isEmpty())
    }

    @Test
    fun `confirm retries on failure and keeps the notification`() {
        showOne()
        patchStatus = 500
        assertEquals(ListenableWorker.Result.retry(), runConfirm())
        assertEquals(1, notifications().activeNotifications.size)
    }

    @Test
    fun `confirm of a deleted transaction (404) drops the notification and does not retry`() {
        showOne()
        patchStatus = 404
        val result = runConfirm()
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "rejected")), result)
        assertTrue(notifications().activeNotifications.isEmpty())
    }

    @Test
    fun `confirm gives up after its last attempt and leaves the notification for another Bien`() {
        showOne()
        patchStatus = 500
        assertEquals(ListenableWorker.Result.retry(), runConfirm(attempt = ConfirmCaptureWorker.MAX_ATTEMPTS - 2))
        val last = runConfirm(attempt = ConfirmCaptureWorker.MAX_ATTEMPTS - 1)
        assertEquals(ListenableWorker.Result.success(workDataOf(CAPTURE_OUTCOME to "gave up")), last)
        assertEquals(1, notifications().activeNotifications.size)
    }

    @Test
    fun `confirm with a refused session or none keeps the notification and does not retry`() {
        showOne()
        patchStatus = 401
        assertEquals(ListenableWorker.Result.success().javaClass, runConfirm().javaClass)
        assertEquals(1, notifications().activeNotifications.size)
        session.stored = null
        requests.clear()
        assertEquals(ListenableWorker.Result.success().javaClass, runConfirm().javaClass)
        assertTrue(requests.isEmpty())
        assertEquals(1, notifications().activeNotifications.size)
    }

    @Test
    fun `confirm without an id or with an unreadable server sends nothing`() {
        assertEquals(ListenableWorker.Result.success().javaClass, runConfirm("").javaClass)
        session.serverUnreadable = true
        runConfirm()
        assertTrue(requests.isEmpty())
    }

    @Test
    fun `each confirm is its own unique job, so one that keeps failing never holds another`() {
        CaptureScheduler.enqueueConfirm(context, "t-1")
        CaptureScheduler.enqueueConfirm(context, "t-1")
        CaptureScheduler.enqueueConfirm(context, "t-2")

        val work = WorkManager.getInstance(context)
        for (id in listOf("t-1", "t-2")) {
            val jobs = work.getWorkInfosForUniqueWork(CaptureScheduler.confirmName(id)).get()
            assertEquals(1, jobs.size)
            assertEquals(WorkInfo.State.ENQUEUED, jobs.single().state)
            assertEquals(NetworkType.CONNECTED, jobs.single().constraints.requiredNetworkType)
        }
        assertEquals("wambito.capture.confirm.t-1", CaptureScheduler.confirmName("t-1"))
    }

    @Test
    fun `a confirm chain left under the old shared name is cancelled`() {
        val work = WorkManager.getInstance(context)
        val stuck = androidx.work.OneTimeWorkRequestBuilder<ConfirmCaptureWorker>()
            .setInputData(workDataOf(ConfirmCaptureWorker.ID to "t-gone"))
            .setConstraints(androidx.work.Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        work.enqueueUniqueWork(CaptureScheduler.CONFIRM, androidx.work.ExistingWorkPolicy.APPEND_OR_REPLACE, stuck).result.get()

        CaptureScheduler.enqueueConfirm(context, "t-1")

        val old = work.getWorkInfosForUniqueWork(CaptureScheduler.CONFIRM).get()
        assertTrue(old.all { it.state == WorkInfo.State.CANCELLED })
    }

    @Test
    fun `the send is a unique job that appends, waits for a network and backs off exponentially`() {
        CaptureScheduler.enqueueSend(context)
        CaptureScheduler.enqueueSend(context)

        val jobs = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CaptureScheduler.SEND).get()
        assertEquals(2, jobs.size)
        assertTrue(jobs.all { it.constraints.requiredNetworkType == NetworkType.CONNECTED })
        assertEquals(1, jobs.count { it.state == WorkInfo.State.ENQUEUED })
    }
}
