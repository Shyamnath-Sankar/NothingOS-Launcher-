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

package app.nothingui.widgets

import app.nothingui.weather.WeatherWidgetForecast
import app.nothingui.weather.WeatherWidgetRender
import app.nothingui.widgets.dotwel.NtWxWeather
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ported art must reflect the shared render state exactly, including the
 * honest placeholders for states that carry no reading.
 */
class NtWxWeatherTest {
    private val now = Instant.parse("2026-11-27T12:00:00Z")

    @Test
    fun offStateCarriesNoReading() {
        val weather = NtWxWeather.from(WeatherWidgetRender.Off, now)
        assertFalse(weather.enabled)
        assertFalse(weather.hasForecast)
        assertEquals("--", weather.temperatureText)
        assertEquals("Forecast", weather.conditionText)
        assertTrue(weather.statusText.contains("off"))
    }

    @Test
    fun notConnectedAndLoadingStatesDoNotInventAForecast() {
        val notConnected = NtWxWeather.from(WeatherWidgetRender.NotConnected, now)
        assertTrue(notConnected.enabled)
        assertFalse(notConnected.hasForecast)
        assertTrue(notConnected.statusText.contains("city"))

        val loading = NtWxWeather.from(WeatherWidgetRender.Loading, now)
        assertTrue(loading.loading)
        assertFalse(loading.hasForecast)
        assertTrue(loading.statusText.contains("Updating"))
    }

    @Test
    fun forecastStateUsesTheSharedReading() {
        val forecast = WeatherWidgetForecast(
            temperatureCelsius = 11.6,
            symbolCode = "clearsky_day",
            asOf = now.minusSeconds(120),
            stale = false,
        )
        val weather = NtWxWeather.from(WeatherWidgetRender.Forecast(forecast), now)
        assertTrue(weather.hasForecast)
        assertFalse(weather.stale)
        assertEquals("12", weather.temperatureText)
        assertEquals("Clear", weather.conditionText)
        assertEquals(0, weather.weatherCode)
        assertTrue(weather.isDay)
        assertTrue(weather.statusText.contains("Updated"))
        assertEquals("2m ago", weather.asOfText)
    }

    @Test
    fun unavailableStateKeepsOnlyTheLastForecastAndMarksItCached() {
        val last = WeatherWidgetForecast(
            temperatureCelsius = -2.6,
            symbolCode = "partlycloudy_night",
            asOf = now.minusSeconds(3_600),
            stale = true,
        )
        val weather = NtWxWeather.from(
            WeatherWidgetRender.Unavailable(lastForecast = last, retryAt = now.plusSeconds(60)),
            now,
        )
        assertTrue(weather.hasForecast)
        assertTrue(weather.stale)
        assertEquals("-3", weather.temperatureText)
        assertEquals("Partly cloudy", weather.conditionText)
        assertFalse(weather.isDay)
        assertTrue(weather.statusText.contains("Cached"))
        assertEquals("1h ago", weather.asOfText)
    }

    @Test
    fun unavailableWithoutACacheSaysSoInsteadOfShowingAFakeReading() {
        val weather = NtWxWeather.from(
            WeatherWidgetRender.Unavailable(lastForecast = null, retryAt = now.plusSeconds(60)),
            now,
        )
        assertFalse(weather.hasForecast)
        assertEquals("--", weather.temperatureText)
        assertTrue(weather.statusText.contains("Refresh failed"))
    }
}
