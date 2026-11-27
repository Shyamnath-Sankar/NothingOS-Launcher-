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
import android.content.ComponentName
import android.content.Context

/**
 * Re-renders the twelve ported weather providers from the shared render state.
 *
 * This is a main-thread `updateAppWidget` pass. It does not start a load,
 * schedule a job, register a receiver or touch the device location; the
 * launcher's weather owner remains the only loader.
 */
object WeatherWidgetUpdater {
    val providers: List<Class<out BaseWidgetProvider>> = listOf(
        NothingTempWidgetProvider::class.java,
        NothingSunInfoWidgetProvider::class.java,
        NtWxCircleProvider::class.java,
        NtWxSquareProvider::class.java,
        NtWxRectProvider::class.java,
        NtWxComboProvider::class.java,
        NtWxSunsetProvider::class.java,
        NtWxAirProvider::class.java,
        NtWxW1TempProvider::class.java,
        NtWxW1StatusProvider::class.java,
        NtWxW1RainProvider::class.java,
        KwgtDateTime3WidgetProvider::class.java,
    )

    fun refreshAll(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        providers.forEach { provider ->
            val ids = manager.getAppWidgetIds(ComponentName(appContext, provider))
            if (ids.isEmpty()) return@forEach
            provider.getDeclaredConstructor().newInstance().onUpdate(appContext, manager, ids)
        }
    }
}
