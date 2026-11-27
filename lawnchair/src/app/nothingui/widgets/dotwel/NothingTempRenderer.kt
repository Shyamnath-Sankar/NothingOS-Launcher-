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

package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.min

/**
 * Native port of the KWGT `Nothing_Temp` surface.
 *
 * Retained source facts: the six-sided surface with side = min(width, height)
 * and corner radius side / 9, and the centred four-line stack.
 *
 * The source's large line is today's forecast low and its small line is a
 * high/low pair. This launcher's shared render state carries neither, so the
 * large line shows the current temperature and the small line shows the
 * condition. Missing values stay `--` instead of being invented.
 */
object NothingTempRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val palette = WeatherCanvas.palette(style)
        val side = min(width, height).toFloat()
        val left = (width - side) / 2f
        val top = (height - side) / 2f
        val hex = RectF(left, top, left + side, top + side)
        palette.background?.let { background ->
            WeatherCanvas.drawRoundedHexagon(
                canvas,
                hex,
                side / 9f,
                WeatherCanvas.paint(background),
            )
        }

        val bigText = if (weather.hasForecast) "${weather.temperatureText}\u00B0" else "--\u00B0"
        val smallText = if (weather.hasForecast) weather.conditionText else "Forecast unavailable"
        val locationLine = weather.statusText
        val updatedLine = if (weather.hasForecast) {
            "Cache only \u00B7 ${weather.asOfText}"
        } else {
            "Tap to configure"
        }

        val centerX = hex.centerX()
        val centerY = hex.centerY()
        val maxWidth = side * 0.74f
        val bigPaint = WeatherCanvas.textPaint(palette.ink)
        val smallPaint = WeatherCanvas.textPaint(palette.ink)
        val statusPaint = WeatherCanvas.textPaint(palette.ink)
        val gap = side * 14f / 415f

        var bigSize = WeatherCanvas.fitTextSize(
            bigPaint,
            bigText,
            maxWidth,
            side * 0.30f,
            side / 3.5f,
        )
        var smallSize = WeatherCanvas.fitTextSize(
            smallPaint,
            smallText,
            maxWidth,
            side * 0.16f,
            side / 10f,
        )
        var statusSize = WeatherCanvas.fitTextSize(
            statusPaint,
            locationLine,
            maxWidth,
            side * 0.08f,
            side / 22f,
        )
        val updatedPaint = WeatherCanvas.textPaint(palette.accent)
        var updatedSize = WeatherCanvas.fitTextSize(
            updatedPaint,
            updatedLine,
            maxWidth,
            side * 0.08f,
            side / 22f,
        )

        fun heights(): FloatArray {
            bigPaint.textSize = bigSize
            smallPaint.textSize = smallSize
            statusPaint.textSize = statusSize
            updatedPaint.textSize = updatedSize
            return floatArrayOf(
                bigPaint.fontMetrics.descent - bigPaint.fontMetrics.ascent,
                smallPaint.fontMetrics.descent - smallPaint.fontMetrics.ascent,
                statusPaint.fontMetrics.descent - statusPaint.fontMetrics.ascent,
                updatedPaint.fontMetrics.descent - updatedPaint.fontMetrics.ascent,
            )
        }

        var heights = heights()
        var total = heights.sum() + gap * 3f
        val limit = side * 0.78f
        if (total > limit) {
            val scale = limit / total
            bigSize *= scale
            smallSize *= scale
            statusSize *= scale
            updatedSize *= scale
            heights = heights()
            total = heights.sum() + gap * 3f
        }
        var y = centerY - total / 2f
        WeatherCanvas.drawCenteredText(canvas, bigPaint, bigText, centerX, y + heights[0] / 2f)
        y += heights[0] + gap
        WeatherCanvas.drawCenteredText(canvas, smallPaint, smallText, centerX, y + heights[1] / 2f)
        y += heights[1] + gap
        WeatherCanvas.drawCenteredText(canvas, statusPaint, locationLine, centerX, y + heights[2] / 2f)
        y += heights[2] + gap * 0.5f
        WeatherCanvas.drawCenteredText(canvas, updatedPaint, updatedLine, centerX, y + heights[3] / 2f)
        return bitmap
    }
}
