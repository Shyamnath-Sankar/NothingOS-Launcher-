package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Native renderer for `Clean_Time_Date_Info` from AumGupta/KWGT-Widgets
 * (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024
 * Om Gupta). Sanitized source data:
 * assets/kwgt/clean_time_date_info.sanitized.json.
 *
 * Retained author composition (553 x 248 source canvas):
 * - rounded card corners 38, card background #FF16161D on dark and #FFE4E4FF on
 *   light
 * - bottom-left stack at left 28 / bottom 28 with the weekday at 69, the
 *   uppercase month/day at 24, and the source -15 stack margin
 * - oversize CENTERRIGHT `h:mm` at 196 in foreground ink at 19% alpha, kept as
 *   the intentional overlapping ghost back layer
 * - top-left battery body 59 x 28 rounded 6, nub 10.5 x 16 rounded 4 overlapped
 *   by the source -5 margin, and the true bilevel percentage at 16 bold painted
 *   in the card background ink
 *
 * Explicit repairs and adaptations:
 * - The source `fgcolor` formula is malformed:
 *   `$if(si(darkmode)#FFFFFF,#000000)$` is missing the comma after
 *   `si(darkmode)`. It is repaired to the intended conditional
 *   `$if(si(darkmode),#FFFFFF,#000000)$`: dark surfaces use white ink, light
 *   surfaces use black ink.
 * - ProductSans-Bold/Medium are not redistributed. The platform `sans-serif`
 *   family is substituted.
 * - The source preview is cropped and the oversized time spills past the card.
 *   Geometry is derived from the JSON numbers and every text size is fitted to
 *   the available bounds instead of reproducing the accidental clipping.
 *
 * The widget itself never draws a frozen time bitmap: it draws only this static
 * card/battery background and overlays live platform TextClocks plus a real
 * BatteryManager percentage.
 */
object KwgtCleanInfoRenderer {
    const val SOURCE_WIDTH = 553f
    const val SOURCE_HEIGHT = 248f
    const val CORNER = 38f
    const val PAD = 28f
    const val STACK_MARGIN = 15f
    const val WEEKDAY_SIZE = 69f
    const val DATE_SIZE = 24f
    const val TIME_SIZE = 196f
    const val BATTERY_TEXT_SIZE = 16f
    const val BATTERY_BODY_WIDTH = 59f
    const val BATTERY_BODY_HEIGHT = 28f
    const val BATTERY_NUB_WIDTH = 10.5f
    const val BATTERY_NUB_HEIGHT = 16f
    const val BATTERY_JOIN = 5f
    const val TIME_ALPHA_PERCENT = 19

    const val DARK_BACKGROUND = 0xFF16161D.toInt()
    const val LIGHT_BACKGROUND = 0xFFE4E4FF.toInt()

    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val BLACK = 0xFF000000.toInt()

    /**
     * Conservative advance-width estimates used to fit live text without a
     * platform Paint in JVM layout tests. The live view keeps the same font
     * family, so these values bound the rendered width.
     */
    internal const val TIME_WIDTH_EM = 2.45f
    internal const val WEEKDAY_WIDTH_EM = 5.8f
    internal const val DATE_WIDTH_EM = 6.8f
    private const val TIME_HEIGHT_FRACTION = 0.82f
    private const val MIN_EDGE_EM = 8f

    data class Rect(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
        val centerX: Float get() = (left + right) / 2f
        val centerY: Float get() = (top + bottom) / 2f

        fun inside(width: Float, height: Float): Boolean = left >= -0.01f &&
            top >= -0.01f &&
            right <= width + 0.01f &&
            bottom <= height + 0.01f
    }

    data class Palette(
        val background: Int,
        val foreground: Int,
        val timeInk: Int,
        val batteryInk: Int,
    )

    data class Layout(
        val width: Float,
        val height: Float,
        val scale: Float,
        val cornerRadius: Float,
        val leftPad: Float,
        val rightPad: Float,
        val topPad: Float,
        val bottomPad: Float,
        val stackMargin: Float,
        val timeTextSize: Float,
        val weekdayTextSize: Float,
        val dateTextSize: Float,
        val batteryTextSize: Float,
        val batteryBody: Rect,
        val batteryNub: Rect,
    )

    fun isDark(context: Context, style: WidgetStyle): Boolean = when (style) {
        WidgetStyle.BLACK -> true

        WidgetStyle.TRANSLUCENT -> false

        WidgetStyle.TRANSPARENT -> {
            val mode = context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK
            mode == Configuration.UI_MODE_NIGHT_YES
        }
    }

    fun palette(dark: Boolean): Palette {
        val background = if (dark) DARK_BACKGROUND else LIGHT_BACKGROUND
        val foreground = if (dark) WHITE else BLACK
        return Palette(
            background = background,
            foreground = foreground,
            timeInk = withAlpha(foreground, TIME_ALPHA_PERCENT),
            batteryInk = background,
        )
    }

    fun palette(context: Context, style: WidgetStyle): Palette {
        val base = palette(isDark(context, style))
        return when (style) {
            WidgetStyle.BLACK -> base
            WidgetStyle.TRANSLUCENT -> base.copy(background = withAlpha(base.background, 88))
            WidgetStyle.TRANSPARENT -> base.copy(background = 0)
        }
    }

    /** Derives source-relative geometry and fits all text inside the box. */
    fun layout(widthPx: Float, heightPx: Float): Layout {
        val width = widthPx.coerceAtLeast(1f)
        val height = heightPx.coerceAtLeast(1f)
        val scale = min(width / SOURCE_WIDTH, height / SOURCE_HEIGHT)
            .coerceAtLeast(0.0001f)
        val leftPad = PAD * scale
        val rightPad = PAD * scale
        val topPad = PAD * scale
        val bottomPad = PAD * scale
        val maxTimeWidth = (width - rightPad - MIN_EDGE_EM * scale).coerceAtLeast(1f)
        val maxStackWidth = (width - leftPad - MIN_EDGE_EM * scale).coerceAtLeast(1f)

        val timeTextSize = minOf(
            TIME_SIZE * scale,
            maxTimeWidth / TIME_WIDTH_EM,
            height * TIME_HEIGHT_FRACTION,
        ).coerceAtLeast(1f)
        val weekdayTextSize = minOf(
            WEEKDAY_SIZE * scale,
            maxStackWidth / WEEKDAY_WIDTH_EM,
        ).coerceAtLeast(1f)
        val dateTextSize = minOf(
            DATE_SIZE * scale,
            maxStackWidth / DATE_WIDTH_EM,
        ).coerceAtLeast(1f)
        val batteryTextSize = (BATTERY_TEXT_SIZE * scale).coerceAtLeast(1f)

        val body = Rect(
            left = leftPad,
            top = topPad,
            right = leftPad + BATTERY_BODY_WIDTH * scale,
            bottom = topPad + BATTERY_BODY_HEIGHT * scale,
        )
        val nubLeft = body.right - BATTERY_JOIN * scale
        val nubTop = body.top +
            (BATTERY_BODY_HEIGHT - BATTERY_NUB_HEIGHT) / 2f * scale
        val nub = Rect(
            left = nubLeft,
            top = nubTop,
            right = nubLeft + BATTERY_NUB_WIDTH * scale,
            bottom = nubTop + BATTERY_NUB_HEIGHT * scale,
        )

        return Layout(
            width = width,
            height = height,
            scale = scale,
            cornerRadius = CORNER * scale,
            leftPad = leftPad,
            rightPad = rightPad,
            topPad = topPad,
            bottomPad = bottomPad,
            stackMargin = STACK_MARGIN * scale,
            timeTextSize = timeTextSize,
            weekdayTextSize = weekdayTextSize,
            dateTextSize = dateTextSize,
            batteryTextSize = batteryTextSize,
            batteryBody = body,
            batteryNub = nub,
        )
    }

    /**
     * Native views must use true host content pixels, never the downsampled
     * background raster. The root's 8dp content inset is removed first.
     */
    fun layoutForHost(
        hostWidthDp: Float,
        hostHeightDp: Float,
        density: Float,
    ): Layout {
        val inset = WidgetSizing.CONTENT_INSET_DP * density
        val width = if (hostWidthDp > 0f) {
            (hostWidthDp * density - inset * 2f).coerceAtLeast(1f)
        } else {
            1f
        }
        val height = if (hostHeightDp > 0f) {
            (hostHeightDp * density - inset * 2f).coerceAtLeast(1f)
        } else {
            1f
        }
        return layout(width, height)
    }

    fun weekdayText(date: Calendar): String = SimpleDateFormat("EEEE", Locale.getDefault()).format(date.time)

    fun dateText(date: Calendar): String = SimpleDateFormat("MMMM d", Locale.getDefault())
        .format(date.time)
        .uppercase(Locale.getDefault())

    fun timeText(date: Calendar): String = SimpleDateFormat("h:mm", Locale.getDefault()).format(date.time)

    fun batteryText(level: Int): String = "${level.coerceIn(0, 100)}%"

    /** Static card plus the source battery body and nub, no text. */
    fun renderBackground(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
    ): Bitmap {
        val layout = layout(
            width.coerceAtLeast(1).toFloat(),
            height.coerceAtLeast(1).toFloat(),
        )
        val bitmap = Bitmap.createBitmap(
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        drawBackground(canvas, layout, palette(context, style))
        return bitmap
    }

    /** Full composition used only by the catalog preview. */
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        date: Calendar = Calendar.getInstance(),
        level: Int = BatteryState.level(context),
        includeBackground: Boolean = true,
    ): Bitmap {
        val layout = layout(
            width.coerceAtLeast(1).toFloat(),
            height.coerceAtLeast(1).toFloat(),
        )
        val bitmap = Bitmap.createBitmap(
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val palette = palette(context, style)
        if (includeBackground) {
            drawBackground(canvas, layout, palette)
        }
        drawPreviewText(canvas, layout, palette, date, level)
        return bitmap
    }

    private fun drawBackground(canvas: Canvas, layout: Layout, palette: Palette) {
        if (((palette.background ushr 24) and 0xFF) != 0) {
            val card = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.background }
            canvas.drawRoundRect(
                RectF(0f, 0f, layout.width, layout.height),
                layout.cornerRadius,
                layout.cornerRadius,
                card,
            )
        }
        val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.foreground }
        val bodyRadius = 6f * layout.scale
        val nubRadius = 4f * layout.scale
        val body = layout.batteryBody
        canvas.drawRoundRect(
            RectF(body.left, body.top, body.right, body.bottom),
            bodyRadius,
            bodyRadius,
            ink,
        )
        val nub = layout.batteryNub
        canvas.drawRoundRect(
            RectF(nub.left, nub.top, nub.right, nub.bottom),
            nubRadius,
            nubRadius,
            ink,
        )
    }

    private fun drawPreviewText(
        canvas: Canvas,
        layout: Layout,
        palette: Palette,
        date: Calendar,
        level: Int,
    ) {
        val sans = Typeface.create("sans-serif", Typeface.NORMAL)
        val sansBold = Typeface.create("sans-serif", Typeface.BOLD)

        val timePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = palette.timeInk
            textSize = layout.timeTextSize
            typeface = sans
            textAlign = Paint.Align.RIGHT
        }
        val timeBaseline = layout.height / 2f -
            (timePaint.fontMetrics.ascent + timePaint.fontMetrics.descent) / 2f
        canvas.drawText(
            timeText(date),
            layout.width - layout.rightPad,
            timeBaseline,
            timePaint,
        )

        val datePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = palette.foreground
            textSize = layout.dateTextSize
            typeface = sansBold
            textAlign = Paint.Align.LEFT
        }
        val dateBaseline = layout.height - layout.bottomPad
        canvas.drawText(
            dateText(date),
            layout.leftPad,
            dateBaseline,
            datePaint,
        )

        val weekdayPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = palette.foreground
            textSize = layout.weekdayTextSize
            typeface = sansBold
            textAlign = Paint.Align.LEFT
        }
        val weekdayBaseline = dateBaseline -
            layout.dateTextSize * 0.95f -
            layout.weekdayTextSize * 0.05f +
            layout.stackMargin * 0.25f
        canvas.drawText(
            weekdayText(date),
            layout.leftPad,
            weekdayBaseline,
            weekdayPaint,
        )

        val batteryPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = palette.batteryInk
            textSize = layout.batteryTextSize
            typeface = sansBold
            textAlign = Paint.Align.CENTER
        }
        val body = layout.batteryBody
        val batteryBaseline = body.centerY -
            (batteryPaint.fontMetrics.ascent + batteryPaint.fontMetrics.descent) / 2f
        canvas.drawText(
            batteryText(level),
            body.centerX,
            batteryBaseline,
            batteryPaint,
        )
    }

    private fun withAlpha(color: Int, percent: Int): Int = ((255f * percent / 100f).roundToInt() shl 24) or (color and 0x00FFFFFF)
}
