package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import com.android.launcher3.R
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/**
 * Small byte-bounded LRU cache. Used for compiled Interstellar layer bitmaps so
 * repeated widget updates at the same pixel size reuse the raster instead of
 * decoding and rescaling every drawable on every pass.
 */
internal class BoundedLayerCache<K, V>(
    private val maxBytes: Long,
    private val sizeOf: (V) -> Long,
) {
    private val entries = object : LinkedHashMap<K, V>(16, 0.75f, true) {}

    @Synchronized
    fun get(key: K): V? = entries[key]

    /**
     * Returns true when [value] is retained by the cache. An entry larger than
     * the whole budget is rejected so the caller can draw and release it.
     */
    @Synchronized
    fun put(key: K, value: V): Boolean {
        val size = sizeOf(value)
        if (size > maxBytes) return false
        entries.remove(key)?.let { bytes -= sizeOf(it) }
        entries[key] = value
        bytes += size
        val iterator = entries.entries.iterator()
        while (bytes > maxBytes && iterator.hasNext()) {
            val eldest = iterator.next()
            iterator.remove()
            bytes -= sizeOf(eldest.value)
        }
        return entries[key] === value
    }

    @Synchronized
    fun size(): Int = entries.size

    @Synchronized
    fun bytes(): Long = bytes

    private var bytes = 0L
}

/**
 * Reusable compiler/renderer for the sanitized Interstellar Endurance source
 * shapes (AumGupta/KWGT-Widgets commit
 * 96ca27be4cbff35efec5a86c64dd39fd065c958f, MIT, Copyright (c) 2024 Om Gupta).
 *
 * The compiler keeps the author ShapeModule geometry, StackLayerModule order,
 * OverlapLayerModule z-order, progress counts and rotation modes. It does not
 * replace the source with a generic dial. Formula evaluation supports the
 * subset the source actually uses (`$gv(side)/(277/N)$`, `$gv(side)/N$`,
 * constants and their negative forms). Unsupported expressions are skipped
 * rather than guessed.
 *
 * The source declares no clipping flag, so the port does not invent clipping.
 * A malformed source colour `##FF363636` is repaired to `#FF363636` and
 * recorded in docs/KWGT-LEDGER.md.
 */
object InterstellarShapeCompiler {
    enum class Variant(val asset: String) {
        ENDURANCE("kwgt/interstellar_endurance.sanitized.json"),
        ANALOG("kwgt/interstellar_endurance_analog.sanitized.json"),
        ANALOG_2("kwgt/interstellar_endurance_analog_2.sanitized.json"),
    }

    fun layoutFor(variant: Variant, style: WidgetStyle): Int = when (variant) {
        Variant.ENDURANCE -> when (style) {
            WidgetStyle.BLACK -> R.layout.widget_interstellar_endurance_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_interstellar_endurance_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_interstellar_endurance_transparent
        }

        Variant.ANALOG -> when (style) {
            WidgetStyle.BLACK -> R.layout.widget_interstellar_analog_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_interstellar_analog_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_interstellar_analog_transparent
        }

        Variant.ANALOG_2 -> when (style) {
            WidgetStyle.BLACK -> R.layout.widget_interstellar_analog2_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_interstellar_analog2_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_interstellar_analog2_transparent
        }
    }

    enum class Stacking {
        VERTICAL_CENTER,
        HORIZONTAL_CENTER,
        HORIZONTAL_BOTTOM,
        HORIZONTAL_TOP,
        UNKNOWN,
    }

    enum class Anchor {
        TOPLEFT,
        TOPRIGHT,
        BOTTOMLEFT,
        BOTTOMRIGHT,
        TOP,
        BOTTOM,
        CENTERLEFT,
        CENTERRIGHT,
        CENTER,
        UNKNOWN,
    }

    sealed class Node {
        data class Shape(
            val type: String,
            val widthExpr: String?,
            val heightExpr: String?,
            val cornersExpr: String?,
            val colorKey: String?,
            val rotateMode: String?,
            val rotateOffset: String?,
        ) : Node()

        data class Progress(
            val count: Int,
            val sizeExpr: String?,
            val widthExpr: String?,
            val heightExpr: String?,
            val fgKey: String?,
            val bgKey: String?,
            val shape: String,
            val rotateOffset: String?,
        ) : Node()

        data class Overlap(
            val children: List<Node>,
            val rotateMode: String?,
            val rotateOffset: String?,
        ) : Node()

        data class Stack(
            val children: List<Node>,
            val stacking: Stacking,
            val marginExpr: String?,
            val anchor: Anchor,
            val offsetXExpr: String?,
            val offsetYExpr: String?,
            val paddingTopExpr: String?,
            val paddingBottomExpr: String?,
            val paddingLeftExpr: String?,
            val paddingRightExpr: String?,
        ) : Node()
    }

    data class Compiled(
        val width: Float,
        val height: Float,
        val nodes: List<Node>,
    )

    data class Palette(
        val background: Int,
        val foreground: Int,
        val accent: Int,
    )

    private const val LAYER_CACHE_BYTES = 8L * 1024L * 1024L
    private const val MAX_LAYER_RASTER = 1024

    private data class LayerKey(
        val variant: Variant,
        val layer: String,
        val style: WidgetStyle,
        val width: Int,
        val height: Int,
    )

    private val cache = HashMap<Variant, Compiled>()
    private val layerCache = BoundedLayerCache<LayerKey, Bitmap>(LAYER_CACHE_BYTES) {
        it.allocationByteCount.toLong()
    }

    fun palette(style: WidgetStyle): Palette {
        val background = when (style) {
            WidgetStyle.BLACK -> 0xFF1B1B1D.toInt()
            WidgetStyle.TRANSLUCENT -> 0xA6FFFFFF.toInt()
            WidgetStyle.TRANSPARENT -> Color.TRANSPARENT
        }
        val foreground = when (style) {
            WidgetStyle.BLACK -> Color.WHITE
            WidgetStyle.TRANSLUCENT -> 0xFF1B1B1D.toInt()
            WidgetStyle.TRANSPARENT -> Color.WHITE
        }
        return Palette(background, foreground, 0xFFD71921.toInt())
    }

    internal fun cachedLayerCount(): Int = layerCache.size()

    fun compile(context: Context, variant: Variant): Compiled {
        cache[variant]?.let { return it }
        val text = context.assets.open(variant.asset).bufferedReader().use { it.readText() }
        val root = JSONObject(text)
        val width = root.optDouble("width", 415.0).toFloat()
        val height = root.optDouble("height", 542.0).toFloat()
        val nodes = parseItems(root.optJSONArray("items"))
        return Compiled(width, height, nodes).also { cache[variant] = it }
    }

    fun render(
        context: Context,
        variant: Variant,
        width: Int,
        height: Int,
        style: WidgetStyle,
        now: Calendar = Calendar.getInstance(),
    ): android.graphics.Bitmap {
        val safeWidth = width.coerceAtLeast(2)
        val safeHeight = height.coerceAtLeast(2)
        val bitmap = android.graphics.Bitmap.createBitmap(
            safeWidth,
            safeHeight,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val palette = palette(style)
        if (palette.background != Color.TRANSPARENT) {
            canvas.drawRect(
                RectF(0f, 0f, safeWidth.toFloat(), safeHeight.toFloat()),
                Paint(Paint.ANTI_ALIAS_FLAG).apply { color = palette.background },
            )
        }
        val scale = min(safeWidth / 277f, safeHeight / 277f).coerceAtLeast(0.01f)
        val offsetX = (safeWidth - 277f * scale) / 2f
        val offsetY = (safeHeight - 277f * scale) / 2f
        canvas.save()
        canvas.translate(offsetX, offsetY)
        canvas.scale(scale, scale)
        val second = now.get(Calendar.SECOND).toFloat()
        val minute = now.get(Calendar.MINUTE).toFloat()
        val hour = now.get(Calendar.HOUR).toFloat() + minute / 60f
        val raster = (277f * scale).roundToInt().coerceIn(2, MAX_LAYER_RASTER)
        val layerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFilterBitmap = true }
        fun drawLayer(layerName: String, degrees: Float) {
            val key = LayerKey(variant, layerName, style, raster, raster)
            val cached = layerCache.get(key)
            val layer = cached ?: compileLayer(context, layerRes(variant, layerName, style), raster)
                ?: return
            val retained = cached != null || layerCache.put(key, layer)
            val saved = canvas.save()
            canvas.rotate(degrees, 138.5f, 138.5f)
            canvas.drawBitmap(
                layer,
                null,
                RectF(0f, 0f, 277f, 277f),
                layerPaint,
            )
            canvas.restoreToCount(saved)
            if (!retained) layer.recycle()
        }
        when (variant) {
            Variant.ENDURANCE -> {
                drawLayer("seconds", second * 6f)
                drawLayer("hour", hour * 30f)
                drawLayer("minute", minute * 6f)
            }

            Variant.ANALOG -> {
                drawLayer("seconds", second * 6f)
                drawLayer("hour", hour * 30f)
                drawLayer("minute", minute * 6f)
            }

            Variant.ANALOG_2 -> {
                drawLayer("dial", 0f)
                drawLayer("hour", hour * 30f)
                drawLayer("minute", minute * 6f)
            }
        }
        canvas.restore()
        return bitmap
    }

    private fun compileLayer(
        context: Context,
        res: Int,
        raster: Int,
    ): Bitmap? {
        val decoded = BitmapFactory.decodeResource(context.resources, res) ?: return null
        if (decoded.width == raster && decoded.height == raster) return decoded
        val scaled = Bitmap.createScaledBitmap(decoded, raster, raster, true)
        if (scaled !== decoded) decoded.recycle()
        return scaled
    }

    internal fun layerRes(variant: Variant, layer: String, style: WidgetStyle): Int {
        val s = style.name.lowercase()
        return when (variant) {
            Variant.ENDURANCE -> when (layer) {
                "seconds" -> when (s) {
                    "black" -> R.drawable.interstellar_endurance_seconds_black
                    "translucent" -> R.drawable.interstellar_endurance_seconds_translucent
                    else -> R.drawable.interstellar_endurance_seconds_transparent
                }

                else -> layerRes(Variant.ANALOG, layer, style)
            }

            Variant.ANALOG -> when (layer) {
                "seconds" -> when (s) {
                    "black" -> R.drawable.interstellar_analog_seconds_black
                    "translucent" -> R.drawable.interstellar_analog_seconds_translucent
                    else -> R.drawable.interstellar_analog_seconds_transparent
                }

                "hour" -> when (s) {
                    "black" -> R.drawable.interstellar_analog_hour_black
                    "translucent" -> R.drawable.interstellar_analog_hour_translucent
                    else -> R.drawable.interstellar_analog_hour_transparent
                }

                else -> when (s) {
                    "black" -> R.drawable.interstellar_analog_minute_black
                    "translucent" -> R.drawable.interstellar_analog_minute_translucent
                    else -> R.drawable.interstellar_analog_minute_transparent
                }
            }

            Variant.ANALOG_2 -> when (layer) {
                "dial" -> when (s) {
                    "black" -> R.drawable.interstellar_analog2_dial_black
                    "translucent" -> R.drawable.interstellar_analog2_dial_translucent
                    else -> R.drawable.interstellar_analog2_dial_transparent
                }

                "hour" -> when (s) {
                    "black" -> R.drawable.interstellar_analog2_hour_black
                    "translucent" -> R.drawable.interstellar_analog2_hour_translucent
                    else -> R.drawable.interstellar_analog2_hour_transparent
                }

                else -> when (s) {
                    "black" -> R.drawable.interstellar_analog2_minute_black
                    "translucent" -> R.drawable.interstellar_analog2_minute_translucent
                    else -> R.drawable.interstellar_analog2_minute_transparent
                }
            }
        }
    }

    private data class TimeState(
        val hour: Float,
        val minute: Float,
        val second: Float,
    ) {
        companion object {
            fun from(calendar: Calendar): TimeState = TimeState(
                hour = calendar.get(Calendar.HOUR_OF_DAY).toFloat(),
                minute = calendar.get(Calendar.MINUTE).toFloat(),
                second = calendar.get(Calendar.SECOND).toFloat(),
            )
        }
    }

    private fun drawNode(
        canvas: Canvas,
        node: Node,
        bounds: RectF,
        side: Float,
        palette: Palette,
        time: TimeState,
    ) {
        when (node) {
            is Node.Shape -> drawShape(canvas, node, bounds, side, palette, time)

            is Node.Progress -> drawProgress(canvas, node, bounds, side, palette, time)

            is Node.Overlap -> {
                val saved = canvas.save()
                applyRotation(canvas, node.rotateMode, node.rotateOffset, bounds, side, time)
                node.children.forEach { drawNode(canvas, it, bounds, side, palette, time) }
                canvas.restoreToCount(saved)
            }

            is Node.Stack -> drawStack(canvas, node, bounds, side, palette, time)
        }
    }

    private fun drawShape(
        canvas: Canvas,
        node: Node.Shape,
        parent: RectF,
        side: Float,
        palette: Palette,
        time: TimeState,
    ) {
        val width = eval(node.widthExpr, side) ?: parent.width()
        val height = eval(node.heightExpr, side) ?: parent.height()
        val corners = eval(node.cornersExpr, side) ?: 0f
        val rect = centered(parent, width, height)
        val color = color(node.colorKey, palette)
        val saved = canvas.save()
        applyRotation(canvas, node.rotateMode, node.rotateOffset, rect, side, time)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.FILL
        }
        when (node.type.uppercase()) {
            "CIRCLE", "OVAL" -> canvas.drawOval(rect, paint)
            "TRIANGLE" -> canvas.drawPath(triangle(rect, right = false), paint)
            "RTRIANGLE" -> canvas.drawPath(triangle(rect, right = true), paint)
            else -> canvas.drawRoundRect(rect, corners, corners, paint)
        }
        canvas.restoreToCount(saved)
    }

    private fun drawProgress(
        canvas: Canvas,
        node: Node.Progress,
        parent: RectF,
        side: Float,
        palette: Palette,
        time: TimeState,
    ) {
        val count = node.count.coerceIn(1, 120)
        val size = eval(node.sizeExpr, side) ?: min(parent.width(), parent.height())
        val width = eval(node.widthExpr, side) ?: size * 0.12f
        val height = eval(node.heightExpr, side) ?: size * 0.04f
        val radius = size / 2f
        val centerX = parent.centerX()
        val centerY = parent.centerY()
        val offset = eval(node.rotateOffset, side) ?: 0f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = color(node.fgKey, palette)
            style = Paint.Style.FILL
        }
        for (index in 0 until count) {
            val angle = offset + index * (360f / count)
            val saved = canvas.save()
            canvas.rotate(angle, centerX, centerY)
            if (node.shape.uppercase() == "CIRCLE") {
                canvas.drawCircle(centerX, centerY - radius, width / 2f, paint)
            } else {
                canvas.drawRect(
                    centerX - width / 2f,
                    centerY - radius - height / 2f,
                    centerX + width / 2f,
                    centerY - radius + height / 2f,
                    paint,
                )
            }
            canvas.restoreToCount(saved)
        }
    }

    private fun drawStack(
        canvas: Canvas,
        node: Node.Stack,
        parent: RectF,
        side: Float,
        palette: Palette,
        time: TimeState,
    ) {
        val sizes = node.children.map { measure(it, parent, side) }
        val margin = eval(node.marginExpr, side) ?: 0f
        val vertical = node.stacking == Stacking.VERTICAL_CENTER
        val totalWidth = if (vertical) {
            sizes.maxOfOrNull { it.first } ?: 0f
        } else {
            sizes.sumOf { it.first.toDouble() }.toFloat() + margin * (sizes.size - 1).coerceAtLeast(0)
        }
        val totalHeight = if (vertical) {
            sizes.sumOf { it.second.toDouble() }.toFloat() + margin * (sizes.size - 1).coerceAtLeast(0)
        } else {
            sizes.maxOfOrNull { it.second } ?: 0f
        }
        var left = parent.left
        var top = parent.top
        when (node.anchor) {
            Anchor.TOPLEFT -> Unit

            Anchor.TOPRIGHT -> left = parent.right - totalWidth

            Anchor.BOTTOMLEFT -> top = parent.bottom - totalHeight

            Anchor.BOTTOMRIGHT -> {
                left = parent.right - totalWidth
                top = parent.bottom - totalHeight
            }

            Anchor.TOP -> left = parent.centerX() - totalWidth / 2f

            Anchor.BOTTOM -> {
                left = parent.centerX() - totalWidth / 2f
                top = parent.bottom - totalHeight
            }

            Anchor.CENTERLEFT -> top = parent.centerY() - totalHeight / 2f

            Anchor.CENTERRIGHT -> {
                left = parent.right - totalWidth
                top = parent.centerY() - totalHeight / 2f
            }

            Anchor.CENTER, Anchor.UNKNOWN -> {
                left = parent.centerX() - totalWidth / 2f
                top = parent.centerY() - totalHeight / 2f
            }
        }
        left += eval(node.paddingLeftExpr, side) ?: 0f
        left -= eval(node.paddingRightExpr, side) ?: 0f
        top += eval(node.paddingTopExpr, side) ?: 0f
        top -= eval(node.paddingBottomExpr, side) ?: 0f
        left += eval(node.offsetXExpr, side) ?: 0f
        top += eval(node.offsetYExpr, side) ?: 0f
        var cursor = if (vertical) top else left
        node.children.forEachIndexed { index, child ->
            val (childWidth, childHeight) = sizes[index]
            val childBounds = if (vertical) {
                val childLeft = when (node.stacking) {
                    Stacking.VERTICAL_CENTER -> left + (totalWidth - childWidth) / 2f
                    else -> left
                }
                RectF(childLeft, cursor, childLeft + childWidth, cursor + childHeight)
            } else {
                val childTop = when (node.stacking) {
                    Stacking.HORIZONTAL_TOP -> top
                    Stacking.HORIZONTAL_BOTTOM -> top + totalHeight - childHeight
                    else -> top + (totalHeight - childHeight) / 2f
                }
                RectF(cursor, childTop, cursor + childWidth, childTop + childHeight)
            }
            drawNode(canvas, child, childBounds, side, palette, time)
            cursor += if (vertical) childHeight + margin else childWidth + margin
        }
    }

    private fun measure(node: Node, parent: RectF, side: Float): Pair<Float, Float> = when (node) {
        is Node.Shape -> Pair(
            eval(node.widthExpr, side) ?: parent.width(),
            eval(node.heightExpr, side) ?: parent.height(),
        )

        is Node.Progress -> {
            val size = eval(node.sizeExpr, side) ?: min(parent.width(), parent.height())
            Pair(size, size)
        }

        is Node.Overlap -> node.children.map { measure(it, parent, side) }
            .maxByOrNull { it.first * it.second }
            ?: Pair(parent.width(), parent.height())

        is Node.Stack -> {
            val sizes = node.children.map { measure(it, parent, side) }
            val margin = eval(node.marginExpr, side) ?: 0f
            if (node.stacking == Stacking.VERTICAL_CENTER) {
                Pair(
                    sizes.maxOfOrNull { it.first } ?: 0f,
                    sizes.sumOf { it.second.toDouble() }.toFloat() +
                        margin * (sizes.size - 1).coerceAtLeast(0),
                )
            } else {
                Pair(
                    sizes.sumOf { it.first.toDouble() }.toFloat() +
                        margin * (sizes.size - 1).coerceAtLeast(0),
                    sizes.maxOfOrNull { it.second } ?: 0f,
                )
            }
        }
    }

    private fun applyRotation(
        canvas: Canvas,
        mode: String?,
        offsetExpr: String?,
        bounds: RectF,
        side: Float,
        time: TimeState,
    ) {
        val centerX = bounds.centerX()
        val centerY = bounds.centerY()
        when (mode?.uppercase()) {
            "CLOCK_SECOND" -> canvas.rotate(
                time.second * 6f + (eval(offsetExpr, side) ?: 0f),
                centerX,
                centerY,
            )

            "CLOCK_MINUTE" -> canvas.rotate(
                time.minute * 6f + (eval(offsetExpr, side) ?: 0f),
                centerX,
                centerY,
            )

            "CLOCK_HOUR" -> canvas.rotate(
                time.hour * 30f + (eval(offsetExpr, side) ?: 0f),
                centerX,
                centerY,
            )

            "CLOCK_HOUR_SMOOTH" -> canvas.rotate(
                (time.hour + time.minute / 60f) * 30f + (eval(offsetExpr, side) ?: 0f),
                centerX,
                centerY,
            )

            "DEG90" -> canvas.rotate(90f, centerX, centerY)

            "DEG180" -> canvas.rotate(180f, centerX, centerY)

            "DEG270" -> canvas.rotate(270f, centerX, centerY)

            "FLIP_X" -> {
                canvas.translate(centerX, centerY)
                canvas.scale(1f, -1f)
                canvas.translate(-centerX, -centerY)
            }

            "FLIP_Y" -> {
                canvas.translate(centerX, centerY)
                canvas.scale(-1f, 1f)
                canvas.translate(-centerX, -centerY)
            }

            "MANUAL" -> canvas.rotate(eval(offsetExpr, side) ?: 0f, centerX, centerY)
        }
    }

    internal fun eval(expr: String?, side: Float): Float? {
        var raw = expr?.trim() ?: return null
        if (raw.isEmpty()) return null
        val negative = raw.startsWith("-")
        if (negative) raw = raw.drop(1).trim()
        raw = raw.removePrefix("$").removeSuffix("$").trim()
        val body = raw
        if (body.isEmpty()) return null
        val value = when {
            body.matches(Regex("""gv\(side\)/\(\s*277\s*/\s*[0-9.]+\s*\)""")) -> {
                val divisor = body.substringAfterLast('/').trim().removeSuffix(")").toFloatOrNull()
                if (divisor == null) null else side * divisor / 277f
            }

            body.matches(Regex("""gv\(side\)/\s*[0-9.]+""")) -> {
                val divisor = body.substringAfterLast('/').trim().toFloatOrNull()
                if (divisor == null || divisor == 0f) null else side / divisor
            }

            body.matches(Regex("""gv\(side\)\*[0-9.]+""")) -> {
                val multiplier = body.substringAfterLast('*').trim().toFloatOrNull()
                if (multiplier == null) null else side * multiplier
            }

            else -> body.toFloatOrNull()
        } ?: return null
        return if (negative) -value else value
    }

    private fun parseItems(items: JSONArray?): List<Node> {
        if (items == null) return emptyList()
        return buildList {
            for (index in 0 until items.length()) {
                parseItem(items.optJSONObject(index))?.let(::add)
            }
        }
    }

    private fun parseItem(item: JSONObject?): Node? {
        if (item == null) return null
        val type = item.optString("internal_type")
        val formulas = item.optJSONObject("internal_formulas")
        val globals = item.optJSONObject("internal_globals")
        return when (type) {
            "ShapeModule" -> Node.Shape(
                type = item.optString("shape_type", "RECT"),
                widthExpr = formulas?.optString("shape_width"),
                heightExpr = formulas?.optString("shape_height"),
                cornersExpr = formulas?.optString("shape_corners"),
                colorKey = globals?.optString("paint_color")
                    ?: item.optString("paint_color").ifBlank { null },
                rotateMode = item.optString("shape_rotate_mode").ifBlank { null },
                rotateOffset = formulas?.optString("shape_rotate_offset")
                    ?: item.optString("shape_rotate_offset").ifBlank { null },
            )

            "ProgressModule" -> Node.Progress(
                count = item.optInt("progress_count", 1),
                sizeExpr = formulas?.optString("style_size")
                    ?: item.optString("style_size").ifBlank { null },
                widthExpr = formulas?.optString("style_width")
                    ?: item.optString("style_width").ifBlank { null },
                heightExpr = formulas?.optString("style_height")
                    ?: item.optString("style_height").ifBlank { null },
                fgKey = globals?.optString("color_fgcolor"),
                bgKey = globals?.optString("color_bgcolor"),
                shape = item.optString("style_shape", "RECT"),
                rotateOffset = formulas?.optString("progress_rotate_offset")
                    ?: item.optString("progress_rotate_offset").ifBlank { null },
            )

            "OverlapLayerModule" -> Node.Overlap(
                children = parseItems(item.optJSONArray("viewgroup_items")),
                rotateMode = formulas?.optString("config_rotate_mode")
                    ?: item.optString("config_rotate_mode").ifBlank { null },
                rotateOffset = formulas?.optString("config_rotate_offset")
                    ?: item.optString("config_rotate_offset").ifBlank { null },
            )

            "StackLayerModule" -> Node.Stack(
                children = parseItems(item.optJSONArray("viewgroup_items")),
                stacking = when (item.optString("config_stacking")) {
                    "HORIZONTAL_CENTER" -> Stacking.HORIZONTAL_CENTER
                    "HORIZONTAL_BOTTOM" -> Stacking.HORIZONTAL_BOTTOM
                    "HORIZONTAL_TOP" -> Stacking.HORIZONTAL_TOP
                    else -> Stacking.VERTICAL_CENTER
                },
                marginExpr = formulas?.optString("config_margin")
                    ?: item.optString("config_margin").ifBlank { null },
                anchor = when (item.optString("position_anchor")) {
                    "TOPLEFT" -> Anchor.TOPLEFT
                    "TOPRIGHT" -> Anchor.TOPRIGHT
                    "BOTTOMLEFT" -> Anchor.BOTTOMLEFT
                    "BOTTOMRIGHT" -> Anchor.BOTTOMRIGHT
                    "TOP" -> Anchor.TOP
                    "BOTTOM" -> Anchor.BOTTOM
                    "CENTERLEFT" -> Anchor.CENTERLEFT
                    "CENTERRIGHT" -> Anchor.CENTERRIGHT
                    "CENTER" -> Anchor.CENTER
                    else -> Anchor.UNKNOWN
                },
                offsetXExpr = formulas?.optString("position_offset_x"),
                offsetYExpr = formulas?.optString("position_offset_y"),
                paddingTopExpr = formulas?.optString("position_padding_top"),
                paddingBottomExpr = formulas?.optString("position_padding_bottom"),
                paddingLeftExpr = formulas?.optString("position_padding_left"),
                paddingRightExpr = formulas?.optString("position_padding_right"),
            )

            else -> null
        }
    }

    private fun color(key: String?, palette: Palette): Int = when (key?.trim()) {
        "bg" -> palette.background
        "hour", "seconds" -> palette.accent
        "minute", "fg" -> palette.foreground
        "fgl" -> withAlpha(palette.foreground, 0xCC)
        else -> palette.foreground
    }

    private fun withAlpha(color: Int, alpha: Int): Int = (alpha shl 24) or (color and 0x00FFFFFF)

    private fun centered(parent: RectF, width: Float, height: Float): RectF {
        val left = parent.centerX() - width / 2f
        val top = parent.centerY() - height / 2f
        return RectF(left, top, left + width, top + height)
    }

    private fun triangle(rect: RectF, right: Boolean): Path = Path().apply {
        if (right) {
            moveTo(rect.left, rect.top)
            lineTo(rect.right, rect.top)
            lineTo(rect.right, rect.bottom)
        } else {
            moveTo(rect.centerX(), rect.top)
            lineTo(rect.right, rect.bottom)
            lineTo(rect.left, rect.bottom)
        }
        close()
    }

    @Suppress("unused")
    private fun sizeOf(node: Node, parent: RectF, side: Float): Float = max(measure(node, parent, side).first, measure(node, parent, side).second)
}
