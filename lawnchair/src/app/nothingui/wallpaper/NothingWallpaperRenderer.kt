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

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint

/**
 * Draws the procedural wallpapers to a plain ARGB bitmap. No file, network or
 * provider access is involved; the same code renders both the gallery preview
 * and the wallpaper handed to [android.app.WallpaperManager].
 */
object NothingWallpaperRenderer {

    fun render(spec: NothingWallpaperSpec, size: NothingWallpaperSize): Bitmap? {
        val layout = NothingWallpaperGeometry.layout(spec, size.widthPx, size.heightPx)
            ?: return null
        val bitmap = Bitmap.createBitmap(size.widthPx, size.heightPx, Bitmap.Config.ARGB_8888)
        draw(Canvas(bitmap), spec, layout)
        return bitmap
    }

    fun draw(canvas: Canvas, spec: NothingWallpaperSpec, layout: NothingWallpaperLayout) {
        val background = Paint().apply {
            color = spec.backgroundArgb
            style = Paint.Style.FILL
        }
        canvas.drawRect(0f, 0f, layout.widthPx.toFloat(), layout.heightPx.toFloat(), background)

        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.dotArgb
            style = Paint.Style.FILL
        }
        for (row in 0 until layout.rows) {
            val y = NothingWallpaperGeometry.dotCenterY(layout, row)
            for (column in 0 until layout.columns) {
                val x = NothingWallpaperGeometry.dotCenterX(layout, column)
                canvas.drawCircle(x, y, layout.dotRadiusPx, dot)
            }
        }

        when (spec.pattern) {
            NothingWallpaperPattern.DOT_GRID -> Unit
            NothingWallpaperPattern.HORIZON -> drawHorizon(canvas, spec, layout)
            NothingWallpaperPattern.GLYPH -> drawGlyph(canvas, spec, layout)
        }
    }

    private fun drawHorizon(canvas: Canvas, spec: NothingWallpaperSpec, layout: NothingWallpaperLayout) {
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.lineArgb
            style = Paint.Style.STROKE
            strokeWidth = layout.lineStrokePx
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawLine(layout.lineStartX, layout.lineY, layout.lineEndX, layout.lineY, line)
        val accent = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.accentArgb
            style = Paint.Style.FILL
        }
        canvas.drawCircle(layout.lineEndX, layout.lineY, layout.accentRadiusPx, accent)
    }

    private fun drawGlyph(canvas: Canvas, spec: NothingWallpaperSpec, layout: NothingWallpaperLayout) {
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.accentArgb
            style = Paint.Style.STROKE
            strokeWidth = layout.glyphStrokePx
        }
        canvas.drawCircle(layout.glyphCenterX, layout.glyphCenterY, layout.glyphRadiusPx, ring)
        val centre = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spec.lineArgb
            style = Paint.Style.FILL
        }
        canvas.drawCircle(layout.glyphCenterX, layout.glyphCenterY, layout.accentRadiusPx, centre)
    }
}
