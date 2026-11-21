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
import androidx.compose.ui.text.font.FontFamily
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class NothingUiTokenTest {
    @Test
    fun darkSchemeMeetsContrastTargets() {
        assertSchemeContrast(DarkNothingUiColors)
    }

    @Test
    fun lightSchemeMeetsContrastTargets() {
        assertSchemeContrast(LightNothingUiColors)
    }

    @Test
    fun paletteKeepsTheOriginalMonochromeAccent() {
        assertEquals(Color(0xFF0B0B0B), NothingUiPalette.Ink)
        assertEquals(Color(0xFFF2F2F2), NothingUiPalette.Paper)
        assertEquals(Color(0xFFD7261E), NothingUiPalette.AccentRed)
        assertEquals(NothingUiPalette.AccentRed, DarkNothingUiColors.accent)
        assertEquals(NothingUiPalette.AccentRed, LightNothingUiColors.accent)
    }

    @Test
    fun spacingScaleIsOrderedAndOnTheFourDpGrid() {
        val values = NothingUiSpacing.scale.map { it.value }
        assertEquals(values.sorted(), values)
        assertEquals(values.distinct(), values)
        assertTrue(values.all { it % 4f == 0f })
        assertEquals(0f, values.first(), 0.001f)
    }

    @Test
    fun motionTokensAreOrderedAndPositive() {
        assertTrue(NothingUiMotion.SHORT_MILLIS > 0)
        assertTrue(NothingUiMotion.SHORT_MILLIS < NothingUiMotion.MEDIUM_MILLIS)
        assertTrue(NothingUiMotion.MEDIUM_MILLIS < NothingUiMotion.LONG_MILLIS)
    }

    @Test
    fun dotoIsReservedForDisplayAndNumericText() {
        assertEquals(DotoFontFamily, NothingUiTypography.displayLarge.fontFamily)
        assertEquals(DotoFontFamily, NothingUiTypography.displayMedium.fontFamily)
        assertEquals(DotoFontFamily, NothingUiTypography.displaySmall.fontFamily)
        assertEquals(DotoFontFamily, NothingUiTypography.displayLargeEmphasized.fontFamily)
        assertEquals(DotoFontFamily, NothingUiType.NumericDisplay.fontFamily)
        assertEquals(DotoFontFamily, NothingUiType.NumericLabel.fontFamily)

        assertEquals(FontFamily.SansSerif, NothingUiTypography.headlineLarge.fontFamily)
        assertEquals(FontFamily.SansSerif, NothingUiTypography.titleLarge.fontFamily)
        assertEquals(FontFamily.SansSerif, NothingUiTypography.bodyLarge.fontFamily)
        assertEquals(FontFamily.SansSerif, NothingUiTypography.bodyMedium.fontFamily)
        assertEquals(FontFamily.SansSerif, NothingUiTypography.labelSmall.fontFamily)
    }

    @Test
    fun displayTextIsLargerThanBodyText() {
        assertTrue(
            NothingUiTypography.displaySmall.fontSize.value >
                NothingUiTypography.bodyLarge.fontSize.value,
        )
        assertTrue(
            NothingUiType.NumericDisplay.fontSize.value >
                NothingUiTypography.bodyLarge.fontSize.value,
        )
    }

    private fun assertSchemeContrast(colors: NothingUiColors) {
        assertTrue(contrast(colors.onBackground, colors.background) >= 7.0)
        assertTrue(contrast(colors.onSurface, colors.surface) >= 7.0)
        assertTrue(contrast(colors.onSurfaceMuted, colors.surface) >= 4.5)
        assertTrue(contrast(colors.accent, colors.background) >= 3.0)
        assertTrue(contrast(colors.onAccent, colors.accent) >= 4.5)
    }

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
