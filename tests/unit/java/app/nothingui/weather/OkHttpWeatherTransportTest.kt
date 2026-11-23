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

import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class OkHttpWeatherTransportTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val location = WeatherCoordinates.from(latitude = 51.5074, longitude = -0.1278)!!
    private val session = WeatherSession(
        enabled = true,
        visible = true,
        generation = 1,
        location = location,
    )

    private fun client(): OkHttpClient = OkHttpClient.Builder()
        .retryOnConnectionFailure(false)
        .readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(90, TimeUnit.SECONDS)
        .build()

    @Test
    fun cancellingTheRepositoryCancelsTheLocalCallAndCommitsNothing() = runBlocking {
        val server = HangingServer()
        try {
            val cache = InMemoryWeatherCacheStore()
            val repository = MetWeatherRepository(
                transport = OkHttpWeatherTransport("test", client = client()),
                cacheStore = cache,
                sessionProvider = WeatherSessionProvider { session },
                clock = { now },
                forecastEndpoint = server.url,
            )

            val job = launch(Dispatchers.IO) { repository.load(session) }
            assertTrue("server never saw the request", server.requestSeen.await(10, TimeUnit.SECONDS))
            job.cancelAndJoin()

            assertTrue("call was not cancelled", server.clientGone.await(10, TimeUnit.SECONDS))
            assertNull(cache.read(location.cacheKey))
        } finally {
            server.close()
        }
    }

    @Test
    fun aDeclaredBodyOverTheBudgetIsRejectedBeforeReading() = runBlocking {
        val server = OneShotServer(
            payload = "x".repeat(128).toByteArray(),
            extraHeaders = "",
        )
        try {
            val transport = OkHttpWeatherTransport(
                appVersion = "test",
                client = client(),
                maxResponseBytes = 32,
            )

            assertThrows(IOException::class.java) {
                runBlocking { transport.get(WeatherHttpRequest(url = server.url)) }
            }
            Unit
        } finally {
            server.close()
        }
    }

    @Test
    fun responseHeadersArePreservedForTheRepositoryPolicy() = runBlocking {
        val server = OneShotServer(
            payload = """{"properties":{"timeseries":[]}}""".toByteArray(),
            extraHeaders = buildString {
                append("Expires: Tue, 24 Nov 2026 12:00:00 GMT\r\n")
                append("Last-Modified: Mon, 23 Nov 2026 11:00:00 GMT\r\n")
                append("Retry-After: 120\r\n")
            },
        )
        try {
            val transport = OkHttpWeatherTransport("test", client = client())

            val response = transport.get(WeatherHttpRequest(url = server.url))

            assertEquals(200, response.code)
            assertEquals(Instant.parse("2026-11-24T12:00:00Z"), response.expiresAt)
            assertEquals("Mon, 23 Nov 2026 11:00:00 GMT", response.lastModified)
            assertEquals("120", response.retryAfter)
        } finally {
            server.close()
        }
    }

    private class HangingServer {
        private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        val requestSeen = CountDownLatch(1)
        val clientGone = CountDownLatch(1)
        private val worker = thread(isDaemon = true, name = "weather-hanging-server") {
            try {
                server.accept().use { socket ->
                    readHeaders(socket)
                    requestSeen.countDown()
                    drainUntilClosed(socket)
                    clientGone.countDown()
                }
            } catch (_: IOException) {
                requestSeen.countDown()
                clientGone.countDown()
            }
        }

        val url: String
            get() = "http://127.0.0.1:${server.localPort}/forecast"

        fun close() {
            runCatching { server.close() }
            worker.join(2_000)
        }
    }

    private class OneShotServer(
        private val payload: ByteArray,
        private val extraHeaders: String,
    ) {
        private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        private val worker = thread(isDaemon = true, name = "weather-one-shot-server") {
            try {
                server.accept().use { socket ->
                    readHeaders(socket)
                    val output = socket.getOutputStream()
                    val head = "HTTP/1.1 200 OK\r\n" +
                        "Content-Length: ${payload.size}\r\n" +
                        "Connection: close\r\n" +
                        extraHeaders +
                        "\r\n"
                    output.write(head.toByteArray(Charsets.UTF_8))
                    output.write(payload)
                    output.flush()
                }
            } catch (_: IOException) {
                // The client may close first; the test asserts on the client result.
            }
        }

        val url: String
            get() = "http://127.0.0.1:${server.localPort}/forecast"

        fun close() {
            runCatching { server.close() }
            worker.join(2_000)
        }
    }

    private companion object {
        fun readHeaders(socket: Socket) {
            val reader = socket.getInputStream().bufferedReader()
            while (true) {
                val line = reader.readLine() ?: return
                if (line.isEmpty()) return
            }
        }

        fun drainUntilClosed(socket: Socket) {
            val input = socket.getInputStream()
            try {
                while (input.read() != -1) {
                    // Keep reading until the cancelled client closes the socket.
                }
            } catch (_: IOException) {
                // A reset is still a cancelled call.
            }
        }
    }
}
