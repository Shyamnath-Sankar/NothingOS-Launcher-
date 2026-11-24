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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetLocationForecastParserTest {

    private val parser = MetLocationForecastParser()
    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val locationKey = "51.5074,-0.1278"

    @Test
    fun itPicksTheNearestValidPeriodInsteadOfTheFirstOutdatedEntry() {
        val body = forecastBody(
            entry(time = "2026-11-23T02:00:00Z", temperature = 1.0, symbol = "rain"),
            entry(time = "2026-11-23T13:00:00Z", temperature = 5.5, symbol = "cloudy"),
            entry(time = "2026-11-23T20:00:00Z", temperature = 4.0, symbol = "clearsky"),
        )

        val result = parser.parse(body, locationKey, retrievedAt = now, now = now)

        assertTrue(result is WeatherParseResult.Success)
        val forecast = (result as WeatherParseResult.Success).forecast
        assertEquals(Instant.parse("2026-11-23T13:00:00Z"), forecast.validAt)
        assertEquals(5.5, forecast.temperatureCelsius, 0.0)
        assertEquals("cloudy", forecast.symbolCode)
        assertEquals(now, forecast.retrievedAt)
        assertEquals(locationKey, forecast.locationKey)
        assertEquals(MetLocationForecastParser.PROVIDER, forecast.provider)
        assertEquals(WeatherUnits.CELSIUS, forecast.units)
        assertEquals("6°C", forecast.temperatureLabel)
    }

    @Test
    fun entriesWithMissingOrInvalidTemperaturesAreSkipped() {
        val body = forecastBody(
            entry(time = "2026-11-23T12:00:00Z", temperature = null),
            entry(time = "not-a-time", temperature = 9.0),
            entry(time = "2026-11-23T12:30:00Z", temperature = 3.25, symbol = null),
        )

        val result = parser.parse(body, locationKey, retrievedAt = now, now = now)

        assertTrue(result is WeatherParseResult.Success)
        val forecast = (result as WeatherParseResult.Success).forecast
        assertEquals(3.25, forecast.temperatureCelsius, 0.0)
        assertNull("symbol is optional", forecast.symbolCode)
    }

    @Test
    fun everyEntryOutsideTheRelevantWindowIsRejected() {
        val staleBody = forecastBody(
            entry(time = "2026-11-23T01:00:00Z", temperature = 1.0),
            entry(time = "2026-11-22T20:00:00Z", temperature = 2.0),
        )
        val farFutureBody = forecastBody(
            entry(time = "2026-11-25T12:00:00Z", temperature = 3.0),
        )

        val stale = parser.parse(staleBody, locationKey, retrievedAt = now, now = now)
        val future = parser.parse(farFutureBody, locationKey, retrievedAt = now, now = now)

        assertEquals(
            WeatherParseResult.Failure(WeatherParseFailure.NO_RELEVANT_PERIOD),
            stale,
        )
        assertEquals(
            WeatherParseResult.Failure(WeatherParseFailure.NO_RELEVANT_PERIOD),
            future,
        )
    }

    @Test
    fun malformedAndOversizedPayloadsFailClosed() {
        val small = MetLocationForecastParser(maxBodyChars = 16)

        assertEquals(
            WeatherParseResult.Failure(WeatherParseFailure.MALFORMED),
            parser.parse("{not json", locationKey, retrievedAt = now, now = now),
        )
        assertEquals(
            WeatherParseResult.Failure(WeatherParseFailure.TOO_LARGE),
            small.parse(forecastBody(entry("2026-11-23T12:00:00Z", 1.0)), locationKey, now, now),
        )
        assertEquals(
            WeatherParseResult.Failure(WeatherParseFailure.EMPTY),
            parser.parse("   ", locationKey, retrievedAt = now, now = now),
        )
    }

    private fun forecastBody(vararg entries: String): String = """
        {
          "type": "Feature",
          "properties": {
            "meta": {"updated_at": "2026-11-23T11:00:00Z"},
            "timeseries": [${entries.joinToString(",")}]
          }
        }
    """.trimIndent()

    private fun entry(time: String, temperature: Double?, symbol: String? = "cloudy"): String {
        val details = temperature?.let { """{"air_temperature":$it}""" } ?: "{}"
        val symbolBlock = symbol?.let {
            ""","next_1_hours":{"summary":{"symbol_code":"$it"}}"""
        } ?: ""
        return """{"time":"$time","data":{"instant":{"details":$details}$symbolBlock}}"""
    }
}
