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

package app.nothingui.settings

/**
 * Pure decision for the user-initiated default-home consent flow.
 *
 * Kept free of Android framework types so the API-level and role-state rules can
 * be unit-tested on the JVM. Starting the system consent screen happens only in
 * [DefaultHomeRoleConsent].
 */
object DefaultHomeRolePolicy {

    const val MIN_SDK_FOR_ROLE_MANAGER = 29

    enum class Action {
        REQUEST_ROLE,
        OPEN_HOME_SETTINGS,
    }

    fun resolve(sdkInt: Int, roleAvailable: Boolean, roleHeld: Boolean): Action {
        return if (sdkInt >= MIN_SDK_FOR_ROLE_MANAGER && roleAvailable && !roleHeld) {
            Action.REQUEST_ROLE
        } else {
            Action.OPEN_HOME_SETTINGS
        }
    }
}
