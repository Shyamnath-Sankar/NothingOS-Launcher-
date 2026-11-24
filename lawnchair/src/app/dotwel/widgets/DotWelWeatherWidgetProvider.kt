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

package app.dotwel.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.RemoteViews
import app.lawnchair.ui.preferences.PreferenceActivity
import app.lawnchair.ui.preferences.navigation.WeatherSettings
import app.lawnchair.ui.util.isPlayStoreFlavor
import app.nothingui.weather.WeatherWidgetForecast
import app.nothingui.weather.WeatherWidgetRender
import app.nothingui.weather.WeatherWidgetStateStore
import app.nothingui.weather.WeatherWidgetText
import app.nothingui.widgets.NothingUiWidgetColors
import com.android.launcher3.R
import java.time.Instant

/**
 * Original compact weather tile.
 *
 * This provider is render-only. `onUpdate`, resize callbacks and any broadcast
 * it receives read the process-wide shared render state published by the
 * launcher's weather owner; they never construct a repository or transport,
 * start a load, schedule an alarm/worker, register a receiver or read the
 * device location. Before the owner has published anything the tile truthfully
 * says the provider is not connected, never a fabricated current temperature.
 *
 * Tapping the tile opens the existing Weather settings destination through an
 * explicit, immutable [PendingIntent]. The tile carries only a coordinate-free
 * temperature/condition/as-of pair, so no location can reach `RemoteViews`,
 * ordinary preferences, logs or backups.
 */
class DotWelWeatherWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {

        private const val REQUEST_WEATHER = 0x0E10

        fun refreshAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, DotWelWeatherWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            ids.forEach { appWidgetId ->
                updateWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val lightSurface = NothingUiWidgetColors.isLightSurface(context)
            val views = RemoteViews(context.packageName, R.layout.nothingui_widget_weather)
            views.setInt(
                R.id.nothingui_weather_surface,
                "setBackgroundResource",
                NothingUiWidgetColors.tileDrawable(lightSurface),
            )
            views.setTextColor(
                R.id.nothingui_weather_label,
                NothingUiWidgetColors.mutedContentColor(lightSurface),
            )
            views.setTextColor(
                R.id.nothingui_weather_value,
                NothingUiWidgetColors.contentColor(lightSurface),
            )
            views.setTextColor(
                R.id.nothingui_weather_detail,
                NothingUiWidgetColors.contentColor(lightSurface),
            )
            views.setTextColor(
                R.id.nothingui_weather_asof,
                NothingUiWidgetColors.mutedContentColor(lightSurface),
            )

            applyRender(
                context = context,
                views = views,
                render = WeatherWidgetStateStore.render(),
                now = Instant.now(),
            )

            weatherPendingIntent(context)?.let { pendingIntent ->
                views.setOnClickPendingIntent(R.id.nothingui_weather_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun applyRender(
            context: Context,
            views: RemoteViews,
            render: WeatherWidgetRender,
            now: Instant,
        ) {
            val text = when (render) {
                WeatherWidgetRender.Off -> RenderText(
                    value = context.getString(R.string.nothingui_weather_value_unknown),
                    detail = context.getString(R.string.nothingui_weather_state_off_short),
                    asOf = "",
                    contentDescription = context.getString(R.string.nothingui_weather_state_off),
                )

                WeatherWidgetRender.NotConnected -> RenderText(
                    value = context.getString(R.string.nothingui_weather_value_unknown),
                    detail = context.getString(R.string.nothingui_weather_state_not_connected_short),
                    asOf = context.getString(R.string.nothingui_weather_state_not_connected),
                    contentDescription = context.getString(
                        R.string.nothingui_weather_state_not_connected_content_description,
                    ),
                )

                WeatherWidgetRender.Loading -> RenderText(
                    value = context.getString(R.string.nothingui_weather_value_loading),
                    detail = context.getString(R.string.nothingui_weather_state_loading),
                    asOf = "",
                    contentDescription = context.getString(R.string.nothingui_weather_state_loading),
                )

                is WeatherWidgetRender.Forecast -> forecastText(
                    context = context,
                    forecast = render.forecast,
                    now = now,
                )

                is WeatherWidgetRender.Unavailable -> unavailableText(
                    context = context,
                    render = render,
                    now = now,
                )
            }
            views.setTextViewText(R.id.nothingui_weather_value, text.value)
            views.setTextViewText(R.id.nothingui_weather_detail, text.detail)
            views.setTextViewText(R.id.nothingui_weather_asof, text.asOf)
            views.setContentDescription(R.id.nothingui_weather_root, text.contentDescription)
        }

        private fun forecastText(
            context: Context,
            forecast: WeatherWidgetForecast,
            now: Instant,
        ): RenderText {
            val age = WeatherWidgetText.asOf(now, forecast.asOf)
            val asOf = if (forecast.stale) {
                context.getString(R.string.nothingui_weather_stale_as_of, age)
            } else {
                context.getString(R.string.nothingui_weather_updated, age)
            }
            return RenderText(
                value = forecast.temperatureLabel,
                detail = forecast.conditionLabel,
                asOf = asOf,
                contentDescription = context.getString(
                    R.string.nothingui_weather_forecast_content_description,
                    forecast.temperatureLabel,
                    forecast.conditionLabel,
                    age,
                ),
            )
        }

        private fun unavailableText(
            context: Context,
            render: WeatherWidgetRender.Unavailable,
            now: Instant,
        ): RenderText {
            val last = render.lastForecast
            if (last == null) {
                return RenderText(
                    value = context.getString(R.string.nothingui_weather_value_unknown),
                    detail = context.getString(R.string.nothingui_weather_state_unavailable),
                    asOf = context.getString(R.string.nothingui_weather_state_retry),
                    contentDescription = context.getString(R.string.nothingui_weather_state_unavailable),
                )
            }
            val age = WeatherWidgetText.asOf(now, last.asOf)
            val asOf = if (render.retryAt != null) {
                context.getString(R.string.nothingui_weather_last_updated_retry, age)
            } else {
                context.getString(R.string.nothingui_weather_last_updated, age)
            }
            return RenderText(
                value = last.temperatureLabel,
                detail = last.conditionLabel,
                asOf = asOf,
                contentDescription = context.getString(
                    R.string.nothingui_weather_last_forecast_content_description,
                    last.temperatureLabel,
                    last.conditionLabel,
                    age,
                ),
            )
        }

        private fun weatherPendingIntent(context: Context): PendingIntent? {
            if (!isPlayStoreFlavor()) return null
            val intent = PreferenceActivity.createIntent(context, WeatherSettings).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val resolved = context.packageManager.resolveActivity(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            if (resolved == null) return null
            return PendingIntent.getActivity(
                context,
                REQUEST_WEATHER,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    private data class RenderText(
        val value: String,
        val detail: String,
        val asOf: String,
        val contentDescription: String,
    )
}
