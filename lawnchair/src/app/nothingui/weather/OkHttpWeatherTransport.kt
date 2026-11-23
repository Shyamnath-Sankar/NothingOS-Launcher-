/*
 * Copyright 2026 the DotWel Launcher project contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app.nothingui.weather

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/**
 * MET's terms require an honest product identity and a contact route. It also
 * allows a moderate, direct request volume for a free commercial app, but no
 * SLA and a 20 requests/second ceiling across all installs: this client has no
 * polling loop and no background scheduler.
 *
 * All network and body I/O runs on OkHttp's worker dispatcher, never on the
 * caller's coroutine context (which may be the main thread). The coroutine is
 * resumed only once the whole response, including the bounded body, has been
 * read. Coroutine cancellation invokes [Call.cancel] for the entire lifetime of
 * the call, so a stalled body is interrupted and the response is closed by the
 * callback's `use` block. Already-sent bytes cannot be retracted; that is
 * the caller's opt-in and lifecycle responsibility.
 *
 * Not constructed anywhere yet. The production path remains disabled until the
 * real opt-in UI, privacy notice and visible HOME lifecycle gate are wired.
 */
class OkHttpWeatherTransport(
    appVersion: String,
    private val client: OkHttpClient = defaultClient(),
    private val maxResponseBytes: Long = MAX_RESPONSE_BYTES,
) : WeatherHttpTransport {
    private val userAgent: String = "DotWelLauncher/$appVersion (+$PROJECT_ISSUES_URL)"

    override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
        val httpRequest = Request.Builder()
            .url(request.url)
            .header("User-Agent", userAgent)
            .header("Accept", request.accept)
            .apply {
                request.ifModifiedSince?.let { header("If-Modified-Since", it) }
            }
            .build()

        return client.newCall(httpRequest).awaitResponse()
    }

    /**
     * The continuation stays pending until the body has been fully read on the
     * OkHttp callback thread. Cancellation is registered for the lifetime of the
     * whole call, and a cancellation that wins after the response exists (but
     * before it is resumed) still closes the response through `use`.
     */
    private suspend fun Call.awaitResponse(): WeatherHttpResponse = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    if (!continuation.isActive) {
                        response.close()
                        return
                    }
                    val result = try {
                        response.use { received -> readResponse(call, received) }
                    } catch (failure: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(failure)
                        return
                    }
                    if (continuation.isActive) continuation.resume(result)
                }
            },
        )
    }

    private fun readResponse(call: Call, response: Response): WeatherHttpResponse {
        if (call.isCanceled()) throw IOException("weather request was cancelled")
        val declaredLength = response.body.contentLength()
        if (declaredLength > maxResponseBytes) {
            throw IOException("weather response is larger than $maxResponseBytes bytes")
        }
        val body = if (response.code == MET_NOT_MODIFIED) {
            null
        } else {
            readBounded(call, response.body.byteStream(), maxResponseBytes)
        }
        if (call.isCanceled()) throw IOException("weather request was cancelled")
        return WeatherHttpResponse(
            code = response.code,
            body = body,
            expiresAt = response.headers.getDate("Expires")?.toInstant(),
            lastModified = response.headers["Last-Modified"],
            retryAfter = response.headers["Retry-After"],
        )
    }

    private fun readBounded(call: Call, stream: InputStream, limit: Long): String {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(READ_BUFFER_BYTES)
        var total = 0L
        stream.use { input ->
            while (true) {
                if (call.isCanceled()) throw IOException("weather request was cancelled")
                val read = input.read(buffer)
                if (read < 0) break
                total += read
                if (total > limit) throw IOException("weather response is larger than $limit bytes")
                output.write(buffer, 0, read)
            }
        }
        return String(output.toByteArray(), Charsets.UTF_8)
    }

    companion object {
        const val MAX_RESPONSE_BYTES: Long = 512L * 1024L
        const val PROJECT_ISSUES_URL: String =
            "https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/issues"
        private const val MET_NOT_MODIFIED = 304
        private const val READ_BUFFER_BYTES = 8 * 1024
        private const val TIMEOUT_SECONDS = 10L
        private const val CALL_TIMEOUT_SECONDS = 20L

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .callTimeout(CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
            .build()
    }
}
