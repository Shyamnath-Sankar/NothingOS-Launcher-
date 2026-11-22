/*
 * Copyright (C) 2026 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.launcher3;

import androidx.annotation.Nullable;

/**
 * Identifies the launcher's own DotWel home-widget providers in the fresh-install default layout.
 *
 * <p>Only these two exact components may fall back to the pending-widget path when the platform
 * denies an automatic widget bind. The package must be the running variant's own package and the
 * class must be one of the two declared DotWel providers; a third-party package, a lookalike class
 * or a different class in our own package keeps the inherited delete-and-skip behavior.
 */
final class DotWelWidgetProviderPolicy {

    static final String CLOCK_PROVIDER_CLASS = "app.dotwel.widgets.DotWelClockWidgetProvider";
    static final String BATTERY_PROVIDER_CLASS = "app.dotwel.widgets.DotWelBatteryWidgetProvider";

    private DotWelWidgetProviderPolicy() {}

    static boolean isOwnDotWelProvider(
            @Nullable String ownPackage,
            @Nullable String componentPackage,
            @Nullable String componentClass) {
        if (ownPackage == null || componentPackage == null || componentClass == null) {
            return false;
        }
        if (!ownPackage.equals(componentPackage)) {
            return false;
        }
        return CLOCK_PROVIDER_CLASS.equals(componentClass)
                || BATTERY_PROVIDER_CLASS.equals(componentClass);
    }
}
