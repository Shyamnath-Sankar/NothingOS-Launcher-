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

package com.android.launcher3

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DotWelWidgetProviderPolicyTest {

    private val ownPackage = "com.launchernos.dotwellabs.debug"

    @Test
    fun ownClockProviderIsRecognised() {
        assertTrue(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun ownBatteryProviderIsRecognised() {
        assertTrue(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                DotWelWidgetProviderPolicy.BATTERY_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun ownDeviceProviderIsRecognised() {
        assertTrue(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                DotWelWidgetProviderPolicy.DEVICE_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun releasePackageIsRecognisedWhenItIsTheRunningPackage() {
        assertTrue(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                "com.launchernos.dotwellabs",
                "com.launchernos.dotwellabs",
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun clockClassInAnotherPackageIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                "com.example.app",
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun batteryClassInAnotherPackageIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                "com.example.app",
                DotWelWidgetProviderPolicy.BATTERY_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun deviceClassInAnotherPackageIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                "com.example.app",
                DotWelWidgetProviderPolicy.DEVICE_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun anotherClassInOurOwnPackageIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                "app.dotwel.widgets.OtherWidgetProvider",
            ),
        )
    }

    @Test
    fun lookalikeClockClassIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS + "X",
            ),
        )
    }

    @Test
    fun classFromTheDotWelPackageButAnotherPackageNameIsRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                "app.dotwel.widgets",
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
    }

    @Test
    fun missingValuesAreRejected() {
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                null,
                ownPackage,
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                null,
                DotWelWidgetProviderPolicy.CLOCK_PROVIDER_CLASS,
            ),
        )
        assertFalse(
            DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                ownPackage,
                ownPackage,
                null,
            ),
        )
    }
}
