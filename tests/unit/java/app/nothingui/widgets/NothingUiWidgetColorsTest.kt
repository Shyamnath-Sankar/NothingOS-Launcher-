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

package app.nothingui.widgets

import androidx.compose.ui.graphics.toArgb
import app.nothingui.theme.NothingUiPalette
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class NothingUiWidgetColorsTest {

    @Test
    fun darkWidgetPairUsesCharcoalAndWhite() {
        assertEquals(NothingUiPalette.Gray900.toArgb(), NothingUiWidgetColors.surfaceColor(lightSurface = false))
        assertEquals(NothingUiPalette.White.toArgb(), NothingUiWidgetColors.contentColor(lightSurface = false))
    }

    @Test
    fun lightWidgetPairUsesPaperAndInk() {
        assertEquals(NothingUiPalette.Paper.toArgb(), NothingUiWidgetColors.surfaceColor(lightSurface = true))
        assertEquals(NothingUiPalette.Ink.toArgb(), NothingUiWidgetColors.contentColor(lightSurface = true))
    }

    @Test
    fun eachPairIsExplicitAndHighContrast() {
        val darkSurface = NothingUiWidgetColors.surfaceColor(lightSurface = false)
        val darkContent = NothingUiWidgetColors.contentColor(lightSurface = false)
        val lightSurface = NothingUiWidgetColors.surfaceColor(lightSurface = true)
        val lightContent = NothingUiWidgetColors.contentColor(lightSurface = true)

        assertNotEquals(darkSurface, darkContent)
        assertNotEquals(lightSurface, lightContent)
        assertNotEquals(darkSurface, lightSurface)
        assertNotEquals(darkContent, lightContent)
    }

    @Test
    fun widgetPaletteStaysNeutral() {
        val colors = listOf(
            NothingUiWidgetColors.surfaceColor(lightSurface = false),
            NothingUiWidgetColors.contentColor(lightSurface = false),
            NothingUiWidgetColors.surfaceColor(lightSurface = true),
            NothingUiWidgetColors.contentColor(lightSurface = true),
        )

        colors.forEach { color ->
            val red = (color shr 16) and 0xFF
            val green = (color shr 8) and 0xFF
            val blue = color and 0xFF
            assertEquals("channel must be neutral for ${Integer.toHexString(color)}", red, green)
            assertEquals("channel must be neutral for ${Integer.toHexString(color)}", red, blue)
        }
    }
}
