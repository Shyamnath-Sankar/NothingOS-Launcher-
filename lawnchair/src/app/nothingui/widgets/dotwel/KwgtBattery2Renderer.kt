package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.ceil
import kotlin.math.min

/**
 * Readable Kotlin conversion of `Nothing_Battery2` from AumGupta/KWGT-Widgets
 * (commit 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024
 * Om Gupta). Sanitized source data: assets/kwgt/nothing_battery2.sanitized.json.
 *
 * Retained author relationships:
 * - `side = min(width, height)`, rounded background corners `side / 5`
 * - dark `#FF1B1B1D` / light white surface with the opposite foreground
 * - `accent = fg at 50% alpha`; primary red `#FFD71921` retained from the
 *   REMAINING text paint because the source `primary` global has no value
 * - information stack offset `side / 8.5` to the right of centre
 * - BATTERY label `side / 18` with the source 16 bottom padding
 * - outlined battery body 195 x 78, corners 14, stroke 3.5; clip 179 x 64,
 *   corners 7; 16 rectangular progress segments across 184 x 64, drawn
 *   foreground over accent and clipped by the rounded clip; pill nub 5 x 28
 *   with a 5 margin
 * - large real level `side / 4.5` with the smaller percent `side / 10`
 * - bottom row `side / 15` with an 8 margin
 *
 * The literal geometry above is expressed against the author's 277 design
 * reference and multiplied by `side / 277`. The source has no `h` global, so
 * the background uses the host height and the whole vertical stack is centred
 * instead of reproducing the missing height. This is a documented fit correction
 * for square and portrait hosts, not pixel-identical upstream output.
 *
 * Android has no reliable discharge-time API. The bottom row only shows a real
 * `BatteryManager.computeChargeTimeRemaining()` value while charging. When that
 * value is unavailable the row shows `--` and `ESTIMATE UNAVAILABLE`; it never
 * fabricates hours or minutes. At 100% it shows `FULL` with no invented time.
 *
 * The prohibited `ndot-47.ttf` is replaced by Dotwel's original dot glyphs for
 * the BATTERY label and the large level. The long bottom status uses the Android
 * platform sans-serif family so the honest unavailable copy stays legible.
 */
object KwgtBattery2Renderer {
    const val SOURCE_WIDTH = 415f
    const val SOURCE_HEIGHT = 542f
    const val REFERENCE_SIDE = 277f

    const val BACKGROUND_CORNER_DIVISOR = 5f
    const val INFO_OFFSET_DIVISOR = 8.5f
    const val LABEL_SIZE_DIVISOR = 18f
    const val LABEL_BOTTOM_PADDING = 16f

    const val BODY_WIDTH = 195f
    const val BODY_HEIGHT = 78f
    const val BODY_CORNER = 14f
    const val BODY_STROKE = 3.5f
    const val CLIP_WIDTH = 179f
    const val CLIP_HEIGHT = 64f
    const val CLIP_CORNER = 7f
    const val SEGMENT_COUNT = 16
    const val PROGRESS_WIDTH = 184f
    const val PROGRESS_HEIGHT = 64f
    const val SEGMENT_GAP = 1.5f
    const val NUB_WIDTH = 5f
    const val NUB_HEIGHT = 28f
    const val NUB_MARGIN = 5f
    const val ROW_GAP = 6f
    const val LEVEL_SIZE_DIVISOR = 4.5f
    const val PERCENT_SIZE_DIVISOR = 10f
    const val PERCENT_GAP = 3f
    const val BOTTOM_SIZE_DIVISOR = 15f
    const val BOTTOM_MARGIN = 8f

    const val DARK_BACKGROUND = 0xFF1B1B1D.toInt()
    const val LIGHT_BACKGROUND = 0xFFFFFFFF.toInt()
    const val PRIMARY = 0xFFFFD71921.toInt()

    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val DARK_INK = 0xFF1B1B1D.toInt()

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
        val accent: Int,
    )

    data class Layout(
        val width: Float,
        val height: Float,
        val side: Float,
        val scale: Float,
        val infoCenterX: Float,
        val background: Rect,
        val backgroundCorner: Float,
        val labelTextSize: Float,
        val labelCenterY: Float,
        val body: Rect,
        val clip: Rect,
        val progress: Rect,
        val nub: Rect,
        val bodyStroke: Float,
        val bodyCorner: Float,
        val clipCorner: Float,
        val levelTextSize: Float,
        val percentTextSize: Float,
        val levelCenterY: Float,
        val bottomTextSize: Float,
        val bottomCenterY: Float,
        val bottomMargin: Float,
    )

    data class Segment(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
        val filledFraction: Float,
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
    }

    enum class EstimateKind {
        FULL,
        TO_FULL,
        UNAVAILABLE,
    }

    data class Estimate(
        val kind: EstimateKind,
        val hours: Int = 0,
        val minutes: Int = 0,
    ) {
        val valueText: String
            get() = when (kind) {
                EstimateKind.FULL -> "FULL"
                EstimateKind.TO_FULL -> "${hours}H ${minutes}M"
                EstimateKind.UNAVAILABLE -> "--"
            }

        val labelText: String
            get() = when (kind) {
                EstimateKind.FULL -> ""
                EstimateKind.TO_FULL -> "TO FULL"
                EstimateKind.UNAVAILABLE -> "ESTIMATE UNAVAILABLE"
            }
    }

    fun isDark(context: Context, style: WidgetStyle): Boolean = when (style) {
        WidgetStyle.BLACK -> true

        WidgetStyle.TRANSLUCENT -> false

        WidgetStyle.TRANSPARENT -> {
            val mode = context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK
            mode == Configuration.UI_MODE_NIGHT_YES
        }
    }

    fun palette(dark: Boolean, style: WidgetStyle): Palette {
        val background = when {
            style == WidgetStyle.TRANSPARENT -> 0

            style == WidgetStyle.TRANSLUCENT -> withAlpha(
                if (dark) DARK_BACKGROUND else LIGHT_BACKGROUND,
                0xA6,
            )

            dark -> DARK_BACKGROUND

            else -> LIGHT_BACKGROUND
        }
        val foreground = if (dark) WHITE else DARK_INK
        return Palette(
            background = background,
            foreground = foreground,
            accent = withAlpha(foreground, 0x80),
        )
    }

    fun palette(context: Context, style: WidgetStyle): Palette = palette(isDark(context, style), style)

    fun layout(widthPx: Float, heightPx: Float): Layout {
        val width = widthPx.coerceAtLeast(1f)
        val height = heightPx.coerceAtLeast(1f)
        val side = min(width, height)
        val scale = (side / REFERENCE_SIDE).coerceAtLeast(0.0001f)
        val infoCenterX = width / 2f + side / INFO_OFFSET_DIVISOR

        val background = Rect(
            left = (width - side) / 2f,
            top = 0f,
            right = (width + side) / 2f,
            bottom = height,
        )
        val backgroundCorner = side / BACKGROUND_CORNER_DIVISOR

        val labelTextSize = side / LABEL_SIZE_DIVISOR
        val labelPadding = LABEL_BOTTOM_PADDING * scale
        val rowGap = ROW_GAP * scale
        val bodyWidth = BODY_WIDTH * scale
        val bodyHeight = BODY_HEIGHT * scale
        val clipWidth = CLIP_WIDTH * scale
        val clipHeight = CLIP_HEIGHT * scale
        val progressWidth = PROGRESS_WIDTH * scale
        val progressHeight = PROGRESS_HEIGHT * scale
        val nubWidth = NUB_WIDTH * scale
        val nubHeight = NUB_HEIGHT * scale
        val levelTextSize = side / LEVEL_SIZE_DIVISOR
        val percentTextSize = side / PERCENT_SIZE_DIVISOR
        val bottomTextSize = side / BOTTOM_SIZE_DIVISOR

        val totalHeight = labelTextSize +
            labelPadding +
            bodyHeight +
            rowGap +
            levelTextSize +
            rowGap +
            bottomTextSize
        var top = (height - totalHeight) / 2f

        val labelCenterY = top + labelTextSize / 2f
        top += labelTextSize + labelPadding

        val batteryCenterY = top + bodyHeight / 2f
        val batteryRowWidth = bodyWidth + (NUB_MARGIN + NUB_WIDTH) * scale
        val bodyLeft = infoCenterX - batteryRowWidth / 2f
        val body = Rect(
            left = bodyLeft,
            top = batteryCenterY - bodyHeight / 2f,
            right = bodyLeft + bodyWidth,
            bottom = batteryCenterY + bodyHeight / 2f,
        )
        val clip = Rect(
            left = body.centerX - clipWidth / 2f,
            top = body.centerY - clipHeight / 2f,
            right = body.centerX + clipWidth / 2f,
            bottom = body.centerY + clipHeight / 2f,
        )
        val progress = Rect(
            left = body.centerX - progressWidth / 2f,
            top = body.centerY - progressHeight / 2f,
            right = body.centerX + progressWidth / 2f,
            bottom = body.centerY + progressHeight / 2f,
        )
        val nubLeft = body.right + NUB_MARGIN * scale
        val nub = Rect(
            left = nubLeft,
            top = body.centerY - nubHeight / 2f,
            right = nubLeft + nubWidth,
            bottom = body.centerY + nubHeight / 2f,
        )
        top += bodyHeight + rowGap

        val levelCenterY = top + levelTextSize / 2f
        top += levelTextSize + rowGap

        val bottomCenterY = top + bottomTextSize / 2f

        return Layout(
            width = width,
            height = height,
            side = side,
            scale = scale,
            infoCenterX = infoCenterX,
            background = background,
            backgroundCorner = backgroundCorner,
            labelTextSize = labelTextSize,
            labelCenterY = labelCenterY,
            body = body,
            clip = clip,
            progress = progress,
            nub = nub,
            bodyStroke = (BODY_STROKE * scale).coerceAtLeast(1f),
            bodyCorner = BODY_CORNER * scale,
            clipCorner = CLIP_CORNER * scale,
            levelTextSize = levelTextSize,
            percentTextSize = percentTextSize,
            levelCenterY = levelCenterY,
            bottomTextSize = bottomTextSize,
            bottomCenterY = bottomCenterY,
            bottomMargin = BOTTOM_MARGIN * scale,
        )
    }

    fun segmentFills(level: Int): FloatArray {
        val safeLevel = level.coerceIn(0, 100)
        val scaled = safeLevel / 100f * SEGMENT_COUNT
        return FloatArray(SEGMENT_COUNT) { index ->
            (scaled - index).coerceIn(0f, 1f)
        }
    }

    fun segments(layout: Layout, level: Int): List<Segment> {
        val gap = (SEGMENT_GAP * layout.scale)
            .coerceAtMost(layout.progress.width / (SEGMENT_COUNT * 2f))
        val segmentWidth =
            (layout.progress.width - gap * (SEGMENT_COUNT - 1)) / SEGMENT_COUNT
        val fills = segmentFills(level)
        return List(SEGMENT_COUNT) { index ->
            val left = layout.progress.left + index * (segmentWidth + gap)
            Segment(
                left = left,
                top = layout.progress.top,
                right = left + segmentWidth,
                bottom = layout.progress.bottom,
                filledFraction = fills[index],
            )
        }
    }

    fun estimate(level: Int, charging: Boolean, remainingMillis: Long?): Estimate {
        val safeLevel = level.coerceIn(0, 100)
        if (safeLevel >= 100) return Estimate(EstimateKind.FULL)
        if (!charging || remainingMillis == null || remainingMillis <= 0L) {
            return Estimate(EstimateKind.UNAVAILABLE)
        }
        val totalMinutes = ceil(remainingMillis / 60_000.0)
            .toInt()
            .coerceAtLeast(1)
        return Estimate(
            kind = EstimateKind.TO_FULL,
            hours = totalMinutes / 60,
            minutes = totalMinutes % 60,
        )
    }

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        level: Int,
        estimate: Estimate,
        includeBackground: Boolean = true,
    ): Bitmap {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val safeLevel = level.coerceIn(0, 100)
        val layout = layout(safeWidth.toFloat(), safeHeight.toFloat())
        val palette = palette(context, style)
        val bitmap = Bitmap.createBitmap(
            safeWidth,
            safeHeight,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        if (includeBackground) {
            drawBackground(canvas, layout, palette)
        }
        drawLabel(canvas, layout, palette)
        drawBattery(canvas, layout, palette, safeLevel)
        drawLevel(canvas, layout, palette, safeLevel)
        drawEstimate(canvas, layout, palette, estimate)
        return bitmap
    }

    private fun drawBackground(canvas: Canvas, layout: Layout, palette: Palette) {
        if (((palette.background ushr 24) and 0xFF) == 0) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = palette.background
        }
        val background = layout.background
        canvas.drawRoundRect(
            RectF(background.left, background.top, background.right, background.bottom),
            layout.backgroundCorner,
            layout.backgroundCorner,
            paint,
        )
    }

    private fun drawLabel(canvas: Canvas, layout: Layout, palette: Palette) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = palette.foreground
        }
        val pitch = DotGlyphFont.fitPitch(
            "BATTERY",
            layout.side * 0.85f,
            layout.labelTextSize,
        )
        DotGlyphFont.drawCentered(
            canvas,
            "BATTERY",
            layout.infoCenterX,
            layout.labelCenterY,
            pitch,
            paint,
        )
    }

    private fun drawBattery(
        canvas: Canvas,
        layout: Layout,
        palette: Palette,
        level: Int,
    ) {
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = palette.foreground
            style = Paint.Style.STROKE
            strokeWidth = layout.bodyStroke
        }
        val body = layout.body
        canvas.drawRoundRect(
            RectF(body.left, body.top, body.right, body.bottom),
            layout.bodyCorner,
            layout.bodyCorner,
            bodyPaint,
        )

        val nubPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = palette.foreground
        }
        val nub = layout.nub
        val nubRadius = min(nub.width, nub.height) / 2f
        canvas.drawRoundRect(
            RectF(nub.left, nub.top, nub.right, nub.bottom),
            nubRadius,
            nubRadius,
            nubPaint,
        )

        val clipPath = Path().apply {
            addRoundRect(
                RectF(
                    layout.clip.left,
                    layout.clip.top,
                    layout.clip.right,
                    layout.clip.bottom,
                ),
                layout.clipCorner,
                layout.clipCorner,
                Path.Direction.CW,
            )
        }
        val segmentPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        canvas.save()
        canvas.clipPath(clipPath)
        segments(layout, level).forEach { segment ->
            segmentPaint.color = palette.accent
            canvas.drawRect(
                segment.left,
                segment.top,
                segment.right,
                segment.bottom,
                segmentPaint,
            )
            if (segment.filledFraction > 0f) {
                segmentPaint.color = palette.foreground
                val filledRight = segment.left + segment.width * segment.filledFraction
                canvas.drawRect(
                    segment.left,
                    segment.top,
                    filledRight,
                    segment.bottom,
                    segmentPaint,
                )
            }
        }
        canvas.restore()
    }

    private fun drawLevel(
        canvas: Canvas,
        layout: Layout,
        palette: Palette,
        level: Int,
    ) {
        val levelText = level.toString()
        val levelPitch = DotGlyphFont.fitPitch(
            levelText,
            layout.side * 0.42f,
            layout.levelTextSize,
        )
        val percentPitch = DotGlyphFont.fitPitch(
            "%",
            layout.side * 0.12f,
            layout.percentTextSize,
        )
        val levelWidth = DotGlyphFont.columnsFor(levelText) * levelPitch
        val percentWidth = DotGlyphFont.columnsFor("%") * percentPitch
        val gap = PERCENT_GAP * layout.scale
        val rowWidth = levelWidth + gap + percentWidth
        val left = layout.infoCenterX - rowWidth / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = palette.foreground
        }
        DotGlyphFont.drawLeft(
            canvas,
            levelText,
            left,
            layout.levelCenterY,
            levelPitch,
            paint,
        )
        DotGlyphFont.drawLeft(
            canvas,
            "%",
            left + levelWidth + gap,
            layout.levelCenterY,
            percentPitch,
            paint,
        )
    }

    private fun drawEstimate(
        canvas: Canvas,
        layout: Layout,
        palette: Palette,
        estimate: Estimate,
    ) {
        val maxWidth = (
            2f * min(layout.infoCenterX, layout.width - layout.infoCenterX) -
                2f * layout.side * 0.08f
            ).coerceAtLeast(1f)
        val typeface = Typeface.create("sans-serif", Typeface.BOLD)
        val valuePaint = Paint(
            Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG,
        ).apply {
            color = palette.foreground
            textSize = layout.bottomTextSize
            this.typeface = typeface
            textAlign = Paint.Align.LEFT
        }
        val labelPaint = Paint(
            Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG,
        ).apply {
            color = PRIMARY
            textSize = layout.bottomTextSize
            this.typeface = typeface
            textAlign = Paint.Align.LEFT
        }

        if (estimate.kind == EstimateKind.FULL) {
            val value = estimate.valueText
            valuePaint.color = PRIMARY
            val width = valuePaint.measureText(value)
            val fit = min(1f, maxWidth / width.coerceAtLeast(1f))
            valuePaint.textSize *= fit
            val baseline = layout.bottomCenterY -
                (valuePaint.fontMetrics.ascent + valuePaint.fontMetrics.descent) / 2f
            canvas.drawText(
                value,
                layout.infoCenterX - valuePaint.measureText(value) / 2f,
                baseline,
                valuePaint,
            )
            return
        }

        val value = estimate.valueText
        val label = estimate.labelText
        val gap = layout.bottomMargin
        val totalWidth = valuePaint.measureText(value) +
            gap +
            labelPaint.measureText(label)
        val fit = min(1f, maxWidth / totalWidth.coerceAtLeast(1f))
        valuePaint.textSize *= fit
        labelPaint.textSize *= fit
        val scaledGap = gap * fit
        val scaledWidth = valuePaint.measureText(value) +
            scaledGap +
            labelPaint.measureText(label)
        val left = layout.infoCenterX - scaledWidth / 2f
        val baseline = layout.bottomCenterY -
            (valuePaint.fontMetrics.ascent + valuePaint.fontMetrics.descent) / 2f
        canvas.drawText(value, left, baseline, valuePaint)
        canvas.drawText(
            label,
            left + valuePaint.measureText(value) + scaledGap,
            baseline,
            labelPaint,
        )
    }

    private fun withAlpha(color: Int, alpha: Int): Int = ((alpha and 0xFF) shl 24) or (color and 0x00FFFFFF)
}
