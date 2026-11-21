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

import androidx.compose.ui.graphics.toArgb
import app.nothingui.theme.NothingUiPalette
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class NothingUiIconColorsTest {

    @Test
    fun darkSurfaceUsesBlackBackgroundAndWhiteGlyph() {
        val colors = NothingUiIconColors.forLightSurface(lightSurface = false)

        assertEquals(NothingUiPalette.Ink.toArgb(), colors[0])
        assertEquals(NothingUiPalette.White.toArgb(), colors[1])
    }

    @Test
    fun lightSurfaceUsesWhiteBackgroundAndBlackGlyph() {
        val colors = NothingUiIconColors.forLightSurface(lightSurface = true)

        assertEquals(NothingUiPalette.White.toArgb(), colors[0])
        assertEquals(NothingUiPalette.Ink.toArgb(), colors[1])
    }

    @Test
    fun paletteIsNeutralBlackOrWhiteNotWallpaperAccent() {
        val dark = NothingUiIconColors.forLightSurface(lightSurface = false)
        val light = NothingUiIconColors.forLightSurface(lightSurface = true)

        (dark + light).forEach { color ->
            val red = (color shr 16) and 0xFF
            val green = (color shr 8) and 0xFF
            val blue = color and 0xFF
            assertEquals("channel must be neutral for ${Integer.toHexString(color)}", red, green)
            assertEquals("channel must be neutral for ${Integer.toHexString(color)}", red, blue)
        }
    }

    @Test
    fun backgroundAndForegroundStayHighContrastPairs() {
        val dark = NothingUiIconColors.forLightSurface(lightSurface = false)
        val light = NothingUiIconColors.forLightSurface(lightSurface = true)

        assertNotEquals(dark[0], dark[1])
        assertNotEquals(light[0], light[1])
        assertArrayEquals(NothingUiIconColors.forLightSurface(false), dark)
    }
}
