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

/**
 * A user-supplied weather location. Nothing in this type reads the device
 * location, a network geocoder or the system locale; the label and coordinates
 * come only from the settings fields.
 */
data class WeatherManualLocation(
    val label: String,
    val coordinates: WeatherCoordinates,
) {
    val cacheKey: String
        get() = coordinates.cacheKey
}

enum class WeatherLocationInputError {
    EMPTY_LABEL,
    LABEL_TOO_LONG,
    LABEL_INVALID_CHARACTER,
    LATITUDE_INVALID,
    LONGITUDE_INVALID,
}

sealed interface WeatherLocationInput {
    data class Valid(val location: WeatherManualLocation) : WeatherLocationInput

    data class Invalid(val errors: Set<WeatherLocationInputError>) : WeatherLocationInput
}

/**
 * The persisted consent. [enabled] is true only after the user pressed the
 * explicit enable action on a valid location. [generation] advances on every
 * enable, disable or edit-revocation so in-flight work from an older decision
 * can never commit.
 */
data class WeatherConsentState(
    val enabled: Boolean,
    val location: WeatherManualLocation?,
    val generation: Long,
) {
    init {
        require(enabled == (location != null)) { "enabled consent requires exactly one location" }
        require(generation >= 0L) { "generation must not be negative" }
    }

    val isActive: Boolean
        get() = enabled && location != null

    companion object {
        val DISABLED: WeatherConsentState = WeatherConsentState(
            enabled = false,
            location = null,
            generation = 0L,
        )
    }
}

/**
 * Pure validation and consent transitions. Coordinates are shortened to four
 * decimal places by [WeatherCoordinates] before they can be persisted or
 * become a cache key; the label is trimmed, whitespace-collapsed and bounded.
 */
object WeatherConsentPolicy {
    const val MAX_LABEL_LENGTH: Int = 48

    fun parseLocation(
        label: String,
        latitudeText: String,
        longitudeText: String,
    ): WeatherLocationInput {
        val errors = mutableSetOf<WeatherLocationInputError>()
        val normalizedLabel = normalizeLabel(label, errors)
        val latitude = parseCoordinate(latitudeText, -90.0, 90.0)
            ?: run {
                errors += WeatherLocationInputError.LATITUDE_INVALID
                null
            }
        val longitude = parseCoordinate(longitudeText, -180.0, 180.0)
            ?: run {
                errors += WeatherLocationInputError.LONGITUDE_INVALID
                null
            }
        if (errors.isNotEmpty()) return WeatherLocationInput.Invalid(errors.toSet())
        val coordinates = WeatherCoordinates.from(latitude!!, longitude!!)
            ?: return WeatherLocationInput.Invalid(
                setOf(
                    WeatherLocationInputError.LATITUDE_INVALID,
                    WeatherLocationInputError.LONGITUDE_INVALID,
                ),
            )
        return WeatherLocationInput.Valid(
            WeatherManualLocation(label = normalizedLabel!!, coordinates = coordinates),
        )
    }

    fun enable(
        previous: WeatherConsentState,
        location: WeatherManualLocation,
    ): WeatherConsentState = WeatherConsentState(
        enabled = true,
        location = location,
        generation = nextGeneration(previous.generation),
    )

    fun disable(previous: WeatherConsentState): WeatherConsentState = WeatherConsentState(
        enabled = false,
        location = null,
        generation = nextGeneration(previous.generation),
    )

    /**
     * Editing a location that is currently enabled revokes the previous
     * consent immediately. The user must explicitly enable the edited,
     * validated location again.
     */
    fun revokeForEdit(previous: WeatherConsentState): WeatherConsentState = disable(previous)

    private fun normalizeLabel(
        label: String,
        errors: MutableSet<WeatherLocationInputError>,
    ): String? {
        val collapsed = label.trim().replace(WHITESPACE, " ")
        if (collapsed.isEmpty()) {
            errors += WeatherLocationInputError.EMPTY_LABEL
            return null
        }
        if (collapsed.any { it.isISOControl() }) {
            errors += WeatherLocationInputError.LABEL_INVALID_CHARACTER
            return null
        }
        if (collapsed.length > MAX_LABEL_LENGTH) {
            errors += WeatherLocationInputError.LABEL_TOO_LONG
            return null
        }
        return collapsed
    }

    private fun parseCoordinate(text: String, minimum: Double, maximum: Double): Double? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        val value = trimmed.toDoubleOrNull() ?: return null
        if (!value.isFinite()) return null
        if (value !in minimum..maximum) return null
        return value
    }

    private fun nextGeneration(generation: Long): Long = when (generation) {
        Long.MAX_VALUE -> Long.MAX_VALUE
        else -> generation + 1L
    }

    private val WHITESPACE = Regex("\\s+")
}
