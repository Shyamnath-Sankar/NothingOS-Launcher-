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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherWidgetRenderTest {

    private val retrievedAt = Instant.parse("2026-11-21T09:00:00Z")
    private val validAt = Instant.parse("2026-11-21T09:00:00Z")
    private val retryAt = Instant.parse("2026-11-21T12:00:00Z")

    private val coordinates = WeatherCoordinates.from(51.5074, -0.1278)!!
    private val otherCoordinates = WeatherCoordinates.from(48.8566, 2.3522)!!

    private fun session(
        enabled: Boolean = true,
        visible: Boolean = true,
        generation: Long = 5L,
        location: WeatherCoordinates? = coordinates,
    ): WeatherSession = WeatherSession(
        enabled = enabled,
        visible = visible,
        generation = generation,
        location = location,
    )

    private fun forecast(
        temperatureCelsius: Double = 11.6,
        symbolCode: String? = "cloudy",
    ): WeatherForecast = WeatherForecast(
        provider = "met.no",
        locationKey = "51.5074,-0.1278",
        temperatureCelsius = temperatureCelsius,
        symbolCode = symbolCode,
        validAt = validAt,
        retrievedAt = retrievedAt,
    )

    private fun success(stale: Boolean = false): WeatherLoadResult.Success = WeatherLoadResult.Success(
        forecast = forecast(),
        stale = stale,
    )

    @Test
    fun anUnpublishedWidgetRendersProviderNotConnectedNeverAForecast() {
        assertEquals(WeatherWidgetRender.NotConnected, WeatherWidgetState().render())
    }

    @Test
    fun aDisabledSessionRendersOff() {
        val state = WeatherWidgetState().withSession(session(enabled = false, location = null))

        assertEquals(WeatherWidgetRender.Off, state.render())
    }

    @Test
    fun anEnabledSetupWithoutAProviderResultIsLoadingAndThenTruthfullyNotConnected() {
        val active = WeatherWidgetState().withSession(session())
        assertEquals(WeatherWidgetRender.Loading, active.render())

        val noNetwork = active.withResult(
            WeatherLoadResult.Unavailable(reason = WeatherFailureReason.CACHE_MISS),
        )

        assertEquals(WeatherWidgetRender.NotConnected, noNetwork.render())
        assertNull((noNetwork.render() as? WeatherWidgetRender.Forecast))
    }

    @Test
    fun aRealSuccessRendersTheCelsiusTemperatureAndCondition() {
        val state = WeatherWidgetState()
            .withSession(session())
            .withResult(success())

        val render = state.render() as WeatherWidgetRender.Forecast

        assertEquals(11.6, render.forecast.temperatureCelsius, 0.0)
        assertEquals("12°C", render.forecast.temperatureLabel)
        assertEquals("Cloudy", render.forecast.conditionLabel)
        assertEquals(retrievedAt, render.forecast.asOf)
        assertFalse(render.forecast.stale)
    }

    @Test
    fun aMissingOrUnknownSymbolFallsBackToAForecastLabelInsteadOfInventingWeather() {
        assertEquals("Forecast", WeatherWidgetForecast(18.0, null, retrievedAt, false).conditionLabel)
        assertEquals("Forecast", WeatherWidgetForecast(18.0, "madeupsymbol", retrievedAt, false).conditionLabel)
        assertEquals("Clear", WeatherWidgetForecast(18.0, "clearsky_day", retrievedAt, false).conditionLabel)
        assertEquals("Partly cloudy", WeatherWidgetForecast(18.0, "partlycloudy_night", retrievedAt, false).conditionLabel)
        assertEquals("Rain", WeatherWidgetForecast(18.0, "rain", retrievedAt, false).conditionLabel)
        assertEquals("Snow", WeatherWidgetForecast(18.0, "lightsnow", retrievedAt, false).conditionLabel)
        assertEquals("Thunder", WeatherWidgetForecast(18.0, "rainandthunder", retrievedAt, false).conditionLabel)
    }

    @Test
    fun aStaleSuccessCarriesItsAsOfAndStaleFlag() {
        val state = WeatherWidgetState()
            .withSession(session())
            .withResult(success(stale = true))

        val render = state.render() as WeatherWidgetRender.Forecast

        assertTrue(render.forecast.stale)
        assertEquals(retrievedAt, render.forecast.asOf)
    }

    @Test
    fun anUnavailableResultKeepsTheLastSuccessWithItsAsOfAndBackoff() {
        val lastSuccess = forecast(temperatureCelsius = 7.4, symbolCode = "rain")
        val state = WeatherWidgetState()
            .withSession(session())
            .withResult(
                WeatherLoadResult.Unavailable(
                    reason = WeatherFailureReason.THROTTLED,
                    lastSuccess = lastSuccess,
                    retryAt = retryAt,
                ),
            )

        val render = state.render() as WeatherWidgetRender.Unavailable
        val last = render.lastForecast!!

        assertEquals(7.4, last.temperatureCelsius, 0.0)
        assertEquals("Rain", last.conditionLabel)
        assertEquals(retrievedAt, last.asOf)
        assertTrue(last.stale)
        assertEquals(retryAt, render.retryAt)
    }

    @Test
    fun anUnavailableResultWithoutLastSuccessRendersUnavailableNotAFabricatedForecast() {
        val state = WeatherWidgetState()
            .withSession(session())
            .withResult(
                WeatherLoadResult.Unavailable(
                    reason = WeatherFailureReason.NETWORK,
                    retryAt = retryAt,
                ),
            )

        val render = state.render() as WeatherWidgetRender.Unavailable
        assertNull(render.lastForecast)
        assertEquals(retryAt, render.retryAt)
    }

    @Test
    fun aCacheMissWithoutLastSuccessRendersProviderNotConnected() {
        val state = WeatherWidgetState()
            .withSession(session())
            .withResult(WeatherLoadResult.Unavailable(reason = WeatherFailureReason.CACHE_MISS))

        assertEquals(WeatherWidgetRender.NotConnected, state.render())
    }

    @Test
    fun disablingClearsThePreviousForecastImmediately() {
        val withForecast = WeatherWidgetState()
            .withSession(session())
            .withResult(success())
        assertTrue(withForecast.render() is WeatherWidgetRender.Forecast)

        val disabled = withForecast.withSession(session(enabled = false, location = null))

        assertEquals(WeatherWidgetRender.Off, disabled.render())
        assertNull(disabled.outcome)
    }

    @Test
    fun editingTheLocationClearsTheForecastBeforeTheNewResultAndShowsLoading() {
        val withForecast = WeatherWidgetState()
            .withSession(session(generation = 4L))
            .withResult(success())
        assertTrue(withForecast.render() is WeatherWidgetRender.Forecast)

        // The settings edit revokes consent first, then a later enable starts a new load.
        val revoked = withForecast.withSession(session(enabled = false, generation = 5L, location = null))
        val reenabled = revoked.withSession(session(generation = 6L))

        assertEquals(WeatherWidgetRender.Loading, reenabled.render())
        assertNull(reenabled.outcome)
    }

    @Test
    fun aCancelledResultDoesNotOverwriteTheCurrentRender() {
        val withForecast = WeatherWidgetState()
            .withSession(session())
            .withResult(success())

        val cancelled = withForecast.withResult(WeatherLoadResult.Cancelled)

        assertTrue(cancelled.render() is WeatherWidgetRender.Forecast)
    }

    @Test
    fun theRenderStateNeverCarriesTheLocation() {
        val first = WeatherWidgetState()
            .withSession(session(location = coordinates))
            .withResult(success())
        val second = WeatherWidgetState()
            .withSession(session(location = otherCoordinates))
            .withResult(success())

        assertEquals(first.render(), second.render())
        assertFalse(first.toString().contains("51.5074"))
        assertFalse(first.toString().contains("-0.1278"))
        assertFalse(first.render().toString().contains("51.5074"))
        assertFalse(first.render().toString().contains("-0.1278"))
    }

    @Test
    fun asOfLabelsAreBoundedRelativeLabels() {
        val now = Instant.parse("2026-11-21T12:00:00Z")

        assertEquals("now", WeatherWidgetText.asOf(now, now.minusSeconds(30)))
        assertEquals("5m ago", WeatherWidgetText.asOf(now, now.minusSeconds(5 * 60)))
        assertEquals("3h ago", WeatherWidgetText.asOf(now, now.minusSeconds(3 * 3600)))
        assertEquals("2d ago", WeatherWidgetText.asOf(now, now.minusSeconds(2 * 86_400)))
        assertEquals("now", WeatherWidgetText.asOf(now, now.plusSeconds(60)))
    }
}
