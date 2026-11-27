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
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.min

/**
 * Native port of the KWGT `Nothing_Sun_Info` surface.
 *
 * Retained source facts: the `SUN` label, the two half-circle arcs, the
 * horizontal red base and the three accent lines at side / 1.6, side / 2 and
 * side / 3 with the 16-unit stack gap.
 *
 * The source prints the next sunrise or sunset. This launcher's shared render
 * state does not carry solar instants, so the time reads "Unavailable" and the
 * progress dot is omitted instead of being placed at a guessed position.
 */
object NothingSunInfoRenderer {
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
        palette.background?.let { background ->
            val surface = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = background
                this.style = Paint.Style.FILL
            }
            val radius = side / 5f
            canvas.drawRoundRect(
                RectF(0f, 0f, width.toFloat(), height.toFloat()),
                radius,
                radius,
                surface,
            )
        }

        val label = "SUN"
        val timeText = if (weather.hasForecast) "Unavailable" else weather.fallbackText(context)
        val footer = weather.statusText

        val centerX = left + side / 2f
        val labelPaint = WeatherCanvas.textPaint(palette.ink)
        val timePaint = WeatherCanvas.textPaint(palette.ink)
        val footerPaint = WeatherCanvas.textPaint(
            WeatherCanvas.withAlpha(palette.ink, 0xB0),
        )
        val maxWidth = side * 0.72f

        val labelSize = WeatherCanvas.fitTextSize(
            labelPaint,
            label,
            maxWidth,
            side * 0.08f,
            side * 18f / 277f,
        )
        val timeSize = WeatherCanvas.fitTextSize(
            timePaint,
            timeText,
            maxWidth,
            side * 0.12f,
            side * 26f / 277f,
        )
        val footerSize = WeatherCanvas.fitTextSize(
            footerPaint,
            footer,
            maxWidth,
            side * 0.055f,
            side * 9f / 277f,
        )
        labelPaint.textSize = labelSize
        timePaint.textSize = timeSize
        footerPaint.textSize = footerSize

        val labelY = top + side * 0.085f
        WeatherCanvas.drawCenteredText(canvas, labelPaint, label, centerX, labelY)

        val baseY = top + side * 0.58f
        val outerRadius = side * 260f / 277f / 2f
        val innerRadius = side * 200f / 277f / 2f
        val arcPaint = WeatherCanvas.paint(
            palette.accent,
            (side / 277f).coerceAtLeast(1f),
        )
        canvas.drawArc(
            RectF(
                centerX - outerRadius,
                baseY - outerRadius,
                centerX + outerRadius,
                baseY + outerRadius,
            ),
            180f,
            180f,
            false,
            arcPaint,
        )
        val redArc = WeatherCanvas.paint(
            palette.primary,
            (side / 277f).coerceAtLeast(1f),
        )
        canvas.drawArc(
            RectF(
                centerX - innerRadius,
                baseY - innerRadius,
                centerX + innerRadius,
                baseY + innerRadius,
            ),
            180f,
            180f,
            false,
            redArc,
        )
        val red = WeatherCanvas.paint(palette.primary)
        canvas.drawRect(
            centerX - side / 1.3f / 2f,
            baseY - (side / 277f).coerceAtLeast(0.5f) / 2f,
            centerX + side / 1.3f / 2f,
            baseY + (side / 277f).coerceAtLeast(0.5f) / 2f,
            red,
        )

        drawArrow(canvas, centerX, top, baseY, side, weather.hasForecast, palette.primary)

        val linePaint = WeatherCanvas.paint(
            palette.accent,
            (side / 277f).coerceAtLeast(0.75f),
        )
        val lineGap = side * 16f / 277f
        val lineStart = baseY + lineGap * 0.75f
        val widths = floatArrayOf(side / 1.6f, side / 2f, side / 3f)
        widths.forEachIndexed { index, lineWidth ->
            val y = lineStart + index * lineGap
            canvas.drawLine(centerX - lineWidth / 2f, y, centerX + lineWidth / 2f, y, linePaint)
        }

        val timeY = top + side * 0.815f
        WeatherCanvas.drawCenteredText(canvas, timePaint, timeText, centerX, timeY)
        val footerY = top + side * 0.93f
        WeatherCanvas.drawCenteredText(canvas, footerPaint, footer, centerX, footerY)
        return bitmap
    }

    private fun drawArrow(
        canvas: Canvas,
        centerX: Float,
        top: Float,
        baseY: Float,
        side: Float,
        hasForecast: Boolean,
        color: Int,
    ) {
        val shaftWidth = (side / 277f).coerceAtLeast(1f)
        val shaftHeight = side * 36f / 277f
        val headRadius = side * 14f / 277f
        val paint = WeatherCanvas.paint(color)
        val stroke = WeatherCanvas.paint(color, (side / 277f).coerceAtLeast(0.75f))
        if (hasForecast) {
            val bottom = baseY
            val arrowTop = bottom - shaftHeight
            canvas.drawRect(
                centerX - shaftWidth / 2f,
                arrowTop,
                centerX + shaftWidth / 2f,
                bottom,
                paint,
            )
            val head = Path()
            head.moveTo(centerX, bottom + headRadius)
            head.lineTo(centerX + headRadius, bottom)
            head.lineTo(centerX, bottom - headRadius)
            head.lineTo(centerX - headRadius, bottom)
            head.close()
            canvas.drawPath(head, stroke)
        } else {
            val arrowTop = top + side * 0.16f
            val bottom = arrowTop + shaftHeight
            canvas.drawRect(
                centerX - shaftWidth / 2f,
                arrowTop,
                centerX + shaftWidth / 2f,
                bottom,
                paint,
            )
            val head = Path()
            head.moveTo(centerX, arrowTop - headRadius)
            head.lineTo(centerX + headRadius, arrowTop)
            head.lineTo(centerX, arrowTop + headRadius)
            head.lineTo(centerX - headRadius, arrowTop)
            head.close()
            canvas.drawPath(head, stroke)
        }
    }
}
