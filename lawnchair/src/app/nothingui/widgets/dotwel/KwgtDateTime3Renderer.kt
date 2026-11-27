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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.min

/**
 * Native renderer for `Nothing_Date_Time3` from AumGupta/KWGT-Widgets
 * (MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained author geometry and formulas:
 * - `side = min(width, height)`
 * - right-aligned stack shifted by `side / 8.5` horizontally and
 *   `side / 30.083` vertically
 * - time `side / 2.8`, AM/PM `side / 5`, date `side / 6.5`, weather `side / 8`
 *
 * The source also prints a US AQI value. This launcher's shared render state
 * carries no AQI, so the line shows `AQI --` instead of a fabricated index.
 */
object KwgtDateTime3Renderer {
    const val SOURCE_WIDTH = 916f
    const val SOURCE_HEIGHT = 542f

    private const val TIME_RATIO = 1f / 2.8f
    private const val AMPM_RATIO = 1f / 5f
    private const val DATE_RATIO = 1f / 6.5f
    private const val WEATHER_RATIO = 1f / 8f
    private const val RIGHT_INSET_RATIO = 1f / 8.5f
    private const val TOP_INSET_RATIO = 1f / 30.083f

    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val LIGHT_INK = 0xFF1B1B1D.toInt()

    data class Palette(
        val background: Int,
        val foreground: Int,
        val accent: Int,
    )

    data class Layout(
        val width: Float,
        val height: Float,
        val side: Float,
        val rightInset: Float,
        val timeSize: Float,
        val ampmSize: Float,
        val dateSize: Float,
        val weatherSize: Float,
        val contentCenterY: Float,
    ) {
        val textRight: Float get() = width - rightInset
    }

    fun palette(style: WidgetStyle): Palette {
        val background = when (style) {
            WidgetStyle.BLACK -> LIGHT_INK
            WidgetStyle.TRANSLUCENT -> 0xA6FFFFFF.toInt()
            WidgetStyle.TRANSPARENT -> 0x00000000
        }
        val foreground = when (style) {
            WidgetStyle.BLACK -> WHITE
            WidgetStyle.TRANSLUCENT -> LIGHT_INK
            WidgetStyle.TRANSPARENT -> WHITE
        }
        return Palette(
            background = background,
            foreground = foreground,
            accent = withAlpha(foreground, 50),
        )
    }

    fun layout(width: Int, height: Int): Layout {
        val safeWidth = width.coerceAtLeast(1).toFloat()
        val safeHeight = height.coerceAtLeast(1).toFloat()
        val side = min(safeWidth, safeHeight)
        return Layout(
            width = safeWidth,
            height = safeHeight,
            side = side,
            rightInset = side * RIGHT_INSET_RATIO,
            timeSize = side * TIME_RATIO,
            ampmSize = side * AMPM_RATIO,
            dateSize = side * DATE_RATIO,
            weatherSize = side * WEATHER_RATIO,
            contentCenterY = safeHeight / 2f + side * TOP_INSET_RATIO,
        )
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
        now: Long = System.currentTimeMillis(),
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(2)
        val safeHeight = height.coerceAtLeast(2)
        val bitmap = Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val layout = layout(safeWidth, safeHeight)
        val palette = palette(style)
        if (palette.background != 0) {
            canvas.drawRect(
                RectF(0f, 0f, layout.width, layout.height),
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.background },
            )
        }
        val time = SimpleDateFormat("hh:mm", Locale.getDefault()).format(Date(now))
        val ampm = SimpleDateFormat("a", Locale.getDefault())
            .format(Date(now))
            .uppercase(Locale.getDefault())
        val date = SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date(now))
        val weatherLine = weatherLine(weather)
        val timePaint = textPaint(palette.foreground, layout.timeSize, Paint.Align.RIGHT)
        val ampmPaint = textPaint(palette.accent, layout.ampmSize, Paint.Align.RIGHT)
        val datePaint = textPaint(palette.foreground, layout.dateSize, Paint.Align.RIGHT)
        val weatherPaint = textPaint(palette.accent, layout.weatherSize, Paint.Align.RIGHT)

        val timeBaseline = layout.contentCenterY
        canvas.drawText(time, layout.textRight, timeBaseline, timePaint)
        canvas.drawText(
            ampm,
            layout.textRight - timePaint.measureText(time) - layout.side * 0.02f,
            timeBaseline,
            ampmPaint,
        )
        val dateBaseline = timeBaseline + layout.dateSize * 1.55f
        canvas.drawText(date, layout.textRight, dateBaseline, datePaint)
        val weatherBaseline = dateBaseline + layout.weatherSize * 1.85f
        canvas.drawText(weatherLine, layout.textRight, weatherBaseline, weatherPaint)
        return bitmap
    }

    fun weatherLine(weather: NtWxWeather): String = if (weather.hasForecast) {
        "${weather.temperatureText}\u00B0 ${weather.conditionText}, AQI --"
    } else {
        "Weather unavailable"
    }

    private fun textPaint(color: Int, size: Float, align: Paint.Align): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textSize = size.coerceAtLeast(1f)
        textAlign = align
        typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
        isSubpixelText = true
    }

    private fun withAlpha(color: Int, alphaPercent: Int): Int {
        val alpha = (((color ushr 24) and 0xFF) * alphaPercent / 100).coerceIn(0, 255)
        return (alpha shl 24) or (color and 0x00FFFFFF)
    }
}
