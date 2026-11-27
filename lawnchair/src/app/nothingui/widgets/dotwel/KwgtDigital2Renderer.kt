package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.format.DateUtils
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.min

/**
 * Native renderer for `Nothing_Digital2` from AumGupta/KWGT-Widgets
 * (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024
 * Om Gupta). Sanitized source data:
 * assets/kwgt/nothing_digital2.sanitized.json.
 *
 * Retained author geometry and formulas:
 * - `side = min(rwidth, rheight)`
 * - background width `side`, rounded corners `side / 5`, background height `h`
 * - right-aligned vertical stack shifted by `side / 8.5` with the source
 *   negative stack margin `-side / 21.875`
 * - previous line `df(mm, r1m)` at `side / 5`, centre line `side / 3.5`,
 *   next line `df(mm, a1m)` at `side / 5`
 *
 * Repairs and substitutions:
 * - The source background height global `h` is not declared by the preset, so
 *   the native port uses the host height and records this as a fit repair
 *   instead of inventing a source formula.
 * - The central text module has no source expression. The port supplies the
 *   live local `HH:mm`/`hh:mm` readout that the preview and stack position
 *   imply, and keeps it in an OS-owned TextClock so it is never a frozen
 *   bitmap.
 * - The upstream `ndot-47.ttf` is not redistributed; the live clock uses the
 *   platform monospace family.
 */
object KwgtDigital2Renderer {
    const val SOURCE_WIDTH = 415f
    const val SOURCE_HEIGHT = 542f

    private const val CORNER_RATIO = 1f / 5f
    private const val RIGHT_INSET_RATIO = 1f / 8.5f
    private const val STACK_GAP_RATIO = 1f / 21.875f
    private const val PREV_SIZE_RATIO = 1f / 5f
    private const val CENTER_SIZE_RATIO = 1f / 3.5f

    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val LIGHT_INK = 0xFF1B1B1D.toInt()

    data class Palette(
        val background: Int,
        val foreground: Int,
        val accent: Int,
    )

    data class Layout(
        val width: Float,
        val height: Float,
        val side: Float,
        val cornerRadius: Float,
        val rightInset: Float,
        val centerTextSize: Float,
        val smallTextSize: Float,
        val clockCenterY: Float,
    ) {
        val backgroundLeft: Float get() = (width - side) / 2f
        val backgroundRight: Float get() = (width + side) / 2f
        val textRight: Float get() = backgroundRight - rightInset
    }

    fun palette(style: WidgetStyle): Palette {
        val background = when (style) {
            WidgetStyle.BLACK -> LIGHT_INK
            WidgetStyle.TRANSLUCENT -> 0xA6FFFFFF.toInt()
            WidgetStyle.TRANSPARENT -> 0x00000000
        }
        val foreground = when (style) {
            WidgetStyle.BLACK -> WHITE
            WidgetStyle.TRANSLUCENT -> LIGHT_INK
            WidgetStyle.TRANSPARENT -> WHITE
        }
        return Palette(
            background = background,
            foreground = foreground,
            accent = withAlpha(foreground, 50),
        )
    }

    fun layout(width: Int, height: Int): Layout {
        val safeWidth = width.coerceAtLeast(1).toFloat()
        val safeHeight = height.coerceAtLeast(1).toFloat()
        val side = min(safeWidth, safeHeight)
        return Layout(
            width = safeWidth,
            height = safeHeight,
            side = side,
            cornerRadius = side * CORNER_RATIO,
            rightInset = side * RIGHT_INSET_RATIO,
            centerTextSize = side * CENTER_SIZE_RATIO,
            smallTextSize = side * PREV_SIZE_RATIO,
            clockCenterY = safeHeight / 2f,
        )
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        now: Long = System.currentTimeMillis(),
        includeBackground: Boolean = true,
        includeShiftedMinutes: Boolean = true,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(2)
        val safeHeight = height.coerceAtLeast(2)
        val bitmap = Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val layout = layout(safeWidth, safeHeight)
        val palette = palette(style)
        if (includeBackground && palette.background != 0) {
            canvas.drawRoundRect(
                RectF(
                    layout.backgroundLeft,
                    0f,
                    layout.backgroundRight,
                    layout.height,
                ),
                layout.cornerRadius,
                layout.cornerRadius,
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.background },
            )
        }
        if (!includeShiftedMinutes) return bitmap
        val previous = relativeLabel(context, now, -DateUtils.MINUTE_IN_MILLIS)
        val next = relativeLabel(context, now, DateUtils.MINUTE_IN_MILLIS)
        val prevPaint = textPaint(palette.accent, layout.smallTextSize, Paint.Align.RIGHT)
        val nextPaint = textPaint(palette.accent, layout.smallTextSize, Paint.Align.RIGHT)
        val centerGap = layout.centerTextSize * 0.62f
        canvas.drawText(
            previous,
            layout.textRight,
            layout.clockCenterY - centerGap - layout.smallTextSize * 0.20f,
            prevPaint,
        )
        canvas.drawText(
            next,
            layout.textRight,
            layout.clockCenterY + centerGap + layout.smallTextSize * 0.95f,
            nextPaint,
        )
        return bitmap
    }

    fun relativeLabel(context: Context, now: Long, offsetMillis: Long): String {
        // Kustom df(mm, r1m/a1m) formats the minute at the shifted instant.
        // It is not a natural-language relative duration.
        return minuteAtOffset(now, offsetMillis)
    }

    internal fun minuteAtOffset(now: Long, offsetMillis: Long): String = SimpleDateFormat("mm", Locale.ROOT).format(Date(now + offsetMillis))

    private fun textPaint(color: Int, size: Float, align: Paint.Align): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textSize = size.coerceAtLeast(1f)
        textAlign = align
        typeface = android.graphics.Typeface.create("monospace", android.graphics.Typeface.BOLD)
        isSubpixelText = true
    }

    private fun withAlpha(color: Int, alphaPercent: Int): Int {
        val alpha = (((color ushr 24) and 0xFF) * alphaPercent / 100).coerceIn(0, 255)
        return (alpha shl 24) or (color and 0x00FFFFFF)
    }
}
