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

package app.nothingui.theme

import androidx.compose.ui.graphics.Color
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NothingUiNativeSurfacesTest {
    @Test
    fun darkNativeSurfacesUseCharcoalAndPaper() {
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.popupSurface(dark = true))
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.popupShadeFirst(dark = true))
        assertEquals(NothingUiPalette.Gray700, NothingUiNativeSurfaces.popupShadeSecond(dark = true))
        assertEquals(NothingUiPalette.Gray700, NothingUiNativeSurfaces.popupShadeThird(dark = true))
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.popupSecondary(dark = true))
        assertEquals(NothingUiPalette.Gray700, NothingUiNativeSurfaces.popupTertiary(dark = true))
        assertEquals(NothingUiPalette.Paper, NothingUiNativeSurfaces.textPrimary(dark = true))
        assertEquals(NothingUiPalette.Ink, NothingUiNativeSurfaces.textPrimaryInverse(dark = true))
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.allAppsBackground(dark = true))
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.allAppsHeader(dark = true))
        assertEquals(NothingUiPalette.Gray900, NothingUiNativeSurfaces.allAppsTabBackground(dark = true))
        assertEquals(NothingUiPalette.Paper, NothingUiNativeSurfaces.allAppsTabSelected(dark = true))
    }

    @Test
    fun lightNativeSurfacesUseWhiteAndInk() {
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.popupSurface(dark = false))
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.popupShadeFirst(dark = false))
        assertEquals(NothingUiPalette.Paper, NothingUiNativeSurfaces.popupShadeSecond(dark = false))
        assertEquals(NothingUiPalette.Gray100, NothingUiNativeSurfaces.popupShadeThird(dark = false))
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.popupSecondary(dark = false))
        assertEquals(NothingUiPalette.Gray100, NothingUiNativeSurfaces.popupTertiary(dark = false))
        assertEquals(NothingUiPalette.Ink, NothingUiNativeSurfaces.textPrimary(dark = false))
        assertEquals(NothingUiPalette.Paper, NothingUiNativeSurfaces.textPrimaryInverse(dark = false))
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.allAppsBackground(dark = false))
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.allAppsHeader(dark = false))
        assertEquals(NothingUiPalette.White, NothingUiNativeSurfaces.allAppsTabBackground(dark = false))
        assertEquals(NothingUiPalette.Ink, NothingUiNativeSurfaces.allAppsTabSelected(dark = false))
    }

    @Test
    fun everyNativeSurfaceStaysAchromatic() {
        listOf(
            NothingUiNativeSurfaces.popupSurface(dark = false),
            NothingUiNativeSurfaces.popupSurface(dark = true),
            NothingUiNativeSurfaces.popupShadeFirst(dark = false),
            NothingUiNativeSurfaces.popupShadeFirst(dark = true),
            NothingUiNativeSurfaces.popupShadeSecond(dark = false),
            NothingUiNativeSurfaces.popupShadeSecond(dark = true),
            NothingUiNativeSurfaces.popupShadeThird(dark = false),
            NothingUiNativeSurfaces.popupShadeThird(dark = true),
            NothingUiNativeSurfaces.popupSecondary(dark = false),
            NothingUiNativeSurfaces.popupSecondary(dark = true),
            NothingUiNativeSurfaces.popupTertiary(dark = false),
            NothingUiNativeSurfaces.popupTertiary(dark = true),
            NothingUiNativeSurfaces.textPrimary(dark = false),
            NothingUiNativeSurfaces.textPrimary(dark = true),
            NothingUiNativeSurfaces.textPrimaryInverse(dark = false),
            NothingUiNativeSurfaces.textPrimaryInverse(dark = true),
            NothingUiNativeSurfaces.allAppsBackground(dark = false),
            NothingUiNativeSurfaces.allAppsBackground(dark = true),
            NothingUiNativeSurfaces.allAppsHeader(dark = false),
            NothingUiNativeSurfaces.allAppsHeader(dark = true),
            NothingUiNativeSurfaces.allAppsTabBackground(dark = false),
            NothingUiNativeSurfaces.allAppsTabBackground(dark = true),
            NothingUiNativeSurfaces.allAppsTabSelected(dark = false),
            NothingUiNativeSurfaces.allAppsTabSelected(dark = true),
        ).forEach { color ->
            assertEquals(color.red, color.green, 0f)
            assertEquals(color.green, color.blue, 0f)
            assertNotEquals(NothingUiPalette.AccentRed, color)
        }
    }

    @Test
    fun darkBodyTextMeetsContrastOnEveryNativeSurface() {
        val text = NothingUiNativeSurfaces.textPrimary(dark = true)
        listOf(
            NothingUiNativeSurfaces.popupSurface(dark = true),
            NothingUiNativeSurfaces.popupShadeSecond(dark = true),
            NothingUiNativeSurfaces.popupShadeThird(dark = true),
            NothingUiNativeSurfaces.popupTertiary(dark = true),
            NothingUiNativeSurfaces.allAppsBackground(dark = true),
            NothingUiNativeSurfaces.allAppsHeader(dark = true),
            NothingUiNativeSurfaces.allAppsTabBackground(dark = true),
        ).forEach { surface ->
            assertTrue(contrast(text, surface) >= 7.0)
        }
        assertTrue(
            contrast(
                NothingUiNativeSurfaces.textPrimaryInverse(dark = true),
                NothingUiNativeSurfaces.allAppsTabSelected(dark = true),
            ) >= 7.0,
        )
    }

    @Test
    fun lightBodyTextMeetsContrastOnEveryNativeSurface() {
        val text = NothingUiNativeSurfaces.textPrimary(dark = false)
        listOf(
            NothingUiNativeSurfaces.popupSurface(dark = false),
            NothingUiNativeSurfaces.popupShadeSecond(dark = false),
            NothingUiNativeSurfaces.popupShadeThird(dark = false),
            NothingUiNativeSurfaces.popupTertiary(dark = false),
            NothingUiNativeSurfaces.allAppsBackground(dark = false),
            NothingUiNativeSurfaces.allAppsHeader(dark = false),
            NothingUiNativeSurfaces.allAppsTabBackground(dark = false),
        ).forEach { surface ->
            assertTrue(contrast(text, surface) >= 7.0)
        }
        assertTrue(
            contrast(
                NothingUiNativeSurfaces.textPrimaryInverse(dark = false),
                NothingUiNativeSurfaces.allAppsTabSelected(dark = false),
            ) >= 7.0,
        )
    }

    @Test
    fun drawerLayersKeepTheirOriginalAlphaBudget() {
        assertEquals(quantizedAlpha(0.40f), NothingUiNativeSurfaces.allAppsScrim(dark = true).alpha, 0f)
        assertEquals(quantizedAlpha(0.40f), NothingUiNativeSurfaces.allAppsScrim(dark = false).alpha, 0f)
        assertEquals(quantizedAlpha(0.50f), NothingUiNativeSurfaces.allAppsExpressive(dark = true).alpha, 0f)
        assertEquals(quantizedAlpha(0.50f), NothingUiNativeSurfaces.allAppsExpressive(dark = false).alpha, 0f)
        assertEquals(quantizedAlpha(0.32f), NothingUiNativeSurfaces.allAppsBlurBackground(dark = true).alpha, 0f)
        assertEquals(quantizedAlpha(0.32f), NothingUiNativeSurfaces.allAppsBlurBackground(dark = false).alpha, 0f)
        assertEquals(quantizedAlpha(0.32f), NothingUiNativeSurfaces.allAppsBlurForeground(dark = true).alpha, 0f)
        assertEquals(quantizedAlpha(0.32f), NothingUiNativeSurfaces.allAppsBlurForeground(dark = false).alpha, 0f)
    }

    private fun quantizedAlpha(alpha: Float): Float = Color.White.copy(alpha = alpha).alpha

    private fun contrast(first: Color, second: Color): Double {
        val firstLuminance = first.relativeLuminance()
        val secondLuminance = second.relativeLuminance()
        return (max(firstLuminance, secondLuminance) + 0.05) /
            (min(firstLuminance, secondLuminance) + 0.05)
    }

    private fun Color.relativeLuminance(): Double {
        fun linearize(channel: Float): Double {
            val value = channel.toDouble()
            return if (value <= 0.04045) {
                value / 12.92
            } else {
                ((value + 0.055) / 1.055).pow(2.4)
            }
        }
        return 0.2126 * linearize(red) +
            0.7152 * linearize(green) +
            0.0722 * linearize(blue)
    }
}
