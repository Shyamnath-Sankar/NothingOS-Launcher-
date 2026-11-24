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

import java.time.Duration
import java.time.Instant
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * Bounded parser for the MET Norway `locationforecast/2.0/compact` payload.
 *
 * The payload can start with an already-passed period, so the parser never
 * blindly takes the first entry: it validates every timestamp, rejects entries
 * outside the relevant window and chooses the period nearest to [now].
 */
class MetLocationForecastParser(
    private val maxBodyChars: Int = DEFAULT_MAX_BODY_CHARS,
    private val maxPast: Duration = MAX_PAST,
    private val maxFuture: Duration = MAX_FUTURE,
) {
    fun parse(
        body: String,
        locationKey: String,
        retrievedAt: Instant,
        now: Instant,
    ): WeatherParseResult {
        if (body.isBlank()) return WeatherParseResult.Failure(WeatherParseFailure.EMPTY)
        if (body.length > maxBodyChars) return WeatherParseResult.Failure(WeatherParseFailure.TOO_LARGE)

        val root = runCatching { Json.parseToJsonElement(body) }.getOrNull() as? JsonObject
            ?: return WeatherParseResult.Failure(WeatherParseFailure.MALFORMED)
        val properties = root["properties"] as? JsonObject
            ?: return WeatherParseResult.Failure(WeatherParseFailure.MALFORMED)
        val timeseries = properties["timeseries"] as? JsonArray
            ?: return WeatherParseResult.Failure(WeatherParseFailure.NO_RELEVANT_PERIOD)

        val nearest = timeseries
            .mapNotNull { it.asCandidate(locationKey, retrievedAt, now) }
            .minByOrNull { it.distanceFromNowMs }
            ?: return WeatherParseResult.Failure(WeatherParseFailure.NO_RELEVANT_PERIOD)

        return WeatherParseResult.Success(nearest.forecast)
    }

    private fun JsonElement.asCandidate(
        locationKey: String,
        retrievedAt: Instant,
        now: Instant,
    ): Candidate? {
        val item = this as? JsonObject ?: return null
        val time = (item["time"] as? JsonPrimitive)?.contentOrNull ?: return null
        val validAt = runCatching { Instant.parse(time) }.getOrNull() ?: return null
        if (validAt.isBefore(now.minus(maxPast)) || validAt.isAfter(now.plus(maxFuture))) return null

        val data = item["data"] as? JsonObject ?: return null
        val details = ((data["instant"] as? JsonObject)?.get("details") as? JsonObject) ?: return null
        val temperature = (details["air_temperature"] as? JsonPrimitive)?.doubleOrNull ?: return null
        if (!temperature.isFinite() || temperature !in MIN_TEMPERATURE..MAX_TEMPERATURE) return null

        val forecast = WeatherForecast(
            provider = PROVIDER,
            locationKey = locationKey,
            temperatureCelsius = temperature,
            symbolCode = data.symbolCode(),
            validAt = validAt,
            retrievedAt = retrievedAt,
        )
        return Candidate(
            forecast = forecast,
            distanceFromNowMs = abs(Duration.between(now, validAt).toMillis()),
        )
    }

    private fun JsonObject.symbolCode(): String? {
        val next = this["next_1_hours"] as? JsonObject
            ?: this["next_6_hours"] as? JsonObject
            ?: return null
        val summary = next["summary"] as? JsonObject ?: return null
        return (summary["symbol_code"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
    }

    private data class Candidate(
        val forecast: WeatherForecast,
        val distanceFromNowMs: Long,
    )

    companion object {
        const val PROVIDER: String = "MET Norway"
        const val DEFAULT_MAX_BODY_CHARS: Int = 512 * 1024
        val MAX_PAST: Duration = Duration.ofHours(6)
        val MAX_FUTURE: Duration = Duration.ofHours(24)
        const val MIN_TEMPERATURE: Double = -100.0
        const val MAX_TEMPERATURE: Double = 100.0
    }
}
