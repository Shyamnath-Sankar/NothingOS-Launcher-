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

package app.nothingui.icons

/**
 * Pure policy for the Play-only NothingUI icon treatment.
 *
 * The policy is intentionally independent of Android so it can be unit tested. The caller supplies
 * the already-resolved Play gate and preference values; this object only decides which inherited
 * icon engine mode to use and which cache key identifies the rendered result.
 */
data class NothingUiIconPolicy(
    val useThemedIcons: Boolean,
    val forceMonochromeFallback: Boolean,
    val cacheKey: String,
) {
    companion object {
        const val CACHE_KEY_OFF = "nothingui-icons-off"
        const val CACHE_KEY_NATIVE = "nothingui-icons-native"
        const val CACHE_KEY_FALLBACK = "nothingui-icons-fallback"

        /**
         * Resolves the effective icon policy.
         *
         * - [themedIconsEnabled] is false when the user explicitly turned themed icons off. On the
         *   Play channel the preference default is on, so a false value is an explicit opt-out.
         * - [forceFallbackEnabled] is the inherited "enforce themed icons" switch. It is only used
         *   when theming is on.
         * - [customIconSelected] is true when the user selected an icon pack or a per-app icon.
         *   Play must not replace that explicit choice with the generated fallback.
         * - Non-Play channels keep the inherited behaviour exactly: no new forced fallback is
         *   introduced, and an explicitly enabled force setting behaves as it did before.
         */
        fun resolve(
            playEnabled: Boolean,
            themedIconsEnabled: Boolean,
            forceFallbackEnabled: Boolean,
            customIconSelected: Boolean,
        ): NothingUiIconPolicy {
            if (!themedIconsEnabled) {
                return NothingUiIconPolicy(
                    useThemedIcons = false,
                    forceMonochromeFallback = false,
                    cacheKey = CACHE_KEY_OFF,
                )
            }

            if (!playEnabled) {
                return NothingUiIconPolicy(
                    useThemedIcons = true,
                    forceMonochromeFallback = forceFallbackEnabled,
                    cacheKey = if (forceFallbackEnabled) {
                        CACHE_KEY_FALLBACK
                    } else {
                        CACHE_KEY_NATIVE
                    },
                )
            }

            if (customIconSelected) {
                return NothingUiIconPolicy(
                    useThemedIcons = true,
                    forceMonochromeFallback = false,
                    cacheKey = CACHE_KEY_NATIVE,
                )
            }

            return if (forceFallbackEnabled) {
                NothingUiIconPolicy(
                    useThemedIcons = true,
                    forceMonochromeFallback = true,
                    cacheKey = CACHE_KEY_FALLBACK,
                )
            } else {
                NothingUiIconPolicy(
                    useThemedIcons = true,
                    forceMonochromeFallback = false,
                    cacheKey = CACHE_KEY_NATIVE,
                )
            }
        }
    }
}
