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

import java.time.Instant
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherHomeOwnerTest {

    private val location = validLocation("Home", "51.5074", "-0.1278")
    private val otherLocation = validLocation("Work", "48.8566", "2.3522")
    private val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)

    @Test
    fun noWorkRunsBeforePersistedConsentAndVisibleHomeAreConfirmed() = runBlocking {
        val harness = Harness(FakeConsentStore(enabled))

        harness.owner.setScreenInteractive(true)
        harness.owner.setUserPresent(true)
        assertEquals("consent must be read from the store, not assumed", 0, harness.work.starts.size)
        assertEquals(0, harness.store.reads)

        harness.owner.setHomeVisible(true)

        assertEquals(1, harness.store.reads)
        assertEquals(1, harness.work.starts.size)
        assertTrue(harness.owner.current().isActive)
        harness.close()
    }

    @Test
    fun persistedDisabledConsentStartsNoWorkEvenOnVisibleHome() {
        val harness = Harness(FakeConsentStore(WeatherConsentState.DISABLED))

        harness.showHome()

        assertTrue(harness.work.starts.isEmpty())
        assertFalse(harness.owner.current().isActive)
        harness.close()
    }

    @Test
    fun storageFailureFailsClosedWithoutWork() {
        val harness = Harness(ThrowingConsentStore())

        harness.showHome()

        assertTrue(harness.work.starts.isEmpty())
        assertFalse(harness.owner.current().enabled)
        assertFalse(harness.owner.current().isActive)
        harness.close()
    }

    @Test
    fun settingsEnableWhileHiddenStartsNoWorkAndIsUsedOnHomeReentry() {
        val harness = Harness(FakeConsentStore(WeatherConsentState.DISABLED))

        harness.store.state = enabled
        harness.owner.onConsentChanged(enabled)
        assertTrue("no work while HOME is hidden", harness.work.starts.isEmpty())

        harness.showHome()

        assertEquals(1, harness.work.starts.size)
        assertEquals(location.coordinates, harness.work.starts.single().location)
        harness.close()
    }

    @Test
    fun observerEnableWaitsForScreenOnAndUserPresent() {
        val harness = Harness(FakeConsentStore(WeatherConsentState.DISABLED))
        harness.owner.setScreenInteractive(true)
        harness.owner.setHomeVisible(true)
        harness.owner.setUserPresent(false)

        harness.store.state = enabled
        harness.owner.onConsentChanged(enabled)
        assertTrue(harness.work.starts.isEmpty())

        harness.owner.setUserPresent(true)

        assertEquals(1, harness.work.starts.size)
        harness.close()
    }

    @Test
    fun screenOffCancelsAndDropsTheInFlightResult() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        val generation = harness.owner.current().generation

        harness.owner.setScreenInteractive(false)
        harness.work.complete(forecast(location))

        assertFalse(harness.owner.current().isActive)
        assertTrue(harness.owner.current().generation > generation)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun userAbsentCancelsAndDropsTheInFlightResult() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        val generation = harness.owner.current().generation

        harness.owner.setUserPresent(false)
        harness.work.complete(forecast(location))

        assertFalse(harness.owner.current().isActive)
        assertTrue(harness.owner.current().generation > generation)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun pauseCancelsAndReentryReReadsThePersistedConsentBeforeLoading() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        assertEquals(1, harness.work.starts.size)

        harness.owner.setHomeVisible(false)
        harness.store.state = WeatherConsentPolicy.enable(enabled, otherLocation)

        harness.owner.setHomeVisible(true)

        assertEquals(2, harness.work.starts.size)
        assertEquals(otherLocation.coordinates, harness.work.starts[1].location)
        harness.close()
    }

    @Test
    fun reentryUsesPersistedDisabledConsentInsteadOfTheStaleInMemoryEnable() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        assertEquals(1, harness.work.starts.size)

        harness.owner.setHomeVisible(false)
        harness.store.state = WeatherConsentPolicy.disable(enabled)

        harness.owner.setHomeVisible(true)

        assertEquals(1, harness.work.starts.size)
        assertFalse(harness.owner.current().isActive)
        harness.close()
    }

    @Test
    fun disableFromTheSharedOwnerCancelsAndDropsTheInFlightResult() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        val generation = harness.owner.current().generation

        harness.owner.onConsentChanged(WeatherConsentPolicy.disable(enabled))
        harness.work.complete(forecast(location))

        assertFalse(harness.owner.current().enabled)
        assertTrue(harness.owner.current().generation > generation)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun editFromTheSharedOwnerCancelsTheOldLoadAndStartsTheNewLocation() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        val old = harness.work.starts.single()
        val edited = WeatherConsentPolicy.enable(enabled, otherLocation)

        harness.owner.onConsentChanged(edited)

        assertEquals(2, harness.work.starts.size)
        assertEquals(otherLocation.coordinates, harness.work.starts[1].location)
        assertTrue(harness.work.starts[1].generation > old.generation)
        harness.work.completeAt(0, forecast(location))
        assertTrue("the cancelled old load must not be delivered", harness.results.isEmpty())
        harness.work.complete(forecast(otherLocation))
        assertEquals(1, harness.results.size)
        harness.close()
    }

    @Test
    fun repeatedVisibleCallsDoNotDuplicateTheReadOrTheLoad() {
        val harness = Harness(FakeConsentStore(enabled))

        harness.showHome()
        harness.owner.setHomeVisible(true)
        harness.owner.setHomeVisible(true)

        assertEquals(1, harness.store.reads)
        assertEquals(1, harness.work.starts.size)
        harness.close()
    }

    @Test
    fun shutdownCancelsWorkAndIgnoresLaterEvents() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()

        harness.owner.shutdown()
        harness.work.complete(forecast(location))

        assertTrue(harness.results.isEmpty())
        assertFalse(harness.owner.current().enabled)

        harness.owner.onConsentChanged(enabled)
        harness.owner.setHomeVisible(true)
        assertEquals(1, harness.work.starts.size)
        harness.close()
    }

    @Test
    fun readQueuedBeforePauseIsDroppedInsteadOfStartingWork() {
        val dispatcher = QueuedDispatcher()
        val harness = Harness(FakeConsentStore(enabled), dispatcher)
        harness.owner.setScreenInteractive(true)
        harness.owner.setUserPresent(true)

        harness.owner.setHomeVisible(true)
        harness.owner.setHomeVisible(false)
        dispatcher.runAll()

        assertTrue(harness.work.starts.isEmpty())
        harness.close()
    }

    @Test
    fun readQueuedBeforeASharedOwnerChangeCannotOverrideTheNewerDecision() {
        val dispatcher = QueuedDispatcher()
        val harness = Harness(FakeConsentStore(enabled), dispatcher)
        harness.owner.setScreenInteractive(true)
        harness.owner.setUserPresent(true)

        harness.owner.setHomeVisible(true)
        harness.owner.onConsentChanged(WeatherConsentPolicy.disable(enabled))
        dispatcher.runAll()

        assertFalse(harness.owner.current().enabled)
        assertTrue(harness.work.starts.isEmpty())
        harness.close()
    }

    @Test
    fun readQueuedBeforeAnEditCannotRestoreTheOlderCoordinates() {
        val dispatcher = QueuedDispatcher()
        val harness = Harness(FakeConsentStore(enabled), dispatcher)
        harness.owner.setScreenInteractive(true)
        harness.owner.setUserPresent(true)
        harness.owner.setHomeVisible(true)

        harness.owner.onConsentChanged(WeatherConsentPolicy.enable(enabled, otherLocation))
        dispatcher.runAll()

        assertEquals(otherLocation.coordinates, harness.owner.current().location)
        assertTrue(harness.work.starts.isNotEmpty())
        assertTrue(harness.work.starts.all { it.location == otherLocation.coordinates })
        harness.close()
    }

    @Test
    fun theProductionPlaceholderWorkNeverReturnsAForecast() = runBlocking {
        val result = NoNetworkWeatherWork.load(
            WeatherSession(
                enabled = true,
                visible = true,
                generation = 1,
                location = location.coordinates,
            ),
        )

        assertTrue(result is WeatherLoadResult.Unavailable)
        assertFalse(result is WeatherLoadResult.Success)
    }

    @Test
    fun activityWiringGuardRequiresResumedConfirmedNormalWithoutATransition() {
        assertTrue(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = true,
                homeConfirmed = true,
                transitionInProgress = false,
                finishing = false,
                destroyed = false,
            ),
        )
        assertFalse(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = false,
                homeConfirmed = true,
                transitionInProgress = false,
                finishing = false,
                destroyed = false,
            ),
        )
        assertFalse(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = true,
                homeConfirmed = false,
                transitionInProgress = false,
                finishing = false,
                destroyed = false,
            ),
        )
        assertFalse(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = true,
                homeConfirmed = true,
                transitionInProgress = true,
                finishing = false,
                destroyed = false,
            ),
        )
        assertFalse(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = true,
                homeConfirmed = true,
                transitionInProgress = false,
                finishing = true,
                destroyed = false,
            ),
        )
        assertFalse(
            WeatherHomeWiring.isHomeVisible(
                activityResumed = true,
                homeConfirmed = true,
                transitionInProgress = false,
                finishing = false,
                destroyed = true,
            ),
        )
    }

    @Test
    fun screenOffClearsBothGatesAndDropsAQueuedConsentRead() {
        val dispatcher = QueuedDispatcher()
        val harness = Harness(FakeConsentStore(enabled), dispatcher)
        harness.owner.setScreenInteractive(true)
        harness.owner.setUserPresent(true)
        harness.owner.setHomeVisible(true)

        harness.owner.onScreenOff()
        dispatcher.runAll()

        assertTrue(harness.work.starts.isEmpty())
        assertFalse(harness.owner.current().visible)

        harness.owner.setScreenInteractive(true)
        dispatcher.runAll()
        assertTrue("screen-on must not restore a stale unlock", harness.work.starts.isEmpty())
        assertFalse(harness.owner.current().visible)

        harness.owner.setUserPresent(true)
        dispatcher.runAll()

        assertEquals(1, harness.work.starts.size)
        assertTrue(harness.owner.current().isActive)
        harness.close()
    }

    @Test
    fun pauseAndResumeReuseTheSameOpenOwnerWithoutShutdown() {
        val harness = Harness(FakeConsentStore(enabled))
        harness.showHome()
        assertEquals(1, harness.work.starts.size)

        harness.owner.setHomeVisible(false)
        assertFalse(harness.owner.isClosed)

        harness.owner.setHomeVisible(true)

        assertEquals(2, harness.work.starts.size)
        assertFalse(harness.owner.isClosed)
        harness.close()
    }

    private fun validLocation(label: String, latitude: String, longitude: String): WeatherManualLocation = (WeatherConsentPolicy.parseLocation(label, latitude, longitude) as WeatherLocationInput.Valid).location

    private fun forecast(location: WeatherManualLocation): WeatherLoadResult = WeatherLoadResult.Success(
        forecast = WeatherForecast(
            provider = "MET Norway",
            locationKey = location.coordinates.cacheKey,
            temperatureCelsius = 7.5,
            symbolCode = "clearsky_day",
            validAt = Instant.parse("2026-11-23T13:00:00Z"),
            retrievedAt = Instant.parse("2026-11-23T12:00:00Z"),
        ),
        stale = false,
        cacheUpdated = true,
    )

    private class Harness(
        val store: FakeConsentStore,
        dispatcher: CoroutineDispatcher = Dispatchers.Unconfined,
    ) {
        private val scope = CoroutineScope(SupervisorJob() + dispatcher)
        val work = ControlledWork()
        val results = mutableListOf<WeatherLoadResult>()
        val owner = WeatherHomeOwner(
            consentStore = store,
            work = work,
            scope = scope,
            resultSink = WeatherResultSink { results += it },
            ioDispatcher = dispatcher,
        )

        fun showHome() {
            owner.setScreenInteractive(true)
            owner.setUserPresent(true)
            owner.setHomeVisible(true)
        }

        fun close() {
            owner.shutdown()
            scope.cancel()
        }
    }

    private open class FakeConsentStore(
        @Volatile var state: WeatherConsentState,
    ) : WeatherConsentStore {
        var reads: Int = 0

        override fun read(): WeatherConsentState {
            reads += 1
            return state
        }

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

    private class ThrowingConsentStore : FakeConsentStore(WeatherConsentState.DISABLED) {
        override fun read(): WeatherConsentState = throw IllegalStateException("storage unavailable")
    }

    private class QueuedDispatcher : CoroutineDispatcher() {
        private val queued = ArrayDeque<Runnable>()

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            queued.addLast(block)
        }

        fun runAll() {
            while (queued.isNotEmpty()) queued.removeFirst().run()
        }
    }

    private class ControlledWork : WeatherLoadWork {
        val starts = mutableListOf<WeatherSession>()
        private val completions = mutableListOf<CompletableDeferred<WeatherLoadResult>>()

        override suspend fun load(session: WeatherSession): WeatherLoadResult {
            starts += session
            val deferred = CompletableDeferred<WeatherLoadResult>()
            completions += deferred
            return deferred.await()
        }

        fun complete(result: WeatherLoadResult) {
            completions.lastOrNull()?.complete(result)
        }

        fun completeAt(index: Int, result: WeatherLoadResult) {
            completions.getOrNull(index)?.complete(result)
        }
    }
}
