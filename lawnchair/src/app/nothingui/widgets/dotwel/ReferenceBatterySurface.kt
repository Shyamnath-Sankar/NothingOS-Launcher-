package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.min
import kotlin.math.roundToInt

enum class BatterySurfaceKind {
    CIRCLE_PROGRESS,
    GLOW_PROGRESS,
    VERTICAL_DOTS,
    TEXT_ARC,
    SMALL_PROGRESSBAR,
    WITH_DEVICE_ICON,
}

/**
 * Reference battery surfaces. Every surface is a pure white card, the digits are
 * black dot-matrix and every known fill uses the reference red #D71921 (circle,
 * pill and bar alike). Unknown levels stay neutral. The iOS device card keeps a
 * black phone glyph on a light pink disc with a small gray status word. The card
 * stays white for every style so the reference contrast is preserved, matching
 * the Bluetooth battery card decision.
 */
internal object ReferenceBatterySurface {
    const val RED = 0xFFD71921.toInt()
    const val GREEN = 0xFF6A9C89.toInt()
    const val WHITE = 0xFFFFFFFF.toInt()
    const val INK = 0xFF000000.toInt()
    const val GRAY = 0xFF777379.toInt()
    const val TRACK = 0xFFEEEEEE.toInt()
    const val TRACK_SOFT = 0xFFE1E1E1.toInt()
    const val EMPTY_DOT = 0xFFB4B4B8.toInt()
    const val DEVICE_PINK = 0xFFF8D7DA.toInt()
    const val LOW_THRESHOLD = 25

    fun cardColor(style: WidgetStyle): Int = WHITE

    fun isLow(level: Int): Boolean = level in 0..LOW_THRESHOLD

    fun accent(level: Int): Int = when {
        level !in 0..100 -> GRAY
        else -> RED
    }

    fun deviceCircleColor(): Int = DEVICE_PINK

    fun deviceStatusColor(): Int = GRAY

    fun digitColor(level: Int): Int = INK

    fun percentText(level: Int): String =
        if (level in 0..100) "$level%" else "--"

    fun fillFraction(level: Int): Float =
        level.coerceIn(0, 100) / 100f

    fun verticalFilledDots(level: Int, total: Int): Int {
        if (total <= 0) return 0
        val clamped = level.coerceIn(0, 100)
        return (clamped / 100f * total).roundToInt()
    }

    fun verticalFilledPerColumn(level: Int, rows: Int): Int {
        if (rows <= 0) return 0
        val clamped = level.coerceIn(0, 100)
        return (clamped / 100f * rows).roundToInt().coerceIn(0, rows)
    }

    fun chargeLabel(charging: Boolean): String =
        if (charging) "CHARGING" else "DISCHARGING"

    fun render(
        context: Context,
        kind: BatterySurfaceKind,
        width: Int,
        height: Int,
        level: Int,
        charging: Boolean,
        style: WidgetStyle,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(safeWidth, safeHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val side = min(safeWidth, safeHeight).toFloat()
        val radius = side * 0.10f
        canvas.drawRoundRect(
            RectF(0f, 0f, safeWidth.toFloat(), safeHeight.toFloat()),
            radius,
            radius,
            fill(WHITE),
        )
        when (kind) {
            BatterySurfaceKind.CIRCLE_PROGRESS ->
                drawCircleProgress(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level, charging)
            BatterySurfaceKind.GLOW_PROGRESS ->
                drawGlowProgress(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level, charging)
            BatterySurfaceKind.VERTICAL_DOTS ->
                drawVerticalDots(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level)
            BatterySurfaceKind.TEXT_ARC ->
                drawTextArc(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level)
            BatterySurfaceKind.SMALL_PROGRESSBAR ->
                drawSmallProgressBar(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level)
            BatterySurfaceKind.WITH_DEVICE_ICON ->
                drawWithDeviceIcon(canvas, safeWidth.toFloat(), safeHeight.toFloat(), side, level, charging)
        }
        return bitmap
    }

    private fun drawCircleProgress(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
        charging: Boolean,
    ) {
        val pad = side * 0.06f
        drawChargeLabel(canvas, charging, pad, pad, side * 0.82f, side * 0.052f)
        drawDotLeft(
            canvas,
            percentText(level),
            pad,
            pad + side * 0.12f,
            side * 0.75f,
            side * 0.17f,
            digitColor(level),
        )

        val diameter = side * 0.30f
        val radius = diameter / 2f
        val cx = width - pad - radius
        val cy = height - pad - radius
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = INK
            style = Paint.Style.STROKE
            strokeWidth = (side * 0.012f).coerceAtLeast(1.5f)
        }
        canvas.drawCircle(cx, cy, radius, ring)

        val fraction = fillFraction(level)
        if (fraction <= 0f) return
        val top = cy + radius - diameter * fraction
        val circle = Path().apply { addCircle(cx, cy, radius, Path.Direction.CW) }
        canvas.save()
        canvas.clipPath(circle)
        canvas.drawRect(
            cx - radius,
            top,
            cx + radius,
            cy + radius,
            fill(accent(level)),
        )
        canvas.restore()
    }

    private fun drawGlowProgress(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
        charging: Boolean,
    ) {
        val pad = side * 0.06f
        drawChargeLabel(canvas, charging, pad, pad, width - pad * 2f, side * 0.052f)
        val barHeight = side * 0.20f
        val barTop = height - pad - barHeight
        val barLeft = pad
        val barRight = width - pad
        val labelSize = side * 0.052f
        val labelY = barTop - side * 0.055f
        drawDotLeft(canvas, "0", barLeft, labelY, side * 0.2f, labelSize, GRAY)
        drawDotCenter(canvas, "50", (barLeft + barRight) / 2f, labelY, side * 0.25f, labelSize, GRAY)
        drawDotRight(canvas, "100", barRight, labelY, side * 0.3f, labelSize, GRAY)

        val rect = RectF(barLeft, barTop, barRight, barTop + barHeight)
        val radius = barHeight / 2f
        canvas.drawRoundRect(rect, radius, radius, fill(GRAY))
        val fraction = fillFraction(level)
        if (fraction > 0f) {
            val accent = accent(level)
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = withAlpha(accent, 0x55)
                setShadowLayer(barHeight * 0.22f, 0f, 0f, accent)
            }
            val filled = RectF(barLeft, barTop, barLeft + (barRight - barLeft) * fraction, rect.bottom)
            canvas.drawRoundRect(filled, radius, radius, glow)
            canvas.drawRoundRect(filled, radius, radius, fill(accent))
        }
    }

    private fun drawVerticalDots(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
    ) {
        val columns = 5
        val rows = 20
        val perColumn = verticalFilledPerColumn(level, rows)
        val pad = side * 0.07f
        val left = pad
        val top = pad
        val right = width - pad
        val bottom = height - pad
        val cellWidth = (right - left) / columns
        val cellHeight = (bottom - top) / rows
        val dotRadius = min(cellWidth, cellHeight) * 0.32f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        for (column in 0 until columns) {
            for (row in 0 until rows) {
                val fromBottom = rows - 1 - row
                paint.color = when {
                    fromBottom >= perColumn -> EMPTY_DOT
                    column == 0 && fromBottom == perColumn - 1 -> accent(level)
                    else -> INK
                }
                canvas.drawCircle(
                    left + cellWidth * (column + 0.5f),
                    top + cellHeight * (row + 0.5f),
                    dotRadius,
                    paint,
                )
            }
        }
    }

    private fun drawTextArc(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
    ) {
        val pad = side * 0.06f
        val diameter = min(height - pad * 2f, width * 0.22f)
        val cx = pad + diameter / 2f
        val cy = height / 2f
        canvas.drawCircle(cx, cy, diameter / 2f, fill(TRACK_SOFT))
        drawDischargeBolt(canvas, cx, cy, diameter * 0.62f, accent(level))
        drawDotRight(
            canvas,
            percentText(level),
            width - pad,
            cy,
            width * 0.42f,
            side * 0.22f,
            digitColor(level),
        )
    }

    private fun drawSmallProgressBar(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
    ) {
        val pad = side * 0.08f
        drawDotLeft(
            canvas,
            percentText(level),
            pad,
            height / 2f,
            width * 0.28f,
            side * 0.22f,
            digitColor(level),
        )
        val barWidth = width * 0.38f
        val barHeight = height * 0.16f
        val barRight = width - pad
        val barLeft = barRight - barWidth
        val barTop = height / 2f - barHeight / 2f
        val rect = RectF(barLeft, barTop, barRight, barTop + barHeight)
        val radius = barHeight / 2f
        canvas.drawRoundRect(rect, radius, radius, fill(TRACK_SOFT))
        val fraction = fillFraction(level)
        if (fraction > 0f) {
            val filled = RectF(barLeft, barTop, barLeft + barWidth * fraction, rect.bottom)
            canvas.drawRoundRect(filled, radius, radius, fill(accent(level)))
        }
    }

    private fun drawWithDeviceIcon(
        canvas: Canvas,
        width: Float,
        height: Float,
        side: Float,
        level: Int,
        charging: Boolean,
    ) {
        val pad = side * 0.06f
        val diameter = side * 0.26f
        val cx = pad + diameter / 2f
        val cy = pad + diameter / 2f
        canvas.drawCircle(cx, cy, diameter / 2f, fill(deviceCircleColor()))
        drawPhone(canvas, cx, cy, diameter * 0.52f, INK)

        drawStatusRight(
            canvas,
            chargeLabel(charging),
            width - pad,
            height - pad - side * 0.17f,
            width * 0.55f,
            side * 0.050f,
            deviceStatusColor(),
        )
        drawDotRight(
            canvas,
            percentText(level),
            width - pad,
            height - pad - side * 0.065f,
            width * 0.45f,
            side * 0.17f,
            digitColor(level),
        )
    }

    private fun drawChargeLabel(
        canvas: Canvas,
        charging: Boolean,
        left: Float,
        centerY: Float,
        maxWidth: Float,
        maxHeight: Float,
    ) {
        drawDotLeft(
            canvas,
            chargeLabel(charging),
            left,
            centerY,
            maxWidth,
            maxHeight,
            GRAY,
        )
    }

    private fun drawDischargeBolt(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        size: Float,
        color: Int,
    ) {
        val halfWidth = size * 0.16f
        val top = cy - size * 0.28f
        val neck = cy + size * 0.02f
        val bottom = cy + size * 0.34f
        val path = Path().apply {
            moveTo(cx - halfWidth, top)
            lineTo(cx + halfWidth, top)
            lineTo(cx + halfWidth, neck)
            lineTo(cx + size * 0.30f, neck)
            lineTo(cx, bottom)
            lineTo(cx - size * 0.30f, neck)
            lineTo(cx - halfWidth, neck)
            close()
        }
        canvas.drawPath(path, fill(color))
    }

    private fun drawPhone(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = size * 0.09f
            strokeCap = Paint.Cap.ROUND
        }
        val halfWidth = size * 0.24f
        val halfHeight = size * 0.38f
        canvas.drawRoundRect(
            RectF(cx - halfWidth, cy - halfHeight, cx + halfWidth, cy + halfHeight),
            size * 0.12f,
            size * 0.12f,
            paint,
        )
        canvas.drawCircle(cx, cy + halfHeight * 0.62f, size * 0.045f, fill(color))
    }

    private fun drawDotLeft(
        canvas: Canvas,
        value: String,
        left: Float,
        centerY: Float,
        maxWidth: Float,
        maxHeight: Float,
        color: Int,
    ) {
        val text = fitted(value, maxWidth, maxHeight) ?: return
        val pitch = DotGlyphFont.fitPitch(text, maxWidth, maxHeight)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        DotGlyphFont.drawLeft(canvas, text, left, centerY, pitch, paint)
    }

    private fun drawDotRight(
        canvas: Canvas,
        value: String,
        right: Float,
        centerY: Float,
        maxWidth: Float,
        maxHeight: Float,
        color: Int,
    ) {
        val text = fitted(value, maxWidth, maxHeight) ?: return
        val pitch = DotGlyphFont.fitPitch(text, maxWidth, maxHeight)
        val textWidth = DotGlyphFont.columnsFor(text) * pitch
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        DotGlyphFont.drawLeft(canvas, text, right - textWidth, centerY, pitch, paint)
    }

    private fun drawStatusRight(
        canvas: Canvas,
        value: String,
        right: Float,
        centerY: Float,
        maxWidth: Float,
        textSize: Float,
        color: Int,
    ) {
        if (value.isEmpty()) return
        val paint = Paint(
            Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG,
        ).apply {
            this.color = color
            this.textSize = textSize.coerceAtLeast(4f)
            textAlign = Paint.Align.RIGHT
            typeface = android.graphics.Typeface.create(
                "sans-serif",
                android.graphics.Typeface.NORMAL,
            )
        }
        val measured = paint.measureText(value)
        if (measured > maxWidth && measured > 0f) {
            paint.textSize *= maxWidth / measured
        }
        val metrics = paint.fontMetrics
        val baseline = centerY - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(value, right, baseline, paint)
    }

    private fun drawDotCenter(
        canvas: Canvas,
        value: String,
        centerX: Float,
        centerY: Float,
        maxWidth: Float,
        maxHeight: Float,
        color: Int,
    ) {
        val text = fitted(value, maxWidth, maxHeight) ?: return
        val pitch = DotGlyphFont.fitPitch(text, maxWidth, maxHeight)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        DotGlyphFont.drawCenteredInk(canvas, text, centerX, centerY, pitch, paint)
    }

    private fun fitted(value: String, maxWidth: Float, maxHeight: Float): String? {
        if (value.isEmpty()) return null
        val fittedPitch = DotGlyphFont.fitPitch(value, maxWidth, maxHeight)
        if (fittedPitch <= 0f) return null
        val maxColumns = (maxWidth / fittedPitch).toInt()
        var end = value.length
        while (end > 0 && DotGlyphFont.columnsFor(value.substring(0, end)) > maxColumns) {
            end--
        }
        return if (end <= 0) null else value.substring(0, end)
    }

    private fun fill(color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
    }

    private fun withAlpha(color: Int, alpha: Int): Int =
        ((alpha and 0xFF) shl 24) or (color and 0x00FFFFFF)
}
