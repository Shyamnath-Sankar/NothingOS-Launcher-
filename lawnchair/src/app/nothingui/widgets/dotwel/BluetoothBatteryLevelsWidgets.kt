package app.nothingui.widgets.dotwel

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.BatteryManager
import android.provider.Settings
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

enum class BluetoothBatteryLevelsStatus {
    PERMISSION_NEEDED,
    UNAVAILABLE,
    OFF,
    EMPTY,
    ROWS,
}

enum class BluetoothBatteryDeviceKind {
    PHONE,
    EARBUDS,
    HEADPHONES,
    SPEAKER,
    GENERIC,
}

data class BluetoothBatteryRow(
    val name: String,
    val percent: Int?,
    val charging: Boolean,
    val kind: BluetoothBatteryDeviceKind,
)

data class BluetoothBatteryLevelsSnapshot(
    val status: BluetoothBatteryLevelsStatus,
    val rows: List<BluetoothBatteryRow> = emptyList(),
)

internal data class BatteryRowFrame(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
}

/**
 * Reads the local phone level plus every connected Bluetooth device for the
 * reference multi-row battery card. It adds no service, polling loop or
 * permission: device levels use the existing hidden `getBatteryLevel`
 * reflection, the existing hidden battery broadcast cache, and the optional
 * `BLUETOOTH_CONNECT` grant. Every call fails closed.
 */
object BluetoothBatteryLevelsReader {
    fun read(context: Context): BluetoothBatteryLevelsSnapshot {
        val rows = mutableListOf<BluetoothBatteryRow>()
        localPhoneRow(context)?.let { rows += it }

        if (!BluetoothAccess.isGranted(context)) {
            return BluetoothBatteryLevelsSnapshot(
                if (rows.isEmpty()) {
                    BluetoothBatteryLevelsStatus.PERMISSION_NEEDED
                } else {
                    BluetoothBatteryLevelsStatus.ROWS
                },
                rows,
            )
        }
        val manager = context.getSystemService(BluetoothManager::class.java)
            ?: return BluetoothBatteryLevelsSnapshot(
                if (rows.isEmpty()) {
                    BluetoothBatteryLevelsStatus.UNAVAILABLE
                } else {
                    BluetoothBatteryLevelsStatus.ROWS
                },
                rows,
            )
        val adapter = manager.adapter
            ?: return BluetoothBatteryLevelsSnapshot(
                if (rows.isEmpty()) {
                    BluetoothBatteryLevelsStatus.UNAVAILABLE
                } else {
                    BluetoothBatteryLevelsStatus.ROWS
                },
                rows,
            )
        val enabled = try {
            adapter.isEnabled
        } catch (_: SecurityException) {
            return BluetoothBatteryLevelsSnapshot(
                if (rows.isEmpty()) {
                    BluetoothBatteryLevelsStatus.PERMISSION_NEEDED
                } else {
                    BluetoothBatteryLevelsStatus.ROWS
                },
                rows,
            )
        }
        if (!enabled) {
            return BluetoothBatteryLevelsSnapshot(
                if (rows.isEmpty()) {
                    BluetoothBatteryLevelsStatus.OFF
                } else {
                    BluetoothBatteryLevelsStatus.ROWS
                },
                rows,
            )
        }
        BluetoothHeadphonesState.connectedDevices(manager).forEach { device ->
            rows += deviceRow(device)
        }
        return BluetoothBatteryLevelsSnapshot(
            if (rows.isEmpty()) {
                BluetoothBatteryLevelsStatus.EMPTY
            } else {
                BluetoothBatteryLevelsStatus.ROWS
            },
            rows,
        )
    }

    private fun localPhoneRow(context: Context): BluetoothBatteryRow? {
        val manager = context.getSystemService(BatteryManager::class.java) ?: return null
        val percent = try {
            manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                .takeIf { it in 0..100 }
        } catch (_: RuntimeException) {
            null
        } ?: return null
        val charging = try {
            when (manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)) {
                BatteryManager.BATTERY_STATUS_CHARGING,
                BatteryManager.BATTERY_STATUS_FULL,
                -> true
                else -> false
            }
        } catch (_: RuntimeException) {
            false
        }
        return BluetoothBatteryRow(
            name = "PHONE",
            percent = percent,
            charging = charging,
            kind = BluetoothBatteryDeviceKind.PHONE,
        )
    }

    @SuppressLint("MissingPermission")
    private fun deviceRow(device: BluetoothDevice): BluetoothBatteryRow {
        val name = BluetoothHeadphonesState.safeName(device) ?: "DEVICE"
        val address = BluetoothHeadphonesState.safeAddress(device)
        val percent = BluetoothHeadphonesState.readDeviceBattery(device)
            ?: address?.let { BluetoothHeadphonesState.cachedLevel(it) }
        return BluetoothBatteryRow(
            name = name,
            percent = percent,
            charging = BluetoothHeadphonesState.readDeviceCharging(device),
            kind = deviceKind(device),
        )
    }

    @SuppressLint("MissingPermission")
    private fun deviceKind(device: BluetoothDevice): BluetoothBatteryDeviceKind {
        val bluetoothClass = try {
            device.bluetoothClass
        } catch (_: SecurityException) {
            null
        } ?: return BluetoothBatteryDeviceKind.GENERIC
        if (bluetoothClass.majorDeviceClass == BluetoothClass.Device.Major.PHONE) {
            return BluetoothBatteryDeviceKind.PHONE
        }
        if (bluetoothClass.majorDeviceClass != BluetoothClass.Device.Major.AUDIO_VIDEO) {
            return BluetoothBatteryDeviceKind.GENERIC
        }
        return when (bluetoothClass.deviceClass) {
            BluetoothClass.Device.AUDIO_VIDEO_LOUDSPEAKER,
            BluetoothClass.Device.AUDIO_VIDEO_PORTABLE_AUDIO,
            BluetoothClass.Device.AUDIO_VIDEO_HIFI_AUDIO,
            -> BluetoothBatteryDeviceKind.SPEAKER
            BluetoothClass.Device.AUDIO_VIDEO_WEARABLE_HEADSET,
            BluetoothClass.Device.AUDIO_VIDEO_HEADPHONES,
            BluetoothClass.Device.AUDIO_VIDEO_HANDSFREE,
            -> BluetoothBatteryDeviceKind.EARBUDS
            else -> BluetoothBatteryDeviceKind.HEADPHONES
        }
    }
}

internal object BluetoothBatteryLevelsRenderer {
    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val CARD = 0xFFFEF7FF.toInt()
    private const val TRACK = 0xFFF4F3F3.toInt()
    private const val FILL = 0xFFD71921.toInt()
    private const val INK = 0xFF000000.toInt()
    private const val MAX_ROWS = 4
    private const val INSET_FRACTION = 0.03f
    private const val CARD_RADIUS_FRACTION = 0.16f
    private const val ROW_HEIGHT_FRACTION = 0.16f
    private const val ROW_GAP_FRACTION = 0.035f
    private const val ROW_PAD_FRACTION = 0.05f

    fun cardColor(style: WidgetStyle): Int = CARD

    fun cardRadius(widthPx: Int, heightPx: Int): Float =
        min(widthPx.coerceAtLeast(1), heightPx.coerceAtLeast(1)) * CARD_RADIUS_FRACTION

    fun trackColor(): Int = TRACK

    fun fillColor(): Int = FILL

    fun percentText(percent: Int?): String =
        percent?.let { "${it.coerceIn(0, 100)}%" } ?: "--"

    fun displayName(name: String?): String {
        val cleaned = name?.trim().orEmpty()
        return if (cleaned.isEmpty()) "DEVICE" else cleaned.uppercase(Locale.US)
    }

    fun fillFraction(percent: Int?): Float =
        (percent ?: 0).coerceIn(0, 100) / 100f

    /**
     * Fixed pill height keeps a single source from stretching into one
     * card-sized red squircle. Rows keep the reference height regardless of
     * how many sources are present and are centred as a group.
     */
    fun rowFrames(widthPx: Int, heightPx: Int, rowCount: Int): List<BatteryRowFrame> {
        val width = widthPx.coerceAtLeast(1)
        val height = heightPx.coerceAtLeast(1)
        val count = rowCount.coerceIn(0, MAX_ROWS)
        if (count == 0) return emptyList()
        val side = min(width, height).toFloat()
        val inset = side * INSET_FRACTION
        val rowHeight = side * ROW_HEIGHT_FRACTION
        val gap = side * ROW_GAP_FRACTION
        val stackHeight = count * rowHeight + (count - 1) * gap
        val contentTop = inset
        val contentBottom = height - inset
        val stackTop = contentTop + ((contentBottom - contentTop) - stackHeight) / 2f
        val left = inset + side * ROW_PAD_FRACTION
        val right = width - inset - side * ROW_PAD_FRACTION
        return List(count) { index ->
            val top = stackTop + index * (rowHeight + gap)
            BatteryRowFrame(left, top, right, top + rowHeight)
        }
    }

    fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        snapshot: BluetoothBatteryLevelsSnapshot,
    ): Bitmap {
        val width = widthPx.coerceAtLeast(1)
        val height = heightPx.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val side = min(width, height).toFloat()
        val inset = side * INSET_FRACTION
        val radius = cardRadius(width, height)
        val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = cardColor(style)
        }
        canvas.drawRoundRect(
            RectF(inset, inset, width - inset, height - inset),
            radius,
            radius,
            cardPaint,
        )

        val rows = snapshot.rows.take(MAX_ROWS)
        if (rows.isEmpty()) {
            drawMessage(canvas, width, height, statusMessage(snapshot.status))
            return bitmap
        }

        val frames = rowFrames(width, height, rows.size)
        rows.forEachIndexed { index, row ->
            val frame = frames[index]
            drawRow(canvas, row, frame.left, frame.top, frame.right, frame.bottom)
        }
        return bitmap
    }

    private fun drawRow(
        canvas: Canvas,
        row: BluetoothBatteryRow,
        left: Float,
        top: Float,
        right: Float,
        bottom: Float,
    ) {
        val height = bottom - top
        val radius = height / 2f
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = TRACK }
        canvas.drawRoundRect(RectF(left, top, right, bottom), radius, radius, trackPaint)

        val fraction = fillFraction(row.percent)
        val fillRight = left + (right - left) * fraction
        if (fraction > 0f) {
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = FILL }
            val fillRadius = min(radius, (fillRight - left) / 2f)
            canvas.drawRoundRect(
                RectF(left, top, fillRight, bottom),
                fillRadius,
                fillRadius,
                fillPaint,
            )
        }

        val centerY = (top + bottom) / 2f
        val glyphSize = height * 0.52f
        drawDeviceGlyph(
            canvas,
            left + height * 0.45f,
            centerY,
            glyphSize,
            INK,
            row.kind,
        )

        val rightPad = height * 0.20f
        val boltSize = if (row.charging) height * 0.40f else 0f
        val boltGap = if (row.charging) height * 0.12f else 0f
        val percentRight = right - rightPad - boltSize - boltGap
        val percent = percentText(row.percent)
        val percentPitch = DotGlyphFont.fitPitch(percent, height * 1.8f, height * 0.40f)
        if (percentPitch > 0f) {
            val percentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK }
            val textWidth = DotGlyphFont.columnsFor(percent) * percentPitch
            DotGlyphFont.drawLeft(
                canvas,
                percent,
                percentRight - textWidth,
                centerY,
                percentPitch,
                percentPaint,
            )
        }
        if (row.charging) {
            drawBolt(
                canvas,
                percentRight + boltGap + boltSize / 2f,
                centerY,
                boltSize,
                INK,
            )
        }

        val nameLeft = left + height * 0.82f
        val nameRight = percentRight - height * 0.10f
        val nameMaxWidth = max(
            nameRight - nameLeft,
            (right - left) * 0.28f,
        )
        val name = displayName(row.name)
        val namePitch = DotGlyphFont.fitPitch(name, nameMaxWidth, height * 0.34f)
        if (namePitch > 0f) {
            val namePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK }
            DotGlyphFont.drawLeft(
                canvas,
                name,
                nameLeft,
                centerY,
                namePitch,
                namePaint,
            )
        }
    }

    private fun drawDeviceGlyph(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        size: Float,
        color: Int,
        kind: BluetoothBatteryDeviceKind,
    ) {
        when (kind) {
            BluetoothBatteryDeviceKind.PHONE -> drawPhone(canvas, cx, cy, size, color)
            BluetoothBatteryDeviceKind.EARBUDS -> drawEarbuds(canvas, cx, cy, size, color)
            BluetoothBatteryDeviceKind.HEADPHONES -> drawHeadphones(canvas, cx, cy, size, color)
            BluetoothBatteryDeviceKind.SPEAKER -> drawSpeaker(canvas, cx, cy, size, color)
            BluetoothBatteryDeviceKind.GENERIC -> drawGeneric(canvas, cx, cy, size, color)
        }
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
        canvas.drawLine(
            cx - size * 0.06f,
            cy + halfHeight * 0.72f,
            cx + size * 0.06f,
            cy + halfHeight * 0.72f,
            paint,
        )
    }

    private fun drawEarbuds(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val bulbRadius = size * 0.17f
        val stemWidth = size * 0.12f
        val stemHeight = size * 0.34f
        val gap = size * 0.34f
        val bulbCy = cy - size * 0.10f
        for (sign in intArrayOf(-1, 1)) {
            val bulbCx = cx + sign * gap / 2f
            canvas.drawCircle(bulbCx, bulbCy, bulbRadius, paint)
            val stemTop = bulbCy + bulbRadius * 0.55f
            canvas.drawRoundRect(
                RectF(
                    bulbCx - stemWidth / 2f,
                    stemTop,
                    bulbCx + stemWidth / 2f,
                    stemTop + stemHeight,
                ),
                stemWidth / 2f,
                stemWidth / 2f,
                paint,
            )
        }
    }

    private fun drawHeadphones(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = size * 0.10f
            strokeCap = Paint.Cap.ROUND
        }
        val arc = RectF(cx - size * 0.34f, cy - size * 0.34f, cx + size * 0.34f, cy + size * 0.30f)
        canvas.drawArc(arc, 180f, 180f, false, paint)
        val cupPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val cupWidth = size * 0.14f
        val cupHeight = size * 0.26f
        for (sign in intArrayOf(-1, 1)) {
            canvas.drawRoundRect(
                RectF(
                    cx + sign * size * 0.34f - cupWidth / 2f,
                    cy - size * 0.02f,
                    cx + sign * size * 0.34f + cupWidth / 2f,
                    cy - size * 0.02f + cupHeight,
                ),
                cupWidth / 2f,
                cupWidth / 2f,
                cupPaint,
            )
        }
    }

    private fun drawSpeaker(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawRoundRect(
            RectF(cx - size * 0.26f, cy - size * 0.36f, cx + size * 0.26f, cy + size * 0.36f),
            size * 0.12f,
            size * 0.12f,
            paint,
        )
        val hole = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = WHITE }
        canvas.drawCircle(cx, cy - size * 0.10f, size * 0.08f, hole)
        canvas.drawCircle(cx, cy + size * 0.16f, size * 0.08f, hole)
    }

    private fun drawGeneric(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = size * 0.09f
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawCircle(cx, cy, size * 0.30f, paint)
        canvas.drawCircle(cx, cy, size * 0.09f, paint)
    }

    private fun drawBolt(canvas: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val path = Path()
        path.moveTo(cx + size * 0.10f, cy - size * 0.50f)
        path.lineTo(cx - size * 0.28f, cy + size * 0.06f)
        path.lineTo(cx - size * 0.02f, cy + size * 0.06f)
        path.lineTo(cx - size * 0.12f, cy + size * 0.50f)
        path.lineTo(cx + size * 0.30f, cy - size * 0.10f)
        path.lineTo(cx + size * 0.04f, cy - size * 0.10f)
        path.close()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.FILL
        }
        canvas.drawPath(path, paint)
    }

    private fun drawMessage(canvas: Canvas, width: Int, height: Int, text: String) {
        val pitch = DotGlyphFont.fitPitch(text, width * 0.70f, height * 0.22f)
        if (pitch <= 0f) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK }
        DotGlyphFont.drawCenteredInk(canvas, text, width / 2f, height / 2f, pitch, paint)
    }

    private fun statusMessage(status: BluetoothBatteryLevelsStatus): String = when (status) {
        BluetoothBatteryLevelsStatus.PERMISSION_NEEDED -> "NO ACCESS"
        BluetoothBatteryLevelsStatus.UNAVAILABLE -> "UNAVAILABLE"
        BluetoothBatteryLevelsStatus.OFF -> "BLUETOOTH OFF"
        BluetoothBatteryLevelsStatus.EMPTY,
        BluetoothBatteryLevelsStatus.ROWS,
        -> "NO DEVICES"
    }
}

class BluetoothBatteryLevelsWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_bt_battery_levels
    override val tapAction: String = Settings.ACTION_BLUETOOTH_SETTINGS

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val snapshot = BluetoothBatteryLevelsReader.read(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.bt_battery_levels_bitmap,
            R.id.bt_battery_levels_fallback,
            render = { widthPx, heightPx ->
                BluetoothBatteryLevelsRenderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    snapshot,
                )
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                R.drawable.bg_widget_none,
            )
            views.setTextColor(R.id.bt_battery_levels_fallback, 0xFF000000.toInt())
            views.setTextViewText(
                R.id.bt_battery_levels_fallback,
                context.getString(R.string.bt_battery_levels_fallback_text),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.bt_battery_levels_bitmap,
                    contentDescription(context, snapshot),
                )
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: android.appwidget.AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        BluetoothHeadphonesState.refreshAsync(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            BluetoothHeadphonesState.ACTION_BATTERY_LEVEL_CHANGED,
            BluetoothDevice.ACTION_ACL_CONNECTED,
            BluetoothDevice.ACTION_ACL_DISCONNECTED,
            android.bluetooth.BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED,
            android.bluetooth.BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED,
            BluetoothAdapter.ACTION_STATE_CHANGED,
            -> {
                BluetoothHeadphonesState.updateFromBroadcast(context, intent)
                refreshWidgets(context)
                BluetoothHeadphonesState.refreshAsync(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    private fun contentDescription(
        context: Context,
        snapshot: BluetoothBatteryLevelsSnapshot,
    ): String {
        val summary = snapshot.rows.joinToString(", ") { row ->
            "${row.name} ${BluetoothBatteryLevelsRenderer.percentText(row.percent)}"
        }.ifBlank {
            context.getString(R.string.bt_battery_levels_fallback_text)
        }
        return context.getString(
            R.string.bt_battery_levels_content_description,
            summary,
        )
    }
}
