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

import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherWorkFactoryTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val location = WeatherCoordinates.from(latitude = 51.5074, longitude = -0.1278)!!
    private val otherLocation = WeatherCoordinates.from(latitude = 48.8566, longitude = 2.3522)!!
    private val enabledConsent = WeatherConsentPolicy.enable(
        WeatherConsentState.DISABLED,
        WeatherManualLocation(label = "Home", coordinates = location),
    )
    private val session = WeatherSession(
        enabled = true,
        visible = true,
        generation = 1,
        location = location,
    )
    private val lastModified = "Mon, 23 Nov 2026 11:00:00 GMT"
    private val threeHours: Duration = Duration.ofHours(3)

    @Test
    fun disabledOrInactiveSessionsNeverReachTheTransport() = runBlocking {
        val transport = ScriptedTransport()
        val clock = FakeClock(now)
        val work = work(transport = transport, provider = StaticSessionProvider(session), clock = clock)

        assertEquals(
            WeatherLoadResult.Disabled,
            work.load(session.copy(enabled = false)),
        )
        assertEquals(
            WeatherLoadResult.Disabled,
            work.load(session.copy(visible = false)),
        )
        assertEquals(
            WeatherLoadResult.Disabled,
            work.load(session.copy(location = null)),
        )
        assertEquals(0, transport.calls)
    }

    @Test
    fun anEnabledVisibleHomeLoadsOneForecastAndPersistsTheAttemptGate() = runBlocking {
        val directory = Files.createTempDirectory("weather-factory-one").toFile()
        try {
            val transport = ScriptedTransport(Respond(successResponse()))
            val throttle = FileWeatherThrottleStore(directory)
            val work = work(
                transport = transport,
                provider = StaticSessionProvider(session),
                throttle = throttle,
                clock = FakeClock(now),
            )

            val result = work.load(session) as WeatherLoadResult.Success

            assertEquals(7.5, result.forecast.temperatureCelsius, 0.0)
            assertEquals(1, transport.calls)
            assertEquals(now, throttle.snapshot()!!.lastAttemptAt)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun aFreshCacheIsServedWithoutAnEarlyRepeatRequest() = runBlocking {
        val directory = Files.createTempDirectory("weather-factory-cache").toFile()
        try {
            val cache = FileWeatherCacheStore(directory)
            val transport = ScriptedTransport(Respond(successResponse()))
            val clock = FakeClock(now)
            val work = work(
                transport = transport,
                cache = cache,
                provider = StaticSessionProvider(session),
                clock = clock,
            )

            work.load(session)
            clock.now = now.plus(Duration.ofMinutes(30))
            val second = work.load(session) as WeatherLoadResult.Success

            assertEquals(1, transport.calls)
            assertEquals(7.5, second.forecast.temperatureCelsius, 0.0)
            assertFalse(second.cacheUpdated)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun aRecreatedWorkReadsThePersistedThrottleFloor() = runBlocking {
        val directory = Files.createTempDirectory("weather-factory-throttle").toFile()
        try {
            val firstTransport = ScriptedTransport(Respond(successResponse()))
            val first = work(
                transport = firstTransport,
                provider = StaticSessionProvider(session),
                throttle = FileWeatherThrottleStore(directory),
                clock = FakeClock(now),
            )
            first.load(session)

            val secondTransport = ScriptedTransport(Respond(successResponse()))
            val movedSession = session.copy(generation = 2, location = otherLocation)
            val recreated = work(
                transport = secondTransport,
                provider = StaticSessionProvider(movedSession),
                throttle = FileWeatherThrottleStore(directory),
                clock = FakeClock(now.plus(Duration.ofMinutes(5))),
            )

            val blocked = recreated.load(movedSession) as WeatherLoadResult.Unavailable

            assertEquals(WeatherFailureReason.THROTTLED, blocked.reason)
            assertEquals(now.plus(threeHours), blocked.retryAt)
            assertEquals(0, secondTransport.calls)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun forbiddenAndRateLimitedResponsesPersistTheServerBackoff() = runBlocking {
        val forbiddenDirectory = Files.createTempDirectory("weather-factory-403").toFile()
        val rateLimitDirectory = Files.createTempDirectory("weather-factory-429").toFile()
        try {
            val forbidden = ScriptedTransport(
                Respond(
                    WeatherHttpResponse(
                        code = 403,
                        body = null,
                        expiresAt = null,
                        lastModified = null,
                        retryAfter = "28800",
                    ),
                ),
            )
            val forbiddenStore = FileWeatherThrottleStore(forbiddenDirectory)
            val forbiddenWork = work(
                transport = forbidden,
                provider = StaticSessionProvider(session),
                throttle = forbiddenStore,
                clock = FakeClock(now),
            )

            val refused = forbiddenWork.load(session) as WeatherLoadResult.Unavailable

            assertEquals(WeatherFailureReason.FORBIDDEN, refused.reason)
            assertEquals(now.plus(Duration.ofHours(8)), refused.retryAt)
            assertEquals(now.plus(Duration.ofHours(8)), forbiddenStore.snapshot()!!.retryNotBefore)

            val afterForbidden = ScriptedTransport(Respond(successResponse()))
            val forbiddenRetry = work(
                transport = afterForbidden,
                provider = StaticSessionProvider(session),
                throttle = FileWeatherThrottleStore(forbiddenDirectory),
                clock = FakeClock(now.plus(Duration.ofMinutes(5))),
            ).load(session) as WeatherLoadResult.Unavailable
            assertEquals(WeatherFailureReason.THROTTLED, forbiddenRetry.reason)
            assertEquals(0, afterForbidden.calls)

            val limited = ScriptedTransport(
                Respond(
                    WeatherHttpResponse(
                        code = 429,
                        body = null,
                        expiresAt = null,
                        lastModified = null,
                        retryAfter = "600",
                    ),
                ),
            )
            val limitedStore = FileWeatherThrottleStore(rateLimitDirectory)
            val limitedWork = work(
                transport = limited,
                provider = StaticSessionProvider(session),
                throttle = limitedStore,
                clock = FakeClock(now),
            )

            val throttled = limitedWork.load(session) as WeatherLoadResult.Unavailable

            assertEquals(WeatherFailureReason.RATE_LIMITED, throttled.reason)
            assertEquals(now.plus(threeHours), throttled.retryAt)
            assertEquals(now.plus(Duration.ofMinutes(10)), limitedStore.snapshot()!!.retryNotBefore)
        } finally {
            forbiddenDirectory.deleteRecursively()
            rateLimitDirectory.deleteRecursively()
        }
    }

    @Test
    fun leavingHomeDropsALateResponseAndNeverCommitsItsCache() = runBlocking {
        val directory = Files.createTempDirectory("weather-factory-late").toFile()
        try {
            val gate = CompletableDeferred<Unit>()
            val transport = GatedTransport(successResponse(), gate)
            val holder = AtomicReference<WeatherHomeOwner?>()
            val provider = WeatherRuntimeSessionProvider { holder.get() }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
            val results = mutableListOf<WeatherLoadResult>()
            val work = work(
                transport = transport,
                cache = FileWeatherCacheStore(directory),
                provider = provider,
                clock = FakeClock(now),
            )
            val owner = WeatherHomeOwner(
                consentStore = FakeConsentStore(enabledConsent),
                work = work,
                scope = scope,
                resultSink = WeatherResultSink { results += it },
                ioDispatcher = Dispatchers.Unconfined,
            )
            holder.set(owner)
            try {
                owner.setScreenInteractive(true)
                owner.setUserPresent(true)
                owner.setHomeVisible(true)
                waitForFirstRequest(transport)

                owner.setScreenInteractive(false)
                gate.complete(Unit)
                repeat(32) { Thread.yield() }

                assertTrue(results.isEmpty())
                assertNull(FileWeatherCacheStore(directory).read(location.cacheKey))
            } finally {
                owner.shutdown()
                scope.cancel()
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun theRuntimeSessionProviderFailsClosedWithoutAFullyAvailableOwner() {
        val provider = WeatherRuntimeSessionProvider { null }
        assertEquals(WeatherSession.DISABLED, provider.current())

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val owner = WeatherHomeOwner(
            consentStore = FakeConsentStore(enabledConsent),
            work = WeatherLoadWork { WeatherLoadResult.Disabled },
            scope = scope,
        )
        val available = WeatherRuntimeSessionProvider { owner }
        owner.shutdown()
        assertEquals(WeatherSession.DISABLED, available.current())
        scope.cancel()
    }

    @Test
    fun disablingThePersistedOptInClearsTheLocationCache() = runBlocking {
        val consentDirectory = Files.createTempDirectory("weather-factory-consent").toFile()
        val cacheDirectory = Files.createTempDirectory("weather-factory-disable-cache").toFile()
        try {
            val consentStore = FileWeatherConsentStore(consentDirectory)
            consentStore.compareAndSet(WeatherConsentState.DISABLED.generation, enabledConsent)
            val cache = FileWeatherCacheStore(cacheDirectory)
            cache.write(
                WeatherCacheEntry(
                    locationKey = location.cacheKey,
                    body = successResponse().body!!,
                    retrievedAt = now,
                    expiresAt = now.plus(Duration.ofHours(4)),
                    lastModified = lastModified,
                ),
            )
            val controller = WeatherSettingsController(
                store = consentStore,
                cacheStore = cache,
                ioDispatcher = Dispatchers.Unconfined,
            )

            controller.load()
            controller.disable()

            assertFalse(controller.state.value.saved.enabled)
            assertNull(cache.read(location.cacheKey))
        } finally {
            consentDirectory.deleteRecursively()
            cacheDirectory.deleteRecursively()
        }
    }

    private fun work(
        transport: WeatherHttpTransport,
        cache: WeatherCacheStore = InMemoryWeatherCacheStore(),
        provider: WeatherSessionProvider,
        throttle: WeatherThrottleStore = InMemoryWeatherThrottleStore(),
        clock: FakeClock,
    ): WeatherLoadWork = WeatherWorkFactory.create(
        transport = transport,
        cacheStore = cache,
        throttleStore = throttle,
        sessionProvider = provider,
        clock = { clock.now },
    )

    private fun waitForFirstRequest(transport: CountingTransport) {
        var spins = 0
        while (transport.calls == 0 && spins++ < 100_000) {
            Thread.yield()
        }
        assertEquals(1, transport.calls)
    }

    private fun successResponse(): WeatherHttpResponse = WeatherHttpResponse(
        code = 200,
        body = """
            {
              "type": "Feature",
              "properties": {
                "meta": {"updated_at": "2026-11-23T11:00:00Z"},
                "timeseries": [
                  {
                    "time": "2026-11-23T13:00:00Z",
                    "data": {
                      "instant": {"details": {"air_temperature": 7.5}},
                      "next_1_hours": {"summary": {"symbol_code": "cloudy"}}
                    }
                  }
                ]
              }
            }
        """.trimIndent(),
        expiresAt = now.plus(Duration.ofHours(4)),
        lastModified = lastModified,
    )

    private class FakeClock(@Volatile var now: Instant)

    private sealed interface Step
    private data class Respond(val response: WeatherHttpResponse) : Step

    private abstract class CountingTransport : WeatherHttpTransport {
        @Volatile
        var calls: Int = 0
    }

    private class ScriptedTransport(vararg steps: Step) : CountingTransport() {
        private val pending = ArrayDeque(steps.toList())

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            return when (val step = pending.removeFirst()) {
                is Respond -> step.response
            }
        }
    }

    private class GatedTransport(
        private val response: WeatherHttpResponse,
        private val gate: CompletableDeferred<Unit>,
    ) : CountingTransport() {
        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            calls++
            withContext(NonCancellable) { gate.await() }
            return response
        }
    }

    private class StaticSessionProvider(private val session: WeatherSession) : WeatherSessionProvider {
        override fun current(): WeatherSession = session
    }

    private open class FakeConsentStore(
        @Volatile var state: WeatherConsentState,
    ) : WeatherConsentStore {
        override fun read(): WeatherConsentState = state

        override fun compareAndSet(
            expectedGeneration: Long,
            next: WeatherConsentState,
        ): WeatherConsentWriteResult {
            if (state.generation != expectedGeneration) {
                return WeatherConsentWriteResult.Conflict(state)
            }
            state = next
            return WeatherConsentWriteResult.Committed(next)
        }
    }
}
