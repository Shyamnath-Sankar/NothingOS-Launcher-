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

import android.content.Context
import android.os.Handler
import android.os.Looper
import app.dotwel.widgets.DotWelWeatherWidgetProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * The single process-wide [WeatherHomeOwner] shared by the launcher HOME
 * lifecycle and the Weather settings screen.
 *
 * Pausing or destroying the launcher activity only hides its HOME surface; it
 * does not shut this owner down, so a recreated activity reuses the same
 * process state without retaining the old activity. The owner is replaced only
 * if it has been explicitly shut down, never by reusing a closed instance.
 *
 * The owner is created with the app-private no-backup consent store and the
 * explicit [NoNetworkWeatherWork] placeholder. This phase constructs no
 * repository, transport, worker, alarm or timer, and reads no device location.
 */
object WeatherHomeRuntime {
    private val lock = Any()
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }
    private var instance: WeatherHomeOwner? = null
    private var ownerScope: CoroutineScope? = null

    fun get(context: Context): WeatherHomeOwner = synchronized(lock) {
        val current = instance
        if (WeatherHomeRuntimePolicy.shouldReuseOwner(current)) return current!!
        ownerScope?.cancel()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val created = create(context.applicationContext, scope)
        ownerScope = scope
        instance = created
        WeatherWidgetStateStore.onSession(created.current())
        refreshWeatherWidgets(context.applicationContext)
        created
    }

    fun observeConsent(context: Context, state: WeatherConsentState) {
        get(context).onConsentChanged(state)
    }

    private fun create(context: Context, scope: CoroutineScope): WeatherHomeOwner = WeatherHomeOwner(
        consentStore = FileWeatherConsentStore(
            WeatherPrivateStorage.consentDirectory(context.noBackupFilesDir),
        ),
        work = NoNetworkWeatherWork,
        scope = scope,
        resultSink = WeatherResultSink { result ->
            WeatherWidgetStateStore.onResult(result)
            refreshWeatherWidgets(context)
        },
        onSessionChanged = { session ->
            WeatherWidgetStateStore.onSession(session)
            refreshWeatherWidgets(context)
        },
    )

    /**
     * Re-render the placed weather tiles after the shared state changes. This is
     * a main-thread `updateAppWidget`, not a new load, alarm, worker or receiver;
     * the provider itself stays render-only.
     */
    private fun refreshWeatherWidgets(context: Context) {
        val appContext = context.applicationContext
        mainHandler.post { DotWelWeatherWidgetProvider.refreshAll(appContext) }
    }
}
