package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.min

/**
 * Readable Kotlin conversion of the author layer geometry in
 * AumGupta/KWGT-Widgets widgets/Nothing_Battery_Mini.kwgt (commit
 * 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained from preset.json: the author's `w = 251`, `side = 277` and eleven
 * concentric ProgressModule rings with `style_size = w / {1.38, 1.23, 1.1, 1.1,
 * 1.005, 1.005, 1.005, 1.1, 1.1, 1.23, 1.38}` and `progress_level = bi(level)`.
 * The foreground colour is the author primary `#FFD71921`; the track is the
 * author accent formula `ce(fg, alpha, 20)`. The preset contains no text layer;
 * Dotwel adds a centered real-level dot readout for legibility, so no charge
 * state or number is invented and the ring geometry stays the author's.
 *
 * Sanitized source data: assets/kwgt/nothing_battery_mini.sanitized.json.
 */
object KwgtBatteryMiniRenderer {
    private const val AUTHOR_SIDE = 277f
    private const val AUTHOR_WIDTH = 251f

    private val DIVISORS = floatArrayOf(
        1.38f,
        1.23f,
        1.1f,
        1.1f,
        1.005f,
        1.005f,
        1.005f,
        1.1f,
        1.1f,
        1.23f,
        1.38f,
    )

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
        val centerX = safeWidth / 2f
        val centerY = safeHeight / 2f
        val baseDiameter = side * (AUTHOR_WIDTH / AUTHOR_SIDE)
        val trackColor = withAlpha(UpstreamNtDraw.ink(context, style), 0x33)
        val foreground = UpstreamNtDraw.accent(context, style)

        DIVISORS.forEach { divisor ->
            val diameter = baseDiameter / divisor
            val radius = diameter / 2f
            val stroke = (diameter * 0.012f).coerceAtLeast(1.5f)
            val inset = stroke / 2f
            val bounds = RectF(
                centerX - radius + inset,
                centerY - radius + inset,
                centerX + radius - inset,
                centerY + radius - inset,
            )
            val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = trackColor
                this.style = Paint.Style.STROKE
                strokeWidth = stroke
            }
            canvas.drawCircle(centerX, centerY, radius - inset, track)
            if (safeLevel > 0) {
                val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = foreground
                    this.style = Paint.Style.STROKE
                    strokeWidth = stroke
                    strokeCap = Paint.Cap.ROUND
                    UpstreamNtDraw.shadow(style, this)
                }
                canvas.drawArc(bounds, -90f, safeLevel * 3.6f, false, arc)
            }
        }

        // Dotwel addition for legibility: the preset has no text layer, so show
        // the real system level with the app-owned dot glyphs. No charge state or
        // number is invented. The ring geometry above stays the author's.
        val label = "$safeLevel%"
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = UpstreamNtDraw.ink(context, style)
            UpstreamNtDraw.shadow(style, this)
        }
        val pitch = DotGlyphFont.fitPitch(
            label,
            baseDiameter * 0.50f,
            baseDiameter * 0.30f,
        )
        DotGlyphFont.drawCentered(
            canvas,
            label,
            centerX,
            centerY,
            pitch,
            labelPaint,
        )
        return bitmap
    }

    private fun withAlpha(color: Int, alpha: Int): Int = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
