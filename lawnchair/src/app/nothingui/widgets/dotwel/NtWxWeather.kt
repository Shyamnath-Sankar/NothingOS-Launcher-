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

import android.content.Context
import app.nothingui.weather.WeatherWidgetForecast
import app.nothingui.weather.WeatherWidgetRender
import app.nothingui.weather.WeatherWidgetStateStore
import app.nothingui.weather.WeatherWidgetText
import com.android.launcher3.R
import java.time.Instant

/**
 * Coordinate-free view of the launcher's shared weather render state.
 *
 * The ported Dotwel weather art predates this launcher and expects a richer
 * snapshot (high/low, solar events, AQI, a city label). The launcher pipeline
 * deliberately exposes only a temperature, a MET symbol, an evidence time and a
 * stale flag, so every field this adapter cannot fill is rendered as an honest
 * `--` or "Unavailable" instead of a fabricated reading.
 */
data class NtWxWeather(
    val render: WeatherWidgetRender,
    val now: Instant,
) {
    val forecast: WeatherWidgetForecast?
        get() = when (render) {
            is WeatherWidgetRender.Forecast -> render.forecast
            is WeatherWidgetRender.Unavailable -> render.lastForecast
            else -> null
        }

    val enabled: Boolean get() = render !is WeatherWidgetRender.Off

    val loading: Boolean get() = render is WeatherWidgetRender.Loading

    val hasForecast: Boolean get() = forecast != null

    val stale: Boolean get() = forecast?.stale == true

    val weatherCode: Int get() = NtWxWeatherCode.weatherCode(forecast?.symbolCode)

    val isDay: Boolean get() = NtWxWeatherCode.isDay(forecast?.symbolCode)

    val temperatureText: String get() = NtWxWeatherCode.number(forecast?.temperatureCelsius)

    val conditionText: String get() = NtWxWeatherCode.condition(forecast?.symbolCode)

    val asOfText: String
        get() = forecast?.let { WeatherWidgetText.asOf(now, it.asOf) }.orEmpty()

    val statusText: String
        get() = when (val current = render) {
            WeatherWidgetRender.Off -> "Weather is off \u00B7 Tap to configure"

            WeatherWidgetRender.NotConnected -> "Choose a city \u00B7 Tap to configure"

            WeatherWidgetRender.Loading -> "Updating weather"

            is WeatherWidgetRender.Forecast -> if (current.forecast.stale) {
                "Cached \u00B7 ${WeatherWidgetText.asOf(now, current.forecast.asOf)}"
            } else {
                "Updated \u00B7 ${WeatherWidgetText.asOf(now, current.forecast.asOf)}"
            }

            is WeatherWidgetRender.Unavailable -> when {
                current.lastForecast != null ->
                    "Cached \u00B7 ${WeatherWidgetText.asOf(now, current.lastForecast.asOf)}"

                current.retryAt != null -> "Refresh failed \u00B7 Tap to retry"

                else -> "No cached weather \u00B7 Tap to refresh"
            }
        }

    fun fallbackText(context: Context): String = when (render) {
        WeatherWidgetRender.Off -> context.getString(R.string.weather_widget_off)

        WeatherWidgetRender.NotConnected -> context.getString(R.string.weather_widget_setup)

        WeatherWidgetRender.Loading -> context.getString(R.string.weather_widget_loading)

        is WeatherWidgetRender.Forecast -> statusText

        is WeatherWidgetRender.Unavailable -> when {
            forecast != null -> context.getString(R.string.weather_widget_unavailable)
            render.retryAt != null -> context.getString(R.string.weather_widget_refresh_failed)
            else -> context.getString(R.string.weather_widget_no_cache)
        }
    }

    fun contentDescription(context: Context): String = if (forecast == null) {
        fallbackText(context)
    } else {
        "$conditionText, $temperatureText degrees. $statusText"
    }

    companion object {
        fun from(context: Context): NtWxWeather = from(WeatherWidgetStateStore.render(), Instant.now())

        fun from(render: WeatherWidgetRender, now: Instant = Instant.now()): NtWxWeather = NtWxWeather(render, now)
    }
}
