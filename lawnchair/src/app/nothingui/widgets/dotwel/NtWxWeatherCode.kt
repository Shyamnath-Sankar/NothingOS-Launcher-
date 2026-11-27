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

package app.nothingui.widgets.dotwel

import app.nothingui.weather.WeatherWidgetText
import kotlin.math.roundToInt

/**
 * Pure mappings shared by the twelve ported Dotwel weather providers.
 *
 * The launcher's weather pipeline exposes only a MET symbol, a temperature and
 * an evidence timestamp. Every helper here therefore treats "not available" as
 * a deliberate neutral value instead of inventing a reading.
 */
object NtWxWeatherCode {
    const val UNKNOWN: String = "--"
    private const val UNKNOWN_ICON: Int = 3

    /** Maps a MET symbol to the nearest WMO icon code used by the NtWx art. */
    fun weatherCode(symbol: String?): Int {
        val code = symbol?.trim()?.lowercase()
        if (code.isNullOrEmpty()) return UNKNOWN_ICON
        return when {
            code.contains("thunder") -> 95
            code.contains("sleet") -> 66
            code.contains("snow") -> 71
            code.contains("rainshowers") -> 80
            code.contains("showers") -> 80
            code.contains("rain") -> 61
            code.contains("fog") -> 45
            code.contains("partlycloudy") -> 2
            code.contains("cloudy") -> 3
            code.contains("clearsky") -> 0
            code.contains("fair") -> 1
            else -> UNKNOWN_ICON
        }
    }

    /** Unknown symbols default to day so the icon is never falsely "night". */
    fun isDay(symbol: String?): Boolean = symbol?.trim()?.lowercase()?.contains("_night") != true

    /** Uses the launcher's bounded weather vocabulary, never a provider string. */
    fun condition(symbol: String?): String = WeatherWidgetText.condition(symbol)

    /** Rounds a reading for display; missing or non-finite values stay unknown. */
    fun number(value: Double?): String = value?.takeIf { it.isFinite() }?.roundToInt()?.toString() ?: UNKNOWN

    /** Maps a US AQI value to the six bands used by the air widget; 0 is unknown. */
    fun airBand(aqi: Int?): Int = when {
        aqi == null || aqi < 0 -> 0
        aqi <= 50 -> 1
        aqi <= 100 -> 2
        aqi <= 150 -> 3
        aqi <= 200 -> 4
        aqi <= 300 -> 5
        else -> 6
    }

    /**
     * Wraps [current] into a zero-based page for a widget with [pageCount] pages.
     * A non-positive count means the widget cannot page, so it stays on page 0.
     */
    fun page(pageCount: Int, current: Int): Int = if (pageCount <= 0) 0 else Math.floorMod(current, pageCount)
}
