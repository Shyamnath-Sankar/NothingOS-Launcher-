package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import com.android.launcher3.R
import kotlin.math.min

/**
 * Readable Kotlin conversion of `iOS_Battery_Widget` from
 * AumGupta/KWGT-Widgets (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f,
 * MIT, Copyright (c) 2024 Om Gupta). Sanitized source data:
 * assets/kwgt/ios_battery.sanitized.json.
 *
 * Retained author relationships (actual source values, not the upstream
 * preview description):
 * - light grey rounded background `#B75B5B5B` with 69 corners
 * - 92-circle ring at 32 top/left padding, 10 stroke and `#343434` dark track
 * - active ring colour `level < 15` red `#ED1B24`, `level < 25` orange
 *   `#FA9F1B`, otherwise green `#3ABD54`
 * - centred 52 battery icon switched by the source
 *   `if(bi(charging)=0, if(gv(b)<gv(b_low), battery_alert, Battery_std), Battery_charging_full)`
 * - 92 percentage readout at 32 left / 16 bottom padding
 *
 * The source `ProductSans.ttf` is replaced by the platform sans-serif family.
 * The ShapeModule `fx_gradient_bitmap = $mi(cover)$` formula is intentionally
 * not rendered: no gradient mode is selected in the source, the embedded
 * preview is flat, and no album or cover is retrieved.
 *
 * The Komponent `config_visible` formula is inactive (toggle 0), so the stale
 * Niagara/media formula has no effect and this widget has no media dependency.
 *
 * Scaling basis: the preset_info canvas is 416x542, but that is the full preview
 * canvas with transparent margins. The actual Komponent design card is the
 * `bgwidth`/`bgheight` global value 290, and the ShapeModule width formula uses
 * `min(bgwidth, bgheight)`. The ring, padding, percentage and corners are
 * therefore normalised to the 290 component card, not the 416 preview canvas.
 * Each bitmap is drawn from its own received raster width/height with one
 * uniform `min(width, height) / 290` scale, so the provider never mixes host
 * coordinates with the raster or applies a second scale.
 */
object IosBatteryRenderer {
    const val SOURCE_COMPONENT_SIDE = 290f

    const val BACKGROUND_CORNER = 69f
    const val RING_PADDING = 32f
    const val RING_SIZE = 92f
    const val RING_STROKE = 10f
    const val ICON_SIZE = 52f
    const val TEXT_SIZE = 92f
    const val TEXT_PADDING_LEFT = 32f
    const val TEXT_PADDING_BOTTOM = 16f

    const val LOW_THRESHOLD = 15
    const val MED_THRESHOLD = 25

    const val TRACK = 0xFF343434.toInt()
    const val LOW_RED = 0xFFED1B24.toInt()
    const val MED_ORANGE = 0xFFFA9F1B.toInt()
    const val HEALTHY_GREEN = 0xFF3ABD54.toInt()

    const val INK = 0xFFFFFFFF.toInt()
    const val BLACK_SURFACE = 0xFF5B5B5B.toInt()
    const val TRANSLUCENT_SURFACE = 0xB75B5B5B.toInt()

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

    data class Layout(
        val width: Float,
        val height: Float,
        val side: Float,
        val scale: Float,
        val background: Rect,
        val backgroundCorner: Float,
        val ring: Rect,
        val ringStroke: Float,
        val icon: Rect,
        val textLeft: Float,
        val textBottom: Float,
        val textSize: Float,
    ) {
        val textMaxWidth: Float get() = width - 2f * textLeft
    }

    fun isKnown(level: Int): Boolean = level in 0..100

    fun surfaceColor(style: WidgetStyle): Int = when (style) {
        WidgetStyle.BLACK -> BLACK_SURFACE
        WidgetStyle.TRANSLUCENT -> TRANSLUCENT_SURFACE
        WidgetStyle.TRANSPARENT -> 0
    }

    fun ringColor(level: Int): Int = when {
        !isKnown(level) -> TRACK
        level < LOW_THRESHOLD -> LOW_RED
        level < MED_THRESHOLD -> MED_ORANGE
        else -> HEALTHY_GREEN
    }

    fun sweepFraction(level: Int): Float = if (isKnown(level)) level / 100f else 0f

    fun percentText(level: Int): String = if (isKnown(level)) "$level%" else "--"

    fun iconRes(charging: Boolean, level: Int): Int = when {
        charging -> R.drawable.dw_ios_battery_charging
        isKnown(level) && level < LOW_THRESHOLD -> R.drawable.dw_ios_battery_alert
        else -> R.drawable.dw_ios_battery_std
    }

    fun layout(widthPx: Float, heightPx: Float): Layout {
        val width = widthPx.coerceAtLeast(1f)
        val height = heightPx.coerceAtLeast(1f)
        val side = min(width, height)
        val scale = side / SOURCE_COMPONENT_SIDE

        val ringPadding = RING_PADDING * scale
        val ringSize = RING_SIZE * scale
        val ring = Rect(
            left = ringPadding,
            top = ringPadding,
            right = ringPadding + ringSize,
            bottom = ringPadding + ringSize,
        )
        val ringStroke = (RING_STROKE * scale).coerceAtLeast(1f)
        val iconSize = (ICON_SIZE * scale)
            .coerceAtMost((ringSize - ringStroke).coerceAtLeast(1f))
        val icon = Rect(
            left = ring.centerX - iconSize / 2f,
            top = ring.centerY - iconSize / 2f,
            right = ring.centerX + iconSize / 2f,
            bottom = ring.centerY + iconSize / 2f,
        )

        return Layout(
            width = width,
            height = height,
            side = side,
            scale = scale,
            background = Rect(0f, 0f, width, height),
            backgroundCorner = BACKGROUND_CORNER * scale,
            ring = ring,
            ringStroke = ringStroke,
            icon = icon,
            textLeft = TEXT_PADDING_LEFT * scale,
            textBottom = TEXT_PADDING_BOTTOM * scale,
            textSize = TEXT_SIZE * scale,
        )
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        level: Int,
        charging: Boolean,
        includeBackground: Boolean = true,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val layout = layout(safeWidth.toFloat(), safeHeight.toFloat())
        val bitmap = Bitmap.createBitmap(
            safeWidth,
            safeHeight,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        if (includeBackground) drawBackground(canvas, layout, style)
        drawPercent(canvas, layout, level)
        drawRing(canvas, layout, level)
        drawIcon(canvas, context, layout, charging, level)
        return bitmap
    }

    private fun drawBackground(
        canvas: Canvas,
        layout: Layout,
        style: WidgetStyle,
    ) {
        val color = surfaceColor(style)
        if (((color ushr 24) and 0xFF) == 0) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val background = layout.background
        canvas.drawRoundRect(
            RectF(background.left, background.top, background.right, background.bottom),
            layout.backgroundCorner,
            layout.backgroundCorner,
            paint,
        )
    }

    private fun drawRing(canvas: Canvas, layout: Layout, level: Int) {
        val inset = layout.ringStroke / 2f
        val arc = RectF(
            layout.ring.left + inset,
            layout.ring.top + inset,
            layout.ring.right - inset,
            layout.ring.bottom - inset,
        )
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            strokeWidth = layout.ringStroke
            // The sanitized ProgressModule has no cap toggle, but the actual
            // source preview shows rounded stroke ends, so keep ROUND.
            strokeCap = Paint.Cap.ROUND
        }
        paint.color = TRACK
        canvas.drawArc(arc, 0f, 360f, false, paint)
        val sweep = sweepFraction(level)
        if (sweep > 0f) {
            paint.color = ringColor(level)
            canvas.drawArc(arc, -90f, sweep * 360f, false, paint)
        }
    }

    private fun drawIcon(
        canvas: Canvas,
        context: Context,
        layout: Layout,
        charging: Boolean,
        level: Int,
    ) {
        val drawable = context.getDrawable(iconRes(charging, level)) ?: return
        drawable.setTint(INK)
        val icon = layout.icon
        drawable.setBounds(
            icon.left.toInt(),
            icon.top.toInt(),
            icon.right.toInt(),
            icon.bottom.toInt(),
        )
        drawable.draw(canvas)
    }

    private fun drawPercent(canvas: Canvas, layout: Layout, level: Int) {
        val text = percentText(level)
        val paint = Paint(
            Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG,
        ).apply {
            color = INK
            textSize = layout.textSize
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            textAlign = Paint.Align.LEFT
        }
        val measured = paint.measureText(text)
        if (measured > layout.textMaxWidth && measured > 0f) {
            paint.textSize *= layout.textMaxWidth / measured
        }
        val baseline = layout.height - layout.textBottom - paint.fontMetrics.descent
        canvas.drawText(text, layout.textLeft, baseline, paint)
    }
}
