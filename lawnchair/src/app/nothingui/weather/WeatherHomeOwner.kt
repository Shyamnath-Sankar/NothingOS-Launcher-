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

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The launcher-owned lifecycle bridge around [WeatherSessionController].
 *
 * It is the single owner shared by the visible HOME lifecycle and the Weather
 * settings screen. It reads the persisted consent off the main thread every
 * time HOME becomes visible and starts no work until that read confirms an
 * enabled consent, the resumed HOME surface, the screen on and a user present.
 *
 * It creates no repository, transport, timer, alarm or worker. The injected
 * [WeatherLoadWork] is the only load seam; this phase supplies
 * [NoNetworkWeatherWork] in production.
 *
 * Every pause, screen-off, user-absent, settings edit/disable and shutdown
 * invalidates the pending read and lets the controller cancel the in-flight
 * job. A late read or a late result therefore cannot re-enable or reach the
 * result sink. A storage read failure fails closed: the session stays disabled
 * and no work starts.
 */
class WeatherHomeOwner(
    private val consentStore: WeatherConsentStore,
    work: WeatherLoadWork,
    private val scope: CoroutineScope,
    resultSink: WeatherResultSink = WeatherResultSink {},
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    onSessionChanged: (WeatherSession) -> Unit = {},
) {
    private val lock = Any()
    private val controller = WeatherSessionController(
        work = work,
        scope = scope,
        initialConsent = WeatherConsentState.DISABLED,
        initialVisibility = WeatherVisibilityState(),
        resultSink = resultSink,
        onSessionChanged = onSessionChanged,
    )

    private var homeVisible = false
    private var closed = false
    private var readEpoch = 0L
    private var readJob: Job? = null
    private var lastObservedConsent = WeatherConsentState.DISABLED

    fun current(): WeatherSession = controller.current()

    /**
     * Marks the resumed, visible HOME surface. Only a false -> true transition
     * reads the persisted consent; repeated NORMAL callbacks do not duplicate
     * the read or the load. Leaving HOME invalidates any pending read first.
     */
    fun setHomeVisible(visible: Boolean) {
        var shouldRead = false
        synchronized(lock) {
            if (closed || homeVisible == visible) return
            homeVisible = visible
            if (visible) {
                controller.setConsent(WeatherConsentState.DISABLED)
                controller.setHomeResumed(true)
                shouldRead = true
            } else {
                invalidateReadLocked()
                controller.setHomeResumed(false)
            }
        }
        if (shouldRead) startConsentRead()
    }

    fun setScreenInteractive(value: Boolean) {
        synchronized(lock) {
            if (closed) return
            controller.setScreenOn(value)
        }
    }

    fun setUserPresent(value: Boolean) {
        synchronized(lock) {
            if (closed) return
            controller.setUserPresent(value)
        }
    }

    /**
     * The settings screen's consent observer. It is synchronous so enable, edit
     * and disable revoke the visible session immediately, and it invalidates a
     * pending HOME read so an older persisted state cannot undo a newer local
     * decision.
     */
    fun onConsentChanged(state: WeatherConsentState) {
        synchronized(lock) {
            if (closed) return
            invalidateReadLocked()
            if (state.generation < lastObservedConsent.generation) return
            lastObservedConsent = state
            controller.setConsent(state)
        }
    }

    /** Permanent teardown. No later lifecycle event starts work. */
    fun shutdown() {
        synchronized(lock) {
            if (closed) return
            closed = true
            invalidateReadLocked()
        }
        controller.stop()
    }

    private fun startConsentRead() {
        val epoch = synchronized(lock) {
            if (closed || !homeVisible) return
            readEpoch += 1L
            readEpoch
        }
        val job = scope.launch {
            val loaded = try {
                withContext(ioDispatcher) { consentStore.read() }
            } catch (_: Exception) {
                null
            }
            synchronized(lock) {
                if (closed || epoch != readEpoch || !homeVisible) return@launch
                if (loaded == null) {
                    failClosedLocked()
                } else {
                    val chosen = chooseConsentLocked(loaded)
                    if (chosen.generation >= lastObservedConsent.generation) {
                        lastObservedConsent = chosen
                    }
                    controller.setConsent(chosen)
                }
            }
        }
        synchronized(lock) {
            if (!closed && epoch == readEpoch && homeVisible) {
                readJob = job
            }
        }
    }

    private fun invalidateReadLocked() {
        readEpoch += 1L
        readJob?.cancel()
        readJob = null
    }

    /**
     * A persisted enable older than the last in-process disable/edit must not
     * resurrect consent. The safe direction (a persisted disable) is always
     * trusted.
     */
    private fun chooseConsentLocked(loaded: WeatherConsentState): WeatherConsentState {
        val observed = lastObservedConsent
        return if (loaded.enabled && !observed.enabled && loaded.generation < observed.generation) {
            observed
        } else {
            loaded
        }
    }

    private fun failClosedLocked() {
        lastObservedConsent = WeatherConsentState(
            enabled = false,
            location = null,
            generation = lastObservedConsent.generation,
        )
        controller.setConsent(lastObservedConsent)
    }
}

/**
 * Pure guard for the launcher wiring. Weather may be shown only while the
 * launcher activity is resumed in its NORMAL (HOME) state and is not finishing
 * or destroyed. All Apps, Overview and a different activity therefore hide it.
 */
object WeatherHomeWiring {
    fun isHomeVisible(
        activityResumed: Boolean,
        homeState: Boolean,
        finishing: Boolean,
        destroyed: Boolean,
    ): Boolean = activityResumed && homeState && !finishing && !destroyed
}

/**
 * The explicit load seam for the phase that connects the HOME lifecycle before
 * any provider exists. It performs no network request and invents no forecast;
 * it reports that no forecast is available yet. The visible weather rendering
 * and the real provider replace this in a later phase.
 */
object NoNetworkWeatherWork : WeatherLoadWork {
    override suspend fun load(session: WeatherSession): WeatherLoadResult = WeatherLoadResult.Unavailable(reason = WeatherFailureReason.CACHE_MISS)
}
