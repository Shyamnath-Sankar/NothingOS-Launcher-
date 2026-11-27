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

package app.nothingui.wallpaper

import androidx.compose.ui.graphics.Color
import app.nothingui.theme.NothingUiPalette
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NothingWallpaperArtTest {

    @Test
    fun paletteMatchesTheAppPalette() {
        assertEquals(NothingUiPalette.Black, Color(NothingWallpaperColors.BLACK))
        assertEquals(NothingUiPalette.Paper, Color(NothingWallpaperColors.PAPER))
        assertEquals(NothingUiPalette.Gray900, Color(NothingWallpaperColors.GRAY_900))
        assertEquals(NothingUiPalette.Gray700, Color(NothingWallpaperColors.GRAY_700))
        assertEquals(NothingUiPalette.Gray500, Color(NothingWallpaperColors.GRAY_500))
        assertEquals(NothingUiPalette.AccentRed, Color(NothingWallpaperColors.ACCENT_RED))
    }

    @Test
    fun backgroundIsExactlyOpaqueBlack() {
        assertEquals(0xFF000000.toInt(), NothingWallpaperColors.BLACK)
        listOf(
            NothingWallpaperSpec(NothingWallpaperPattern.DOT_GRID),
            NothingWallpaperSpec(NothingWallpaperPattern.HORIZON),
            NothingWallpaperSpec(NothingWallpaperPattern.GLYPH),
        ).forEach { spec ->
            assertEquals(0xFF000000.toInt(), spec.backgroundArgb)
        }
    }

    @Test
    fun backgroundsAreTrueBlackAndAccentsStayInThePalette() {
        listOf(
            NothingWallpaperSpec(NothingWallpaperPattern.DOT_GRID),
            NothingWallpaperSpec(NothingWallpaperPattern.HORIZON),
            NothingWallpaperSpec(NothingWallpaperPattern.GLYPH),
        ).forEach { spec ->
            assertEquals(NothingWallpaperColors.BLACK, spec.backgroundArgb)
            assertTrue(spec.dotArgb != spec.backgroundArgb)
            assertTrue(spec.lineArgb != spec.backgroundArgb)
            assertTrue(spec.accentArgb != spec.backgroundArgb)
        }
    }

    @Test
    fun catalogSizesAreDistinctPortraitPhoneResolutions() {
        val sizes = NothingWallpaperSizes.entries
        assertEquals(sizes.size, sizes.map { it.id }.distinct().size)
        sizes.forEach { size ->
            assertTrue(size.widthPx > 0)
            assertTrue(size.heightPx > 0)
            assertTrue("${size.id} must be portrait", size.heightPx > size.widthPx)
            assertTrue("${size.id} aspect ${size.aspectRatio} is not a phone ratio", size.aspectRatio in 1.6..2.4)
        }
        assertTrue(NothingWallpaperSizes.preview.heightPx > NothingWallpaperSizes.preview.widthPx)
    }

    @Test
    fun bestForReturnsTheExactCatalogSizeWhenItMatches() {
        NothingWallpaperSizes.entries.forEach { size ->
            assertEquals(size, NothingWallpaperSizes.bestFor(size.widthPx, size.heightPx))
            assertEquals(size, NothingWallpaperSizes.bestFor(size.heightPx, size.widthPx))
        }
    }

    @Test
    fun bestForPicksTheClosestAspectForAnOffCatalogDisplay() {
        assertEquals(
            NothingWallpaperSizes.tall19_5x9,
            NothingWallpaperSizes.bestFor(1080, 2310),
        )
        assertEquals(
            NothingWallpaperSizes.qhd20x9,
            NothingWallpaperSizes.bestFor(1440, 3200),
        )
    }

    @Test
    fun bestForPrefersTheSmallestCoveringSize() {
        assertEquals(
            NothingWallpaperSizes.tall20x9,
            NothingWallpaperSizes.bestFor(720, 1600),
        )
        assertEquals(
            NothingWallpaperSizes.qhd19_5x9,
            NothingWallpaperSizes.bestFor(1440, 3120),
        )
    }

    @Test
    fun bestForFallsBackSafelyForInvalidDimensions() {
        assertEquals(NothingWallpaperSizes.tall20x9, NothingWallpaperSizes.bestFor(0, 2400))
        assertEquals(NothingWallpaperSizes.tall20x9, NothingWallpaperSizes.bestFor(1080, -1))
    }

    @Test
    fun geometryRejectsInvalidSurface() {
        val spec = NothingWallpaperSpec(NothingWallpaperPattern.DOT_GRID)
        listOf(0 to 2400, 1080 to 0, -1 to 2400, 1080 to -1, 0 to 0).forEach { (width, height) ->
            assertNull("${width}x$height must not layout", NothingWallpaperGeometry.layout(spec, width, height))
        }
    }

    @Test
    fun geometryIsDeterministicAndFitsTheSurface() {
        NothingWallpaperSizes.entries.forEach { size ->
            listOf(
                NothingWallpaperSpec(NothingWallpaperPattern.DOT_GRID),
                NothingWallpaperSpec(NothingWallpaperPattern.HORIZON),
                NothingWallpaperSpec(NothingWallpaperPattern.GLYPH),
            ).forEach { spec ->
                val first = NothingWallpaperGeometry.layout(spec, size.widthPx, size.heightPx)
                val second = NothingWallpaperGeometry.layout(spec, size.widthPx, size.heightPx)

                assertNotNull(first)
                assertEquals(first, second)
                val layout = first!!
                assertTrue(layout.columns >= 1)
                assertTrue(layout.rows >= 1)
                assertTrue(layout.spacingPx >= NothingWallpaperGeometry.MIN_SPACING_PX)
                assertTrue(layout.spacingPx <= NothingWallpaperGeometry.MAX_SPACING_PX)
                assertTrue(layout.dotRadiusPx > 0f)
                assertTrue(layout.dotRadiusPx < layout.spacingPx)
                assertTrue(layout.lineStartX >= 0f)
                assertTrue(layout.lineEndX <= layout.widthPx.toFloat())
                assertTrue(layout.lineY in 0f..layout.heightPx.toFloat())
                assertTrue(layout.glyphRadiusPx > 0f)
                assertTrue(layout.glyphStrokePx > 0f)
                assertTrue(layout.accentRadiusPx > 0f)

                for (column in 0 until layout.columns) {
                    val x = NothingWallpaperGeometry.dotCenterX(layout, column)
                    assertTrue("dot x=$x outside ${layout.widthPx}", x >= 0f && x <= layout.widthPx.toFloat())
                }
                for (row in 0 until layout.rows) {
                    val y = NothingWallpaperGeometry.dotCenterY(layout, row)
                    assertTrue("dot y=$y outside ${layout.heightPx}", y >= 0f && y <= layout.heightPx.toFloat())
                }
            }
        }
    }

    @Test
    fun everyProceduralCatalogChoiceRendersEveryCuratedSize() {
        val procedural = AmoledWallpaperCatalog.entries.filter {
            it.kind == AmoledWallpaperKind.PROCEDURAL
        }
        assertEquals(3, procedural.size)
        procedural.forEach { wallpaper ->
            val spec = wallpaper.spec
            assertNotNull(spec)
            NothingWallpaperSizes.entries.forEach { size ->
                val layout = NothingWallpaperGeometry.layout(spec!!, size.widthPx, size.heightPx)
                assertNotNull("${wallpaper.id} @ ${size.id} must layout", layout)
                assertTrue(layout!!.columns * layout.rows > 0)
            }
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun aSpecWithAnEmptyDotGridIsRejected() {
        NothingWallpaperSpec(
            pattern = NothingWallpaperPattern.DOT_GRID,
            dotColumnsOnShortSide = 1,
        )
    }
}
