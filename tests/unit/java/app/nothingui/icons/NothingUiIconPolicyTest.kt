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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NothingUiIconPolicyTest {

    @Test
    fun playDefaultsUseNativeThemedIconsWithGeneratedFallback() {
        val policy = resolve(play = true, themed = true, forceFallback = true, custom = false)

        assertTrue(policy.useThemedIcons)
        assertTrue(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_FALLBACK, policy.cacheKey)
    }

    @Test
    fun playExplicitOptOutLeavesIconsUnthemed() {
        val policy = resolve(play = true, themed = false, forceFallback = true, custom = false)

        assertFalse(policy.useThemedIcons)
        assertFalse(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_OFF, policy.cacheKey)
    }

    @Test
    fun playExplicitFallbackOffUsesOnlyNativeThemedIcons() {
        val policy = resolve(play = true, themed = true, forceFallback = false, custom = false)

        assertTrue(policy.useThemedIcons)
        assertFalse(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_NATIVE, policy.cacheKey)
    }

    @Test
    fun playCustomIconChoiceIsNotReplacedByTheGeneratedFallback() {
        val policy = resolve(play = true, themed = true, forceFallback = true, custom = true)

        assertTrue(policy.useThemedIcons)
        assertFalse(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_NATIVE, policy.cacheKey)
    }

    @Test
    fun nonPlayDefaultStaysUnthemed() {
        val policy = resolve(play = false, themed = false, forceFallback = false, custom = false)

        assertFalse(policy.useThemedIcons)
        assertFalse(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_OFF, policy.cacheKey)
    }

    @Test
    fun nonPlayExplicitForceKeepsInheritedBehaviour() {
        val policy = resolve(play = false, themed = true, forceFallback = true, custom = true)

        assertTrue(policy.useThemedIcons)
        assertTrue(policy.forceMonochromeFallback)
        assertEquals(NothingUiIconPolicy.CACHE_KEY_FALLBACK, policy.cacheKey)
    }

    @Test
    fun fallbackAndNativeRendersUseDifferentCacheKeys() {
        val native = resolve(play = true, themed = true, forceFallback = false, custom = false)
        val fallback = resolve(play = true, themed = true, forceFallback = true, custom = false)

        assertNotEquals(native.cacheKey, fallback.cacheKey)
        assertNotEquals(native.cacheKey, NothingUiIconPolicy.CACHE_KEY_OFF)
        assertNotEquals(fallback.cacheKey, NothingUiIconPolicy.CACHE_KEY_OFF)
    }

    private fun resolve(
        play: Boolean,
        themed: Boolean,
        forceFallback: Boolean,
        custom: Boolean,
    ) = NothingUiIconPolicy.resolve(
        playEnabled = play,
        themedIconsEnabled = themed,
        forceFallbackEnabled = forceFallback,
        customIconSelected = custom,
    )
}
