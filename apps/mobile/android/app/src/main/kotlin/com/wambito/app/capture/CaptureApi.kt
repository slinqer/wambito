package com.wambito.app.capture

import com.wambito.app.notices.ApiResult
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.ZoneId
import java.util.Locale

/** What the API says of a capture (`captureResultDto`). */
data class CaptureAnswer(
    /** The server had already saved this purchase (the other bank app notified it too). */
    val merged: Boolean,
    val id: String,
    /** Signed: negative for an expense. */
    val amountCents: Long,
    val currency: String,
    val name: String,
    val categoryName: String,
    /** The category is the kind's fallback ("Otros gastos"): the merchant is new. */
    val isFallback: Boolean,
    /**
     * The transaction still waits for the person's "¿bien?". False only for a merged answer whose
     * capture was already confirmed (Bien on the other app's notification, or in the app).
     */
    val needsReview: Boolean = true,
)

/**
 * Reads the answer of a capture (`{result, transaction, category}`): the server's `POST /v1/captures`
 * and the phone's own local route say the same. Null when it is not that shape.
 */
fun parseCaptureAnswer(json: String): CaptureAnswer? = try {
    val doc = JSONObject(json)
    val transaction = doc.getJSONObject("transaction")
    val category = doc.getJSONObject("category")
    CaptureAnswer(
        merged = doc.getString("result") == "merged",
        id = transaction.getString("id"),
        amountCents = transaction.getLong("amount"),
        currency = transaction.getString("currency"),
        name = transaction.getString("name"),
        categoryName = category.getString("name"),
        isFallback = category.getBoolean("fallback"),
        // A server that does not say is asked again, as before the field existed.
        needsReview = transaction.optBoolean("needsReview", true),
    )
} catch (_: JSONException) {
    null
}

/**
 * The two calls a capture makes, as [com.wambito.app.notices.NoticeApi] makes its reads: `<server>/api`,
 * the bearer token, the phone's zone and language, `x-wambito-background: 1` (a job the person did
 * not start is not activity). With the platform's HttpURLConnection: no HTTP library.
 */
class CaptureApi(
    private val connectTimeoutMillis: Int = 10_000,
    private val readTimeoutMillis: Int = 20_000,
) {
    /**
     * `POST /v1/captures` with the item's key as `Idempotency-Key`, so a send repeated after a
     * crash or a lost answer saves nothing twice. The body is exactly the six fields of
     * [ParsedCapture]. 401 is [ApiResult.Unauthorized]; 403, 404, 408 and 429 are
     * [ApiResult.Failed] (tried again: 403 and 404 are a server that lacks the endpoint yet, R10);
     * any other 4xx is [ApiResult.Rejected]: the server refuses the capture itself, so sending it
     * again can only fail again.
     */
    fun send(server: String, token: String, item: QueuedCapture): ApiResult<CaptureAnswer> {
        val body = item.capture.toJson()
        val answer = call(server, token, "POST", "/v1/captures", body.toString(), item.key, endpointMayBeMissing = true)
        return when (answer) {
            is ApiResult.Ok -> parseCaptureAnswer(answer.value)?.let { ApiResult.Ok(it) } ?: ApiResult.Failed
            ApiResult.Unauthorized -> ApiResult.Unauthorized
            ApiResult.Failed -> ApiResult.Failed
            ApiResult.Rejected -> ApiResult.Rejected
        }
    }

    /**
     * "Bien": `POST /v1/transactions/review` with `{"ids":[id]}`. Confirming twice is harmless. The
     * endpoint ships with Bien, so a 404 is a transaction deleted meanwhile, or another account's
     * (the session changed): [ApiResult.Rejected], like any 4xx other than 401, 408 and 429.
     */
    fun confirm(server: String, token: String, id: String): ApiResult<Unit> {
        val body = JSONObject().put("ids", JSONArray().put(id)).toString()
        return when (call(server, token, "POST", "/v1/transactions/review", body, null, endpointMayBeMissing = false)) {
            is ApiResult.Ok -> ApiResult.Ok(Unit)
            ApiResult.Unauthorized -> ApiResult.Unauthorized
            ApiResult.Failed -> ApiResult.Failed
            ApiResult.Rejected -> ApiResult.Rejected
        }
    }

    private fun call(
        server: String,
        token: String,
        method: String,
        path: String,
        body: String,
        idempotencyKey: String?,
        endpointMayBeMissing: Boolean,
    ): ApiResult<String> {
        val url = try {
            URL("${server.trimEnd('/')}/api$path")
        } catch (_: IOException) {
            return ApiResult.Failed
        }
        if (url.protocol != "https" && url.protocol != "http") return ApiResult.Failed
        val connection = try {
            url.openConnection() as HttpURLConnection
        } catch (_: IOException) {
            return ApiResult.Failed
        }
        return try {
            connection.connectTimeout = connectTimeoutMillis
            connection.readTimeout = readTimeoutMillis
            connection.instanceFollowRedirects = false
            connection.requestMethod = method
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Content-Type", "application/json")
            if (idempotencyKey != null) connection.setRequestProperty("Idempotency-Key", idempotencyKey)
            connection.setRequestProperty("x-wambito-background", "1")
            connection.setRequestProperty("x-wambito-timezone", ZoneId.systemDefault().id)
            connection.setRequestProperty("x-wambito-locale", Locale.getDefault().toLanguageTag())
            connection.doOutput = true
            connection.outputStream.use { it.write(body.toByteArray()) }
            when (connection.responseCode) {
                200, 201 -> ApiResult.Ok(connection.inputStream.bufferedReader().use { it.readText() })
                401 -> ApiResult.Unauthorized
                // 408 and 429 ask to be tried again.
                408, 429 -> ApiResult.Failed
                // For a capture, 403 and 404 are a server that lacks the endpoint (a phone updated
                // before its server): the capture waits for it instead of being lost.
                403, 404 -> if (endpointMayBeMissing) ApiResult.Failed else ApiResult.Rejected
                // 426: the account moved to end-to-end encryption and this request predates it.
                // The capture or the confirm waits: once the app opens, it learns the account is
                // `preview` and the queue goes to the vault.
                426 -> ApiResult.Failed
                in 400..499 -> ApiResult.Rejected
                else -> ApiResult.Failed
            }
        } catch (_: IOException) {
            // ProtocolException (a method this platform does not know) is an IOException too.
            ApiResult.Failed
        } finally {
            connection.disconnect()
        }
    }
}
