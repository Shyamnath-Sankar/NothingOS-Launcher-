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

class WeatherConsentPolicyTest {

    @Test
    fun theDefaultStateIsExplicitlyDisabledWithoutALocation() {
        val state = WeatherConsentState.DISABLED

        assertFalse(state.enabled)
        assertFalse(state.isActive)
        assertNull(state.location)
        assertEquals(0L, state.generation)
    }

    @Test
    fun aValidDraftNormalizesTheLabelAndRoundsCoordinatesToFourDecimals() {
        val result = WeatherConsentPolicy.parseLocation(
            label = "  Home   window  ",
            latitudeText = "51.50744999",
            longitudeText = "-0.12784999",
        )

        val valid = result as WeatherLocationInput.Valid
        assertEquals("Home window", valid.location.label)
        assertEquals("51.5074", valid.location.coordinates.latitudeText)
        assertEquals("-0.1278", valid.location.coordinates.longitudeText)
        assertEquals("51.5074,-0.1278", valid.location.cacheKey)
    }

    @Test
    fun blankCoordinatesAreRejectedIndependently() {
        val result = WeatherConsentPolicy.parseLocation(
            label = "Home",
            latitudeText = " ",
            longitudeText = "",
        )

        val invalid = result as WeatherLocationInput.Invalid
        assertTrue(WeatherLocationInputError.LATITUDE_INVALID in invalid.errors)
        assertTrue(WeatherLocationInputError.LONGITUDE_INVALID in invalid.errors)
    }

    @Test
    fun nonFiniteOutOfRangeAndNonNumericCoordinatesAreRejected() {
        val invalidLatitudes = listOf("NaN", "Infinity", "-Infinity", "90.0001", "-90.0001", "abc", "51,5")
        val invalidLongitudes = listOf("NaN", "Infinity", "-Infinity", "180.0001", "-180.0001", "abc", "1e999")

        invalidLatitudes.forEach { latitude ->
            val result = WeatherConsentPolicy.parseLocation("Home", latitude, "0")
            assertTrue(
                "$latitude must be rejected",
                WeatherLocationInputError.LATITUDE_INVALID in
                    (result as WeatherLocationInput.Invalid).errors,
            )
        }
        invalidLongitudes.forEach { longitude ->
            val result = WeatherConsentPolicy.parseLocation("Home", "0", longitude)
            assertTrue(
                "$longitude must be rejected",
                WeatherLocationInputError.LONGITUDE_INVALID in
                    (result as WeatherLocationInput.Invalid).errors,
            )
        }
    }

    @Test
    fun bothCoordinateBoundariesAreAccepted() {
        listOf(
            "-90" to "-180",
            "90" to "180",
            "0" to "0",
        ).forEach { (latitude, longitude) ->
            val result = WeatherConsentPolicy.parseLocation("Edge", latitude, longitude)
            assertTrue("$latitude,$longitude must be valid", result is WeatherLocationInput.Valid)
        }
    }

    @Test
    fun theLabelIsRequiredBoundedAndFreeOfControlCharacters() {
        assertTrue(
            WeatherLocationInputError.EMPTY_LABEL in
                (WeatherConsentPolicy.parseLocation("   ", "0", "0") as WeatherLocationInput.Invalid).errors,
        )
        assertTrue(
            WeatherLocationInputError.LABEL_TOO_LONG in
                (
                    WeatherConsentPolicy.parseLocation(
                        "x".repeat(WeatherConsentPolicy.MAX_LABEL_LENGTH + 1),
                        "0",
                        "0",
                    ) as WeatherLocationInput.Invalid
                    ).errors,
        )
        assertTrue(
            WeatherLocationInputError.LABEL_INVALID_CHARACTER in
                (WeatherConsentPolicy.parseLocation("Home\u0000", "0", "0") as WeatherLocationInput.Invalid).errors,
        )
    }

    @Test
    fun enablingRequiresAValidLocationAndAdvancesTheGeneration() {
        val location = validLocation("Home")

        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)

        assertTrue(enabled.enabled)
        assertTrue(enabled.isActive)
        assertEquals(location, enabled.location)
        assertEquals(1L, enabled.generation)
    }

    @Test
    fun disablingClearsTheLocationAndAdvancesTheGeneration() {
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, validLocation("Home"))

        val disabled = WeatherConsentPolicy.disable(enabled)

        assertFalse(disabled.enabled)
        assertFalse(disabled.isActive)
        assertNull(disabled.location)
        assertEquals(enabled.generation + 1, disabled.generation)
    }

    @Test
    fun editingAnEnabledLocationUsesTheSameRevocationTransition() {
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, validLocation("Home"))

        val revoked = WeatherConsentPolicy.revokeForEdit(enabled)

        assertFalse(revoked.enabled)
        assertNull(revoked.location)
        assertTrue(revoked.generation > enabled.generation)
    }

    @Test
    fun aRevocationOfAnAlreadyDisabledStateStillAdvancesTheGeneration() {
        val first = WeatherConsentPolicy.disable(WeatherConsentState.DISABLED)
        val second = WeatherConsentPolicy.disable(first)

        assertTrue(second.generation > first.generation)
        assertNull(second.location)
    }

    private fun validLocation(label: String): WeatherManualLocation = (
        WeatherConsentPolicy.parseLocation(label, "51.5074", "-0.1278")
            as WeatherLocationInput.Valid
        ).location
}
