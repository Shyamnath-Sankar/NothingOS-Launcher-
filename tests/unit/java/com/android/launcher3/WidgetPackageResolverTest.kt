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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WidgetPackageResolverTest {

    private val debugPackage = "com.launchernos.dotwellabs.debug"

    @Test
    fun compiledLauncherComponentResourceUsesTheRunningDebugPackage() {
        assertEquals(
            debugPackage,
            WidgetPackageResolver.resolve(
                "com.launchernos.dotwellabs/app.lawnchair.LawnchairLauncher",
                0x7f130001,
                0x7f130001,
                debugPackage,
                "com.launchernos.dotwellabs/app.lawnchair.LawnchairLauncher",
            ),
        )
    }

    @Test
    fun otherCompiledStringResourceResolvesItsPackagePart() {
        assertEquals(
            "com.example.app",
            WidgetPackageResolver.resolve(
                null,
                0x7f130002,
                0x7f130001,
                debugPackage,
                "com.example.app/.WidgetProvider",
            ),
        )
    }

    @Test
    fun compiledStringWithoutSlashIsThePackage() {
        assertEquals(
            "com.example.app",
            WidgetPackageResolver.resolve(
                null,
                0x7f130002,
                0x7f130001,
                debugPackage,
                "com.example.app",
            ),
        )
    }

    @Test
    fun literalPackageIsUnchanged() {
        assertEquals(
            "com.example.app",
            WidgetPackageResolver.resolve(
                "com.example.app",
                0,
                0x7f130001,
                debugPackage,
                null,
            ),
        )
    }

    @Test
    fun literalLauncherComponentFallsBackToTheRunningDebugPackage() {
        assertEquals(
            debugPackage,
            WidgetPackageResolver.resolve(
                "@string/launcher_component",
                0,
                0x7f130001,
                debugPackage,
                null,
            ),
        )
    }

    @Test
    fun literalOtherStringUsesTheResolvedValue() {
        assertEquals(
            "com.example.app",
            WidgetPackageResolver.resolve(
                "@string/other_component",
                0,
                0x7f130001,
                debugPackage,
                "com.example.app/.WidgetProvider",
            ),
        )
    }

    @Test
    fun missingPackageIsNull() {
        assertNull(WidgetPackageResolver.resolve(null, 0, 0x7f130001, debugPackage, null))
    }
}
