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

import java.time.Duration
import java.time.Instant

/**
 * The pure composition root for the visible-HOME weather load.
 *
 * It owns no lifecycle of its own: the caller supplies the already-gated
 * [sessionProvider], the no-backup cache store and the persisted throttle
 * store, so the returned work cannot run unless the owner's current session is
 * enabled and visible. Tests inject a fake transport and clock; the Android
 * runtime injects the real OkHttp transport and the app-private file stores.
 */
object WeatherWorkFactory {
    fun create(
        transport: WeatherHttpTransport,
        cacheStore: WeatherCacheStore,
        throttleStore: WeatherThrottleStore,
        sessionProvider: WeatherSessionProvider,
        clock: () -> Instant = { Instant.now() },
        minimumInterval: Duration = WeatherRefreshPolicy.MIN_REFRESH_INTERVAL,
    ): WeatherLoadWork {
        val repository = MetWeatherRepository(
            transport = transport,
            cacheStore = cacheStore,
            sessionProvider = sessionProvider,
            throttleStore = throttleStore,
            clock = clock,
            minimumInterval = minimumInterval,
        )
        return WeatherLoadWork { session -> repository.load(session) }
    }
}

/**
 * The explicit separation between the shipped network path and debug/test
 * installs. The emulator smoke gate enables a synthetic location and returns to
 * HOME; that debug build must never reach the live MET endpoint. Release builds
 * keep the wired network path. This is a build-type boundary, not an exported
 * test hook, and it adds no runtime switch that a caller could flip.
 */
object WeatherNetworkMode {
    fun isEnabled(debugBuild: Boolean): Boolean = !debugBuild
}
