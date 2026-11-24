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
import android.os.StatFs
import android.provider.Settings
import android.widget.RemoteViews
import app.nothingui.widgets.NothingUiDeviceStorage
import app.nothingui.widgets.NothingUiWidgetColors
import com.android.launcher3.R

/**
 * Original wide device card: real app data-volume storage plus Settings shortcuts.
 *
 * The storage reading comes from [StatFs] on the launcher's own data directory. A missing,
 * negative or inconsistent reading renders the neutral unknown label instead of a fabricated
 * value, and the percentage is clamped by [NothingUiDeviceStorage]. The three action pills are
 * clearly labelled Settings shortcuts, never on/off toggles or invented connection states; every
 * tap resolves a standard [Settings] action and falls back to the top-level Settings screen when
 * the specific one is unavailable. There is no new permission, alarm, wake lock, foreground
 * service or network access.
 */
class DotWelDeviceWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val storage = readStorage(context)
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId, storage)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId, readStorage(context))
    }

    companion object {

        private const val REQUEST_WIFI = 0x0D11
        private const val REQUEST_SOUND = 0x0D12
        private const val REQUEST_DISPLAY = 0x0D13

        fun refreshAll(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, DotWelDeviceWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            val storage = readStorage(context)
            ids.forEach { appWidgetId ->
                updateWidget(context, appWidgetManager, appWidgetId, storage)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            storage: StorageState,
        ) {
            val lightSurface = NothingUiWidgetColors.isLightSurface(context)
            val views = RemoteViews(context.packageName, R.layout.nothingui_widget_device)
            views.setInt(
                R.id.nothingui_device_surface,
                "setBackgroundResource",
                NothingUiWidgetColors.tileDrawable(lightSurface),
            )

            val content = NothingUiWidgetColors.contentColor(lightSurface)
            val muted = NothingUiWidgetColors.mutedContentColor(lightSurface)
            views.setTextColor(R.id.nothingui_device_storage_label, muted)
            views.setTextColor(R.id.nothingui_device_storage_value, content)
            views.setTextColor(R.id.nothingui_device_storage_detail, muted)
            views.setTextColor(R.id.nothingui_device_wifi, content)
            views.setTextColor(R.id.nothingui_device_sound, content)
            views.setTextColor(R.id.nothingui_device_display, content)

            val pill = NothingUiWidgetColors.pillDrawable(lightSurface)
            views.setInt(R.id.nothingui_device_wifi, "setBackgroundResource", pill)
            views.setInt(R.id.nothingui_device_sound, "setBackgroundResource", pill)
            views.setInt(R.id.nothingui_device_display, "setBackgroundResource", pill)

            val known = NothingUiDeviceStorage.isKnown(storage.total, storage.available)
            if (known) {
                views.setTextViewText(
                    R.id.nothingui_device_storage_value,
                    context.getString(
                        R.string.nothingui_device_storage_free,
                        NothingUiDeviceStorage.formatSize(storage.available),
                    ),
                )
                views.setTextViewText(
                    R.id.nothingui_device_storage_detail,
                    context.getString(
                        R.string.nothingui_device_storage_detail,
                        NothingUiDeviceStorage.usedPercent(storage.total, storage.available),
                        NothingUiDeviceStorage.formatSize(storage.total),
                    ),
                )
            } else {
                views.setTextViewText(
                    R.id.nothingui_device_storage_value,
                    context.getString(R.string.nothingui_device_storage_unknown_value),
                )
                views.setTextViewText(
                    R.id.nothingui_device_storage_detail,
                    context.getString(R.string.nothingui_device_storage_unknown),
                )
            }
            views.setProgressBar(
                R.id.nothingui_device_storage_progress,
                100,
                NothingUiDeviceStorage.progress(storage.total, storage.available),
                false,
            )

            settingsPendingIntent(context, Settings.ACTION_WIFI_SETTINGS, REQUEST_WIFI)?.let {
                views.setOnClickPendingIntent(R.id.nothingui_device_wifi, it)
            }
            settingsPendingIntent(context, Settings.ACTION_SOUND_SETTINGS, REQUEST_SOUND)?.let {
                views.setOnClickPendingIntent(R.id.nothingui_device_sound, it)
            }
            settingsPendingIntent(context, Settings.ACTION_DISPLAY_SETTINGS, REQUEST_DISPLAY)?.let {
                views.setOnClickPendingIntent(R.id.nothingui_device_display, it)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun readStorage(context: Context): StorageState {
            return runCatching {
                val stat = StatFs(context.dataDir.path)
                val total = stat.totalBytes
                val available = stat.availableBytes
                if (NothingUiDeviceStorage.isKnown(total, available)) {
                    StorageState(total, available)
                } else {
                    StorageState.UNKNOWN
                }
            }.getOrDefault(StorageState.UNKNOWN)
        }

        private fun settingsPendingIntent(
            context: Context,
            action: String,
            requestCode: Int,
        ): PendingIntent? {
            val candidates = listOf(Intent(action), Intent(Settings.ACTION_SETTINGS))
            for (intent in candidates) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                val resolved = context.packageManager.resolveActivity(
                    intent,
                    PackageManager.MATCH_DEFAULT_ONLY,
                )
                if (resolved != null) {
                    return PendingIntent.getActivity(
                        context,
                        requestCode,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }
            }
            return null
        }
    }

    private data class StorageState(val total: Long, val available: Long) {
        companion object {
            val UNKNOWN = StorageState(-1L, -1L)
        }
    }
}
