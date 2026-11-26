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

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The app palette as Android ARGB integers.
 *
 * These are the exact values of [app.nothingui.theme.NothingUiPalette]; the
 * theme test asserts they stay in sync. Keeping them as plain Ints lets the
 * geometry and renderer stay free of Compose and Android types where possible.
 */
object NothingWallpaperColors {
    const val Black: Int = 0xFF000000.toInt()
    const val Paper: Int = 0xFFF2F2F2.toInt()
    const val Gray900: Int = 0xFF1A1A1A.toInt()
    const val Gray700: Int = 0xFF3A3A3A.toInt()
    const val Gray500: Int = 0xFF6E6E6E.toInt()
    const val AccentRed: Int = 0xFFD7261E.toInt()
}

/**
 * The three original, code-drawn wallpaper motifs. They all sit on true black
 * and only use the monochrome palette plus the single accent red.
 */
enum class NothingWallpaperPattern {
    /** A quiet uniform dot grid. */
    DOT_GRID,

    /** A dot grid crossed by one thin line with a single accent dot. */
    HORIZON,

    /** A dot grid with one thin ring and a single centre dot. */
    GLYPH,
}

/**
 * Resolution-independent recipe for one procedural wallpaper. The layout is
 * derived from the real pixel size, so the same spec works on every phone
 * aspect ratio without a raster asset.
 */
data class NothingWallpaperSpec(
    val pattern: NothingWallpaperPattern,
    val backgroundArgb: Int = NothingWallpaperColors.Black,
    val dotArgb: Int = NothingWallpaperColors.Gray700,
    val lineArgb: Int = NothingWallpaperColors.Gray500,
    val accentArgb: Int = NothingWallpaperColors.AccentRed,
    val dotColumnsOnShortSide: Int = 22,
    val dotRadiusFraction: Float = 0.09f,
    val lineFraction: Float = 0.42f,
    val lineMarginFraction: Float = 0.12f,
    val lineStrokeFraction: Float = 0.0015f,
    val glyphRadiusFraction: Float = 0.16f,
    val glyphStrokeFraction: Float = 0.004f,
) {
    init {
        require(dotColumnsOnShortSide >= 2) { "a dot grid needs at least two columns" }
        require(dotRadiusFraction > 0f) { "dots must have a positive radius" }
        require(lineFraction in 0f..1f) { "the accent line must stay on the surface" }
        require(lineMarginFraction in 0f..0.5f) { "the accent line margin is out of range" }
        require(lineStrokeFraction > 0f) { "the accent line needs a positive stroke" }
        require(glyphRadiusFraction > 0f) { "the glyph needs a positive radius" }
        require(glyphStrokeFraction > 0f) { "the glyph needs a positive stroke" }
    }
}

/** One portrait phone resolution variant the gallery can render. */
data class NothingWallpaperSize(
    val id: String,
    val widthPx: Int,
    val heightPx: Int,
) {
    init {
        require(widthPx > 0) { "wallpaper width must be positive" }
        require(heightPx > 0) { "wallpaper height must be positive" }
    }

    /** Height divided by width; always >= 1 for the curated portrait sizes. */
    val aspectRatio: Double get() = heightPx.toDouble() / widthPx.toDouble()
}

/**
 * A small curated set of portrait phone resolutions. The applier picks the
 * closest aspect ratio that still covers the real display, so a wallpaper is
 * always rendered at a sensible size for the device.
 */
object NothingWallpaperSizes {
    val classic16x9 = NothingWallpaperSize("classic_16x9", 1080, 1920)
    val tall18x9 = NothingWallpaperSize("tall_18x9", 1080, 2160)
    val tall19_5x9 = NothingWallpaperSize("tall_19_5x9", 1080, 2340)
    val tall20x9 = NothingWallpaperSize("tall_20x9", 1080, 2400)
    val qhd19_5x9 = NothingWallpaperSize("qhd_19_5x9", 1440, 3120)
    val qhd20x9 = NothingWallpaperSize("qhd_20x9", 1440, 3200)

    val entries: List<NothingWallpaperSize> = listOf(
        classic16x9,
        tall18x9,
        tall19_5x9,
        tall20x9,
        qhd19_5x9,
        qhd20x9,
    )

    /** A small bitmap size used for the in-app gallery previews. */
    val preview = NothingWallpaperSize("preview", 270, 540)

    /**
     * Chooses the best catalog size for a display. The display is normalized
     * to portrait, then the closest aspect ratio wins. Sizes that cover the
     * display are preferred; the smallest covering size breaks a tie. When
     * nothing covers the display, the largest closest-aspect size is used so
     * the wallpaper is never needlessly low-resolution.
     */
    fun bestFor(displayWidthPx: Int, displayHeightPx: Int): NothingWallpaperSize {
        if (displayWidthPx <= 0 || displayHeightPx <= 0) return tall20x9
        val width = min(displayWidthPx, displayHeightPx)
        val height = max(displayWidthPx, displayHeightPx)
        val target = height.toDouble() / width.toDouble()
        val covering = entries.filter { it.widthPx >= width && it.heightPx >= height }
        return if (covering.isNotEmpty()) {
            covering.minWith(
                compareBy(
                    { abs(it.aspectRatio - target) },
                    { it.widthPx.toLong() * it.heightPx },
                ),
            )
        } else {
            entries.minWith(
                compareBy(
                    { abs(it.aspectRatio - target) },
                    { -it.widthPx.toLong() * it.heightPx },
                ),
            )
        }
    }
}

/**
 * Deterministic pixel layout for one spec and surface size. All values are
 * derived from the surface, so the same spec always produces the same art.
 */
data class NothingWallpaperLayout(
    val widthPx: Int,
    val heightPx: Int,
    val columns: Int,
    val rows: Int,
    val spacingPx: Float,
    val offsetX: Float,
    val offsetY: Float,
    val dotRadiusPx: Float,
    val lineStartX: Float,
    val lineEndX: Float,
    val lineY: Float,
    val lineStrokePx: Float,
    val glyphCenterX: Float,
    val glyphCenterY: Float,
    val glyphRadiusPx: Float,
    val glyphStrokePx: Float,
    val accentRadiusPx: Float,
)

object NothingWallpaperGeometry {
    const val MIN_SPACING_PX: Float = 8f
    const val MAX_SPACING_PX: Float = 120f
    const val MIN_DOT_RADIUS_PX: Float = 0.5f
    const val MAX_DOT_RADIUS_FRACTION_OF_SPACING: Float = 0.35f

    fun layout(
        spec: NothingWallpaperSpec,
        widthPx: Int,
        heightPx: Int,
    ): NothingWallpaperLayout? {
        if (widthPx <= 0 || heightPx <= 0) return null
        val shortSide = min(widthPx, heightPx).toFloat()
        val spacing = (shortSide / spec.dotColumnsOnShortSide)
            .coerceIn(MIN_SPACING_PX, MAX_SPACING_PX)
        val columns = max(1, (widthPx / spacing).toInt())
        val rows = max(1, (heightPx / spacing).toInt())
        val gridWidth = (columns - 1) * spacing
        val gridHeight = (rows - 1) * spacing
        val offsetX = (widthPx - gridWidth) / 2f
        val offsetY = (heightPx - gridHeight) / 2f
        val dotRadius = (spacing * spec.dotRadiusFraction)
            .coerceIn(MIN_DOT_RADIUS_PX, spacing * MAX_DOT_RADIUS_FRACTION_OF_SPACING)
        val margin = widthPx * spec.lineMarginFraction
        val lineStroke = (shortSide * spec.lineStrokeFraction).coerceAtLeast(1f)
        val glyphStroke = (shortSide * spec.glyphStrokeFraction).coerceAtLeast(1f)
        return NothingWallpaperLayout(
            widthPx = widthPx,
            heightPx = heightPx,
            columns = columns,
            rows = rows,
            spacingPx = spacing,
            offsetX = offsetX,
            offsetY = offsetY,
            dotRadiusPx = dotRadius,
            lineStartX = margin,
            lineEndX = widthPx - margin,
            lineY = heightPx * spec.lineFraction,
            lineStrokePx = lineStroke,
            glyphCenterX = widthPx / 2f,
            glyphCenterY = heightPx / 2f,
            glyphRadiusPx = shortSide * spec.glyphRadiusFraction,
            glyphStrokePx = glyphStroke,
            accentRadiusPx = (dotRadius * 1.6f).coerceAtLeast(1f),
        )
    }

    fun dotCenterX(layout: NothingWallpaperLayout, column: Int): Float =
        layout.offsetX + column * layout.spacingPx

    fun dotCenterY(layout: NothingWallpaperLayout, row: Int): Float =
        layout.offsetY + row * layout.spacingPx
}
