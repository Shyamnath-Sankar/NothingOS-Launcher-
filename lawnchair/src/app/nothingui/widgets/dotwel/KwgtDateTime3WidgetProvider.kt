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

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import app.lawnchair.ui.preferences.PreferenceActivity
import app.lawnchair.ui.preferences.navigation.WeatherSettings
import com.android.launcher3.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native provider for KWGT `Nothing_Date_Time3`.
 *
 * The layout uses a live `TextClock`, so no minute alarm or worker is needed.
 * The optional weather line reads only the launcher's shared cache state; it
 * never requests location or network from the widget.
 */
class KwgtDateTime3WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_date_time3

    override fun tapIntent(context: Context): Intent = PreferenceActivity.createIntent(context, WeatherSettings).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val palette = KwgtDateTime3Renderer.palette(style)
        val views = baseViews(context, appWidgetId)
        val manager = AppWidgetManager.getInstance(context)
        val options = manager.getAppWidgetOptions(appWidgetId)
        val target = WidgetSizing.targets(
            context,
            options,
            WidgetSizing.exactSizesFromOptions(options),
        ).firstOrNull()
        val layout = target?.let { KwgtDateTime3Renderer.layout(it.widthPx, it.heightPx) }
        val weather = NtWxWeather.from(context)
        val weatherText = if (weather.hasForecast) {
            KwgtDateTime3Renderer.weatherLine(weather)
        } else {
            weather.fallbackText(context)
        }
        val is24 = DateFormat.is24HourFormat(context)
        val ampm = SimpleDateFormat("a", Locale.getDefault())
            .format(Date())
            .uppercase(Locale.getDefault())

        views.setTextColor(R.id.kwgt_date_time3_time, palette.foreground)
        views.setTextColor(R.id.kwgt_date_time3_ampm, palette.accent)
        views.setTextColor(R.id.kwgt_date_time3_date, palette.foreground)
        views.setTextColor(R.id.kwgt_date_time3_weather, palette.accent)
        views.setTextViewText(R.id.kwgt_date_time3_ampm, ampm)
        views.setTextViewText(R.id.kwgt_date_time3_weather, weatherText)
        if (layout != null) {
            views.setTextViewTextSize(
                R.id.kwgt_date_time3_time,
                android.util.TypedValue.COMPLEX_UNIT_PX,
                layout.timeSize,
            )
            views.setTextViewTextSize(
                R.id.kwgt_date_time3_ampm,
                android.util.TypedValue.COMPLEX_UNIT_PX,
                layout.ampmSize,
            )
            views.setTextViewTextSize(
                R.id.kwgt_date_time3_date,
                android.util.TypedValue.COMPLEX_UNIT_PX,
                layout.dateSize,
            )
            views.setTextViewTextSize(
                R.id.kwgt_date_time3_weather,
                android.util.TypedValue.COMPLEX_UNIT_PX,
                layout.weatherSize,
            )
            views.setViewPadding(
                R.id.kwgt_date_time3_content,
                0,
                (layout.side * 0.02f).toInt(),
                layout.rightInset.toInt(),
                0,
            )
        }
        views.setViewVisibility(
            R.id.kwgt_date_time3_ampm,
            if (is24) View.GONE else View.VISIBLE,
        )
        views.setCharSequence(
            R.id.kwgt_date_time3_time,
            "setFormat12Hour",
            if (is24) "HH:mm" else "hh:mm",
        )
        views.setCharSequence(
            R.id.kwgt_date_time3_time,
            "setFormat24Hour",
            if (is24) "HH:mm" else "hh:mm",
        )
        views.setContentDescription(
            R.id.widget_root,
            weather.contentDescription(context),
        )
        return views
    }
}
