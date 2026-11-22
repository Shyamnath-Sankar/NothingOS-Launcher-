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

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Original square dot clock widget.
 *
 * The time itself is a native [android.widget.TextClock] inflated from
 * `nothingui_widget_clock.xml`. It follows the system 12/24-hour setting, the current timezone and
 * minute ticks without an alarm, wake lock or foreground service. This provider applies the
 * theme-resolved rounded tile and content colour, a safe clock tap and the actual widget size; it
 * never paints a static clock.
 */
class NothingUiClockWidgetProvider : AppWidgetProvider() {

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

        fun refreshAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, NothingUiClockWidgetProvider::class.java),
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
            val views = RemoteViews(context.packageName, R.layout.nothingui_widget_clock)
            views.setInt(
                R.id.nothingui_clock_surface,
                "setBackgroundResource",
                NothingUiWidgetColors.tileDrawable(lightSurface),
            )
            views.setTextColor(
                R.id.nothingui_clock_time,
                NothingUiWidgetColors.contentColor(lightSurface),
            )
            clockPendingIntent(context)?.let { pendingIntent ->
                views.setOnClickPendingIntent(R.id.nothingui_clock_time, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun clockPendingIntent(context: Context): PendingIntent? {
            val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val resolved = context.packageManager.resolveActivity(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            if (resolved == null) return null
            return PendingIntent.getActivity(
                context,
                REQUEST_CLOCK,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private const val REQUEST_CLOCK = 0x0C10
    }
}
