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
 * Resolves the repository's session check through the current process-wide
 * owner without capturing it during construction.
 *
 * The runtime assigns its owner only after the owner and its work graph are
 * fully built. Until that assignment, or after an explicit shutdown, [current]
 * fails closed with [WeatherSession.DISABLED]; a stale repository can therefore
 * never treat an uninitialized or closed owner as its own live session.
 */
class WeatherRuntimeSessionProvider(
    private val owner: () -> WeatherHomeOwner?,
) : WeatherSessionProvider {
    override fun current(): WeatherSession {
        val current = owner() ?: return WeatherSession.DISABLED
        if (current.isClosed) return WeatherSession.DISABLED
        return current.current()
    }
}
