package com.wambito.app.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.net.InetAddress
import java.net.ServerSocket
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** A stored session in memory, which the test can sign out. */
private class FakeSession(var stored: String?, var serverUrl: String?) : SessionSource {
    /** The server setting is stored but cannot be decrypted. */
    var serverUnreadable = false

    override fun token(): String? = stored
    override fun mark(): String? = stored?.let { "mark:$it" }
    override fun server(): ServerSetting = when {
        serverUnreadable -> ServerSetting.Unreadable
        serverUrl == null -> ServerSetting.Default
        else -> ServerSetting.Chosen(serverUrl!!)
    }
}

@RunWith(RobolectricTestRunner::class)
class RefreshWorkerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val now = Instant.parse("2026-10-22T20:00:00Z")
    private lateinit var server: TinyHttpServer
    private val requests = mutableListOf<TinyRequest>()
    private val headers = mutableListOf<Map<String, String?>>()
    private var status = 200
    private var body = """
        {"month":"2026-10","budgetTotal":200000000,"spent":80000000,"remaining":120000000,
         "income":0,"balance":-80000000,
         "categories":[{"categoryId":"c","budget":1000,"spent":950,"remaining":50,"ratio":0.95,"state":"near"}]}
    """.trimIndent()

    /** Called while the server holds the answer (a request in flight). */
    private var whileAnswering: (() -> Unit)? = null

    private lateinit var session: FakeSession

    @Before
    fun setUp() {
        server = TinyHttpServer { request ->
            requests += request
            headers += mapOf(
                "path" to request.path,
                "authorization" to request.headers["authorization"],
                "timezone" to request.headers["x-wambito-timezone"],
                "locale" to request.headers["x-wambito-locale"],
                "background" to request.headers["x-wambito-background"],
            )
            whileAnswering?.invoke()
            status to body
        }
        session = FakeSession("token-1", "http://127.0.0.1:${server.port}")
        RefreshWorker.dependencies = {
            RefreshDependencies(
                session = session,
                fetcher = SummaryFetcher(),
                clock = { now },
                writeContext = Dispatchers.Unconfined,
            )
        }
    }

    @After
    fun tearDown() {
        RefreshWorker.dependencies = null
        server.stop()
        WidgetSnapshot.preferences(context).edit().clear().commit()
    }

    private fun store(snapshot: WidgetSnapshot) {
        WidgetSnapshot.preferences(context).edit().putString(WidgetSnapshot.KEY, snapshot.toJson()).commit()
    }

    private fun stored(): WidgetSnapshot? = WidgetSnapshot.read(context)

    private val earlier = WidgetSnapshot(
        signedIn = true,
        remaining = 150000000,
        spent = 50000000,
        budgetTotal = 200000000,
        currency = "COP",
        locale = "es",
        month = "2026-10",
        mood = "happy",
        updatedAt = now.minus(Duration.ofHours(3)),
        hideAmount = true,
        theme = "light",
    )

    /** A loopback port that was free a moment ago and has no listener: connecting is refused. */
    private fun closedPort(): Int = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }

    private fun runWorker() = runBlocking {
        TestListenableWorkerBuilder<RefreshWorker>(context).build().doWork()
    }

    @Test
    fun `RefreshWorker updates the snapshot from GET v1 summary, with the stored session`() {
        store(earlier)
        runWorker()

        assertEquals(1, requests.size)
        assertEquals("/api/v1/summary", headers[0]["path"])
        assertEquals("Bearer token-1", headers[0]["authorization"])
        assertEquals(ZoneId.systemDefault().id, headers[0]["timezone"])
        assertTrue(headers[0]["locale"]!!.isNotEmpty())
        // A job the person did not start is not activity: the API reads the session without
        // sliding it (x-wambito-background), so the widget never keeps a guest from being cleaned up.
        assertEquals("1", headers[0]["background"])
        assertEquals(
            earlier.copy(
                remaining = 120000000,
                spent = 80000000,
                mood = "worried",
                updatedAt = now,
            ),
            stored(),
        )
    }

    @Test
    fun `a preview account is never asked and keeps the snapshot the app wrote`() {
        com.wambito.app.account.AccountMode(context).value = "preview"
        store(earlier)

        val outcome = runWorker().let { (it as androidx.work.ListenableWorker.Result.Success).outputData }

        assertEquals("encrypted account", outcome.getString(RefreshWorker.OUTCOME))
        assertTrue(requests.isEmpty())
        assertEquals(earlier, stored())
    }

    @Test
    fun `a mode the app has not learned yet is not asked either`() {
        com.wambito.app.account.AccountMode(context).value = "unknown"
        store(earlier)
        val outcome = (runWorker() as androidx.work.ListenableWorker.Result.Success).outputData
        assertEquals("mode unknown", outcome.getString(RefreshWorker.OUTCOME))
        assertTrue(requests.isEmpty())
        assertEquals(earlier, stored())
    }

    @Test
    fun `the server chosen in Settings is used, with any path it has`() {
        session.serverUrl = "http://127.0.0.1:${server.port}/wambito/"
        store(earlier)
        runWorker()
        assertEquals("/wambito/api/v1/summary", headers[0]["path"])
    }

    @Test
    fun `a server setting that cannot be read sends nothing, never the token to the default server`() {
        store(earlier)
        session.serverUnreadable = true
        val outcome = runBlocking {
            RefreshWorker.refresh(context, RefreshWorker.dependencies!!(context))
        }
        assertEquals("server unreadable", outcome)
        assertTrue(requests.isEmpty())
        assertEquals(earlier, stored())
    }

    @Test
    fun `a token that cannot be read sends nothing and changes nothing`() {
        store(earlier)
        val unreadable = object : SessionSource {
            override fun token(): String? = null
            override fun mark(): String = "mark:stored"
            override fun server(): ServerSetting = ServerSetting.Default
        }
        val outcome = runBlocking {
            RefreshWorker.refresh(
                context,
                RefreshDependencies(unreadable, SummaryFetcher(), { now }, Dispatchers.Unconfined),
            )
        }
        assertEquals("token unreadable", outcome)
        assertTrue(requests.isEmpty())
        assertEquals(earlier, stored())
    }

    @Test
    fun `a midnight run schedules the next midnight`() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        store(earlier)
        runBlocking {
            TestListenableWorkerBuilder<RefreshWorker>(context)
                .setTags(listOf(RefreshScheduler.MIDNIGHT))
                .build()
                .doWork()
        }
        val next = WorkManager.getInstance(context).getWorkInfosForUniqueWork(RefreshScheduler.MIDNIGHT).get()
        assertEquals(1, next.count { it.state == WorkInfo.State.ENQUEUED })
    }

    @Test
    fun `RefreshWorker is scheduled about every 3 h, on a network, and at midnight`() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        val bogota = ZoneId.of("America/Bogota")
        val at = LocalDateTime.of(2026, 10, 22, 21, 30).atZone(bogota).toInstant()
        // No snapshot yet: the phone's zone.
        RefreshScheduler.schedule(context, at, bogota)

        val workManager = WorkManager.getInstance(context)
        val periodic = workManager.getWorkInfosForUniqueWork(RefreshScheduler.PERIODIC).get().single()
        assertEquals(WorkInfo.State.ENQUEUED, periodic.state)
        assertEquals(Duration.ofHours(3).toMillis(), periodic.periodicityInfo!!.repeatIntervalMillis)
        assertEquals(NetworkType.CONNECTED, periodic.constraints.requiredNetworkType)

        val midnight = workManager.getWorkInfosForUniqueWork(RefreshScheduler.MIDNIGHT).get().single()
        // 21:30 to one minute past midnight.
        assertEquals(Duration.ofMinutes(151).toMillis(), midnight.initialDelayMillis)

        // Scheduling again (every app start) keeps the same periodic job.
        RefreshScheduler.schedule(context, at, bogota)
        assertEquals(periodic.id, workManager.getWorkInfosForUniqueWork(RefreshScheduler.PERIODIC).get().single().id)
        assertEquals(midnight.id, workManager.getWorkInfosForUniqueWork(RefreshScheduler.MIDNIGHT).get().single().id)
    }

    @Test
    fun `midnight is the profile's, from the snapshot, and moves when its zone does`() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        val workManager = WorkManager.getInstance(context)
        val bogota = ZoneId.of("America/Bogota")
        // 2026-10-22 11:00 UTC: 06:00 in Bogotá (the phone), 20:00 in Tokyo (the profile).
        val at = Instant.parse("2026-10-22T11:00:00Z")
        store(earlier.copy(timezone = "Asia/Tokyo"))
        RefreshScheduler.schedule(context, at, bogota)
        val tokyo = workManager.getWorkInfosForUniqueWork(RefreshScheduler.MIDNIGHT).get().single()
        // 20:00 to one minute past midnight in Tokyo.
        assertEquals(Duration.ofMinutes(241).toMillis(), tokyo.initialDelayMillis)

        // The profile moved to Bogotá: the next start puts midnight there.
        store(earlier.copy(timezone = "America/Bogota"))
        RefreshScheduler.schedule(context, at, ZoneId.of("Asia/Tokyo"))
        val moved = workManager.getWorkInfosForUniqueWork(RefreshScheduler.MIDNIGHT).get()
            .single { it.state == WorkInfo.State.ENQUEUED }
        assertNotEquals(tokyo.id, moved.id)
        // 06:00 to one minute past midnight in Bogotá.
        assertEquals(Duration.ofMinutes(18 * 60 + 1).toMillis(), moved.initialDelayMillis)
    }

    @Test
    fun `a refresh keeps the snapshot's zone`() {
        store(earlier.copy(timezone = "America/Bogota"))
        runWorker()
        assertEquals("America/Bogota", stored()!!.timezone)
    }

    @Test
    fun `signed out, nothing is asked and the widget says Abre Wambito`() {
        store(earlier)
        session.stored = null
        runWorker()
        assertTrue(requests.isEmpty())
        val now = stored()!!
        assertFalse(now.signedIn)
        assertEquals("light", now.theme)
    }

    @Test
    fun `a session the server no longer knows shows Abre Wambito, never the old figure`() {
        store(earlier)
        status = 401
        body = """{"type":"about:blank","status":401}"""
        runWorker()
        assertFalse(stored()!!.signedIn)
    }

    @Test
    fun `offline, the last figure stays, marked as a failed refresh`() {
        store(earlier)
        // A port nobody listens on, not a stopped server: closing a listening socket that another
        // thread is blocked in accept() on can leave it accepting for a moment on Linux (the
        // blocked call holds the socket), so the request could still be answered there.
        session.serverUrl = "http://127.0.0.1:${closedPort()}"
        runWorker()
        assertEquals(earlier.copy(refreshFailedAt = now), stored())
    }

    @Test
    fun `a server error keeps the last figure, marked as a failed refresh`() {
        store(earlier)
        status = 503
        body = "{}"
        runWorker()
        assertEquals(earlier.copy(refreshFailedAt = now), stored())
    }

    @Test
    fun `a refresh that works clears an earlier failure`() {
        store(earlier.copy(refreshFailedAt = now.minusSeconds(600)))
        runWorker()
        assertNull(stored()!!.refreshFailedAt)
        assertEquals(now, stored()!!.updatedAt)
    }

    @Test
    fun `a failure after the sign-out marks nothing`() {
        store(earlier)
        status = 503
        body = "{}"
        whileAnswering = {
            session.stored = null
            store(WidgetSnapshot(signedIn = false, theme = "light", hideAmount = true, locale = "es"))
        }
        runWorker()
        assertEquals(WidgetSnapshot(signedIn = false, theme = "light", hideAmount = true, locale = "es"), stored())
    }

    @Test
    fun `after sign out the widget never shows the previous figure, even with a refresh in flight`() {
        store(earlier)
        // The person signs out while the request is on its way: the app forgets the token and
        // writes the signed-out snapshot (lib/home/widget_sync.dart).
        whileAnswering = {
            session.stored = null
            store(WidgetSnapshot(signedIn = false, theme = "light", hideAmount = true, locale = "es"))
        }
        runWorker()
        val after = stored()!!
        assertFalse(after.signedIn)
        assertEquals(0L, after.remaining)
    }

    @Test
    fun `signed in again as someone else meanwhile, the first session's figures are dropped`() {
        store(earlier)
        whileAnswering = {
            session.stored = "token-2"
            store(earlier.copy(remaining = 7, updatedAt = now.minus(Duration.ofHours(5))))
        }
        runWorker()
        assertEquals(7L, stored()!!.remaining)
    }

    @Test
    fun `figures the app wrote while the request was on its way are newer, and stay`() {
        store(earlier)
        val fresher = earlier.copy(remaining = 99, updatedAt = now.plusSeconds(1))
        whileAnswering = { store(fresher) }
        RefreshWorker.dependencies = {
            RefreshDependencies(session, SummaryFetcher(), clock = { now }, writeContext = Dispatchers.Unconfined)
        }
        runWorker()
        assertEquals(fresher, stored())
    }

    @Test
    fun `nothing from the app yet (no currency known), nothing is written`() {
        runWorker()
        assertNull(stored())
    }

    @Test
    fun `a hung server is given up on`() {
        store(earlier)
        val release = CountDownLatch(1)
        whileAnswering = { release.await(30, TimeUnit.SECONDS) }
        val fetcher = SummaryFetcher(connectTimeoutMillis = 500, readTimeoutMillis = 500)
        RefreshWorker.dependencies = {
            RefreshDependencies(session, fetcher, clock = { now }, writeContext = Dispatchers.Unconfined)
        }
        runWorker()
        release.countDown()
        assertEquals(earlier.copy(refreshFailedAt = now), stored())
    }
}
