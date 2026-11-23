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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherSessionControllerTest {

    private val location = (
        WeatherConsentPolicy.parseLocation("Home", "51.5074", "-0.1278")
            as WeatherLocationInput.Valid
        ).location
    private val otherLocation = (
        WeatherConsentPolicy.parseLocation("Work", "48.8566", "2.3522")
            as WeatherLocationInput.Valid
        ).location
    private val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)

    @Test
    fun noWorkRunsUntilConsentAndEveryVisibleHomeConditionAreTrue() = runBlocking {
        val harness = Harness()

        harness.controller.setConsent(enabled)
        harness.controller.setHomeResumed(true)
        harness.controller.setScreenOn(true)
        assertEquals(0, harness.work.starts.size)

        harness.controller.setUserPresent(true)

        assertEquals(1, harness.work.starts.size)
        assertTrue(harness.controller.current().isActive)
        harness.close()
    }

    @Test
    fun theFirstActiveTransitionStartsExactlyOneLoad() = runBlocking {
        val harness = Harness()
        harness.activate()

        assertEquals(1, harness.work.starts.size)

        harness.controller.setHomeResumed(true)
        harness.controller.setScreenOn(true)
        harness.controller.setUserPresent(true)

        assertEquals(1, harness.work.starts.size)
        harness.close()
    }

    @Test
    fun pausingImmediatelyRevokesTheSessionAndDropsTheInFlightResult() = runBlocking {
        val harness = Harness()
        harness.activate()
        val inFlight = harness.work.starts.single()
        val generation = harness.controller.current().generation

        harness.controller.setHomeResumed(false)
        harness.work.complete(forecast())

        assertFalse(harness.controller.current().isActive)
        assertTrue(harness.controller.current().generation > generation)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun screenOffAndUserAbsentAlsoCancelAndRevoke() = runBlocking {
        val harness = Harness()
        harness.activate()
        harness.controller.setScreenOn(false)

        assertFalse(harness.controller.current().isActive)
        assertTrue(harness.results.isEmpty())

        harness.controller.setScreenOn(true)
        harness.controller.setUserPresent(false)

        assertFalse(harness.controller.current().isActive)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun disablingConsentCancelsTheLoadWithoutWaitingForIt() = runBlocking {
        val harness = Harness()
        harness.activate()

        harness.controller.setConsent(WeatherConsentPolicy.disable(enabled))
        harness.work.complete(forecast())

        assertFalse(harness.controller.current().enabled)
        assertFalse(harness.controller.current().isActive)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    @Test
    fun resumingAfterAPauseStartsAFreshLoadWithANewGeneration() = runBlocking {
        val harness = Harness()
        harness.activate()
        val first = harness.work.starts.single()
        harness.controller.setHomeResumed(false)
        harness.controller.setHomeResumed(true)

        assertEquals(2, harness.work.starts.size)
        assertTrue(harness.work.starts[1].generation > first.generation)
        harness.close()
    }

    @Test
    fun editingTheLocationCancelsTheOldLoadAndStartsTheNewOne() = runBlocking {
        val harness = Harness()
        harness.activate()
        val oldSession = harness.work.starts.single()
        val edited = WeatherConsentPolicy.enable(enabled, otherLocation)

        harness.controller.setConsent(edited)

        assertEquals(2, harness.work.starts.size)
        assertEquals(otherLocation.coordinates, harness.work.starts[1].location)
        assertTrue(harness.work.starts[1].generation > oldSession.generation)
        harness.work.completeAt(0, forecast())
        assertTrue("the cancelled old load must not be delivered", harness.results.isEmpty())
        harness.work.complete(forecast())
        assertEquals(1, harness.results.size)
        harness.close()
    }

    @Test
    fun anExplicitLoadRequestDoesNotDuplicateAnAlreadyRunningLoad() = runBlocking {
        val harness = Harness()
        harness.activate()

        harness.controller.requestLoad()
        harness.controller.requestLoad()

        assertEquals(1, harness.work.starts.size)
        harness.work.complete(forecast())
        assertEquals(1, harness.results.size)
        harness.close()
    }

    @Test
    fun aCompletedCurrentLoadIsDeliveredOnce() = runBlocking {
        val harness = Harness()
        harness.activate()

        harness.work.complete(forecast())

        assertEquals(1, harness.results.size)
        assertTrue(harness.results.single() is WeatherLoadResult.Success)
        harness.close()
    }

    @Test
    fun stopCancelsEverythingAndLeavesTheSessionDisabled() = runBlocking {
        val harness = Harness()
        harness.activate()

        harness.controller.stop()
        harness.work.complete(forecast())

        assertFalse(harness.controller.current().enabled)
        assertFalse(harness.controller.current().isActive)
        assertTrue(harness.results.isEmpty())
        harness.close()
    }

    private fun forecast(): WeatherLoadResult = WeatherLoadResult.Success(
        forecast = WeatherForecast(
            provider = "MET Norway",
            locationKey = location.cacheKey,
            temperatureCelsius = 7.5,
            symbolCode = "clearsky_day",
            validAt = Instant.parse("2026-11-23T13:00:00Z"),
            retrievedAt = Instant.parse("2026-11-23T12:00:00Z"),
        ),
        stale = false,
        cacheUpdated = true,
    )

    private class Harness {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val work = ControlledWork()
        val results = mutableListOf<WeatherLoadResult>()
        val controller = WeatherSessionController(
            work = work,
            scope = scope,
            initialConsent = WeatherConsentState.DISABLED,
            initialVisibility = WeatherVisibilityState(),
            resultSink = WeatherResultSink { results += it },
        )

        fun activate() {
            controller.setConsent(
                WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location()),
            )
            controller.setHomeResumed(true)
            controller.setScreenOn(true)
            controller.setUserPresent(true)
        }

        fun close() {
            controller.stop()
            scope.cancel()
        }

        private fun location(): WeatherManualLocation = (
            WeatherConsentPolicy.parseLocation("Home", "51.5074", "-0.1278")
                as WeatherLocationInput.Valid
            ).location
    }

    private class ControlledWork : WeatherLoadWork {
        val starts = mutableListOf<WeatherSession>()
        private val results = mutableListOf<CompletableDeferred<WeatherLoadResult>>()

        override suspend fun load(session: WeatherSession): WeatherLoadResult {
            starts += session
            val deferred = CompletableDeferred<WeatherLoadResult>()
            results += deferred
            return deferred.await()
        }

        fun complete(result: WeatherLoadResult) {
            results.lastOrNull()?.complete(result)
        }

        fun completeAt(index: Int, result: WeatherLoadResult) {
            results.getOrNull(index)?.complete(result)
        }
    }
}
