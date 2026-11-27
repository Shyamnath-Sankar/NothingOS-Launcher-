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
import android.content.Intent
import android.graphics.Bitmap
import android.widget.RemoteViews
import app.lawnchair.ui.preferences.PreferenceActivity
import app.lawnchair.ui.preferences.navigation.WeatherSettings
import com.android.launcher3.R

/**
 * Shared contract for the ported Dotwel weather providers.
 *
 * Updates only read [NtWxWeather], which wraps the process-wide shared render
 * state. No receiver path performs network I/O, reads the device location or
 * schedules a background job; the launcher's weather owner remains the only
 * loader.
 */
abstract class BaseWeatherWidgetProvider : BaseWidgetProvider() {
    protected abstract val bitmapViewId: Int
    protected abstract val fallbackViewId: Int

    protected abstract fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
    ): Bitmap

    override fun tapIntent(context: Context): Intent = PreferenceActivity.createIntent(context, WeatherSettings).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val weather = NtWxWeather.from(context)
        return buildBitmapViews(
            context = context,
            appWidgetId = appWidgetId,
            bitmapViewId = bitmapViewId,
            fallbackViewId = fallbackViewId,
            render = { widthPx, heightPx ->
                render(context, widthPx, heightPx, style, weather)
            },
        ) { views, usedBitmap ->
            views.setTextColor(fallbackViewId, UpstreamNtDraw.ink(context, style))
            if (!usedBitmap) {
                views.setTextViewText(fallbackViewId, weather.fallbackText(context))
            }
            views.setContentDescription(
                if (usedBitmap) bitmapViewId else fallbackViewId,
                weather.contentDescription(context),
            )
            decorateWeatherViews(views, context, appWidgetId, usedBitmap)
        }
    }

    /**
     * Per-variant hook for extra RemoteViews calls.
     *
     * `buildBitmapViews` can return a combined `RemoteViews(Map<SizeF, RemoteViews>)`
     * on API 31+ when the host supplies exact sizes. That object cannot be
     * modified afterwards, so this hook runs for every per-size view before it
     * enters the size map.
     */
    protected open fun decorateWeatherViews(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        usedBitmap: Boolean,
    ) = Unit

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            -> {
                refreshWidgets(context)
                return
            }
        }
        super.onReceive(context, intent)
    }
}

class NothingTempWidgetProvider : BaseWeatherWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_weather_temp
    override val bitmapViewId: Int = R.id.weather_temp_bitmap
    override val fallbackViewId: Int = R.id.weather_temp_fallback

    override fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
    ): Bitmap = NothingTempRenderer.render(context, widthPx, heightPx, style, weather)
}

class NothingSunInfoWidgetProvider : BaseWeatherWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_weather_sun
    override val bitmapViewId: Int = R.id.weather_sun_bitmap
    override val fallbackViewId: Int = R.id.weather_sun_fallback

    override fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
    ): Bitmap = NothingSunInfoRenderer.render(context, widthPx, heightPx, style, weather)
}
