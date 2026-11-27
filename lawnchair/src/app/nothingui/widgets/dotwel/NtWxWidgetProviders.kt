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

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Source NtWx page state and geometry, reading only the launcher's shared,
 * coordinate-free weather render state.
 *
 * Multi-page kinds (circle, square) cycle on tap; single-page kinds keep the
 * normal tap that opens Weather settings.
 */
abstract class BaseNtWxWidgetProvider : BaseWeatherWidgetProvider() {
    protected abstract val kind: NtWxRenderer.Kind
    override val layoutRes: Int = R.layout.widget_weather_temp
    override val bitmapViewId: Int = R.id.weather_temp_bitmap
    override val fallbackViewId: Int = R.id.weather_temp_fallback
    private var renderingPage: Int = 0

    override fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
    ): Bitmap = NtWxRenderer.render(
        context,
        kind,
        widthPx,
        heightPx,
        style,
        weather,
        renderingPage,
        DotwelWeatherIcons,
    )

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        renderingPage = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt("pg_$appWidgetId", 0)
        return super.buildViews(context, appWidgetId)
    }

    override fun decorateWeatherViews(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        usedBitmap: Boolean,
    ) {
        if (kind.pages > 1 && NtWxWeather.from(context).hasForecast) {
            val intent = Intent(context, this::class.java)
                .setAction(NEXT)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NEXT) {
            val appWidgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )
            val manager = AppWidgetManager.getInstance(context)
            if (manager.getAppWidgetInfo(appWidgetId)?.provider?.className == this::class.java.name) {
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val key = "pg_$appWidgetId"
                prefs.edit()
                    .putInt(key, NtWxRenderer.page(kind, prefs.getInt(key, 0) + 1))
                    .apply()
                manager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        appWidgetIds.forEach { edit.remove("pg_$it") }
        edit.apply()
        super.onDeleted(context, appWidgetIds)
    }

    companion object {
        private const val PREFS = "nt_weather_pages"
        private const val NEXT = "app.nothingui.widgets.dotwel.WX_NEXT"
    }
}

class NtWxCircleProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.CIRCLE
}

class NtWxSquareProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.SQUARE
}

class NtWxRectProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.RECT
}

class NtWxComboProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.COMBO
}

class NtWxSunsetProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.SUNSET
}

class NtWxAirProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.AIR
}

class NtWxW1TempProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.W1_TEMP
}

class NtWxW1StatusProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.W1_STATUS
}

class NtWxW1RainProvider : BaseNtWxWidgetProvider() {
    override val kind: NtWxRenderer.Kind = NtWxRenderer.Kind.W1_RAIN
}
