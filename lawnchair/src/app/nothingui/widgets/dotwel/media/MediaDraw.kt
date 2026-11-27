package app.nothingui.widgets.dotwel.media

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import app.nothingui.widgets.dotwel.WidgetStyle
import kotlin.math.min

internal data class MediaPalette(
    val background: Int?,
    val ink: Int,
    val muted: Int,
    val accent: Int,
    val primary: Int,
    val onPrimary: Int,
)

internal object MediaDraw {
    const val RED = 0xFFD71921.toInt()
    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val INK_DARK = 0xFF1B1B1D.toInt()
    private const val TRANSLUCENT = 0xA6FFFFFF.toInt()

    fun palette(style: WidgetStyle): MediaPalette = when (style) {
        WidgetStyle.BLACK -> MediaPalette(
            background = INK_DARK,
            ink = WHITE,
            muted = 0x80FFFFFF.toInt(),
            accent = 0x4DFFFFFF,
            primary = RED,
            onPrimary = WHITE,
        )

        WidgetStyle.TRANSLUCENT -> MediaPalette(
            background = TRANSLUCENT,
            ink = INK_DARK,
            muted = 0x801B1B1D.toInt(),
            accent = 0x4D1B1B1D,
            primary = RED,
            onPrimary = WHITE,
        )

        WidgetStyle.TRANSPARENT -> MediaPalette(
            background = null,
            ink = WHITE,
            muted = 0x80FFFFFF.toInt(),
            accent = 0x33FFFFFF,
            primary = RED,
            onPrimary = WHITE,
        )
    }

    fun fill(color: Int, stroke: Float = 0f): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        if (stroke > 0f) {
            style = Paint.Style.STROKE
            strokeWidth = stroke
        }
    }

    fun text(color: Int, size: Float, bold: Boolean = false): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textSize = size.coerceAtLeast(1f)
        typeface = Typeface.create(
            "sans-serif",
            if (bold) Typeface.BOLD else Typeface.NORMAL,
        )
        isSubpixelText = true
    }

    fun background(canvas: Canvas, rect: RectF, radius: Float, color: Int?) {
        if (color == null) return
        canvas.drawRoundRect(rect, radius, radius, fill(color))
    }

    fun cover(canvas: Canvas, bitmap: Bitmap?, rect: RectF, radius: Float, fallback: Int) {
        canvas.save()
        val path = Path().apply {
            addRoundRect(rect, radius, radius, Path.Direction.CW)
        }
        canvas.clipPath(path)
        if (bitmap != null && !bitmap.isRecycled) {
            val scale = min(rect.width() / bitmap.width, rect.height() / bitmap.height)
            val width = bitmap.width * scale
            val height = bitmap.height * scale
            val left = rect.centerX() - width / 2f
            val top = rect.centerY() - height / 2f
            canvas.drawBitmap(
                bitmap,
                null,
                RectF(left, top, left + width, top + height),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
        } else {
            canvas.drawRect(rect, fill(fallback))
            val wave = fill(0x33FFFFFF)
            val step = rect.width() / 7f
            for (index in 0 until 7) {
                val x = rect.left + step * index
                canvas.drawRect(
                    x,
                    rect.top,
                    x + step * 0.55f,
                    rect.bottom,
                    wave,
                )
            }
        }
        canvas.restore()
    }

    fun ellipsize(paint: Paint, value: String?, maxWidth: Float): String {
        val text = value?.trim().orEmpty()
        if (text.isEmpty()) return ""
        if (paint.measureText(text) <= maxWidth) return text
        val ellipsis = "\u2026"
        var end = text.length
        while (end > 1 && paint.measureText(text.substring(0, end) + ellipsis) > maxWidth) {
            end--
        }
        return text.substring(0, end).trimEnd() + ellipsis
    }

    fun drawText(
        canvas: Canvas,
        paint: Paint,
        value: String?,
        x: Float,
        baseline: Float,
        maxWidth: Float,
        align: Paint.Align = Paint.Align.LEFT,
    ) {
        paint.textAlign = align
        val text = ellipsize(paint, value, maxWidth)
        if (text.isEmpty()) return
        val px = when (align) {
            Paint.Align.CENTER -> x
            Paint.Align.RIGHT -> x
            else -> x
        }
        canvas.drawText(text, px, baseline, paint)
    }

    fun drawProgress(
        canvas: Canvas,
        rect: RectF,
        fraction: Float,
        foreground: Int,
        background: Int,
        rounded: Boolean = true,
    ) {
        val radius = if (rounded) rect.height() / 2f else 0f
        canvas.drawRoundRect(rect, radius, radius, fill(background))
        if (fraction <= 0f) return
        val width = rect.width() * fraction.coerceIn(0f, 1f)
        if (width <= 0f) return
        val filled = RectF(rect.left, rect.top, rect.left + width.coerceAtLeast(1f), rect.bottom)
        canvas.drawRoundRect(filled, radius, radius, fill(foreground))
    }

    fun drawPlayPause(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        size: Float,
        playing: Boolean,
        color: Int,
    ) {
        val paint = fill(color)
        if (playing) {
            val barWidth = size * 0.2f
            val gap = size * 0.12f
            val top = centerY - size / 2f
            canvas.drawRect(
                centerX - gap / 2f - barWidth,
                top,
                centerX - gap / 2f,
                top + size,
                paint,
            )
            canvas.drawRect(
                centerX + gap / 2f,
                top,
                centerX + gap / 2f + barWidth,
                top + size,
                paint,
            )
        } else {
            val path = Path().apply {
                moveTo(centerX - size * 0.32f, centerY - size / 2f)
                lineTo(centerX + size * 0.5f, centerY)
                lineTo(centerX - size * 0.32f, centerY + size / 2f)
                close()
            }
            canvas.drawPath(path, paint)
        }
    }

    fun drawSkip(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        size: Float,
        previous: Boolean,
        color: Int,
        enabled: Boolean = true,
    ) {
        if (!enabled) return
        val paint = fill(color)
        val direction = if (previous) -1f else 1f
        val path = Path().apply {
            if (previous) {
                moveTo(centerX + size * 0.28f, centerY - size / 2f)
                lineTo(centerX - size * 0.36f, centerY)
                lineTo(centerX + size * 0.28f, centerY + size / 2f)
            } else {
                moveTo(centerX - size * 0.28f, centerY - size / 2f)
                lineTo(centerX + size * 0.36f, centerY)
                lineTo(centerX - size * 0.28f, centerY + size / 2f)
            }
            close()
        }
        canvas.drawPath(path, paint)
        val barX = centerX + direction * size * 0.42f
        canvas.drawRect(
            barX - size * 0.06f,
            centerY - size / 2f,
            barX + size * 0.06f,
            centerY + size / 2f,
            paint,
        )
    }

    fun drawDevice(canvas: Canvas, centerX: Float, centerY: Float, size: Float, color: Int) {
        val paint = fill(color)
        val rect = RectF(
            centerX - size * 0.34f,
            centerY - size * 0.46f,
            centerX + size * 0.34f,
            centerY + size * 0.28f,
        )
        canvas.drawRoundRect(rect, size * 0.1f, size * 0.1f, paint)
        canvas.drawRect(
            centerX - size * 0.12f,
            centerY + size * 0.32f,
            centerX + size * 0.12f,
            centerY + size * 0.42f,
            paint,
        )
    }

    fun timeText(millis: Long): String {
        val safe = millis.coerceAtLeast(0L) / 1000L
        val minutes = safe / 60L
        val seconds = safe % 60L
        return "%d:%02d".format(minutes, seconds)
    }
}
