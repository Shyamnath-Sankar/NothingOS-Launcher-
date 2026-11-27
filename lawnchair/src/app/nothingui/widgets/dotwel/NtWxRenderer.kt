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
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Native translation of the AwesomeAWidgets `NtWxDraw.render` circle and square
 * branches (commit 0fae607, MIT, Copyright (c) 2026 Sameer Al Sahab).
 *
 * Adaptations for this launcher:
 * - The richer upstream snapshot is replaced by [NtWxWeather], which carries
 *   only the shared, coordinate-free render state.
 * - High/low, solar events, AQI and precipitation probability are not part of
 *   that state, so those pages draw an explicit `--` instead of a guess.
 * - Fonts are platform families; the icons are Dotwel's original geometry.
 */
object NtWxRenderer {
    enum class Kind(val sourceKind: Int, val pages: Int) {
        CIRCLE(0, 3),
        SQUARE(1, 2),
        RECT(2, 1),
        COMBO(3, 1),
        SUNSET(4, 1),
        AIR(5, 1),
        W1_TEMP(6, 1),
        W1_STATUS(7, 1),
        W1_RAIN(8, 1),
    }

    fun interface IconDrawer {
        fun draw(canvas: Canvas, code: Int, isDay: Boolean, cx: Float, cy: Float, side: Float, color: Int)
    }

    fun page(kind: Kind, requested: Int): Int = NtWxWeatherCode.page(kind.pages, requested)

    fun render(
        context: Context,
        kind: Kind,
        width: Int,
        height: Int,
        style: WidgetStyle,
        weather: NtWxWeather,
        requestedPage: Int,
        icons: IconDrawer,
    ): Bitmap {
        val w = width.coerceAtLeast(1).toFloat()
        val h = height.coerceAtLeast(1).toFloat()
        val side = min(w, h)
        val bitmap = Bitmap.createBitmap(w.toInt(), h.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val bg = UpstreamNtDraw.background(context, style)
        val ink = UpstreamNtDraw.ink(context, style)
        val muted = UpstreamNtDraw.muted(context, style)
        val pad = side * .10f
        if (Color.alpha(bg) > 0) {
            val paint = paint(bg, 1f)
            if (kind == Kind.CIRCLE || kind.sourceKind >= 6) {
                canvas.drawOval(
                    RectF((w - side) / 2, (h - side) / 2, (w + side) / 2, (h + side) / 2),
                    paint,
                )
            } else if (kind != Kind.COMBO) {
                val radius = if (kind == Kind.SUNSET || kind == Kind.AIR) h / 2 else side * .22f
                canvas.drawRoundRect(RectF(0f, 0f, w, h), radius, radius, paint)
            }
        }
        if (!weather.hasForecast) {
            text(
                canvas,
                weather.fallbackText(context),
                w / 2,
                h / 2 - side * .02f,
                side * .11f,
                muted,
                Paint.Align.CENTER,
                side * .85f,
            )
            return bitmap
        }
        val selectedPage = page(kind, requestedPage)
        if (kind == Kind.CIRCLE) {
            when (selectedPage) {
                0 -> icons.draw(
                    canvas,
                    weather.weatherCode,
                    weather.isDay,
                    w / 2,
                    h / 2,
                    side * .46f,
                    ink,
                )

                1 -> {
                    val value = weather.temperatureText
                    val size = fitTemperature(value, side * .62f, side * .40f)
                    temperature(canvas, value, w / 2, h / 2 + size * .35f, size, Paint.Align.CENTER, ink)
                }

                else -> {
                    arrowTemperature(canvas, true, null, w / 2, h / 2 - side * .13f, side * .19f, ink)
                    arrowTemperature(canvas, false, null, w / 2, h / 2 + side * .13f, side * .19f, ink)
                }
            }
        } else if (kind == Kind.SQUARE && selectedPage == 0) {
            icons.draw(
                canvas,
                weather.weatherCode,
                weather.isDay,
                pad + side * .11f,
                pad + side * .11f,
                side * .22f,
                ink,
            )
            text(
                canvas,
                weather.conditionText,
                w - pad,
                pad + side * .07f,
                side * .075f,
                muted,
                Paint.Align.RIGHT,
                w * .45f,
            )
            temperature(
                canvas,
                weather.temperatureText,
                pad,
                h - pad,
                side * .34f,
                Paint.Align.LEFT,
                ink,
            )
        } else if (kind == Kind.SQUARE) {
            arrowTemperature(canvas, true, null, pad + side * .25f, pad + side * .14f, side * .19f, ink)
            arrowTemperature(canvas, false, null, pad + side * .25f, pad + side * .40f, side * .19f, ink)
            text(
                canvas,
                weather.conditionText,
                pad,
                h - pad,
                side * .09f,
                muted,
                Paint.Align.LEFT,
                w - pad * 2,
            )
        } else {
            NtWxExtraRenderer.draw(context, canvas, kind, w, h, style, weather, icons)
        }
        return bitmap
    }

    internal fun number(value: Double?): String = NtWxWeatherCode.number(value)

    private fun paint(color: Int, size: Float, align: Paint.Align = Paint.Align.LEFT): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.color = color
            textSize = size
            textAlign = align
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        }

    internal fun text(
        canvas: Canvas,
        value: String,
        x: Float,
        baseline: Float,
        size: Float,
        color: Int,
        align: Paint.Align,
        maxWidth: Float,
    ) {
        val paint = paint(color, size, align)
        val fitted = TextUtils.ellipsize(
            value,
            TextPaint(paint),
            maxWidth.coerceAtLeast(1f),
            TextUtils.TruncateAt.END,
        ).toString()
        canvas.drawText(fitted, x, baseline, paint)
    }

    internal fun fitTemperature(value: String, maxWidth: Float, requested: Float): Float {
        val paint = paint(Color.WHITE, requested)
        return min(requested, requested * maxWidth / (paint.measureText(value) + requested * .36f).coerceAtLeast(1f))
    }

    /** Source temp() draws eight degree dots, preserving its 0.36-size advance. */
    internal fun temperature(
        canvas: Canvas,
        value: String,
        anchorX: Float,
        baseline: Float,
        size: Float,
        align: Paint.Align,
        color: Int,
    ) {
        val paint = paint(color, size)
        val digitsWidth = paint.measureText(value)
        val total = digitsWidth + size * .36f
        val x = when (align) {
            Paint.Align.CENTER -> anchorX - total / 2
            Paint.Align.RIGHT -> anchorX - total
            else -> anchorX
        }
        canvas.drawText(value, x, baseline, paint)
        val cx = x + digitsWidth + size * .18f
        val cy = baseline - size * .58f
        for (index in 0..7) {
            val angle = index * Math.PI / 4
            canvas.drawCircle(
                cx + cos(angle).toFloat() * size * .12f,
                cy + sin(angle).toFloat() * size * .12f,
                size * .04f,
                paint,
            )
        }
    }

    internal fun arrowTemperature(
        canvas: Canvas,
        high: Boolean,
        value: Double?,
        x: Float,
        y: Float,
        size: Float,
        color: Int,
    ) {
        val valueText = number(value)
        val digits = paint(color, size).measureText(valueText) + size * .36f
        val left = x - (digits + size) / 2
        val centerX = left + size * .375f
        val radius = size * .25f
        val paint = paint(color, 1f).apply {
            style = Paint.Style.STROKE
            strokeWidth = size * .07f
            strokeCap = Paint.Cap.ROUND
        }
        val direction = if (high) -1f else 1f
        canvas.drawLine(centerX, y - radius, centerX, y + radius, paint)
        canvas.drawLine(centerX, y + direction * radius, centerX - radius * .6f, y, paint)
        canvas.drawLine(centerX, y + direction * radius, centerX + radius * .6f, y, paint)
        temperature(canvas, valueText, left + size, y + size * .36f, size, Paint.Align.LEFT, color)
    }

    internal fun condition(code: Int): String = when (code) {
        0 -> "Clear"
        1 -> "Mainly clear"
        2 -> "Partly cloudy"
        3 -> "Overcast"
        45, 48 -> "Fog"
        in 51..57 -> "Drizzle"
        in 61..67 -> "Rain"
        in 71..77 -> "Snow"
        in 80..82 -> "Showers"
        in 85..86 -> "Snow showers"
        in 95..99 -> "Thunderstorm"
        else -> "Weather"
    }
}
