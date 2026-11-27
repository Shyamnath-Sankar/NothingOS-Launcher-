package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Native renderer for `Nothing_Digital` from AumGupta/KWGT-Widgets
 * (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024
 * Om Gupta). Sanitized source data:
 * assets/kwgt/nothing_digital.sanitized.json.
 *
 * Retained author geometry from the preset:
 * - `side = min(rwidth, rheight)`, rounded surface corners `side / 5`
 * - three right-edge circles at `side / 1.1`, `side / 1.4` and `side / 2`,
 *   each 50% primary `#D71921` fading to transparent across a source gradient
 *   band (widths 45/71/54, offsets 69/61/64)
 * - centred 12-hour `hh` at `side / 3` in foreground ink
 * - a `side / 6` red minute chip at the right edge with `mm` at `side / 12`
 *   in the contrasting background colour
 *
 * Substitutions and adaptations:
 * - The upstream `ndot-47.ttf` is not redistributed. Dotwel's original
 *   circular-dot glyphs are fitted to the host, and the hour size shrinks if
 *   its ink would reach the minute chip.
 * - The source rotates each gradient circle to 170 degrees. Android's
 *   [LinearGradient] is drawn on a horizontal right-to-left axis here; the
 *   source offsets and widths still drive the gradient stops. This is a
 *   documented legibility approximation, not pixel-identical upstream output.
 * - The source minute chip is a 45% primary gradient. The native chip keeps a
 *   red gradient but is more opaque so `mm` stays legible on every surface.
 */
object KwgtGradientClockRenderer {
    const val RED = 0xFFD71921.toInt()

    private const val CORNER_RATIO = 1f / 5f
    private const val HOUR_TEXT_RATIO = 1f / 3f
    private const val MINUTE_TEXT_RATIO = 1f / 12f
    private const val CHIP_DIAMETER_RATIO = 1f / 6f
    private const val CHIP_INK_FRACTION = 0.62f
    private const val HOUR_CHIP_GAP_RATIO = 1f / 30f
    private const val HEIGHT_INK_FRACTION = 0.94f
    private const val DOT_INK_ROWS = 6.8f
    private const val DOT_INK_X_MARGIN = 0.4f
    private const val CIRCLE_ALPHA = 0x80

    private data class CircleSpec(
        val divisor: Float,
        val offsetPercent: Int,
        val widthPercent: Int,
    )

    private val CIRCLE_SPECS = listOf(
        CircleSpec(1.1f, 69, 45),
        CircleSpec(1.4f, 61, 71),
        CircleSpec(2f, 64, 54),
    )

    internal data class CircleLayout(
        val centerX: Float,
        val centerY: Float,
        val radius: Float,
        val offsetPercent: Int,
        val widthPercent: Int,
    )

    internal data class GradientLayout(
        val width: Float,
        val height: Float,
        val side: Float,
        val centerX: Float,
        val centerY: Float,
        val cornerRadius: Float,
        val hourPitch: Float,
        val hourCenterX: Float,
        val hourCenterY: Float,
        val hourInkWidth: Float,
        val hourInkHeight: Float,
        val minuteChipCenterX: Float,
        val minuteChipCenterY: Float,
        val minuteChipDiameter: Float,
        val minutePitch: Float,
        val minuteInkWidth: Float,
        val minuteInkHeight: Float,
        val circles: List<CircleLayout>,
    ) {
        val minuteChipRadius: Float get() = minuteChipDiameter / 2f
        val hourLeft: Float get() = hourCenterX - hourInkWidth / 2f
        val hourRight: Float get() = hourCenterX + hourInkWidth / 2f
        val minuteLeft: Float get() = minuteChipCenterX - minuteInkWidth / 2f
        val minuteRight: Float get() = minuteChipCenterX + minuteInkWidth / 2f
    }

    internal fun layout(
        width: Float,
        height: Float,
        hourText: String,
        minuteText: String,
    ): GradientLayout {
        val safeWidth = width.coerceAtLeast(1f)
        val safeHeight = height.coerceAtLeast(1f)
        val side = min(safeWidth, safeHeight)
        val centerX = safeWidth / 2f
        val centerY = safeHeight / 2f
        val cornerRadius = side * CORNER_RATIO

        val chipDiameter = side * CHIP_DIAMETER_RATIO
        val chipRadius = chipDiameter / 2f
        val chipCenterX = safeWidth - chipRadius
        val chipCenterY = centerY
        val chipLeft = chipCenterX - chipRadius

        val hourColumns = max(1f, DotGlyphFont.columnsFor(hourText).toFloat())
        val minuteColumns = max(1f, DotGlyphFont.columnsFor(minuteText).toFloat())

        val nominalHourPitch = side * HOUR_TEXT_RATIO / DotGlyphFont.ROWS
        val hourGap = side * HOUR_CHIP_GAP_RATIO
        val hourRightLimit = (chipLeft - hourGap).coerceAtLeast(0f)
        val halfLimit = min(centerX, (hourRightLimit - centerX).coerceAtLeast(0f))
        val hourPitch = min(
            nominalHourPitch,
            min(
                (2f * halfLimit) / (hourColumns - DOT_INK_X_MARGIN),
                safeHeight * HEIGHT_INK_FRACTION / DOT_INK_ROWS,
            ),
        ).coerceAtLeast(0f)

        val nominalMinutePitch = side * MINUTE_TEXT_RATIO / DotGlyphFont.ROWS
        val chipInkWidth = chipDiameter * CHIP_INK_FRACTION
        val minutePitch = min(
            nominalMinutePitch,
            min(
                chipInkWidth / (minuteColumns - DOT_INK_X_MARGIN),
                chipInkWidth / DOT_INK_ROWS,
            ),
        ).coerceAtLeast(0f)

        val circles = CIRCLE_SPECS.map { spec ->
            val diameter = side / spec.divisor
            val radius = diameter / 2f
            CircleLayout(
                centerX = safeWidth - radius,
                centerY = centerY,
                radius = radius,
                offsetPercent = spec.offsetPercent,
                widthPercent = spec.widthPercent,
            )
        }

        return GradientLayout(
            width = safeWidth,
            height = safeHeight,
            side = side,
            centerX = centerX,
            centerY = centerY,
            cornerRadius = cornerRadius,
            hourPitch = hourPitch,
            hourCenterX = centerX,
            hourCenterY = centerY,
            hourInkWidth = (hourColumns - DOT_INK_X_MARGIN) * hourPitch,
            hourInkHeight = DOT_INK_ROWS * hourPitch,
            minuteChipCenterX = chipCenterX,
            minuteChipCenterY = chipCenterY,
            minuteChipDiameter = chipDiameter,
            minutePitch = minutePitch,
            minuteInkWidth = (minuteColumns - DOT_INK_X_MARGIN) * minutePitch,
            minuteInkHeight = DOT_INK_ROWS * minutePitch,
            circles = circles,
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
        val boundary = layout(
            width.coerceAtLeast(1).toFloat(),
            height.coerceAtLeast(1).toFloat(),
            hourText(date),
            minuteText(date),
        )
        val bitmap = Bitmap.createBitmap(
            boundary.width.toInt(),
            boundary.height.toInt(),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)

        if (includeBackground) {
            drawSurface(canvas, context, style, boundary)
        }
        canvas.save()
        canvas.clipPath(surfacePath(boundary))
        drawCircles(canvas, boundary)
        drawMinuteChip(canvas, boundary)
        if (boundary.minutePitch > 0f) {
            DotGlyphFont.drawCentered(
                canvas,
                minuteText(date),
                boundary.minuteChipCenterX,
                boundary.minuteChipCenterY,
                boundary.minutePitch,
                chipTextPaint(context, style),
            )
        }
        if (boundary.hourPitch > 0f) {
            DotGlyphFont.drawCentered(
                canvas,
                hourText(date),
                boundary.hourCenterX,
                boundary.hourCenterY,
                boundary.hourPitch,
                dotPaint(context, style, UpstreamNtDraw.ink(context, style)),
            )
        }
        canvas.restore()
        return bitmap
    }

    /**
     * Static, time-free composition used by the live TextClock fallback. It
     * contains only the rounded surface and the three gradient circles, so no
     * stale bitmap time can ever be presented as live.
     */
    fun renderStaticBackground(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
    ): Bitmap {
        val boundary = layout(
            width.coerceAtLeast(1).toFloat(),
            height.coerceAtLeast(1).toFloat(),
            "00",
            "00",
        )
        val bitmap = Bitmap.createBitmap(
            boundary.width.toInt(),
            boundary.height.toInt(),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        drawSurface(canvas, context, style, boundary)
        canvas.save()
        canvas.clipPath(surfacePath(boundary))
        drawCircles(canvas, boundary)
        canvas.restore()
        return bitmap
    }

    fun hourText(date: Calendar): String = SimpleDateFormat("hh", Locale.getDefault()).format(date.time)

    fun minuteText(date: Calendar): String = SimpleDateFormat("mm", Locale.getDefault()).format(date.time)

    /** Contrasting colour for `mm` on the red chip, adapted for transparency. */
    fun minuteInk(context: Context, style: WidgetStyle): Int {
        val background = UpstreamNtDraw.background(context, style)
        if (Color.alpha(background) >= 0x80) return background
        return if (style == WidgetStyle.TRANSPARENT) WHITE else DARK_INK
    }

    private fun drawSurface(
        canvas: Canvas,
        context: Context,
        style: WidgetStyle,
        boundary: GradientLayout,
    ) {
        val background = UpstreamNtDraw.background(context, style)
        if (Color.alpha(background) == 0) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
        canvas.drawRoundRect(
            RectF(0f, 0f, boundary.width, boundary.height),
            boundary.cornerRadius,
            boundary.cornerRadius,
            paint,
        )
    }

    private fun surfacePath(boundary: GradientLayout): Path = Path().apply {
        addRoundRect(
            RectF(0f, 0f, boundary.width, boundary.height),
            boundary.cornerRadius,
            boundary.cornerRadius,
            Path.Direction.CW,
        )
    }

    private fun drawCircles(canvas: Canvas, boundary: GradientLayout) {
        boundary.circles.forEach { circle ->
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.shader = circleShader(circle)
            canvas.drawCircle(circle.centerX, circle.centerY, circle.radius, paint)
        }
    }

    /**
     * Right-to-left fade mapped from the source gradient width/offset values:
     * the right `offset` percent stays at 50% primary, then the band fades to
     * transparent over `width` percent of the diameter.
     */
    private fun circleShader(circle: CircleLayout): Shader {
        val right = circle.centerX + circle.radius
        val left = circle.centerX - circle.radius
        val solid = Color.argb(
            CIRCLE_ALPHA,
            Color.red(RED),
            Color.green(RED),
            Color.blue(RED),
        )
        val clear = Color.argb(0, Color.red(RED), Color.green(RED), Color.blue(RED))
        val hold = (circle.offsetPercent / 100f).coerceIn(0f, 0.95f)
        val fade = (circle.widthPercent / 100f).coerceIn(0.05f, 1f)
        val end = (hold + fade).coerceIn(hold + 0.01f, 1f)
        return LinearGradient(
            right,
            circle.centerY,
            left,
            circle.centerY,
            intArrayOf(solid, solid, clear, clear),
            floatArrayOf(0f, hold, end, 1f),
            Shader.TileMode.CLAMP,
        )
    }

    private fun drawMinuteChip(canvas: Canvas, boundary: GradientLayout) {
        val chip = boundary.minuteChipRadius
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(
            boundary.minuteChipCenterX + chip,
            boundary.minuteChipCenterY,
            boundary.minuteChipCenterX - chip,
            boundary.minuteChipCenterY,
            intArrayOf(BRIGHT_RED, RED, DARK_RED),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(
            boundary.minuteChipCenterX,
            boundary.minuteChipCenterY,
            chip,
            paint,
        )
    }

    private fun dotPaint(context: Context, style: WidgetStyle, color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        this.color = color
        UpstreamNtDraw.shadow(style, this)
    }

    private fun chipTextPaint(context: Context, style: WidgetStyle): Paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
        color = minuteInk(context, style)
        UpstreamNtDraw.shadow(style, this)
    }

    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val DARK_INK = 0xFF1B1D1F.toInt()
    private const val BRIGHT_RED = 0xF2E11B25.toInt()
    private const val DARK_RED = 0xF2B01018.toInt()
}
