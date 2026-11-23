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
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetWeatherRepositoryTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val location = WeatherCoordinates.from(latitude = 51.5074, longitude = -0.1278)!!
    private val session = WeatherSession(
        enabled = true,
        visible = true,
        generation = 1,
        location = location,
    )
    private val lastModified = "Mon, 23 Nov 2026 11:00:00 GMT"

    @Test
    fun aFreshCacheIsServedWithoutTransportEvenForManualRefresh() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofMinutes(30))))
        val transport = FakeTransport()
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val automatic = repository.load(session) as WeatherLoadResult.Success
        val manual = repository.refresh(session) as WeatherLoadResult.Success

        assertEquals(7.5, automatic.forecast.temperatureCelsius, 0.0)
        assertEquals(7.5, manual.forecast.temperatureCelsius, 0.0)
        assertEquals(0, transport.requests.size)
    }

    @Test
    fun aConditionalRequestReusesTheExactLastModifiedAnd304KeepsTheForecastTime() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofHours(4))))
        val transport = FakeTransport(
            WeatherHttpResponse(
                code = 304,
                body = null,
                expiresAt = now.plus(Duration.ofHours(2)),
                lastModified = lastModified,
            ),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Success

        assertEquals(1, transport.requests.size)
        assertEquals(lastModified, transport.requests.single().ifModifiedSince)
        assertTrue(transport.requests.single().url.contains("lat=51.5074"))
        assertTrue(transport.requests.single().url.contains("lon=-0.1278"))
        assertEquals(Instant.parse("2026-11-23T13:00:00Z"), result.forecast.validAt)
        assertEquals(now, result.forecast.retrievedAt)
        assertEquals(now, cache.read(location.cacheKey)!!.retrievedAt)
    }

    @Test
    fun a304WithoutAValidatedCachedBodyIsACacheMiss() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val transport = FakeTransport(
            WeatherHttpResponse(code = 304, body = null, expiresAt = null, lastModified = lastModified),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.CACHE_MISS, result.reason)
        assertNull(transport.requests.single().ifModifiedSince)
        assertNull(cache.read(location.cacheKey))
    }

    @Test
    fun rateLimitBackoffBlocksFurtherRequestsUntilTheRetryBoundary() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        val transport = FakeTransport(
            WeatherHttpResponse(
                code = 429,
                body = null,
                expiresAt = null,
                lastModified = null,
                retryAfterSeconds = 120,
            ),
            successResponse(),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session)) { clockNow }

        val limited = repository.load(session) as WeatherLoadResult.Unavailable
        val stillLimited = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.RATE_LIMITED, limited.reason)
        assertEquals(now.plusSeconds(120), limited.retryAt)
        assertEquals(WeatherFailureReason.RATE_LIMITED, stillLimited.reason)
        assertEquals(1, transport.requests.size)

        clockNow = now.plusSeconds(121)
        val recovered = repository.load(session) as WeatherLoadResult.Success

        assertEquals(2, transport.requests.size)
        assertEquals(7.5, recovered.forecast.temperatureCelsius, 0.0)
    }

    @Test
    fun aNetworkFailurePreservesTheLastSuccessfulForecast() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofHours(4))))
        val transport = ThrowingTransport(IOException("offline"))
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.NETWORK, result.reason)
        assertEquals(Instant.parse("2026-11-23T13:00:00Z"), result.lastSuccess!!.validAt)
        assertEquals(1, transport.calls)
        assertEquals(now.minus(Duration.ofHours(4)), cache.read(location.cacheKey)!!.retrievedAt)
    }

    @Test
    fun anInactiveOrUnlocatedSessionNeverTouchesTheNetwork() = runBlocking {
        val transport = FakeTransport()
        val repository = repository(transport, InMemoryWeatherCacheStore(), FakeSessionProvider(session))

        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(enabled = false)))
        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(visible = false)))
        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(location = null)))
        assertEquals(0, transport.requests.size)
    }

    @Test
    fun aChangedGenerationWhenTheResponseArrivesIsNotCommitted() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val gate = CompletableDeferred<Unit>()
        val transport = GatedTransport(successResponse(), gate)
        val provider = FakeSessionProvider(session)
        val repository = repository(transport, cache, provider)

        val job = async(Dispatchers.Default) { repository.load(session) }
        waitForFirstRequest(transport)
        provider.session = session.copy(generation = 2)
        gate.complete(Unit)

        assertEquals(WeatherLoadResult.Cancelled, job.await())
        assertNull(cache.read(location.cacheKey))
    }

    @Test
    fun revokedOptInWhenTheResponseArrivesIsNotCommitted() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val gate = CompletableDeferred<Unit>()
        val transport = GatedTransport(successResponse(), gate)
        val provider = FakeSessionProvider(session)
        val repository = repository(transport, cache, provider)

        val job = async(Dispatchers.Default) { repository.load(session) }
        waitForFirstRequest(transport)
        provider.session = session.copy(enabled = false)
        gate.complete(Unit)

        assertEquals(WeatherLoadResult.Cancelled, job.await())
        assertNull(cache.read(location.cacheKey))
    }

    @Test
    fun concurrentLoadsShareOneInFlightRequest() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val gate = CompletableDeferred<Unit>()
        val transport = GatedTransport(successResponse(), gate)
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val first = async(Dispatchers.Default) { repository.load(session) }
        waitForFirstRequest(transport)
        val second = async(Dispatchers.Default) { repository.load(session) }
        repeat(16) { yield() }

        assertEquals("one in-flight request", 1, transport.calls)

        gate.complete(Unit)
        val firstResult = first.await()
        val secondResult = second.await()

        assertTrue(firstResult is WeatherLoadResult.Success)
        assertTrue(secondResult is WeatherLoadResult.Success)
        assertEquals(1, transport.calls)
    }

    private fun waitForFirstRequest(transport: GatedTransport) {
        var spins = 0
        while (transport.calls == 0 && spins++ < 100_000) {
            Thread.yield()
        }
        assertEquals(1, transport.calls)
    }

    private fun repository(
        transport: WeatherHttpTransport,
        cache: WeatherCacheStore,
        provider: WeatherSessionProvider,
        clock: () -> Instant = { now },
    ): MetWeatherRepository = MetWeatherRepository(
        transport = transport,
        cacheStore = cache,
        sessionProvider = provider,
        clock = clock,
    )

    private fun cachedEntry(retrievedAt: Instant): WeatherCacheEntry = WeatherCacheEntry(
        locationKey = location.cacheKey,
        body = bodyAt("2026-11-23T13:00:00Z"),
        retrievedAt = retrievedAt,
        expiresAt = retrievedAt.plus(Duration.ofHours(4)),
        lastModified = lastModified,
    )

    private fun successResponse(): WeatherHttpResponse = WeatherHttpResponse(
        code = 200,
        body = bodyAt("2026-11-23T13:00:00Z"),
        expiresAt = now.plus(Duration.ofHours(4)),
        lastModified = lastModified,
    )

    private fun bodyAt(time: String): String = """
        {
          "type": "Feature",
          "properties": {
            "meta": {"updated_at": "2026-11-23T11:00:00Z"},
            "timeseries": [
              {
                "time": "$time",
                "data": {
                  "instant": {"details": {"air_temperature": 7.5}},
                  "next_1_hours": {"summary": {"symbol_code": "cloudy"}}
                }
              }
            ]
          }
        }
    """.trimIndent()

    private class FakeSessionProvider(session: WeatherSession) : WeatherSessionProvider {
        @Volatile
        var session: WeatherSession = session

        override fun current(): WeatherSession = session
    }

    private class FakeTransport(vararg responses: WeatherHttpResponse) : WeatherHttpTransport {
        private val pending = ArrayDeque(responses.toList())
        val requests = mutableListOf<WeatherHttpRequest>()

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            requests += request
            return pending.removeFirst()
        }
    }

    private class ThrowingTransport(private val error: IOException) : WeatherHttpTransport {
        var calls = 0

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            throw error
        }
    }

    private class GatedTransport(
        private val response: WeatherHttpResponse,
        private val gate: CompletableDeferred<Unit>,
    ) : WeatherHttpTransport {
        @Volatile
        var calls = 0
        val requests = mutableListOf<WeatherHttpRequest>()

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            requests += request
            gate.await()
            return response
        }
    }
}
