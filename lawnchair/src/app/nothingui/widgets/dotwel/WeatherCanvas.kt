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

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

internal data class WeatherPalette(
    val background: Int?,
    val ink: Int,
    val accent: Int,
    val primary: Int,
)

internal object WeatherCanvas {
    const val RED = 0xFFD71921.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val INK_DARK = 0xFF1B1B1D.toInt()
    private const val TRANSLUCENT_SURFACE = 0xA6FFFFFF.toInt()

    fun palette(style: WidgetStyle): WeatherPalette = when (style) {
        WidgetStyle.BLACK -> WeatherPalette(INK_DARK, WHITE, withAlpha(WHITE, 0x33), RED)
        WidgetStyle.TRANSLUCENT -> WeatherPalette(
            TRANSLUCENT_SURFACE,
            INK_DARK,
            withAlpha(INK_DARK, 0x33),
            RED,
        )
        WidgetStyle.TRANSPARENT -> WeatherPalette(
            null,
            WHITE,
            withAlpha(WHITE, 0x33),
            RED,
        )
    }

    fun withAlpha(color: Int, alpha: Int): Int =
        (color and 0x00FFFFFF) or (alpha.coerceIn(0, 255) shl 24)

    fun paint(color: Int, strokeWidth: Float = 0f): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        if (strokeWidth > 0f) {
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
        }
    }

    fun textPaint(color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        textAlign = Paint.Align.CENTER
    }

    fun drawRoundedHexagon(
        canvas: Canvas,
        rect: RectF,
        cornerRadius: Float,
        paint: Paint,
    ) {
        val radius = min(rect.width(), rect.height()) / 2f
        val cx = rect.centerX()
        val cy = rect.centerY()
        val points = FloatArray(12)
        for (index in 0 until 6) {
            val angle = Math.toRadians((-90 + index * 60).toDouble())
            points[index * 2] = (cx + radius * cos(angle)).toFloat()
            points[index * 2 + 1] = (cy + radius * sin(angle)).toFloat()
        }
        val path = Path()
        for (index in 0 until 6) {
            val current = index * 2
            val prev = ((index + 5) % 6) * 2
            val next = ((index + 1) % 6) * 2
            val cx0 = points[current]
            val cy0 = points[current + 1]
            val edgePrev = sqrt(
                (cx0 - points[prev]) * (cx0 - points[prev]) +
                    (cy0 - points[prev + 1]) * (cy0 - points[prev + 1]),
            )
            val edgeNext = sqrt(
                (points[next] - cx0) * (points[next] - cx0) +
                    (points[next + 1] - cy0) * (points[next + 1] - cy0),
            )
            val r = min(cornerRadius, min(edgePrev, edgeNext) / 2f)
            val p1x = cx0 + (points[prev] - cx0) / edgePrev * r
            val p1y = cy0 + (points[prev + 1] - cy0) / edgePrev * r
            val p2x = cx0 + (points[next] - cx0) / edgeNext * r
            val p2y = cy0 + (points[next + 1] - cy0) / edgeNext * r
            if (index == 0) path.moveTo(p1x, p1y) else path.lineTo(p1x, p1y)
            path.quadTo(cx0, cy0, p2x, p2y)
        }
        path.close()
        canvas.drawPath(path, paint)
    }

    fun fitTextSize(
        paint: Paint,
        text: String,
        maxWidth: Float,
        maxHeight: Float,
        desired: Float,
    ): Float {
        if (text.isEmpty() || maxWidth <= 0f || maxHeight <= 0f) return 0f
        paint.textSize = desired.coerceAtLeast(1f)
        val metrics = paint.fontMetrics
        val height = (metrics.descent - metrics.ascent).coerceAtLeast(0.001f)
        val width = paint.measureText(text).coerceAtLeast(0.001f)
        val scale = min(maxWidth / width, maxHeight / height).coerceAtMost(1f)
        return (desired * scale).coerceAtLeast(1f)
    }

    fun drawCenteredText(
        canvas: Canvas,
        paint: Paint,
        text: String,
        centerX: Float,
        centerY: Float,
    ) {
        val metrics = paint.fontMetrics
        val baseline = centerY - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(text, centerX, baseline, paint)
    }
}
