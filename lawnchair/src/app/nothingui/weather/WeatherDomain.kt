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

import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import kotlin.math.roundToInt

/**
 * A rounded, opt-in weather location. Coordinates are limited to four decimal
 * places before they become a network parameter or a cache key. Nothing in this
 * type reads the device location; a caller must supply the values explicitly.
 */
class WeatherCoordinates private constructor(
    val latitude: Double,
    val longitude: Double,
) {
    val latitudeText: String = latitude.coordinateText()
    val longitudeText: String = longitude.coordinateText()
    val cacheKey: String = "$latitudeText,$longitudeText"

    override fun equals(other: Any?): Boolean = this === other ||
        (other is WeatherCoordinates && latitude == other.latitude && longitude == other.longitude)

    override fun hashCode(): Int = 31 * latitude.hashCode() + longitude.hashCode()

    override fun toString(): String = cacheKey

    companion object {
        const val DECIMAL_PLACES: Int = 4

        fun from(latitude: Double, longitude: Double): WeatherCoordinates? {
            if (!latitude.isFinite() || !longitude.isFinite()) return null
            if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return null
            val roundedLatitude = latitude.roundCoordinate()
            val roundedLongitude = longitude.roundCoordinate()
            if (roundedLatitude !in -90.0..90.0 || roundedLongitude !in -180.0..180.0) return null
            return WeatherCoordinates(latitude = roundedLatitude, longitude = roundedLongitude)
        }

        private fun Double.roundCoordinate(): Double = BigDecimal.valueOf(this)
            .setScale(DECIMAL_PLACES, RoundingMode.HALF_UP)
            .toDouble()

        private fun Double.coordinateText(): String = BigDecimal.valueOf(this)
            .setScale(DECIMAL_PLACES, RoundingMode.HALF_UP)
            .toPlainString()
    }
}

enum class WeatherUnits(val symbol: String) {
    CELSIUS("°C"),
}

/**
 * A MET locationforecast entry. This is a forecast, not an observation. The
 * symbol is optional because a valid entry can omit the summary block.
 */
data class WeatherForecast(
    val provider: String,
    val locationKey: String,
    val temperatureCelsius: Double,
    val symbolCode: String?,
    val validAt: Instant,
    val retrievedAt: Instant,
    val units: WeatherUnits = WeatherUnits.CELSIUS,
) {
    val temperatureLabel: String
        get() = "${temperatureCelsius.roundToInt()}${units.symbol}"
}

/**
 * The caller-owned gate. A home widget may fetch only while weather is enabled,
 * the visible HOME surface is active and the opt-in location is still current.
 * [generation] changes whenever the user edits or revokes the opt-in.
 */
data class WeatherSession(
    val enabled: Boolean,
    val visible: Boolean,
    val generation: Long,
    val location: WeatherCoordinates?,
) {
    val isActive: Boolean
        get() = enabled && visible && location != null

    companion object {
        val DISABLED: WeatherSession = WeatherSession(
            enabled = false,
            visible = false,
            generation = 0,
            location = null,
        )
    }
}

fun interface WeatherSessionProvider {
    fun current(): WeatherSession
}

sealed interface WeatherLoadResult {
    data class Success(
        val forecast: WeatherForecast,
        val stale: Boolean,
    ) : WeatherLoadResult

    data class Unavailable(
        val reason: WeatherFailureReason,
        val lastSuccess: WeatherForecast? = null,
        val retryAt: Instant? = null,
    ) : WeatherLoadResult

    data object Disabled : WeatherLoadResult

    data object Cancelled : WeatherLoadResult
}

enum class WeatherFailureReason {
    NETWORK,
    HTTP_ERROR,
    FORBIDDEN,
    RATE_LIMITED,
    MALFORMED,
    NO_RELEVANT_PERIOD,
    CACHE_MISS,
}

sealed interface WeatherParseResult {
    data class Success(val forecast: WeatherForecast) : WeatherParseResult

    data class Failure(val reason: WeatherParseFailure) : WeatherParseResult
}

enum class WeatherParseFailure {
    EMPTY,
    TOO_LARGE,
    MALFORMED,
    NO_RELEVANT_PERIOD,
}
