package app.nothingui.widgets.dotwel

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.TextPaint
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.min

enum class HeadphonesState { PERMISSION_NEEDED, UNAVAILABLE, OFF, DISCONNECTED, CONNECTED }

data class BluetoothHeadphonesSnapshot(
    val state: HeadphonesState,
    val name: String? = null,
    val percent: Int? = null,
) {
    fun stateText(context: Context): String = when (state) {
        HeadphonesState.PERMISSION_NEEDED ->
            context.getString(R.string.headphones_state_permission)

        HeadphonesState.UNAVAILABLE ->
            context.getString(R.string.headphones_state_unavailable)

        HeadphonesState.OFF -> context.getString(R.string.headphones_state_off)

        HeadphonesState.DISCONNECTED ->
            context.getString(R.string.headphones_state_disconnected)

        HeadphonesState.CONNECTED -> percent?.let {
            context.getString(R.string.headphones_percent_format, it)
        } ?: context.getString(R.string.headphones_state_no_level)
    }
}

/**
 * Reads the connected headphone battery without adding a service or polling.
 *
 * `BluetoothDevice.getBatteryLevel()` and the battery-level broadcast are hidden
 * platform APIs, so they are accessed by reflection/string action and every call
 * fails closed. The hidden headset usage-hint fallback runs only on a short-lived
 * background thread and is throttled; it never blocks widget rendering.
 */
object BluetoothHeadphonesState {
    const val ACTION_BATTERY_LEVEL_CHANGED =
        "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED"
    private const val EXTRA_BATTERY_LEVEL =
        "android.bluetooth.device.extra.BATTERY_LEVEL"
    private const val EXTRA_DEVICE =
        "android.bluetooth.device.extra.DEVICE"
    private const val HINT_INTERVAL_MILLIS = 2 * 60 * 1000L

    private val cache = ConcurrentHashMap<String, Int>()
    private val hintLock = Any()
    private var lastHintAttempt = 0L

    @SuppressLint("MissingPermission")
    fun read(context: Context): BluetoothHeadphonesSnapshot {
        if (!BluetoothAccess.isGranted(context)) {
            return BluetoothHeadphonesSnapshot(HeadphonesState.PERMISSION_NEEDED)
        }
        val manager = context.getSystemService(BluetoothManager::class.java)
            ?: return BluetoothHeadphonesSnapshot(HeadphonesState.UNAVAILABLE)
        val adapter = manager.adapter
            ?: return BluetoothHeadphonesSnapshot(HeadphonesState.UNAVAILABLE)
        val enabled = try {
            adapter.isEnabled
        } catch (_: SecurityException) {
            return BluetoothHeadphonesSnapshot(HeadphonesState.PERMISSION_NEEDED)
        }
        if (!enabled) return BluetoothHeadphonesSnapshot(HeadphonesState.OFF)
        val device = connectedHeadphones(manager)
            ?: return BluetoothHeadphonesSnapshot(HeadphonesState.DISCONNECTED)
        val name = safeName(device)
        val address = safeAddress(device)
        val reflected = readDeviceBattery(device)
        if (reflected != null && address != null) cache[address] = reflected
        val percent = reflected ?: address?.let { cache[it] }
        return BluetoothHeadphonesSnapshot(HeadphonesState.CONNECTED, name, percent)
    }

    @SuppressLint("MissingPermission")
    fun updateFromBroadcast(context: Context, intent: Intent): Boolean {
        if (intent.action != ACTION_BATTERY_LEVEL_CHANGED) return false
        if (!BluetoothAccess.isGranted(context)) return false
        val level = intent.getIntExtra(EXTRA_BATTERY_LEVEL, -1)
        if (level !in 0..100) return false
        val device = parcelableDevice(intent) ?: return false
        val address = safeAddress(device) ?: return false
        return cache.put(address, level) != level
    }

    @SuppressLint("MissingPermission")
    fun refreshAsync(context: Context) {
        if (!BluetoothAccess.isGranted(context)) return
        val now = SystemClock.elapsedRealtime()
        synchronized(hintLock) {
            if (now - lastHintAttempt < HINT_INTERVAL_MILLIS) return
            lastHintAttempt = now
        }
        val app = context.applicationContext
        Thread({
            try {
                val manager = app.getSystemService(BluetoothManager::class.java)
                    ?: return@Thread
                val adapter = manager.adapter ?: return@Thread
                val device = connectedHeadphones(manager) ?: return@Thread
                if (readDeviceBattery(device) != null) return@Thread
                val proxyRef = AtomicReference<BluetoothProfile?>(null)
                val latch = CountDownLatch(1)
                val listener = object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(
                        profile: Int,
                        proxy: BluetoothProfile?,
                    ) {
                        proxyRef.set(proxy)
                        latch.countDown()
                    }

                    override fun onServiceDisconnected(profile: Int) {
                        latch.countDown()
                    }
                }
                if (!adapter.getProfileProxy(app, listener, BluetoothProfile.HEADSET)) {
                    return@Thread
                }
                latch.await(2, TimeUnit.SECONDS)
                val service = proxyRef.get() ?: return@Thread
                try {
                    val method = service.javaClass.getMethod(
                        "getBatteryUsageHint",
                        BluetoothDevice::class.java,
                    )
                    val level = (method.invoke(service, device) as? Int)
                        ?.takeIf { it in 0..100 }
                    if (level != null) {
                        safeAddress(device)?.let { cache[it] = level }
                        Handler(Looper.getMainLooper()).post {
                            WidgetUpdater.updateHeadphonesProviders(app)
                        }
                    }
                } finally {
                    adapter.closeProfileProxy(BluetoothProfile.HEADSET, service)
                }
            } catch (_: Throwable) {
            }
        }, "dotwel-bt-headphones-battery").start()
    }

    @SuppressLint("MissingPermission")
    internal fun connectedDevices(manager: BluetoothManager): List<BluetoothDevice> {
        val profiles = intArrayOf(
            BluetoothProfile.A2DP,
            BluetoothProfile.HEADSET,
            BluetoothProfile.GATT,
        )
        val seen = LinkedHashMap<String, BluetoothDevice>()
        for (profile in profiles) {
            val devices = try {
                manager.getConnectedDevices(profile)
            } catch (_: RuntimeException) {
                null
            }
            devices.orEmpty().forEach { device ->
                val key = safeAddress(device) ?: device.hashCode().toString()
                seen.putIfAbsent(key, device)
            }
        }
        return seen.values.toList()
    }

    private fun connectedHeadphones(manager: BluetoothManager): BluetoothDevice? {
        val devices = connectedDevices(manager)
        return devices.firstOrNull { safeName(it) != null } ?: devices.firstOrNull()
    }

    internal fun cachedLevel(address: String): Int? = cache[address]

    @SuppressLint("MissingPermission")
    internal fun safeName(device: BluetoothDevice): String? = try {
        device.name?.takeIf { it.isNotBlank() }
    } catch (_: SecurityException) {
        null
    }

    @SuppressLint("MissingPermission")
    internal fun safeAddress(device: BluetoothDevice): String? = try {
        device.address?.takeIf { it.isNotBlank() }
    } catch (_: SecurityException) {
        null
    }

    internal fun readDeviceBattery(device: BluetoothDevice): Int? = try {
        val method = device.javaClass.getMethod("getBatteryLevel")
        (method.invoke(device) as? Int)?.takeIf { it in 0..100 }
    } catch (_: Throwable) {
        null
    }

    internal fun readDeviceCharging(device: BluetoothDevice): Boolean = try {
        val method = device.javaClass.getMethod("isCharging")
        method.invoke(device) as? Boolean ?: false
    } catch (_: Throwable) {
        false
    }

    @Suppress("DEPRECATION")
    private fun parcelableDevice(intent: Intent): BluetoothDevice? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_DEVICE)
        }
    } catch (_: RuntimeException) {
        null
    }
}

internal object BluetoothHeadphonesRenderer {
    private const val CARD = 0xFFFEF7FF.toInt()
    private val GLYPH_INK = 0xFF1D1B20.toInt()
    val HALO = 0xFFE9E7EC.toInt()
    private val NAME_GRAY = 0xFF777379.toInt()
    private val GREEN = 0xFF6A9C89.toInt()
    private val RED = 0xFFD71921.toInt()
    private val TRANSPARENT_NAME = 0xCCFFFFFF.toInt()

    private const val NAME_WIDTH_ESTIMATE = 0.68f
    private const val NAME_HEIGHT_FACTOR = 1.25f

    data class TextBox(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
        val centerX: Float get() = (left + right) / 2f
        val centerY: Float get() = (top + bottom) / 2f
    }

    data class HeadphonesLayout(
        val icon: TextBox,
        val status: TextBox,
        val percent: TextBox,
        val name: TextBox,
        val cardRadius: Float,
    )

    fun cardColor(style: WidgetStyle): Int = CARD

    fun fittedNameSize(text: String, maxWidth: Float, maxHeight: Float): Float {
        if (text.isEmpty()) return 0f
        val byWidth = maxWidth / (text.length * NAME_WIDTH_ESTIMATE)
        val byHeight = maxHeight / NAME_HEIGHT_FACTOR
        return min(byWidth, byHeight).coerceAtLeast(0f)
    }

    fun layout(widthPx: Float, heightPx: Float, square: Boolean): HeadphonesLayout {
        val width = widthPx.coerceAtLeast(1f)
        val height = heightPx.coerceAtLeast(1f)
        val side = min(width, height)
        val cardRadius = side * 0.16f
        if (square) {
            val iconSize = side * 0.36f
            fun box(cx: Float, cy: Float, w: Float, h: Float) = TextBox(
                cx - w / 2f,
                cy - h / 2f,
                cx + w / 2f,
                cy + h / 2f,
            )
            return HeadphonesLayout(
                icon = box(width / 2f, height * 0.25f, iconSize, iconSize),
                status = box(width / 2f, height * 0.52f, width * 0.86f, height * 0.12f),
                percent = box(width / 2f, height * 0.66f, width * 0.60f, height * 0.14f),
                name = box(width / 2f, height * 0.82f, width * 0.86f, height * 0.075f),
                cardRadius = cardRadius,
            )
        }
        val iconSize = min(height * 0.78f, width * 0.24f)
        val textLeft = width * 0.33f
        val textRight = width * 0.95f
        val textCenter = (textLeft + textRight) / 2f
        val textWidth = textRight - textLeft
        fun box(cx: Float, cy: Float, w: Float, h: Float) = TextBox(
            cx - w / 2f,
            cy - h / 2f,
            cx + w / 2f,
            cy + h / 2f,
        )
        return HeadphonesLayout(
            icon = box(width * 0.17f, height * 0.50f, iconSize, iconSize),
            status = box(textCenter, height * 0.32f, textWidth, height * 0.30f),
            percent = box(textCenter, height * 0.58f, textWidth, height * 0.24f),
            name = box(textCenter, height * 0.84f, textWidth, height * 0.18f),
            cardRadius = cardRadius,
        )
    }

    fun batteryColor(percent: Int?): Int = when {
        percent == null -> NAME_GRAY
        percent >= 30 -> GREEN
        else -> RED
    }

    fun percentText(percent: Int?): String = percent?.let { "$it%" } ?: "NA%"

    fun statusWord(context: Context, snapshot: BluetoothHeadphonesSnapshot): String = when (snapshot.state) {
        HeadphonesState.CONNECTED ->
            context.getString(R.string.headphones_status_connected)

        HeadphonesState.OFF -> context.getString(R.string.headphones_status_off)

        HeadphonesState.DISCONNECTED ->
            context.getString(R.string.headphones_status_disconnected)

        HeadphonesState.UNAVAILABLE ->
            context.getString(R.string.headphones_status_unavailable)

        HeadphonesState.PERMISSION_NEEDED ->
            context.getString(R.string.headphones_status_no_access)
    }

    fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        snapshot: BluetoothHeadphonesSnapshot,
        square: Boolean,
    ): Bitmap {
        val width = widthPx.coerceAtLeast(1)
        val height = heightPx.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val inset = min(width, height) * 0.03f
        val radius = min(width, height) * 0.16f
        if (style != WidgetStyle.TRANSPARENT) {
            val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = cardColor(style)
                if (style == WidgetStyle.TRANSLUCENT) {
                    setShadowLayer(6f, 0f, 3f, 0x33000000)
                }
            }
            canvas.drawRoundRect(
                RectF(inset, inset, width - inset, height - inset),
                radius,
                radius,
                cardPaint,
            )
        }
        val ink = GLYPH_INK
        val nameColor = if (style == WidgetStyle.TRANSPARENT) TRANSPARENT_NAME else NAME_GRAY
        if (square) {
            drawSquare(context, canvas, width, height, style, snapshot, ink, nameColor)
        } else {
            drawWide(context, canvas, width, height, style, snapshot, ink, nameColor)
        }
        return bitmap
    }

    private fun drawWide(
        context: Context,
        canvas: Canvas,
        width: Int,
        height: Int,
        style: WidgetStyle,
        snapshot: BluetoothHeadphonesSnapshot,
        ink: Int,
        nameColor: Int,
    ) {
        val layout = layout(width.toFloat(), height.toFloat(), square = false)
        drawEarbuds(
            canvas,
            layout.icon.centerX,
            layout.icon.centerY,
            layout.icon.width,
            ink,
            style,
        )
        drawDotText(
            canvas,
            statusWord(context, snapshot),
            layout.status.centerX,
            layout.status.centerY,
            layout.status.width,
            layout.status.height,
            ink,
            style,
        )
        drawDotText(
            canvas,
            percentText(snapshot.percent),
            layout.percent.centerX,
            layout.percent.centerY,
            layout.percent.width,
            layout.percent.height,
            batteryColor(snapshot.percent),
            style,
        )
        drawName(
            canvas,
            snapshot.name ?: context.getString(R.string.headphones_label_text),
            layout.name.centerX,
            layout.name.centerY,
            layout.name.width,
            layout.name.height,
            nameColor,
            style,
        )
    }

    private fun drawSquare(
        context: Context,
        canvas: Canvas,
        width: Int,
        height: Int,
        style: WidgetStyle,
        snapshot: BluetoothHeadphonesSnapshot,
        ink: Int,
        nameColor: Int,
    ) {
        val layout = layout(width.toFloat(), height.toFloat(), square = true)
        drawEarbuds(
            canvas,
            layout.icon.centerX,
            layout.icon.centerY,
            layout.icon.width,
            ink,
            style,
        )
        drawDotText(
            canvas,
            statusWord(context, snapshot),
            layout.status.centerX,
            layout.status.centerY,
            layout.status.width,
            layout.status.height,
            ink,
            style,
        )
        drawDotText(
            canvas,
            percentText(snapshot.percent),
            layout.percent.centerX,
            layout.percent.centerY,
            layout.percent.width,
            layout.percent.height,
            batteryColor(snapshot.percent),
            style,
        )
        drawName(
            canvas,
            snapshot.name ?: context.getString(R.string.headphones_label_text),
            layout.name.centerX,
            layout.name.centerY,
            layout.name.width,
            layout.name.height,
            nameColor,
            style,
        )
    }

    private fun drawEarbuds(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        size: Float,
        color: Int,
        style: WidgetStyle,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
            }
        }
        val haloCenterY = cy + size * 0.05f
        val haloRadius = size * 0.52f
        val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = HALO }
        val haloEdge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = (HALO and 0x00FFFFFF) or (0x55 shl 24)
        }
        canvas.drawCircle(cx, haloCenterY, haloRadius * 1.18f, haloEdge)
        canvas.drawCircle(cx, haloCenterY, haloRadius, haloPaint)
        val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = RED
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
            }
        }
        val bulbRadius = size * 0.19f
        val stemWidth = size * 0.13f
        val stemHeight = size * 0.38f
        val gap = size * 0.36f
        val bulbCy = cy - size * 0.10f
        for (sign in intArrayOf(-1, 1)) {
            val bulbCx = cx + sign * gap / 2f
            canvas.drawCircle(bulbCx, bulbCy, bulbRadius, paint)
            if (sign > 0) {
                canvas.drawCircle(bulbCx, bulbCy, bulbRadius * 0.30f, accentPaint)
            }
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

    private fun drawDotText(
        canvas: Canvas,
        text: String,
        cx: Float,
        cy: Float,
        maxWidth: Float,
        maxHeight: Float,
        color: Int,
        style: WidgetStyle,
    ) {
        val pitch = DotGlyphFont.fitPitch(text, maxWidth, maxHeight)
        if (pitch <= 0f) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
            }
        }
        DotGlyphFont.drawCenteredInk(canvas, text, cx, cy, pitch, paint)
    }

    private fun drawName(
        canvas: Canvas,
        text: String,
        cx: Float,
        cy: Float,
        maxWidth: Float,
        maxHeight: Float,
        color: Int,
        style: WidgetStyle,
    ) {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            this.textSize = fittedNameSize(text, maxWidth, maxHeight).coerceAtLeast(4f)
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
            }
        }
        val measured = paint.measureText(text)
        if (measured > maxWidth.coerceAtLeast(1f) && measured > 0f) {
            paint.textSize *= maxWidth / measured
        }
        val metrics = paint.fontMetrics
        val baseline = cy - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(text, cx, baseline, paint)
    }
}

abstract class BaseBluetoothHeadphonesWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_bt_headphones
    override val tapAction: String = Settings.ACTION_BLUETOOTH_SETTINGS
    protected abstract val square: Boolean

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val snapshot = BluetoothHeadphonesState.read(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.headphones_bitmap,
            R.id.headphones_fallback,
            render = { widthPx, heightPx ->
                BluetoothHeadphonesRenderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    snapshot,
                    square,
                )
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                R.drawable.bg_widget_none,
            )
            views.setTextColor(
                R.id.headphones_fallback,
                if (style == WidgetStyle.TRANSPARENT) 0xFFFFFFFF.toInt() else 0xFF1B1B1D.toInt(),
            )
            views.setTextViewText(
                R.id.headphones_fallback,
                fallbackText(context, snapshot),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.headphones_bitmap,
                    context.getString(
                        R.string.bt_headphones_content_description,
                        snapshot.name ?: context.getString(R.string.headphones_label_text),
                        snapshot.stateText(context),
                    ),
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

    private fun fallbackText(
        context: Context,
        snapshot: BluetoothHeadphonesSnapshot,
    ): String = context.getString(
        R.string.headphones_fallback_format,
        snapshot.name ?: context.getString(R.string.headphones_label_text),
        snapshot.stateText(context),
    )
}

class BluetoothHeadphonesWideWidgetProvider : BaseBluetoothHeadphonesWidgetProvider() {
    override val square: Boolean = false
}

class BluetoothHeadphonesSquareWidgetProvider : BaseBluetoothHeadphonesWidgetProvider() {
    override val square: Boolean = true
}
