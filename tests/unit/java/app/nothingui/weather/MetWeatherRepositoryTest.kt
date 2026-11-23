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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetWeatherRepositoryTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val location = WeatherCoordinates.from(latitude = 51.5074, longitude = -0.1278)!!
    private val otherLocation = WeatherCoordinates.from(latitude = 48.8566, longitude = 2.3522)!!
    private val session = WeatherSession(
        enabled = true,
        visible = true,
        generation = 1,
        location = location,
    )
    private val lastModified = "Mon, 23 Nov 2026 11:00:00 GMT"
    private val threeHours: Duration = Duration.ofHours(3)

    @Test
    fun aFreshCacheIsServedWithoutTransportEvenForManualRefresh() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofMinutes(30))))
        val transport = ScriptedTransport()
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val automatic = repository.load(session) as WeatherLoadResult.Success
        val manual = repository.refresh(session) as WeatherLoadResult.Success

        assertEquals(7.5, automatic.forecast.temperatureCelsius, 0.0)
        assertEquals(7.5, manual.forecast.temperatureCelsius, 0.0)
        assertEquals(0, transport.calls)
        assertFalse(automatic.cacheUpdated)
    }

    @Test
    fun aConditionalRequestReusesTheExactLastModifiedAnd304KeepsTheOriginalRetrieval() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofHours(4))))
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 304,
                    body = null,
                    expiresAt = now.plus(Duration.ofHours(2)),
                    lastModified = lastModified,
                ),
            ),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Success

        assertEquals(1, transport.calls)
        assertEquals(lastModified, transport.requests.single().ifModifiedSince)
        assertTrue(transport.requests.single().url.contains("lat=51.5074"))
        assertTrue(transport.requests.single().url.contains("lon=-0.1278"))
        assertEquals(Instant.parse("2026-11-23T13:00:00Z"), result.forecast.validAt)
        assertEquals(now.minus(Duration.ofHours(4)), result.forecast.retrievedAt)
        assertEquals(now, result.forecast.revalidatedAt)
        assertFalse(result.stale)
        assertTrue(result.cacheUpdated)
        val stored = cache.read(location.cacheKey)!!
        assertEquals(now.minus(Duration.ofHours(4)), stored.retrievedAt)
        assertEquals(now, stored.revalidatedAt)
        assertEquals(now.plus(Duration.ofHours(2)), stored.expiresAt)
    }

    @Test
    fun aRevalidatedCacheIsNotRefetchedBeforeTheThreeHourEvidenceFloor() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofHours(4))))
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 304,
                    body = null,
                    expiresAt = now.plus(Duration.ofHours(2)),
                    lastModified = lastModified,
                ),
            ),
        )
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            clock = { clockNow },
        )

        repository.load(session)
        clockNow = now.plus(Duration.ofMinutes(1))
        val second = repository.load(session) as WeatherLoadResult.Success

        assertEquals(1, transport.calls)
        assertEquals(now, second.forecast.revalidatedAt)
        assertFalse(second.stale)
    }

    @Test
    fun a304WithoutAValidatedCachedBodyIsACacheMiss() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val transport = ScriptedTransport(
            Respond(WeatherHttpResponse(code = 304, body = null, expiresAt = null, lastModified = lastModified)),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.CACHE_MISS, result.reason)
        assertNull(transport.requests.single().ifModifiedSince)
        assertNull(cache.read(location.cacheKey))
    }

    @Test
    fun aGlobalAttemptFloorBlocksAManualRefreshAfterAnError() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        val transport = ScriptedTransport(
            Fail(IOException("offline")),
            Respond(successResponse()),
        )
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            clock = { clockNow },
        )

        val failed = repository.load(session) as WeatherLoadResult.Unavailable
        val blocked = repository.refresh(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.NETWORK, failed.reason)
        assertEquals(WeatherFailureReason.THROTTLED, blocked.reason)
        assertEquals(now.plus(threeHours), blocked.retryAt)
        assertEquals(1, transport.calls)

        clockNow = now.plus(threeHours)
        val recovered = repository.load(session) as WeatherLoadResult.Success

        assertEquals(2, transport.calls)
        assertEquals(7.5, recovered.forecast.temperatureCelsius, 0.0)
    }

    @Test
    fun aChangedLocationCannotBypassTheGlobalAttemptFloor() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        val throttle = InMemoryWeatherThrottleStore()
        val transport = ScriptedTransport(Respond(successResponse()))
        val provider = FakeSessionProvider(session)
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = provider,
            throttle = throttle,
            clock = { clockNow },
        )

        val first = repository.load(session) as WeatherLoadResult.Success
        clockNow = now.plus(Duration.ofMinutes(30))
        val changedSession = session.copy(location = otherLocation)
        provider.session = changedSession
        val changed = repository.load(changedSession) as WeatherLoadResult.Unavailable

        assertEquals(7.5, first.forecast.temperatureCelsius, 0.0)
        assertEquals(WeatherFailureReason.THROTTLED, changed.reason)
        assertEquals(now.plus(threeHours), changed.retryAt)
        assertNull(changed.lastSuccess)
        assertEquals(1, transport.calls)
    }

    @Test
    fun thePersistedAttemptFloorSurvivesARecreatedRepository() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val throttle = InMemoryWeatherThrottleStore()
        val transport = ScriptedTransport(Fail(IOException("offline")), Respond(successResponse()))

        val firstRepository = repository(transport, cache, FakeSessionProvider(session), throttle = throttle)
        firstRepository.load(session) as WeatherLoadResult.Unavailable

        val recreated = repository(transport, cache, FakeSessionProvider(session), throttle = throttle)
        val blocked = recreated.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.THROTTLED, blocked.reason)
        assertEquals(1, transport.calls)
    }

    @Test
    fun concurrentErrorLoadsShareOneAttempt() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val gate = CompletableDeferred<Unit>()
        val transport = GatedFailingTransport(gate)
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val first = async(Dispatchers.Default) { repository.load(session) }
        waitForFirstRequest(transport)
        val second = async(Dispatchers.Default) { repository.load(session) }
        gate.complete(Unit)

        val firstResult = first.await() as WeatherLoadResult.Unavailable
        val secondResult = second.await() as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.NETWORK, firstResult.reason)
        assertEquals(WeatherFailureReason.THROTTLED, secondResult.reason)
        assertEquals(1, transport.calls)
    }

    @Test
    fun retryAfterSecondsExtendsThePersistedBoundaryBeyondTheLocalFloor() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        val throttle = InMemoryWeatherThrottleStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 429,
                    body = null,
                    expiresAt = null,
                    lastModified = null,
                    retryAfter = "120",
                ),
            ),
            Respond(successResponse()),
        )
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            throttle = throttle,
            clock = { clockNow },
            minimumInterval = Duration.ofSeconds(10),
        )

        val limited = repository.load(session) as WeatherLoadResult.Unavailable
        val stillLimited = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.RATE_LIMITED, limited.reason)
        assertEquals(now.plusSeconds(120), limited.retryAt)
        assertEquals(now.plusSeconds(120), throttle.snapshot()!!.retryNotBefore)
        assertEquals(WeatherFailureReason.THROTTLED, stillLimited.reason)
        assertEquals(now.plusSeconds(120), stillLimited.retryAt)
        assertEquals(1, transport.calls)

        clockNow = now.plusSeconds(119)
        assertEquals(
            WeatherFailureReason.THROTTLED,
            (repository.load(session) as WeatherLoadResult.Unavailable).reason,
        )
        clockNow = now.plusSeconds(121)
        val recovered = repository.load(session) as WeatherLoadResult.Success

        assertEquals(2, transport.calls)
        assertEquals(7.5, recovered.forecast.temperatureCelsius, 0.0)
    }

    @Test
    fun aShortServerDelayIsReportedAtTheLaterGlobalFloor() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val throttle = InMemoryWeatherThrottleStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 429,
                    body = null,
                    expiresAt = null,
                    lastModified = null,
                    retryAfter = "120",
                ),
            ),
        )
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            throttle = throttle,
        )

        val limited = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(now.plus(threeHours), limited.retryAt)
        assertEquals(now.plusSeconds(120), throttle.snapshot()!!.retryNotBefore)
        assertEquals(
            WeatherAttemptDecision.Denied(now.plus(threeHours)),
            throttle.claim(now, threeHours),
        )
    }

    @Test
    fun aFailedBoundaryPersistIsKeptConservativelyInMemoryAndReported() = runBlocking {
        var clockNow = now
        val throttle = PersistFailingThrottleStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 429,
                    body = null,
                    expiresAt = null,
                    lastModified = null,
                    retryAfter = "Tue, 24 Nov 2026 20:00:00 GMT",
                ),
            ),
            Respond(successResponse()),
        )
        val repository = repository(
            transport = transport,
            cache = InMemoryWeatherCacheStore(),
            provider = FakeSessionProvider(session),
            throttle = throttle,
            clock = { clockNow },
        )

        val limited = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.RATE_LIMITED, limited.reason)
        assertEquals(Instant.parse("2026-11-24T20:00:00Z"), limited.retryAt)
        assertFalse("the boundary was not persisted", limited.retryPersisted)
        assertNull(throttle.snapshot()!!.retryNotBefore)

        clockNow = now.plus(Duration.ofHours(10))
        val blocked = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.THROTTLED, blocked.reason)
        assertEquals(Instant.parse("2026-11-24T20:00:00Z"), blocked.retryAt)
        assertFalse("the in-memory boundary is still unpersisted", blocked.retryPersisted)
        assertEquals("the conservative boundary must not be shortened", 1, transport.calls)
    }

    @Test
    fun aLongHttpDateRetryAfterIsNotClampedDown() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 429,
                    body = null,
                    expiresAt = null,
                    lastModified = null,
                    retryAfter = "Tue, 24 Nov 2026 22:00:00 GMT",
                ),
            ),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val limited = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(Instant.parse("2026-11-24T22:00:00Z"), limited.retryAt)
    }

    @Test
    fun aMalformedOrMissingRetryAfterUsesTheBoundedFallback() = runBlocking {
        val malformedCache = InMemoryWeatherCacheStore()
        val malformed = repository(
            transport = ScriptedTransport(
                Respond(
                    WeatherHttpResponse(
                        code = 429,
                        body = null,
                        expiresAt = null,
                        lastModified = null,
                        retryAfter = "not-a-delay",
                    ),
                ),
            ),
            cache = malformedCache,
            provider = FakeSessionProvider(session),
            minimumInterval = Duration.ofSeconds(5),
        ).load(session) as WeatherLoadResult.Unavailable

        val missing = repository(
            transport = ScriptedTransport(
                Respond(WeatherHttpResponse(code = 429, body = null, expiresAt = null, lastModified = null)),
            ),
            cache = InMemoryWeatherCacheStore(),
            provider = FakeSessionProvider(session),
            minimumInterval = Duration.ofSeconds(5),
        ).load(session) as WeatherLoadResult.Unavailable

        assertEquals(now.plusSeconds(60), malformed.retryAt)
        assertEquals(now.plusSeconds(60), missing.retryAt)
    }

    @Test
    fun forbiddenUsesItsOwnFallbackAndStillRespectsALongerServerDate() = runBlocking {
        val fallback = repository(
            transport = ScriptedTransport(
                Respond(WeatherHttpResponse(code = 403, body = null, expiresAt = null, lastModified = null)),
            ),
            cache = InMemoryWeatherCacheStore(),
            provider = FakeSessionProvider(session),
            minimumInterval = Duration.ofSeconds(5),
        ).load(session) as WeatherLoadResult.Unavailable

        val serverDate = repository(
            transport = ScriptedTransport(
                Respond(
                    WeatherHttpResponse(
                        code = 403,
                        body = null,
                        expiresAt = null,
                        lastModified = null,
                        retryAfter = "Tue, 24 Nov 2026 17:00:00 GMT",
                    ),
                ),
            ),
            cache = InMemoryWeatherCacheStore(),
            provider = FakeSessionProvider(session),
            minimumInterval = Duration.ofSeconds(5),
        ).load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.FORBIDDEN, fallback.reason)
        assertEquals(now.plus(Duration.ofHours(1)), fallback.retryAt)
        assertEquals(Instant.parse("2026-11-24T17:00:00Z"), serverDate.retryAt)
    }

    @Test
    fun aLaterPerLocationExpiresDelaysTheNextRequestBeyondTheGlobalFloor() = runBlocking {
        var clockNow = now
        val cache = InMemoryWeatherCacheStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 200,
                    body = bodyAt("2026-11-23T13:00:00Z"),
                    expiresAt = now.plus(Duration.ofHours(5)),
                    lastModified = lastModified,
                ),
            ),
        )
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            clock = { clockNow },
        )

        val first = repository.load(session) as WeatherLoadResult.Success
        clockNow = now.plus(Duration.ofHours(4))
        val second = repository.load(session) as WeatherLoadResult.Success

        assertFalse(first.stale)
        assertEquals(1, transport.calls)
        assertTrue(second.stale)
        assertEquals(now.plus(Duration.ofHours(5)), cache.read(location.cacheKey)!!.expiresAt)
    }

    @Test
    fun aNetworkFailurePreservesTheLastSuccessfulForecastAndMarksItStale() = runBlocking {
        val oldRetrieval = now.minus(Duration.ofHours(6))
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = oldRetrieval, validAt = "2026-11-23T06:00:00Z"))
        val transport = ScriptedTransport(Fail(IOException("offline")))
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            minimumInterval = Duration.ofSeconds(5),
        )

        val result = repository.load(session) as WeatherLoadResult.Unavailable

        assertEquals(WeatherFailureReason.NETWORK, result.reason)
        assertEquals(Instant.parse("2026-11-23T06:00:00Z"), result.lastSuccess!!.validAt)
        assertTrue(result.lastSuccessStale)
        assertEquals(oldRetrieval, cache.read(location.cacheKey)!!.retrievedAt)
    }

    @Test
    fun aThrottledLoadServesAnHonestStaleCacheAndNeverFabricatesAForecast() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        cache.write(cachedEntry(retrievedAt = now.minus(Duration.ofHours(6)), validAt = "2026-11-23T06:00:00Z"))
        val throttle = InMemoryWeatherThrottleStore()
        assertEquals(
            WeatherAttemptDecision.Allowed,
            throttle.claim(now, threeHours),
        )
        val transport = ScriptedTransport(Respond(successResponse()))
        val repository = repository(
            transport = transport,
            cache = cache,
            provider = FakeSessionProvider(session),
            throttle = throttle,
        )

        val served = repository.load(session) as WeatherLoadResult.Success

        assertEquals(0, transport.calls)
        assertTrue(served.stale)
        assertFalse(served.cacheUpdated)
        assertEquals(Instant.parse("2026-11-23T06:00:00Z"), served.forecast.validAt)
        assertEquals(now.minus(Duration.ofHours(6)), served.forecast.retrievedAt)
    }

    @Test
    fun anAnchoredForecastThatIsOldIsReportedStaleEvenWhenJustFetched() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val transport = ScriptedTransport(
            Respond(
                WeatherHttpResponse(
                    code = 200,
                    body = bodyAt("2026-11-23T06:00:00Z"),
                    expiresAt = now.plus(Duration.ofHours(4)),
                    lastModified = lastModified,
                ),
            ),
        )
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Success

        assertEquals(now, result.forecast.retrievedAt)
        assertEquals(Instant.parse("2026-11-23T06:00:00Z"), result.forecast.validAt)
        assertTrue(result.stale)
    }

    @Test
    fun aCacheWriteFailureIsReportedWithoutDiscardingTheForecast() = runBlocking {
        val cache = WriteFailingCacheStore()
        val transport = ScriptedTransport(Respond(successResponse()))
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val result = repository.load(session) as WeatherLoadResult.Success

        assertEquals(7.5, result.forecast.temperatureCelsius, 0.0)
        assertFalse(result.stale)
        assertFalse(result.cacheUpdated)
    }

    @Test
    fun aCacheReadFailureIsDistinguishedFromANetworkFailure() = runBlocking {
        val transport304 = ScriptedTransport(
            Respond(WeatherHttpResponse(code = 304, body = null, expiresAt = null, lastModified = lastModified)),
        )
        val storage = repository(
            transport = transport304,
            cache = ReadFailingCacheStore(),
            provider = FakeSessionProvider(session),
        ).load(session) as WeatherLoadResult.Unavailable

        val transport200 = ScriptedTransport(Respond(successResponse()))
        val recovered = repository(
            transport = transport200,
            cache = ReadFailingCacheStore(),
            provider = FakeSessionProvider(session),
        ).load(session) as WeatherLoadResult.Success

        assertEquals(WeatherFailureReason.CACHE_STORAGE, storage.reason)
        assertEquals(7.5, recovered.forecast.temperatureCelsius, 0.0)
    }

    @Test
    fun anInactiveOrUnlocatedSessionNeverTouchesTheNetwork() = runBlocking {
        val transport = ScriptedTransport()
        val repository = repository(transport, InMemoryWeatherCacheStore(), FakeSessionProvider(session))

        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(enabled = false)))
        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(visible = false)))
        assertEquals(WeatherLoadResult.Disabled, repository.load(session.copy(location = null)))
        assertEquals(0, transport.calls)
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
    fun cancellationAfterSuspensionDoesNotCommitTheLateResponse() = runBlocking {
        val cache = InMemoryWeatherCacheStore()
        val gate = CompletableDeferred<Unit>()
        val transport = LateResponseTransport(successResponse(), gate)
        val repository = repository(transport, cache, FakeSessionProvider(session))

        val job = launch(Dispatchers.Default) { repository.load(session) }
        waitForFirstRequest(transport)
        job.cancel()
        gate.complete(Unit)
        job.join()

        assertTrue(job.isCancelled)
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

    private fun waitForFirstRequest(transport: CountingTransport) {
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
        throttle: WeatherThrottleStore = InMemoryWeatherThrottleStore(),
        clock: () -> Instant = { now },
        minimumInterval: Duration = threeHours,
        endpoint: String = MetWeatherRepository.FORECAST_ENDPOINT,
    ): MetWeatherRepository = MetWeatherRepository(
        transport = transport,
        cacheStore = cache,
        sessionProvider = provider,
        throttleStore = throttle,
        clock = clock,
        minimumInterval = minimumInterval,
        forecastEndpoint = endpoint,
    )

    private fun cachedEntry(
        retrievedAt: Instant,
        validAt: String = "2026-11-23T13:00:00Z",
        revalidatedAt: Instant? = null,
    ): WeatherCacheEntry = WeatherCacheEntry(
        locationKey = location.cacheKey,
        body = bodyAt(validAt),
        retrievedAt = retrievedAt,
        expiresAt = retrievedAt.plus(Duration.ofHours(4)),
        lastModified = lastModified,
        revalidatedAt = revalidatedAt,
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

    private sealed interface Step
    private data class Respond(val response: WeatherHttpResponse) : Step
    private data class Fail(val error: IOException) : Step

    private abstract class CountingTransport : WeatherHttpTransport {
        @Volatile
        var calls: Int = 0
        val requests = mutableListOf<WeatherHttpRequest>()
    }

    private class FakeSessionProvider(session: WeatherSession) : WeatherSessionProvider {
        @Volatile
        var session: WeatherSession = session

        override fun current(): WeatherSession = session
    }

    private class ScriptedTransport(vararg steps: Step) : CountingTransport() {
        private val pending = ArrayDeque(steps.toList())

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            requests += request
            return when (val step = pending.removeFirst()) {
                is Respond -> step.response
                is Fail -> throw step.error
            }
        }
    }

    private class GatedTransport(
        private val response: WeatherHttpResponse,
        private val gate: CompletableDeferred<Unit>,
    ) : CountingTransport() {
        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            requests += request
            gate.await()
            return response
        }
    }

    private class GatedFailingTransport(private val gate: CompletableDeferred<Unit>) : CountingTransport() {
        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            requests += request
            gate.await()
            throw IOException("offline")
        }
    }

    private class LateResponseTransport(
        private val response: WeatherHttpResponse,
        private val gate: CompletableDeferred<Unit>,
    ) : CountingTransport() {
        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            requests += request
            withContext(NonCancellable) { gate.await() }
            return response
        }
    }

    private class PersistFailingThrottleStore : WeatherThrottleStore {
        private val delegate = InMemoryWeatherThrottleStore()

        override fun claim(now: Instant, minimumInterval: Duration): WeatherAttemptDecision =
            delegate.claim(now, minimumInterval)

        override fun recordRetryNotBefore(until: Instant): Boolean = false

        override fun snapshot(): WeatherAttemptGate? = delegate.snapshot()
    }

    private class WriteFailingCacheStore : WeatherCacheStore {
        override fun read(locationKey: String): WeatherCacheEntry? = null

        override fun write(entry: WeatherCacheEntry): Boolean = false
    }

    private class ReadFailingCacheStore : WeatherCacheStore {
        override fun read(locationKey: String): WeatherCacheEntry? = throw IOException("cache read failed")

        override fun write(entry: WeatherCacheEntry): Boolean = true
    }
}
