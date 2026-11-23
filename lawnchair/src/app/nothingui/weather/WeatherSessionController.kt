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

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * The caller-owned facts about the visible launcher surface. Weather may run
 * only while the user is on the resumed HOME screen, with the screen on and a
 * user present; the controller has no timers, alarms or background triggers.
 */
data class WeatherVisibilityState(
    val homeResumed: Boolean = false,
    val screenOn: Boolean = false,
    val userPresent: Boolean = false,
) {
    val canShowWeather: Boolean
        get() = homeResumed && screenOn && userPresent
}

object WeatherSessionPolicy {
    fun session(
        consent: WeatherConsentState,
        visibility: WeatherVisibilityState,
        generation: Long,
    ): WeatherSession = WeatherSession(
        enabled = consent.isActive,
        visible = visibility.canShowWeather,
        generation = generation,
        location = consent.location?.coordinates,
    )
}

/** The injected load seam; production supplies the MET repository next phase. */
fun interface WeatherLoadWork {
    suspend fun load(session: WeatherSession): WeatherLoadResult
}

fun interface WeatherResultSink {
    fun onResult(result: WeatherLoadResult)
}

/**
 * Pure lifecycle/session controller with an injected fake work seam. It does
 * not construct a repository, perform a network request or schedule a timer in
 * this phase; next phase wires the real visible HOME lifecycle and repository.
 *
 * Every consent, visibility or stop transition advances an in-memory
 * generation, immediately cancels the in-flight job and only delivers a result
 * whose session still equals the current one. A pause, screen-off, edit or
 * disable therefore cannot commit stale data, and no work runs off HOME.
 */
class WeatherSessionController(
    private val work: WeatherLoadWork,
    private val scope: CoroutineScope,
    initialConsent: WeatherConsentState = WeatherConsentState.DISABLED,
    initialVisibility: WeatherVisibilityState = WeatherVisibilityState(),
    private val resultSink: WeatherResultSink = WeatherResultSink {},
    private val onSessionChanged: (WeatherSession) -> Unit = {},
) : WeatherSessionProvider {
    private val lock = Any()
    private var consent: WeatherConsentState = initialConsent
    private var visibility: WeatherVisibilityState = initialVisibility
    private var revision: Long = 0L
    private var job: Job? = null

    @Volatile
    private var session: WeatherSession =
        WeatherSessionPolicy.session(initialConsent, initialVisibility, initialConsent.generation)

    override fun current(): WeatherSession = session

    fun setConsent(newConsent: WeatherConsentState) {
        synchronized(lock) {
            if (newConsent == consent) return
            consent = newConsent
            transitionLocked()
        }
    }

    fun setHomeResumed(value: Boolean) {
        synchronized(lock) {
            if (value == visibility.homeResumed) return
            visibility = visibility.copy(homeResumed = value)
            transitionLocked()
        }
    }

    fun setScreenOn(value: Boolean) {
        synchronized(lock) {
            if (value == visibility.screenOn) return
            visibility = visibility.copy(screenOn = value)
            transitionLocked()
        }
    }

    fun setUserPresent(value: Boolean) {
        synchronized(lock) {
            if (value == visibility.userPresent) return
            visibility = visibility.copy(userPresent = value)
            transitionLocked()
        }
    }

    /**
     * An explicit, user-initiated load. It is never called by a timer or a
     * background scheduler and does not duplicate an already running load.
     */
    fun requestLoad() {
        synchronized(lock) {
            if (!session.isActive) return
            if (job?.isActive == true) return
            startLocked(session)
        }
    }

    /** Cancels immediately and leaves the session disabled with a new generation. */
    fun stop() {
        synchronized(lock) {
            consent = WeatherConsentState.DISABLED
            visibility = WeatherVisibilityState()
            revision = nextRevision()
            session = WeatherSessionPolicy.session(consent, visibility, consent.generation + revision)
            job?.cancel()
            job = null
            onSessionChanged(session)
        }
    }

    private fun transitionLocked() {
        revision = nextRevision()
        val next = WeatherSessionPolicy.session(
            consent = consent,
            visibility = visibility,
            generation = consent.generation + revision,
        )
        session = next
        job?.cancel()
        job = null
        onSessionChanged(next)
        if (next.isActive) startLocked(next)
    }

    private fun startLocked(target: WeatherSession) {
        job = scope.launch {
            val result = try {
                work.load(target)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                WeatherLoadResult.Unavailable(reason = WeatherFailureReason.NETWORK)
            }
            if (isCurrent(target)) resultSink.onResult(result)
        }
    }

    private fun isCurrent(target: WeatherSession): Boolean = synchronized(lock) {
        session == target
    }

    private fun nextRevision(): Long = when (revision) {
        Long.MAX_VALUE -> Long.MAX_VALUE
        else -> revision + 1L
    }
}
