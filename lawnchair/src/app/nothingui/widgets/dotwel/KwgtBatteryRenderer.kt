package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Readable Kotlin conversion of the author layer geometry in
 * AumGupta/KWGT-Widgets widgets/Nothing_Battery.kwgt (commit
 * 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained from preset.json:
 * - side = min(widget width, widget height)
 * - circle diameter = side / 2, vertical offset = 4 / 415 of side
 * - battery colour = cm(215, max(level,25)*2.55, max(level,33)*2.55)
 * - level rotation = level * 3.6 degrees
 * - percent text size = side / 9
 *
 * Substitutions: the bundled ndot-47.ttf is replaced by Dotwel's original
 * circular-dot glyphs. The author's sweep-gradient disc is rendered as the same
 * level-scaled arc plus a faint disc and track. Dotwel scales the whole gauge
 * proportionally to 92% of the short side so a 2x2 host is filled without
 * stretch, while the arc, colour formula, offset and text ratios are retained.
 * Sanitized source data: assets/kwgt/nothing_battery.sanitized.json.
 */
object KwgtBatteryRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        level: Int,
        includeBackground: Boolean = false,
    ): Bitmap {
        val safeLevel = level.coerceIn(0, 100)
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, safeWidth, safeHeight, style)
        } else {
            Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        val side = min(safeWidth, safeHeight).toFloat()
        // Fit the authored gauge to the available surface. The level arc, colour
        // formula, text and 4/415 offset keep their preset proportions; only the
        // overall scale is enlarged so a 2x2 host is not mostly empty.
        val gaugeSide = side * 0.92f
        val centerX = safeWidth / 2f
        val centerY = safeHeight / 2f + gaugeSide * (4f / 415f)
        val radius = gaugeSide * 0.36f
        val strokeWidth = (radius * 0.10f).coerceAtLeast(2f)
        val inset = strokeWidth / 2f
        val bounds = RectF(
            centerX - radius + inset,
            centerY - radius + inset,
            centerX + radius - inset,
            centerY + radius - inset,
        )

        val discPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = withAlpha(UpstreamNtDraw.muted(context, style), 0x30)
        }
        canvas.drawCircle(centerX, centerY, radius, discPaint)

        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = withAlpha(UpstreamNtDraw.muted(context, style), 0x24)
            this.style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
        }
        canvas.drawArc(bounds, 0f, 360f, false, trackPaint)

        if (safeLevel > 0) {
            val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = batteryColor(safeLevel)
                this.style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                this.strokeCap = Paint.Cap.ROUND
                UpstreamNtDraw.shadow(style, this)
            }
            canvas.drawArc(bounds, -90f, safeLevel * 3.6f, false, ringPaint)
        }

        val percentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = UpstreamNtDraw.ink(context, style)
            UpstreamNtDraw.shadow(style, this)
        }
        val label = "$safeLevel%"
        val pitch = DotGlyphFont.fitPitch(label, radius * 1.45f, radius * 0.95f)
        DotGlyphFont.drawCentered(
            canvas,
            label,
            centerX,
            centerY,
            pitch,
            percentPaint,
        )
        return bitmap
    }

    private fun batteryColor(level: Int): Int {
        val green = (maxOf(level, 25) * 2.55f).roundToInt().coerceIn(0, 255)
        val blue = (maxOf(level, 33) * 2.55f).roundToInt().coerceIn(0, 255)
        return Color.rgb(215, green, blue)
    }

    private fun withAlpha(color: Int, alpha: Int): Int = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
