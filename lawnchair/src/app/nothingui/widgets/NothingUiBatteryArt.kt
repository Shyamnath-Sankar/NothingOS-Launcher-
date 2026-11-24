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

package app.nothingui.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.Size
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.ColorUtils
import app.nothingui.theme.NothingUiPalette
import kotlin.math.min

/**
 * Original circular battery art for the square 2×2 home widget.
 *
 * The circular face, ring, dot-matrix numerals and charging marker are drawn from the real sticky
 * battery level; there is no sample/placeholder percentage. The surface and content colours are
 * resolved by the provider from [NothingUiWidgetColors], so the face stays a deliberate charcoal/
 * white or paper/ink pair even when the update arrives from a non-themed context. A missing or
 * invalid level renders a neutral `--` fallback. The bitmap is created at the widget's own bounded
 * size (see [NothingUiWidgetBudget]), never at a fixed display-sized resolution.
 */
object NothingUiBatteryArt {

    private const val UNKNOWN = "--"
    private const val LOW_PERCENT = 15

    fun render(
        context: Context,
        percent: Int,
        charging: Boolean,
        size: Size,
        surfaceColor: Int,
        contentColor: Int,
    ): Bitmap {
        val width = size.width.coerceAtLeast(1)
        val height = size.height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val offColor = ColorUtils.setAlphaComponent(contentColor, OFF_ALPHA)
        val accentColor = NothingUiPalette.AccentRed.toArgb()

        val diameter = min(width, height) * FACE_FRACTION
        val stroke = (diameter * 0.06f).coerceAtLeast(2f)
        val radius = (diameter - stroke) / 2f
        val centerX = width / 2f
        val centerY = height / 2f

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.style = Paint.Style.FILL
        paint.color = surfaceColor
        canvas.drawCircle(centerX, centerY, diameter / 2f, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = stroke
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = offColor
        canvas.drawCircle(centerX, centerY, radius, paint)

        if (percent >= 0) {
            paint.color = if (percent <= LOW_PERCENT) accentColor else contentColor
            val oval = RectF(
                centerX - radius,
                centerY - radius,
                centerX + radius,
                centerY + radius,
            )
            canvas.drawArc(oval, START_ANGLE, SWEEP * percent / 100f, false, paint)
        }

        val label = if (percent >= 0) "$percent%" else UNKNOWN
        val inner = radius * 2f * 0.62f
        val density = context.resources.configuration.densityDpi / 160f
        val innerDp = inner / density
        val pitchDp = DotText.pitchFor(label, innerDp, innerDp)
        val art = DotText.art(
            text = label,
            pitchDp = pitchDp,
            density = density,
            lit = contentColor,
            matrixColor = offColor,
            matrix = percent >= 0,
        )
        canvas.drawBitmap(
            art.bmp,
            centerX - art.bmp.width / 2f,
            centerY - art.bmp.height / 2f,
            null,
        )

        if (charging) {
            paint.style = Paint.Style.FILL
            paint.color = accentColor
            canvas.drawCircle(centerX, centerY - radius, stroke * 0.85f, paint)
        }

        return bitmap
    }

    fun contentDescription(percent: Int, charging: Boolean): String {
        val value = if (percent >= 0) "$percent%" else UNKNOWN
        return if (charging) "$value, charging" else value
    }

    private const val OFF_ALPHA = 44
    private const val START_ANGLE = -90f
    private const val SWEEP = 360f
    private const val FACE_FRACTION = 0.98f
}
