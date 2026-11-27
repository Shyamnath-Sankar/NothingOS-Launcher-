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
 * Readable Kotlin conversion of the author layer geometry in
 * AumGupta/KWGT-Widgets widgets/Nothing_Date_Time.kwgt (commit
 * 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained from preset.json:
 * - side = min(widget width, widget height)
 * - rounded background corners = side / 5 (preset literal 58)
 * - left stack offset x = side / 8.5
 * - four text rows: EEE, hh:mma, MMMM, d + ordinal suffix
 * - text size side / 7 for weekday, month and day; side / 6 for the time
 * - primary colour #FFD71921 for the time row
 *
 * Deliberate legibility adaptation, not exact preset geometry: the source
 * stack margin is -4 preset units (-4/415 of side). Dotwel's 5x7 glyphs fill
 * their line box with visible dots (6.8 pitches tall), so that negative margin
 * made adjacent rows physically collide. This renderer keeps the source
 * proportions but uses a positive clear gap and fits the whole stack inside
 * the host height with padding. It is not a pixel-exact reproduction of the
 * upstream KWGT composition.
 *
 * Substitutions: the bundled ndot-47.ttf is replaced by Dotwel's original
 * circular-dot glyphs. Each row is width-fitted so long localized month names
 * do not clip. Sanitized source data:
 * assets/kwgt/nothing_date_time.sanitized.json.
 */
object KwgtDateTimeRenderer {
    private const val ACCENT = 0xFFD71921.toInt()
    private const val CORNER_RATIO = 1f / 5f
    private const val LEFT_RATIO = 1f / 8.5f
    private const val RIGHT_PADDING_RATIO = 1f / 20f

    /** Vertical extent of the drawn dots: 6 pitches between row centres plus 0.4 each side. */
    private const val DOT_BOUND_ROWS = 6.8f
    private const val VERTICAL_GAP_RATIO = 0.045f
    private const val MIN_ROW_CLEARANCE_PITCHES = 1.5f
    private const val VERTICAL_PADDING_RATIO = 0.04f

    private data class Line(val text: String, val baseTextSize: Float, val color: Int)

    internal data class FittedRow(
        val pitch: Float,
        val top: Float,
        val height: Float,
        val gapAfter: Float,
    ) {
        val centerY: Float get() = top + height / 2f
        val bottom: Float get() = top + height
    }

    /**
     * Pure layout math used by [render] and by unit assertions. All values are
     * in bitmap pixels; [side] is the short side used by the source preset.
     */
    internal fun fitRows(
        texts: List<String>,
        baseTextSizes: List<Float>,
        side: Float,
        width: Float,
        height: Float,
    ): List<FittedRow> {
        require(texts.size == baseTextSizes.size) { "text and size counts differ" }
        if (texts.isEmpty()) return emptyList()

        val left = side * LEFT_RATIO
        val maxTextWidth = (width - left - side * RIGHT_PADDING_RATIO).coerceAtLeast(1f)
        val basePitches = texts.mapIndexed { index, text ->
            val columns = DotGlyphFont.columnsFor(text).coerceAtLeast(1)
            min(baseTextSizes[index] / DotGlyphFont.ROWS, maxTextWidth / columns)
        }

        val padding = side * VERTICAL_PADDING_RATIO
        val available = (height - 2f * padding).coerceAtLeast(1f)
        val rawGap = side * VERTICAL_GAP_RATIO
        val maxAffordableGap = available / (2f * (texts.size - 1).coerceAtLeast(1))
        val minGap = min(rawGap, maxAffordableGap)

        var scale = 1f
        var pitches = basePitches
        var gaps = gapsFor(pitches, minGap)
        var total = totalFor(pitches, gaps)
        repeat(8) {
            if (total > available) {
                scale *= available / total
                pitches = basePitches.map { it * scale }
                gaps = gapsFor(pitches, minGap)
                total = totalFor(pitches, gaps)
            }
        }
        if (total > available) {
            val excessPerRow = (total - available) / pitches.size
            pitches = pitches.map { (it - excessPerRow / DOT_BOUND_ROWS).coerceAtLeast(0f) }
            gaps = gapsFor(pitches, minGap)
            total = totalFor(pitches, gaps)
        }

        var top = (height - total) / 2f
        return texts.indices.map { index ->
            val rowHeight = pitches[index] * DOT_BOUND_ROWS
            val row = FittedRow(
                pitch = pitches[index],
                top = top,
                height = rowHeight,
                gapAfter = if (index < gaps.size) gaps[index] else 0f,
            )
            top += rowHeight + row.gapAfter
            row
        }
    }

    private fun gapsFor(pitches: List<Float>, minGap: Float): List<Float> = (0 until (pitches.size - 1).coerceAtLeast(0)).map { index ->
        max(minGap, MIN_ROW_CLEARANCE_PITCHES * min(pitches[index], pitches[index + 1]))
    }

    private fun totalFor(pitches: List<Float>, gaps: List<Float>): Float {
        var total = 0f
        pitches.forEach { total += it * DOT_BOUND_ROWS }
        gaps.forEach { total += it }
        return total
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        date: Calendar = Calendar.getInstance(),
        includeBackground: Boolean = false,
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

        val locale = Locale.getDefault()
        val weekday = SimpleDateFormat("EEE", locale)
            .format(date.time)
            .uppercase(locale)
        val time = SimpleDateFormat("hh:mma", locale)
            .format(date.time)
            .uppercase(locale)
        val month = SimpleDateFormat("MMMM", locale)
            .format(date.time)
            .uppercase(locale)
        val dayNumber = date.get(Calendar.DAY_OF_MONTH)
        val day = "$dayNumber${ordinalSuffix(dayNumber)}".uppercase(locale)

        val ink = UpstreamNtDraw.ink(context, style)
        val lines = listOf(
            Line(weekday, side / 7f, ink),
            Line(time, side / 6f, ACCENT),
            Line(month, side / 7f, ink),
            Line(day, side / 7f, ink),
        )

        val left = side * LEFT_RATIO
        val fitted = fitRows(
            texts = lines.map { it.text },
            baseTextSizes = lines.map { it.baseTextSize },
            side = side,
            width = safeWidth.toFloat(),
            height = safeHeight.toFloat(),
        )

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
        lines.forEachIndexed { index, line ->
            paint.color = line.color
            paint.setShadowLayer(0f, 0f, 0f, 0)
            UpstreamNtDraw.shadow(style, paint)
            DotGlyphFont.drawLeft(
                canvas,
                line.text,
                left,
                fitted[index].centerY,
                fitted[index].pitch,
                paint,
            )
        }
        return bitmap
    }

    fun ordinalSuffix(dayOfMonth: Int): String {
        if (dayOfMonth % 100 in 11..13) return "TH"
        return when (dayOfMonth % 10) {
            1 -> "ST"
            2 -> "ND"
            3 -> "RD"
            else -> "TH"
        }
    }
}
