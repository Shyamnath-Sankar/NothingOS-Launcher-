package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Native renderer for Nothing_Date_Time2 from
 * AumGupta/KWGT-Widgets (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f,
 * MIT, Copyright (c) 2024 Om Gupta).
 *
 * Retained author geometry from preset.json:
 * - side = min(widget width, widget height)
 * - rounded surface corners = side / 5
 * - left information offset = side / 8.5
 * - abbreviated weekday text = side / 10, huge day text = side / 4
 * - clock group left padding = side / 2.5
 * - hour and minute discs = side / 5 diameter
 * - hour smooth rotation = (hour + minute / 60) * 30 degrees
 * - minute rotation = minute * 6 degrees
 * - radial notch width = side / 69.25
 * - hour notch length = side / 28, offset = side / 6.1
 * - minute notch length = side / 12, offset = side / 8.5
 * - primary red = #FFD71921
 *
 * Font substitution: the source NType82 regular/headline fonts are not
 * redistributable here. This renderer uses the Android platform serif regular
 * and bold headlines, with a fit-down guard so substituted glyph metrics never
 * clip the composition.
 *
 * Sanitized source data: assets/kwgt/nothing_date_time2.sanitized.json.
 */
object KwgtDateTime2Renderer {
    private const val RED = 0xFFD71921.toInt()
    private const val TRANSPARENT_NOTCH = 0xCC000000.toInt()

    private const val CORNER_RATIO = 1f / 5f
    private const val LEFT_RATIO = 1f / 8.5f
    private const val RIGHT_RATIO = 1f / 8.5f
    private const val TOP_RATIO = 0.06f

    private const val WEEKDAY_TEXT_RATIO = 1f / 10f
    private const val DAY_TEXT_RATIO = 1f / 4f
    private const val CLOCK_TEXT_RATIO = 1f / 10f

    private const val DISC_DIAMETER_RATIO = 1f / 5f
    private const val HOUR_NOTCH_LENGTH_RATIO = 1f / 28f
    private const val HOUR_NOTCH_OFFSET_RATIO = 1f / 6.1f
    private const val MINUTE_NOTCH_LENGTH_RATIO = 1f / 12f
    private const val MINUTE_NOTCH_OFFSET_RATIO = 1f / 8.5f
    private const val NOTCH_WIDTH_RATIO = 1f / 69.25f

    private const val CLOCK_GROUP_LEFT_RATIO = 1f / 2.5f
    private const val CLOCK_GROUP_MARGIN_RATIO = 1f / 23.079f
    private const val CLOCK_ROW_GAP_RATIO = 1f / 40f
    private const val CLOCK_TEXT_GAP_RATIO = 1f / 30f

    private const val WEEKDAY_DAY_GAP_RATIO = 0.012f

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
        val ink = UpstreamNtDraw.ink(context, style)
        val background = UpstreamNtDraw.background(context, style)

        if (includeBackground) {
            drawSurface(canvas, safeWidth, safeHeight, side, background)
        }

        drawDateStack(canvas, side, safeWidth, ink, background, date)
        drawClockGroup(canvas, side, safeWidth, safeHeight, style, ink, background, date)
        return bitmap
    }

    private fun drawSurface(
        canvas: Canvas,
        width: Int,
        height: Int,
        side: Float,
        background: Int,
    ) {
        if (Color.alpha(background) == 0) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
        val radius = side * CORNER_RATIO
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()),
            radius,
            radius,
            paint,
        )
    }

    private fun drawDateStack(
        canvas: Canvas,
        side: Float,
        width: Int,
        ink: Int,
        background: Int,
        date: Calendar,
    ) {
        val locale = Locale.getDefault()
        val weekday = SimpleDateFormat("EEE", locale)
            .format(date.time)
            .uppercase(locale)
        val day = SimpleDateFormat("d", locale).format(date.time)

        val left = side * LEFT_RATIO
        val maxWidth = (width - left - side * RIGHT_RATIO).coerceAtLeast(1f)

        val weekdayPaint = serifPaint(ink, Typeface.NORMAL, side, background)
        weekdayPaint.textSize = fitTextSize(
            weekdayPaint,
            weekday,
            side * WEEKDAY_TEXT_RATIO,
            maxWidth,
        )
        val weekdayTop = side * TOP_RATIO
        val weekdayMetrics = weekdayPaint.fontMetrics
        val weekdayHeight = weekdayMetrics.descent - weekdayMetrics.top
        drawTopLeft(canvas, weekdayPaint, weekday, left, weekdayTop)

        val dayPaint = serifPaint(ink, Typeface.BOLD, side, background)
        dayPaint.color = RED
        dayPaint.textSize = fitTextSize(
            dayPaint,
            day,
            side * DAY_TEXT_RATIO,
            maxWidth,
        )
        val dayTop = weekdayTop + weekdayHeight + side * WEEKDAY_DAY_GAP_RATIO
        drawTopLeft(canvas, dayPaint, day, left, dayTop)
    }

    private fun drawClockGroup(
        canvas: Canvas,
        side: Float,
        width: Int,
        height: Int,
        style: WidgetStyle,
        ink: Int,
        background: Int,
        date: Calendar,
    ) {
        val locale = Locale.getDefault()
        val hourText = SimpleDateFormat("hh", locale).format(date.time)
        val minuteText = SimpleDateFormat("mm", locale).format(date.time)

        val discDiameter = side * DISC_DIAMETER_RATIO
        val radius = discDiameter / 2f
        val textGap = side * CLOCK_TEXT_GAP_RATIO
        val rowGap = side * CLOCK_ROW_GAP_RATIO
        val right = width - side * RIGHT_RATIO
        val bottom = height - side * RIGHT_RATIO
        val groupLeft = side * CLOCK_GROUP_LEFT_RATIO - side * CLOCK_GROUP_MARGIN_RATIO

        val textPaint = serifPaint(ink, Typeface.NORMAL, side, background)
        textPaint.textSize = fitTextSize(
            textPaint,
            "00",
            side * CLOCK_TEXT_RATIO,
            (right - groupLeft - discDiameter).coerceAtLeast(1f),
        )

        val minuteCenterY = bottom - radius
        val hourCenterY = minuteCenterY - discDiameter - rowGap
        val hour = date.get(Calendar.HOUR)
        val minute = date.get(Calendar.MINUTE)
        val hourAngle = (hour + minute / 60f) * 30f
        val minuteAngle = minute * 6f

        drawClockRow(
            canvas = canvas,
            text = hourText,
            centerY = hourCenterY,
            angle = hourAngle,
            right = right,
            groupLeft = groupLeft,
            radius = radius,
            textGap = textGap,
            textPaint = textPaint,
            style = style,
            discColor = ink,
            notchColor = notchColor(background),
            notchWidth = side * NOTCH_WIDTH_RATIO,
            notchStart = notchStart(side, radius, HOUR_NOTCH_OFFSET_RATIO),
            notchOuter = notchOuter(
                radius,
                notchStart(side, radius, HOUR_NOTCH_OFFSET_RATIO),
                side * HOUR_NOTCH_LENGTH_RATIO,
            ),
        )
        drawClockRow(
            canvas = canvas,
            text = minuteText,
            centerY = minuteCenterY,
            angle = minuteAngle,
            right = right,
            groupLeft = groupLeft,
            radius = radius,
            textGap = textGap,
            textPaint = textPaint,
            style = style,
            discColor = RED,
            notchColor = notchColor(background),
            notchWidth = side * NOTCH_WIDTH_RATIO,
            notchStart = notchStart(side, radius, MINUTE_NOTCH_OFFSET_RATIO),
            notchOuter = notchOuter(
                radius,
                notchStart(side, radius, MINUTE_NOTCH_OFFSET_RATIO),
                side * MINUTE_NOTCH_LENGTH_RATIO,
            ),
        )
    }

    private fun drawClockRow(
        canvas: Canvas,
        text: String,
        centerY: Float,
        angle: Float,
        right: Float,
        groupLeft: Float,
        radius: Float,
        textGap: Float,
        textPaint: Paint,
        style: WidgetStyle,
        discColor: Int,
        notchColor: Int,
        notchWidth: Float,
        notchStart: Float,
        notchOuter: Float,
    ) {
        val textWidth = textPaint.measureText(text)
        val discCenterX = max(
            groupLeft + radius,
            right - textWidth - textGap - radius,
        )

        val discPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = discColor
            UpstreamNtDraw.shadow(style, this)
        }
        canvas.drawCircle(discCenterX, centerY, radius, discPaint)

        val notchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = notchColor
        }
        canvas.save()
        canvas.rotate(angle, discCenterX, centerY)
        canvas.drawRoundRect(
            RectF(
                discCenterX - notchWidth / 2f,
                centerY - notchOuter,
                discCenterX + notchWidth / 2f,
                centerY - notchStart,
            ),
            notchWidth / 2f,
            notchWidth / 2f,
            notchPaint,
        )
        canvas.restore()

        val metrics = textPaint.fontMetrics
        val baseline = centerY - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(text, discCenterX + radius + textGap, baseline, textPaint)
    }

    private fun notchColor(background: Int): Int = if (Color.alpha(background) == 0) TRANSPARENT_NOTCH else background

    private fun notchStart(side: Float, radius: Float, offsetRatio: Float): Float = max(radius * 0.05f, side * offsetRatio - radius)

    private fun notchOuter(radius: Float, start: Float, length: Float): Float = min(radius * 0.98f, start + length)

    private fun serifPaint(
        color: Int,
        style: Int,
        side: Float,
        background: Int,
    ): Paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        this.color = color
        typeface = Typeface.create(Typeface.SERIF, style)
        textAlign = Paint.Align.LEFT
        if (Color.alpha(background) == 0) {
            setShadowLayer(side * 0.012f, 0f, side * 0.005f, 0x99000000.toInt())
        }
    }

    private fun fitTextSize(
        paint: Paint,
        text: String,
        desired: Float,
        maxWidth: Float,
    ): Float {
        paint.textSize = desired
        val measured = paint.measureText(text)
        if (measured <= 0f || measured <= maxWidth) return desired
        return (desired * maxWidth / measured).coerceAtLeast(1f)
    }

    private fun drawTopLeft(
        canvas: Canvas,
        paint: Paint,
        text: String,
        x: Float,
        top: Float,
    ) {
        canvas.drawText(text, x, top - paint.fontMetrics.top, paint)
    }
}
