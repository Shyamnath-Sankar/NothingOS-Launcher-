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
import kotlin.math.roundToInt

/**
 * The coordinate-free forecast the HOME weather widget may render.
 *
 * It deliberately carries only a temperature, an optional provider symbol,
 * the moment the value was known and a stale flag. Coordinates and the
 * user-supplied location label never enter this type, so nothing location
 * bearing can reach `RemoteViews`, ordinary preferences, logs or backups.
 */
data class WeatherWidgetForecast(
    val temperatureCelsius: Double,
    val symbolCode: String?,
    val asOf: Instant,
    val stale: Boolean,
) {
    val temperatureLabel: String
        get() = WeatherWidgetText.temperature(temperatureCelsius)

    val conditionLabel: String
        get() = WeatherWidgetText.condition(symbolCode)
}

/** What the widget should paint. None of these carry a location. */
sealed interface WeatherWidgetRender {
    data object Off : WeatherWidgetRender

    data object NotConnected : WeatherWidgetRender

    data object Loading : WeatherWidgetRender

    data class Forecast(val forecast: WeatherWidgetForecast) : WeatherWidgetRender

    data class Unavailable(
        val lastForecast: WeatherWidgetForecast?,
        val retryAt: Instant?,
    ) : WeatherWidgetRender
}

/** The last committed outcome. It is kept separate from the live session gate. */
sealed interface WeatherWidgetOutcome {
    data object NotConnected : WeatherWidgetOutcome

    data class Current(val forecast: WeatherWidgetForecast) : WeatherWidgetOutcome

    data class Unavailable(
        val lastForecast: WeatherWidgetForecast?,
        val retryAt: Instant?,
    ) : WeatherWidgetOutcome
}

/**
 * Pure render state for the HOME weather widget.
 *
 * The widget has no load path of its own. It only observes the shared owner's
 * session and result. A disabled or revoked session drops the committed result
 * immediately, so an edit or disable can never leave the previous location's
 * forecast on screen, and a new load shows [WeatherWidgetRender.Loading] until
 * a fresh result arrives.
 */
data class WeatherWidgetState(
    val initialized: Boolean = false,
    val enabled: Boolean = false,
    val loading: Boolean = false,
    val outcome: WeatherWidgetOutcome? = null,
) {
    fun withSession(session: WeatherSession): WeatherWidgetState {
        if (!session.enabled) {
            return WeatherWidgetState(initialized = true)
        }
        if (!session.isActive) {
            return copy(initialized = true, enabled = true, loading = false)
        }
        if (outcome == null) {
            return copy(initialized = true, enabled = true, loading = true)
        }
        return copy(initialized = true, enabled = true, loading = false)
    }

    fun withResult(result: WeatherLoadResult): WeatherWidgetState = when (result) {
        is WeatherLoadResult.Success -> copy(
            initialized = true,
            enabled = true,
            loading = false,
            outcome = WeatherWidgetOutcome.Current(result.toWidgetForecast()),
        )

        is WeatherLoadResult.Unavailable -> copy(
            initialized = true,
            enabled = true,
            loading = false,
            outcome = result.toWidgetOutcome(),
        )

        WeatherLoadResult.Disabled -> WeatherWidgetState(initialized = true)

        WeatherLoadResult.Cancelled -> this
    }

    fun render(): WeatherWidgetRender = when {
        !initialized -> WeatherWidgetRender.NotConnected

        !enabled -> WeatherWidgetRender.Off

        loading -> WeatherWidgetRender.Loading

        else -> when (val current = outcome) {
            null -> WeatherWidgetRender.NotConnected

            WeatherWidgetOutcome.NotConnected -> WeatherWidgetRender.NotConnected

            is WeatherWidgetOutcome.Current -> WeatherWidgetRender.Forecast(current.forecast)

            is WeatherWidgetOutcome.Unavailable -> WeatherWidgetRender.Unavailable(
                lastForecast = current.lastForecast,
                retryAt = current.retryAt,
            )
        }
    }

    private fun WeatherLoadResult.Success.toWidgetForecast(): WeatherWidgetForecast {
        return WeatherWidgetForecast(
            temperatureCelsius = forecast.temperatureCelsius,
            symbolCode = forecast.symbolCode,
            asOf = forecast.evidenceAt,
            stale = stale,
        )
    }

    private fun WeatherLoadResult.Unavailable.toWidgetOutcome(): WeatherWidgetOutcome {
        val lastForecast = lastSuccess?.let {
            WeatherWidgetForecast(
                temperatureCelsius = it.temperatureCelsius,
                symbolCode = it.symbolCode,
                asOf = it.evidenceAt,
                stale = true,
            )
        }
        if (lastForecast != null) {
            return WeatherWidgetOutcome.Unavailable(lastForecast, retryAt)
        }
        return when (reason) {
            WeatherFailureReason.CACHE_MISS -> WeatherWidgetOutcome.NotConnected
            else -> WeatherWidgetOutcome.Unavailable(lastForecast = null, retryAt = retryAt)
        }
    }
}

/**
 * Process-wide shared render state. The runtime owner publishes session and
 * result changes here; the widget provider only reads it. Keeping the state in
 * memory (rather than an ordinary preference or a backup-visible store) means
 * a location cannot leak through widget state, and a process restart starts
 * from the honest provider-not-connected placeholder.
 */
object WeatherWidgetStateStore {
    private val lock = Any()
    private var state = WeatherWidgetState()

    fun onSession(session: WeatherSession) {
        synchronized(lock) {
            state = state.withSession(session)
        }
    }

    fun onResult(result: WeatherLoadResult) {
        synchronized(lock) {
            state = state.withResult(result)
        }
    }

    fun render(): WeatherWidgetRender = synchronized(lock) { state.render() }

    fun renderState(): WeatherWidgetState = synchronized(lock) { state }
}

/** Bounded, locale-free presentation helpers shared by the widget and its tests. */
object WeatherWidgetText {
    const val FALLBACK_CONDITION: String = "Forecast"

    fun temperature(celsius: Double): String = "${celsius.roundToInt()}°C"

    fun condition(symbolCode: String?): String {
        val code = symbolCode?.lowercase() ?: return FALLBACK_CONDITION
        return when {
            code.contains("thunder") -> "Thunder"
            code.contains("sleet") -> "Sleet"
            code.contains("snow") -> "Snow"
            code.contains("rainshowers") -> "Showers"
            code.contains("rain") -> "Rain"
            code.contains("fog") -> "Fog"
            code.contains("partlycloudy") -> "Partly cloudy"
            code.contains("cloudy") -> "Cloudy"
            code.contains("clearsky") -> "Clear"
            code.contains("fair") -> "Fair"
            else -> FALLBACK_CONDITION
        }
    }

    fun asOf(now: Instant, at: Instant): String {
        val seconds = Duration.between(at, now).seconds
        return when {
            seconds < 60 -> "now"
            seconds < 3_600 -> "${seconds / 60}m ago"
            seconds < 86_400 -> "${seconds / 3_600}h ago"
            else -> "${seconds / 86_400}d ago"
        }
    }
}
