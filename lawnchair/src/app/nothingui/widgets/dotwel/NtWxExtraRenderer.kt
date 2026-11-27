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
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.sin

/**
 * Native translation of the AwesomeAWidgets `NtWxDraw.render` kinds 2-8
 * (commit 0fae607, MIT, Copyright (c) 2026 Sameer Al Sahab).
 *
 * The launcher render state has no forecast days, solar instants, AQI or
 * precipitation probability, so those fields are drawn as `--` rather than a
 * fabricated value. The geometry and page behaviour follow the source.
 */
internal object NtWxExtraRenderer {
    private fun paint(color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

    fun draw(
        context: Context,
        canvas: Canvas,
        kind: NtWxRenderer.Kind,
        w: Float,
        h: Float,
        style: WidgetStyle,
        weather: NtWxWeather,
        icons: NtWxRenderer.IconDrawer,
    ) {
        val side = minOf(w, h)
        val pad = side * .1f
        val ink = UpstreamNtDraw.ink(context, style)
        val muted = UpstreamNtDraw.muted(context, style)
        val bg = UpstreamNtDraw.background(context, style)
        val accent = UpstreamNtDraw.accent(context, style)

        fun text(
            value: String,
            x: Float,
            y: Float,
            size: Float,
            color: Int = ink,
            align: Paint.Align = Paint.Align.LEFT,
            max: Float = w,
        ) = NtWxRenderer.text(canvas, value, x, y, size, color, align, max)

        fun temp(
            value: Double?,
            x: Float,
            y: Float,
            size: Float,
            align: Paint.Align = Paint.Align.LEFT,
        ) = NtWxRenderer.temperature(canvas, NtWxRenderer.number(value), x, y, size, align, ink)

        when (kind) {
            NtWxRenderer.Kind.RECT -> {
                val split = w * .38f
                icons.draw(
                    canvas,
                    weather.weatherCode,
                    weather.isDay,
                    pad + h * .11f,
                    pad + h * .11f,
                    h * .22f,
                    ink,
                )
                temp(weather.forecast?.temperatureCelsius, pad, h * .66f, h * .36f)
                text(
                    weather.conditionText,
                    pad,
                    h - pad,
                    h * .075f,
                    muted,
                    max = split - pad,
                )
                val line = paint((ink and 0xFFFFFF) or (40 shl 24)).apply {
                    strokeWidth = maxOf(1f, h * .008f)
                }
                canvas.drawLine(split, pad, split, h - pad, line)
                text(
                    "Forecast unavailable",
                    split + (w - split - pad) / 2f,
                    h * .52f,
                    h * .085f,
                    muted,
                    Paint.Align.CENTER,
                    w - split - pad,
                )
            }

            NtWxRenderer.Kind.COMBO -> {
                val gap = side * .03f
                val radius = side * .13f
                val tile = if (Color.alpha(bg) > 0) bg else (ink and 0xFFFFFF) or (40 shl 24)
                listOf(
                    RectF(0f, 0f, w, h / 2 - gap),
                    RectF(0f, h / 2 + gap, w / 2 - gap, h),
                    RectF(w / 2 + gap, h / 2 + gap, w, h),
                ).forEach { canvas.drawRoundRect(it, radius, radius, paint(tile)) }
                val iconY = h * .25f - gap / 2
                icons.draw(
                    canvas,
                    weather.weatherCode,
                    weather.isDay,
                    side * .17f,
                    iconY,
                    side * .22f,
                    ink,
                )
                text(
                    weather.conditionText,
                    side * .33f,
                    iconY + side * .035f,
                    side * .1f,
                    max = w - side * .4f,
                )
                val value = weather.temperatureText
                val size = NtWxRenderer.fitTemperature(value, w / 2 - side * .2f, side * .26f)
                NtWxRenderer.temperature(
                    canvas,
                    value,
                    w / 4 - gap / 2,
                    h * .75f + gap / 2 + size * .36f,
                    size,
                    Paint.Align.CENTER,
                    ink,
                )
                NtWxRenderer.arrowTemperature(
                    canvas,
                    true,
                    null,
                    w * .75f + gap / 2,
                    h * .75f - side * .07f,
                    side * .12f,
                    ink,
                )
                NtWxRenderer.arrowTemperature(
                    canvas,
                    false,
                    null,
                    w * .75f + gap / 2,
                    h * .75f + side * .11f,
                    side * .12f,
                    ink,
                )
            }

            NtWxRenderer.Kind.SUNSET -> sunset(canvas, w, h, ink)

            NtWxRenderer.Kind.AIR -> {
                val band = NtWxWeatherCode.airBand(null)
                val x = h * .3f
                text("US AQI", x, h * .36f, h * .15f, muted, max = w * .4f)
                text(NtWxWeatherCode.UNKNOWN, x, h * .8f, h * .4f, max = w * .4f)
                val labels = arrayOf("--", "Good", "Moderate", "Sensitive", "Unhealthy", "Very unhealthy", "Hazardous")
                text(labels[band], w - x, h * .36f, h * .15f, align = Paint.Align.RIGHT, max = w * .42f)
                for (index in 1..6) {
                    val selected = index == band
                    val color = if (selected) accent else (ink and 0xFFFFFF) or (90 shl 24)
                    canvas.drawCircle(
                        w - x - (6 - index) * h * .13f - h * .045f,
                        h * .7f,
                        h * .045f * (if (selected) 1.5f else 1f),
                        paint(color),
                    )
                }
            }

            NtWxRenderer.Kind.W1_TEMP -> {
                val value = weather.temperatureText
                val size = NtWxRenderer.fitTemperature(value, side * .62f, side * .4f)
                NtWxRenderer.temperature(canvas, value, w / 2, h / 2 + size * .35f, size, Paint.Align.CENTER, ink)
            }

            NtWxRenderer.Kind.W1_STATUS -> icons.draw(
                canvas,
                weather.weatherCode,
                weather.isDay,
                w / 2,
                h / 2,
                side * .5f,
                ink,
            )

            NtWxRenderer.Kind.W1_RAIN -> {
                icons.draw(canvas, 61, true, w / 2, h * .4f, side * .46f, ink)
                text("--%", w / 2, h * .8f, side * .17f, align = Paint.Align.CENTER, max = side * .8f)
            }

            NtWxRenderer.Kind.CIRCLE, NtWxRenderer.Kind.SQUARE -> Unit
        }
    }

    fun airBand(value: Int?): Int = NtWxWeatherCode.airBand(value)

    private fun sunset(canvas: Canvas, w: Float, h: Float, ink: Int) {
        val left = h * .3f
        val right = w - left
        NtWxRenderer.text(canvas, "--:--", left, h * .36f, h * .17f, ink, Paint.Align.LEFT, w * .35f)
        NtWxRenderer.text(canvas, "--:--", right, h * .36f, h * .17f, ink, Paint.Align.RIGHT, w * .35f)
        val base = h * .66f
        val amplitude = h * .24f
        val dots = paint((ink and 0xFFFFFF) or (110 shl 24))
        var x = left
        while (x <= right) {
            canvas.drawCircle(x, base, h * .012f, dots)
            x += h * .075f
        }
        val path = Path()
        for (index in 0..60) {
            val fraction = -.28f + index * 1.56f / 60
            val px = left + (right - left) * (fraction + .28f) / 1.56f
            val py = base - sin(fraction * Math.PI).toFloat() * amplitude
            if (index == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        val paint = paint((ink and 0xFFFFFF) or (150 shl 24)).apply {
            style = Paint.Style.STROKE
            strokeWidth = maxOf(1.5f, h * .015f)
        }
        canvas.drawPath(path, paint)
    }
}
