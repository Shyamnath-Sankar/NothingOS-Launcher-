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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherSessionPolicyTest {

    private val location = (
        WeatherConsentPolicy.parseLocation("Home", "51.5074", "-0.1278")
            as WeatherLocationInput.Valid
        ).location
    private val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)

    @Test
    fun aVisibleHomeNeedsConsentScreenOnAndAUserWhoIsPresent() {
        val fullyVisible = WeatherVisibilityState(
            homeResumed = true,
            screenOn = true,
            userPresent = true,
        )

        val session = WeatherSessionPolicy.session(enabled, fullyVisible, generation = 7L)

        assertTrue(session.isActive)
        assertEquals(7L, session.generation)
        assertEquals(location.coordinates, session.location)
        assertEquals(true, session.enabled)
        assertEquals(true, session.visible)
    }

    @Test
    fun everyVisibilityConditionIndependentlyBlocksTheSession() {
        listOf(
            WeatherVisibilityState(homeResumed = false, screenOn = true, userPresent = true),
            WeatherVisibilityState(homeResumed = true, screenOn = false, userPresent = true),
            WeatherVisibilityState(homeResumed = true, screenOn = true, userPresent = false),
            WeatherVisibilityState(),
        ).forEach { visibility ->
            val session = WeatherSessionPolicy.session(enabled, visibility, generation = 1L)
            assertFalse("$visibility must not be active", session.isActive)
        }
    }

    @Test
    fun consentAloneIsNeverActiveWithoutTheVisibleHomeGate() {
        val session = WeatherSessionPolicy.session(
            consent = enabled,
            visibility = WeatherVisibilityState(homeResumed = true, screenOn = false, userPresent = true),
            generation = enabled.generation,
        )

        assertFalse(session.isActive)
        assertEquals(location.coordinates, session.location)
    }

    @Test
    fun disabledConsentProducesAnInactiveSessionEvenWhenTheHomeIsVisible() {
        val session = WeatherSessionPolicy.session(
            consent = WeatherConsentState.DISABLED,
            visibility = WeatherVisibilityState(homeResumed = true, screenOn = true, userPresent = true),
            generation = 0L,
        )

        assertFalse(session.isActive)
        assertFalse(session.enabled)
        assertNull(session.location)
    }
}
