package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Native renderer for Nothing_Digital4 from AumGupta/KWGT-Widgets
 * (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024
 * Om Gupta).
 *
 * Retained author geometry from preset.json:
 * - side = min(widget width, widget height)
 * - rounded surface corners = side / 5
 * - centre divider width = side * 2 / 277, the source 277-unit reference
 * - centre divider is the author primary red #FFD71921
 * - hour text = 12-hour hh, minute text = mm, both at nominal side * 28 / 277
 * - hour gap from the divider = side * 8 / 277
 * - minute gap from the divider = side * 10 / 277
 *
 * The source hour is on the left in primary red and the minute is on the right
 * in foreground ink. The source has no AM/PM layer, so both the styled bitmap
 * and the live fallback use a fixed 12-hour hh/mm composition.
 *
 * Font substitution: ndot-47.ttf is not redistributed. Dotwel's original
 * circular-dot glyphs replace it. A width pass shrinks the dot pitch so each
 * two-digit readout's actual ink stays inside its own half of the divider and
 * inside the host height. The divider is drawn full host height as requested,
 * rather than the preset's side-tall shape, so a resized tall host keeps the
 * visible split.
 *
 * Sanitized source data: assets/kwgt/nothing_digital4.sanitized.json.
 */
object KwgtDigital4Renderer {
    const val RED = 0xFFD71921.toInt()

    private const val REFERENCE = 277f
    private const val CORNER_RATIO = 1f / 5f
    private const val LINE_RATIO = 2f / REFERENCE
    private const val TEXT_RATIO = 28f / REFERENCE
    private const val HOUR_GAP_RATIO = 8f / REFERENCE
    private const val MINUTE_GAP_RATIO = 10f / REFERENCE
    private const val DOT_INK_ROWS = 6.8f
    private const val DOT_INK_X_MARGIN = 0.4f

    internal data class SplitLayout(
        val centerX: Float,
        val centerY: Float,
        val lineWidth: Float,
        val pitch: Float,
        val hourGap: Float,
        val minuteGap: Float,
        val hourInkWidth: Float,
        val minuteInkWidth: Float,
        val hourInkHeight: Float,
        val minuteInkHeight: Float,
        val hourCenterX: Float,
        val minuteCenterX: Float,
    ) {
        val hourLeft: Float get() = hourCenterX - hourInkWidth / 2f
        val hourRight: Float get() = hourCenterX + hourInkWidth / 2f
        val minuteLeft: Float get() = minuteCenterX - minuteInkWidth / 2f
        val minuteRight: Float get() = minuteCenterX + minuteInkWidth / 2f
    }

    /**
     * Pure layout math used by [render] and by unit assertions. The divider is
     * centred on the host width and spans the full host height. Text is fitted
     * to each half after subtracting the divider half-width and its source gap.
     */
    internal fun layout(
        width: Float,
        height: Float,
        hourText: String,
        minuteText: String,
    ): SplitLayout {
        val safeWidth = width.coerceAtLeast(1f)
        val safeHeight = height.coerceAtLeast(1f)
        val side = min(safeWidth, safeHeight)
        val centerX = safeWidth / 2f
        val centerY = safeHeight / 2f
        val lineWidth = side * LINE_RATIO
        val dividerHalf = lineWidth / 2f
        val hourGap = side * HOUR_GAP_RATIO
        val minuteGap = side * MINUTE_GAP_RATIO

        val hourColumns = max(1f, DotGlyphFont.columnsFor(hourText).toFloat())
        val minuteColumns = max(1f, DotGlyphFont.columnsFor(minuteText).toFloat())
        val nominalPitch = side * TEXT_RATIO / DotGlyphFont.ROWS

        val hourHalfWidth = (centerX - dividerHalf - hourGap).coerceAtLeast(0f)
        val minuteHalfWidth =
            (safeWidth - centerX - dividerHalf - minuteGap).coerceAtLeast(0f)
        val pitch = min(
            nominalPitch,
            min(
                hourHalfWidth / (hourColumns - DOT_INK_X_MARGIN),
                minuteHalfWidth / (minuteColumns - DOT_INK_X_MARGIN),
            ),
        ).let { min(it, safeHeight / DOT_INK_ROWS) }.coerceAtLeast(0f)

        val hourInkWidth = (hourColumns - DOT_INK_X_MARGIN) * pitch
        val minuteInkWidth = (minuteColumns - DOT_INK_X_MARGIN) * pitch
        val hourRight = centerX - dividerHalf - hourGap
        val minuteLeft = centerX + dividerHalf + minuteGap
        return SplitLayout(
            centerX = centerX,
            centerY = centerY,
            lineWidth = lineWidth,
            pitch = pitch,
            hourGap = hourGap,
            minuteGap = minuteGap,
            hourInkWidth = hourInkWidth,
            minuteInkWidth = minuteInkWidth,
            hourInkHeight = DOT_INK_ROWS * pitch,
            minuteInkHeight = DOT_INK_ROWS * pitch,
            hourCenterX = hourRight - hourInkWidth / 2f,
            minuteCenterX = minuteLeft + minuteInkWidth / 2f,
        )
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        date: Calendar = Calendar.getInstance(),
        includeBackground: Boolean = true,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(
            safeWidth,
            safeHeight,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val side = min(safeWidth, safeHeight).toFloat()
        val boundary = layout(
            safeWidth.toFloat(),
            safeHeight.toFloat(),
            hourText(date),
            minuteText(date),
        )

        if (includeBackground) {
            val background = UpstreamNtDraw.background(context, style)
            if (Color.alpha(background) != 0) {
                val radius = side * CORNER_RATIO
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
                canvas.drawRoundRect(
                    RectF(0f, 0f, safeWidth.toFloat(), safeHeight.toFloat()),
                    radius,
                    radius,
                    paint,
                )
            }
        }

        val dividerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = RED }
        canvas.drawRect(
            boundary.centerX - boundary.lineWidth / 2f,
            0f,
            boundary.centerX + boundary.lineWidth / 2f,
            safeHeight.toFloat(),
            dividerPaint,
        )

        if (boundary.pitch <= 0f) return bitmap

        val hourPaint = dotPaint(style, RED)
        val minutePaint = dotPaint(style, UpstreamNtDraw.ink(context, style))
        DotGlyphFont.drawCentered(
            canvas,
            hourText(date),
            boundary.hourCenterX,
            boundary.centerY,
            boundary.pitch,
            hourPaint,
        )
        DotGlyphFont.drawCentered(
            canvas,
            minuteText(date),
            boundary.minuteCenterX,
            boundary.centerY,
            boundary.pitch,
            minutePaint,
        )
        return bitmap
    }

    fun hourText(date: Calendar): String = SimpleDateFormat("hh", Locale.getDefault()).format(date.time)

    fun minuteText(date: Calendar): String = SimpleDateFormat("mm", Locale.getDefault()).format(date.time)

    private fun dotPaint(style: WidgetStyle, color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        this.color = color
        UpstreamNtDraw.shadow(style, this)
    }
}
