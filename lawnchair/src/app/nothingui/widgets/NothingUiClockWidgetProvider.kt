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

import android.app.AlarmClock
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.RemoteViews
import app.nothingui.home.NothingUiHomeChrome
import com.android.launcher3.R

/**
 * Original square dot clock widget.
 *
 * The time itself is a native [android.widget.TextClock] inflated from
 * `nothingui_widget_clock.xml`. It follows the system 12/24-hour setting, the current timezone and
 * minute ticks without an alarm, wake lock or foreground service. This provider only applies the
 * theme colour, a safe clock tap and the actual widget size; it never paints a static clock.
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

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.nothingui_widget_clock)
        views.setTextColor(R.id.nothingui_clock_time, textColor(context))
        clockPendingIntent(context)?.let { pendingIntent ->
            views.setOnClickPendingIntent(R.id.nothingui_clock_time, pendingIntent)
        }
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun textColor(context: Context): Int {
        return runCatching { NothingUiHomeChrome.textColor(context) }
            .getOrElse { DEFAULT_TEXT_COLOR }
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

    private companion object {
        const val REQUEST_CLOCK = 0x0C10
        const val DEFAULT_TEXT_COLOR = 0xFFF2F2F2.toInt()
    }
}
