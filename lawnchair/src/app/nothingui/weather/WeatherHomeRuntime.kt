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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The single process-wide [WeatherHomeOwner] shared by the launcher HOME
 * lifecycle and the Weather settings screen.
 *
 * The owner is created with the app-private no-backup consent store and the
 * explicit [NoNetworkWeatherWork] placeholder. This phase constructs no
 * repository, transport, worker, alarm or timer, and reads no device location.
 */
object WeatherHomeRuntime {
    private val lock = Any()
    private var instance: WeatherHomeOwner? = null

    fun get(context: Context): WeatherHomeOwner = synchronized(lock) {
        instance ?: create(context.applicationContext).also { instance = it }
    }

    fun observeConsent(context: Context, state: WeatherConsentState) {
        get(context).onConsentChanged(state)
    }

    private fun create(context: Context): WeatherHomeOwner = WeatherHomeOwner(
        consentStore = FileWeatherConsentStore(
            WeatherPrivateStorage.consentDirectory(context.noBackupFilesDir),
        ),
        work = NoNetworkWeatherWork,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        resultSink = WeatherResultSink {},
    )
}
