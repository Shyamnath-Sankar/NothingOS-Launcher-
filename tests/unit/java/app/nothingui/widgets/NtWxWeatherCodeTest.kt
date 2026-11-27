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

import app.nothingui.widgets.dotwel.NtWxWeatherCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure mapping tests for the ported NtWx weather widgets. The widgets must never
 * invent a reading, so every unknown symbol, missing value and missing AQI has a
 * deliberate neutral result.
 */
class NtWxWeatherCodeTest {

    @Test
    fun mapsMetSymbolsToTheNearestWmoIconCode() {
        assertEquals(0, NtWxWeatherCode.weatherCode("clearsky_day"))
        assertEquals(1, NtWxWeatherCode.weatherCode("fair_day"))
        assertEquals(2, NtWxWeatherCode.weatherCode("partlycloudy_day"))
        assertEquals(3, NtWxWeatherCode.weatherCode("cloudy"))
        assertEquals(45, NtWxWeatherCode.weatherCode("fog"))
        assertEquals(61, NtWxWeatherCode.weatherCode("lightrain"))
        assertEquals(61, NtWxWeatherCode.weatherCode("heavyrain"))
        assertEquals(80, NtWxWeatherCode.weatherCode("rainshowers"))
        assertEquals(71, NtWxWeatherCode.weatherCode("lightsnow"))
        assertEquals(66, NtWxWeatherCode.weatherCode("sleet"))
        assertEquals(95, NtWxWeatherCode.weatherCode("rainandthunder"))
    }

    @Test
    fun unknownOrMissingSymbolsFallBackToACloudInsteadOfInventingClearWeather() {
        assertEquals(3, NtWxWeatherCode.weatherCode(null))
        assertEquals(3, NtWxWeatherCode.weatherCode("madeupsymbol"))
        assertEquals(3, NtWxWeatherCode.weatherCode(""))
    }

    @Test
    fun nightSymbolsUseTheNightIconAndUnknownDaylightDefaultsToDay() {
        assertFalse(NtWxWeatherCode.isDay("clearsky_night"))
        assertFalse(NtWxWeatherCode.isDay("partlycloudy_night"))
        assertTrue(NtWxWeatherCode.isDay("clearsky_day"))
        assertTrue(NtWxWeatherCode.isDay(null))
    }

    @Test
    fun conditionLabelsMatchTheLauncherWeatherVocabulary() {
        assertEquals("Clear", NtWxWeatherCode.condition("clearsky_day"))
        assertEquals("Partly cloudy", NtWxWeatherCode.condition("partlycloudy_night"))
        assertEquals("Rain", NtWxWeatherCode.condition("rain"))
        assertEquals("Snow", NtWxWeatherCode.condition("lightsnow"))
        assertEquals("Thunder", NtWxWeatherCode.condition("rainandthunder"))
        assertEquals("Forecast", NtWxWeatherCode.condition("madeupsymbol"))
    }

    @Test
    fun temperatureNumbersRoundAndMissingValuesStayUnknown() {
        assertEquals("12", NtWxWeatherCode.number(11.6))
        assertEquals("-3", NtWxWeatherCode.number(-2.6))
        assertEquals("--", NtWxWeatherCode.number(null))
        assertEquals("--", NtWxWeatherCode.number(Double.NaN))
        assertEquals("--", NtWxWeatherCode.number(Double.POSITIVE_INFINITY))
    }

    @Test
    fun airQualityBandsUseTheUsAqiBoundaries() {
        assertEquals(0, NtWxWeatherCode.airBand(null))
        assertEquals(0, NtWxWeatherCode.airBand(-1))
        assertEquals(1, NtWxWeatherCode.airBand(0))
        assertEquals(1, NtWxWeatherCode.airBand(50))
        assertEquals(2, NtWxWeatherCode.airBand(51))
        assertEquals(2, NtWxWeatherCode.airBand(100))
        assertEquals(3, NtWxWeatherCode.airBand(101))
        assertEquals(3, NtWxWeatherCode.airBand(150))
        assertEquals(4, NtWxWeatherCode.airBand(151))
        assertEquals(4, NtWxWeatherCode.airBand(200))
        assertEquals(5, NtWxWeatherCode.airBand(201))
        assertEquals(5, NtWxWeatherCode.airBand(300))
        assertEquals(6, NtWxWeatherCode.airBand(301))
    }

    @Test
    fun pageWrappingIsSafeForSingleAndMultiPageWidgets() {
        assertEquals(0, NtWxWeatherCode.page(1, 5))
        assertEquals(1, NtWxWeatherCode.page(3, 4))
        assertEquals(2, NtWxWeatherCode.page(3, -1))
        assertEquals(0, NtWxWeatherCode.page(0, 7))
    }
}
