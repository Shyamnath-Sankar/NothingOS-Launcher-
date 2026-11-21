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

import app.nothingui.settings.DefaultHomeRolePolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultHomeRolePolicyTest {

    @Test
    fun availableUnownedRoleOnApi29RequestsConsent() {
        assertEquals(
            Action.REQUEST_ROLE,
            DefaultHomeRolePolicy.resolve(sdkInt = 29, roleAvailable = true, roleHeld = false),
        )
    }

    @Test
    fun api26FallsBackToHomeSettings() {
        assertEquals(
            Action.OPEN_HOME_SETTINGS,
            DefaultHomeRolePolicy.resolve(sdkInt = 26, roleAvailable = true, roleHeld = false),
        )
    }

    @Test
    fun api28NeverRequestsEvenWhenRoleIsReportedAvailable() {
        assertEquals(
            Action.OPEN_HOME_SETTINGS,
            DefaultHomeRolePolicy.resolve(sdkInt = 28, roleAvailable = true, roleHeld = false),
        )
    }

    @Test
    fun unavailableRoleFallsBackToHomeSettings() {
        assertEquals(
            Action.OPEN_HOME_SETTINGS,
            DefaultHomeRolePolicy.resolve(sdkInt = 37, roleAvailable = false, roleHeld = false),
        )
    }

    @Test
    fun alreadyHeldRoleNeverReRequestsConsent() {
        assertEquals(
            Action.OPEN_HOME_SETTINGS,
            DefaultHomeRolePolicy.resolve(sdkInt = 37, roleAvailable = true, roleHeld = true),
        )
    }

    @Test
    fun roleManagerConsentStartsAtApi29() {
        assertEquals(29, DefaultHomeRolePolicy.MIN_SDK_FOR_ROLE_MANAGER)
    }
}
