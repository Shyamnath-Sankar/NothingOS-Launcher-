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

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherHomeLifecycleTest {

    private val home = validLocation("Home", "51.5074", "-0.1278")
    private val work = validLocation("Work", "48.8566", "2.3522")
    private val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, home)

    @Test
    fun screenGateNeedsAnInteractiveAndUnlockedScreen() {
        assertEquals(
            WeatherScreenGate(screenInteractive = true, userPresent = true),
            WeatherScreenPolicy.evaluate(interactive = true, keyguardLocked = false),
        )
        assertEquals(
            WeatherScreenGate(screenInteractive = true, userPresent = false),
            WeatherScreenPolicy.evaluate(interactive = true, keyguardLocked = true),
        )
        assertEquals(
            WeatherScreenGate(screenInteractive = false, userPresent = false),
            WeatherScreenPolicy.evaluate(interactive = false, keyguardLocked = false),
        )
        assertEquals(
            WeatherScreenGate(screenInteractive = false, userPresent = false),
            WeatherScreenPolicy.evaluate(interactive = false, keyguardLocked = true),
        )
    }

    @Test
    fun transitionStartHidesEvenWhenItTargetsHome() {
        val surface = WeatherHomeSurfaceState()
        surface.onResume(currentStateIsHome = true, transitionInProgress = false)
        assertTrue(surface.isVisible)

        surface.onTransitionStart()

        assertFalse(surface.isVisible)
        assertFalse(surface.isHomeConfirmed)
        assertTrue(surface.isTransitionInProgress)

        surface.onTransitionComplete(finalStateIsHome = true)

        assertTrue(surface.isVisible)
    }

    @Test
    fun reversedTransitionStaysHiddenUntilACompletedHomeArrives() {
        val surface = WeatherHomeSurfaceState()
        surface.onResume(currentStateIsHome = true, transitionInProgress = false)

        surface.onTransitionStart()
        assertFalse(surface.isVisible)

        surface.onTransitionComplete(finalStateIsHome = false)
        assertFalse(surface.isVisible)

        surface.onTransitionStart()
        assertFalse("returning toward HOME must stay hidden until it completes", surface.isVisible)

        surface.onTransitionStart()
        assertFalse(surface.isVisible)

        surface.onTransitionComplete(finalStateIsHome = false)
        assertFalse(surface.isVisible)

        surface.onTransitionStart()
        surface.onTransitionComplete(finalStateIsHome = true)

        assertTrue(surface.isVisible)
    }

    @Test
    fun resumeConfirmsHomeOnlyWhenNoTransitionIsInProgress() {
        val surface = WeatherHomeSurfaceState()

        surface.onResume(currentStateIsHome = true, transitionInProgress = true)
        assertFalse(surface.isVisible)

        surface.onTransitionComplete(finalStateIsHome = true)
        assertTrue(surface.isVisible)

        surface.onPause()
        assertFalse(surface.isVisible)

        surface.onResume(currentStateIsHome = false, transitionInProgress = false)
        assertFalse(surface.isVisible)

        surface.onDestroy()
        assertFalse(surface.isVisible)
    }

    @Test
    fun olderPersistedEnabledLocationCannotOverrideANewerEdit() {
        val edited = WeatherConsentPolicy.enable(enabled, work)

        val chosen = WeatherHomeConsentPolicy.choose(loaded = enabled, observed = edited)

        assertEquals(edited, chosen)
    }

    @Test
    fun sameGenerationEnabledConflictKeepsTheInProcessState() {
        val conflicting = WeatherConsentState(
            enabled = true,
            location = work,
            generation = enabled.generation,
        )

        val chosen = WeatherHomeConsentPolicy.choose(loaded = enabled, observed = conflicting)

        assertEquals(conflicting, chosen)
    }

    @Test
    fun persistedDisableIsAlwaysAcceptedEvenWhenItIsOlder() {
        val disabled = WeatherConsentPolicy.disable(enabled)
        val newerObserved = WeatherConsentPolicy.enable(
            WeatherConsentPolicy.enable(disabled, work),
            home,
        )

        val chosen = WeatherHomeConsentPolicy.choose(loaded = disabled, observed = newerObserved)

        assertEquals(disabled, chosen)
    }

    @Test
    fun newerPersistedEnableIsAccepted() {
        val observed = WeatherConsentPolicy.disable(enabled)
        val newerLoaded = WeatherConsentPolicy.enable(observed, work)

        val chosen = WeatherHomeConsentPolicy.choose(loaded = newerLoaded, observed = observed)

        assertEquals(newerLoaded, chosen)
    }

    @Test
    fun identicalPersistedStateIsAccepted() {
        assertEquals(
            enabled,
            WeatherHomeConsentPolicy.choose(loaded = enabled, observed = enabled),
        )
    }

    @Test
    fun aClosedOwnerIsNeverReused() {
        assertFalse(WeatherHomeRuntimePolicy.shouldReuseOwner(null))

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val owner = WeatherHomeOwner(
            consentStore = DisabledConsentStore,
            work = WeatherLoadWork {
                WeatherLoadResult.Unavailable(reason = WeatherFailureReason.CACHE_MISS)
            },
            scope = scope,
        )
        assertTrue(WeatherHomeRuntimePolicy.shouldReuseOwner(owner))

        owner.shutdown()

        assertFalse(WeatherHomeRuntimePolicy.shouldReuseOwner(owner))
        scope.coroutineContext[Job]?.cancel()
    }

    private fun validLocation(label: String, latitude: String, longitude: String): WeatherManualLocation = (WeatherConsentPolicy.parseLocation(label, latitude, longitude) as WeatherLocationInput.Valid).location

    private object DisabledConsentStore : WeatherConsentStore {
        override fun read(): WeatherConsentState = WeatherConsentState.DISABLED

        override fun compareAndSet(
            expectedGeneration: Long,
            next: WeatherConsentState,
        ): WeatherConsentWriteResult = WeatherConsentWriteResult.StorageFailure
    }
}
