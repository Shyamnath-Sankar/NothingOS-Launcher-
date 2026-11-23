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

/**
 * The screen/keyguard facts the launcher queries immediately before it feeds
 * the owner. `userPresent` is never carried over from an earlier broadcast: it
 * is true only for an interactive, unlocked screen.
 */
data class WeatherScreenGate(
    val screenInteractive: Boolean,
    val userPresent: Boolean,
)

/**
 * Pure screen/keyguard policy used by the Android hookup. A powered-off screen
 * clears both gates, and a screen-on broadcast cannot claim an unlock by
 * itself; only a fresh `KeyguardManager` check may set `userPresent`.
 */
object WeatherScreenPolicy {
    fun evaluate(interactive: Boolean, keyguardLocked: Boolean): WeatherScreenGate = WeatherScreenGate(
        screenInteractive = interactive,
        userPresent = interactive && !keyguardLocked,
    )
}

/**
 * Pure HOME surface gate. A transition start always invalidates a previous
 * NORMAL confirmation, so weather hides immediately when the launcher starts
 * leaving HOME and stays hidden while a transition toward HOME is still in
 * progress. A canceled or reversed transition therefore fails closed until a
 * transition actually completes in NORMAL while the activity is resumed.
 */
class WeatherHomeSurfaceState {
    var isResumed: Boolean = false
        private set

    var isHomeConfirmed: Boolean = false
        private set

    var isTransitionInProgress: Boolean = false
        private set

    val isVisible: Boolean
        get() = isResumed && isHomeConfirmed && !isTransitionInProgress

    fun onResume(currentStateIsHome: Boolean, transitionInProgress: Boolean): Boolean {
        isResumed = true
        isTransitionInProgress = transitionInProgress
        isHomeConfirmed = currentStateIsHome && !transitionInProgress
        return isVisible
    }

    fun onPause(): Boolean {
        isResumed = false
        isHomeConfirmed = false
        isTransitionInProgress = false
        return isVisible
    }

    fun onDestroy(): Boolean = onPause()

    fun onTransitionStart(): Boolean {
        isTransitionInProgress = true
        isHomeConfirmed = false
        return isVisible
    }

    fun onTransitionComplete(finalStateIsHome: Boolean): Boolean {
        isTransitionInProgress = false
        isHomeConfirmed = finalStateIsHome
        return isVisible
    }
}

/**
 * Conservative resolution of a freshly read persisted consent against the last
 * state observed in this process.
 *
 * A persisted disable is always accepted because staying disabled cannot show
 * weather. A persisted enable may only win when it is strictly newer than the
 * in-process state. An older enable, or an enable that conflicts at the same
 * generation (for example an edit of the location), keeps the in-process
 * state so a stale read cannot overwrite a newer enable or edit.
 */
object WeatherHomeConsentPolicy {
    fun choose(
        loaded: WeatherConsentState,
        observed: WeatherConsentState,
    ): WeatherConsentState {
        if (!loaded.enabled) return loaded
        if (loaded.generation < observed.generation) return observed
        if (loaded.generation == observed.generation && loaded != observed) return observed
        return loaded
    }
}

/**
 * Pure singleton-reuse policy. A [WeatherHomeOwner] that was explicitly shut
 * down is never reused, so a runtime holding a stale closed instance creates a
 * new owner instead of returning a permanently disabled session.
 */
object WeatherHomeRuntimePolicy {
    fun shouldReuseOwner(existing: WeatherHomeOwner?): Boolean = existing != null && !existing.isClosed
}
