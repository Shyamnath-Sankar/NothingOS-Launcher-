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
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Bundle
import android.provider.Settings
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Original circular battery widget.
 *
 * Values come from the real sticky [Intent.ACTION_BATTERY_CHANGED] broadcast, not a sample. Because
 * that broadcast cannot be received by a manifest-declared receiver, [NothingUiWidgetMonitor]
 * registers a lifecycle-bounded foreground receiver from the launcher activity and forwards it
 * here. Power connect/disconnect and widget resize events also refresh the art. A power event does
 * not carry the level/scale extras, so it re-reads the sticky battery broadcast instead of
 * rendering `--`. A missing or invalid level renders the neutral `--` fallback instead of a guessed
 * percentage.
 */
class NothingUiBatteryWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val sticky = readStickyBattery(context)
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId, sticky)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId, readStickyBattery(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BATTERY_CHANGED -> refreshAll(context, intent)

            Intent.ACTION_POWER_CONNECTED,
            Intent.ACTION_POWER_DISCONNECTED,
            -> refreshAll(context)

            else -> super.onReceive(context, intent)
        }
    }

    companion object {

        private const val DEFAULT_SIZE_DP = 110
        private const val REQUEST_BATTERY = 0x0BA7

        fun refreshAll(context: Context, batteryIntent: Intent? = null) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, NothingUiBatteryWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            val state = batteryIntent ?: readStickyBattery(context)
            ids.forEach { appWidgetId ->
                updateWidget(context, appWidgetManager, appWidgetId, state)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            batteryIntent: Intent?,
        ) {
            val battery = BatteryState.from(batteryIntent)
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                .takeIf { it > 0 } ?: DEFAULT_SIZE_DP
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
                .takeIf { it > 0 } ?: DEFAULT_SIZE_DP
            val size = NothingUiWidgetBudget.boundedSize(context, widthDp, heightDp)
            val bitmap = NothingUiBatteryArt.render(
                context = context,
                percent = battery.percent,
                charging = battery.charging,
                size = size,
                surfaceColor = NothingUiWidgetColors.surfaceColor(context),
                contentColor = NothingUiWidgetColors.contentColor(context),
            )
            val views = RemoteViews(context.packageName, R.layout.nothingui_widget_battery)
            views.setImageViewBitmap(R.id.nothingui_battery_art, bitmap)
            views.setContentDescription(
                R.id.nothingui_battery_art,
                NothingUiBatteryArt.contentDescription(battery.percent, battery.charging),
            )
            batteryPendingIntent(context)?.let { pendingIntent ->
                views.setOnClickPendingIntent(R.id.nothingui_battery_art, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun readStickyBattery(context: Context): Intent? {
            return context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            )
        }

        private fun batteryPendingIntent(context: Context): PendingIntent? {
            val candidates = listOf(
                Intent(Intent.ACTION_POWER_USAGE_SUMMARY),
                Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS),
            )
            for (intent in candidates) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                val resolved = context.packageManager.resolveActivity(
                    intent,
                    PackageManager.MATCH_DEFAULT_ONLY,
                )
                if (resolved != null) {
                    return PendingIntent.getActivity(
                        context,
                        REQUEST_BATTERY,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }
            }
            return null
        }
    }

    private data class BatteryState(val percent: Int, val charging: Boolean) {
        companion object {
            fun from(intent: Intent?): BatteryState {
                if (intent == null) return BatteryState(UNKNOWN_PERCENT, false)
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val percent = if (level in 0..scale && scale > 0) {
                    level * 100 / scale
                } else {
                    UNKNOWN_PERCENT
                }
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL ||
                    plugged != 0
                return BatteryState(percent, charging)
            }
        }
    }
}

private const val UNKNOWN_PERCENT = -1
