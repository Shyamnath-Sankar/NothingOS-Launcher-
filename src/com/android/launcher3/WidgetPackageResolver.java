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
 * Resolves the package part of a default-layout widget's {@code packageName} attribute.
 *
 * <p>Compiled XML exposes resource references as numeric ids, not as the literal {@code @string/}
 * spelling. The {@code launcher_component} resource is generated from the flavor applicationId,
 * while the running context package includes the build-type suffix, so the context package is the
 * authoritative value for this app's own component. Other string resources resolve their package
 * part normally, and literal package names are returned unchanged.
 */
final class WidgetPackageResolver {

    private static final String STRING_PREFIX = "@string/";
    private static final String LAUNCHER_COMPONENT = "launcher_component";

    private WidgetPackageResolver() {}

    @Nullable
    static String resolve(
            @Nullable String attributeValue,
            int resourceId,
            int launcherComponentResourceId,
            String contextPackage,
            @Nullable String resourceValue) {
        if (resourceId != 0) {
            if (resourceId == launcherComponentResourceId) {
                return contextPackage;
            }
            if (resourceValue == null) {
                return attributeValue;
            }
            return packagePart(resourceValue);
        }
        if (attributeValue == null) {
            return null;
        }
        if (attributeValue.startsWith(STRING_PREFIX)) {
            if (LAUNCHER_COMPONENT.equals(attributeValue.substring(STRING_PREFIX.length()))) {
                return contextPackage;
            }
            if (resourceValue != null) {
                return packagePart(resourceValue);
            }
        }
        return attributeValue;
    }

    @Nullable
    static String packagePart(@Nullable String value) {
        if (value == null) {
            return null;
        }
        int separator = value.indexOf('/');
        return separator > 0 ? value.substring(0, separator) : value;
    }
}
