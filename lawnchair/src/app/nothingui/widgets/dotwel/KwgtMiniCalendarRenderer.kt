package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min

/**
 * Native renderer for Nothing_Mini_Calender from
 * AumGupta/KWGT-Widgets (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f,
 * MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained author relationships:
 * - weekday `EEE` at `side / 6.291`, two-digit `dd` at `side / 3.282`
 * - five relative-day columns at offsets -2, -1, today, +1, +2
 * - outer columns use the source `accent` (ink at 50% alpha); inner columns and
 *   today use full ink
 * - today has a rounded highlight of `widgetWidth / 5` and a primary
 *   `#FFD71921` dot below the date
 * - the source horizontal margin is 58 of a 916-wide preset, scaled with the
 *   host width
 *
 * Deliberate host adaptation: the source is a wide 916x226 strip whose narrow
 * centre day was the practical result of the upstream preview host aspect ratio.
 * This renderer keeps that natural wide aspect. When the host is more square
 * than the source (the gallery tile), the strip is centred in a letterboxed band
 * instead of stretching a row across the full square, and the today highlight is
 * limited to that band. The source ndot-47.ttf is replaced with Dotwel's
 * app-owned [DotGlyphFont]; no font file is copied.
 *
 * The source highlight is `bg` (contrasting wallpaper tone). Dotwel replaces it
 * with a low-alpha ink wash so it remains visible over all three app-owned
 * widget backgrounds instead of disappearing into the black style.
 *
 * Fitting: the source text-size divisors limit each glyph's ink height. Width is
 * limited by the real dot extent (`columns - 1 + 2 * radius`, not the nominal
 * `columns` count), so a three-letter weekday cannot spill out of its own column
 * or under the adjacent today highlight. Both weekday and date rows use their own
 * height divisor.
 *
 * Sanitized source data: assets/kwgt/nothing_mini_calender.sanitized.json.
 */
object KwgtMiniCalendarRenderer {
    private const val RED = 0xFFD71921.toInt()
    private const val WEEKDAY_DIVISOR = 6.291f
    private const val DATE_DIVISOR = 3.282f
    private const val SOURCE_WIDTH = 916f
    private const val SOURCE_HEIGHT = 226f
    private const val SOURCE_MARGIN = 58f
    private const val NATURAL_ASPECT = SOURCE_WIDTH / SOURCE_HEIGHT

    /** Drawn ink bounds of one [DotGlyphFont] glyph: 6 pitches plus 0.4 each end. */
    private const val DOT_BOUND_ROWS = 6.8f
    private const val GLYPH_RADIUS_RATIO = 0.40f
    private const val CONTENT_VERTICAL_RATIO = 0.92f
    private const val COLUMN_TEXT_RATIO = 0.92f
    private const val DOT_RADIUS_RATIO = 0.0397f
    private const val DOT_GAP_RATIO = 0.053f
    private const val ROW_GAP_RATIO = 0.02f
    private const val HIGHLIGHT_ALPHA = 0x24
    private const val ACCENT_ALPHA = 0x80

    internal data class ColumnLayout(
        val day: MiniCalendarDay,
        val centerX: Float,
        val cellLeft: Float,
        val cellRight: Float,
        val weekdayPitch: Float,
        val datePitch: Float,
        val weekdayCenterY: Float,
        val dateCenterY: Float,
        val dotRadius: Float,
        val dotCenterY: Float,
    )

    internal data class StripLayout(
        val stripTop: Float,
        val stripHeight: Float,
        val contentTop: Float,
        val contentBottom: Float,
        val columnWidth: Float,
        val gap: Float,
        val highlightLeft: Float,
        val highlightTop: Float,
        val highlightRight: Float,
        val highlightBottom: Float,
        val columns: List<ColumnLayout>,
    ) {
        val stripBottom: Float get() = stripTop + stripHeight
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
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, safeWidth, safeHeight, style)
        } else {
            Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        val ink = UpstreamNtDraw.ink(context, style)
        val accent = withAlpha(ink, ACCENT_ALPHA)
        val todayHighlight = withAlpha(ink, HIGHLIGHT_ALPHA)
        val days = KwgtMiniCalendarDates.days(date)
        val layout = layoutStrip(safeWidth, safeHeight, days)

        drawTodayHighlight(
            canvas = canvas,
            layout = layout,
            color = todayHighlight,
        )

        layout.columns.forEach { column ->
            val color = if (column.day.offset == -2 || column.day.offset == 2) accent else ink
            drawColumn(
                canvas = canvas,
                style = style,
                column = column,
                color = color,
            )
        }
        return bitmap
    }

    /**
     * Pure layout math shared by [render] and the unit assertions. All values are
     * bitmap pixels. The vertical band is the source strip aspect fitted inside
     * the host, so a square host letterboxes rather than stretching the row.
     */
    internal fun layoutStrip(
        width: Int,
        height: Int,
        days: List<MiniCalendarDay>,
    ): StripLayout {
        val w = width.coerceAtLeast(1).toFloat()
        val h = height.coerceAtLeast(1).toFloat()
        val side = min(w, h)

        val stripHeight = min(h, w / NATURAL_ASPECT).coerceAtLeast(1f)
        val stripTop = (h - stripHeight) / 2f
        val stripSide = min(side, stripHeight)

        val margin = w * (SOURCE_MARGIN / SOURCE_WIDTH)
        val gap = max(1f, w * 0.005f)
        val columnWidth = ((w - 2f * margin - 4f * gap) / 5f).coerceAtLeast(1f)
        val highlightWidth = (w / 5f).coerceAtLeast(1f)

        // The source highlight is widgetWidth / 5, wider than the inner column.
        // Keep every glyph clear of the adjacent highlight as well as its cell.
        val neighbourDistance = columnWidth + gap / 2f
        val highlightGuard = 2f * neighbourDistance - highlightWidth
        val maxGlyphWidth = min(
            columnWidth * COLUMN_TEXT_RATIO,
            if (highlightGuard > 0f) highlightGuard else columnWidth * COLUMN_TEXT_RATIO,
        ).coerceAtLeast(1f)

        var weekdayPitch = days.minOfOrNull { day ->
            min(
                widthPitch(day.weekday, maxGlyphWidth),
                heightPitch(side / WEEKDAY_DIVISOR),
            )
        }?.coerceAtLeast(0f) ?: 0f
        var datePitch = days.minOfOrNull { day ->
            min(
                widthPitch(day.day, maxGlyphWidth),
                heightPitch(side / DATE_DIVISOR),
            )
        }?.coerceAtLeast(0f) ?: 0f

        var dotRadius = max(1f, stripSide * DOT_RADIUS_RATIO)
        var rowGap = max(1f, stripSide * ROW_GAP_RATIO)
        var dotGap = max(1f, stripSide * DOT_GAP_RATIO)
        var total = totalHeight(weekdayPitch, datePitch, rowGap, dotGap, dotRadius)

        val available = stripHeight * CONTENT_VERTICAL_RATIO
        if (total > available && total > 0f) {
            val scale = available / total
            weekdayPitch *= scale
            datePitch *= scale
            dotRadius = max(0.6f, dotRadius * scale)
            rowGap *= scale
            dotGap *= scale
        }

        val weekdayHeight = weekdayPitch * DOT_BOUND_ROWS
        val dateHeight = datePitch * DOT_BOUND_ROWS
        total = totalHeight(weekdayPitch, datePitch, rowGap, dotGap, dotRadius)
        val contentTop = stripTop + (stripHeight - total) / 2f

        val weekdayCenterY = contentTop + weekdayHeight / 2f
        val dateCenterY = contentTop + weekdayHeight + rowGap + dateHeight / 2f
        val dotCenterY = contentTop + weekdayHeight + rowGap + dateHeight +
            dotGap + dotRadius

        val startX = margin + gap / 2f + columnWidth / 2f
        val columns = days.mapIndexed { index, day ->
            val centerX = startX + index * (columnWidth + gap)
            ColumnLayout(
                day = day,
                centerX = centerX,
                cellLeft = centerX - columnWidth / 2f,
                cellRight = centerX + columnWidth / 2f,
                weekdayPitch = weekdayPitch,
                datePitch = datePitch,
                weekdayCenterY = weekdayCenterY,
                dateCenterY = dateCenterY,
                dotRadius = dotRadius,
                dotCenterY = dotCenterY,
            )
        }

        val highlightHalfHeight = stripHeight * 0.49f
        val stripCenterY = stripTop + stripHeight / 2f
        return StripLayout(
            stripTop = stripTop,
            stripHeight = stripHeight,
            contentTop = contentTop,
            contentBottom = contentTop + total,
            columnWidth = columnWidth,
            gap = gap,
            highlightLeft = w / 2f - highlightWidth / 2f,
            highlightTop = stripCenterY - highlightHalfHeight,
            highlightRight = w / 2f + highlightWidth / 2f,
            highlightBottom = stripCenterY + highlightHalfHeight,
            columns = columns,
        )
    }

    /** Actual drawn width of [text] at [pitch], including the end dot radii. */
    internal fun glyphWidth(text: String, pitch: Float): Float {
        val columns = DotGlyphFont.columnsFor(text)
        if (columns <= 0 || pitch <= 0f) return 0f
        return (columns - 1 + 2f * GLYPH_RADIUS_RATIO) * pitch
    }

    private fun widthPitch(text: String, maxWidth: Float): Float {
        if (maxWidth <= 0f) return 0f
        val units = DotGlyphFont.columnsFor(text) - 1 + 2f * GLYPH_RADIUS_RATIO
        return if (units <= 0f) 0f else maxWidth / units
    }

    private fun heightPitch(maxHeight: Float): Float = if (maxHeight <= 0f) 0f else maxHeight / DOT_BOUND_ROWS

    private fun drawTodayHighlight(
        canvas: Canvas,
        layout: StripLayout,
        color: Int,
    ) {
        if (Color.alpha(color) == 0) return
        val highlightHeight = layout.highlightBottom - layout.highlightTop
        if (highlightHeight <= 0f) return
        val width = layout.highlightRight - layout.highlightLeft
        if (width <= 0f) return
        val corner = min(width, highlightHeight) * 0.16f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawRoundRect(
            RectF(
                layout.highlightLeft,
                layout.highlightTop,
                layout.highlightRight,
                layout.highlightBottom,
            ),
            corner,
            corner,
            paint,
        )
    }

    private fun drawColumn(
        canvas: Canvas,
        style: WidgetStyle,
        column: ColumnLayout,
        color: Int,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.color = color
            UpstreamNtDraw.shadow(style, this)
        }
        DotGlyphFont.drawCentered(
            canvas,
            column.day.weekday,
            column.centerX,
            column.weekdayCenterY,
            column.weekdayPitch,
            paint,
        )
        DotGlyphFont.drawCentered(
            canvas,
            column.day.day,
            column.centerX,
            column.dateCenterY,
            column.datePitch,
            paint,
        )
        if (column.day.isToday) {
            val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = RED
                UpstreamNtDraw.shadow(style, this)
            }
            canvas.drawCircle(column.centerX, column.dotCenterY, column.dotRadius, dotPaint)
        }
    }

    private fun totalHeight(
        weekdayPitch: Float,
        datePitch: Float,
        rowGap: Float,
        dotGap: Float,
        dotRadius: Float,
    ): Float = (weekdayPitch + datePitch) * DOT_BOUND_ROWS + rowGap + dotGap +
        dotRadius * 2f

    private fun withAlpha(color: Int, alpha: Int): Int = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
