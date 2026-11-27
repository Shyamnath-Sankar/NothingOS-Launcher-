package app.nothingui.widgets.dotwel

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.SupplicantState
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.widget.RemoteViews
import com.android.launcher3.R
import kotlin.math.max
import kotlin.math.min

/**
 * Optional Bluetooth access. The dangerous permission only exists on Android 12+
 * (API 31); older releases use the normal install-time BLUETOOTH permission.
 * Nothing here prompts the user: the activity owns the explained opt-in.
 */
object BluetoothAccess {
    fun isGranted(context: Context): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
        PackageManager.PERMISSION_GRANTED
}

enum class StatusKind { BLUETOOTH, WIFI, CELLULAR, BATTERY }

enum class ConnectivityState { OFF, ON, CONNECTED, DISCONNECTED, PERMISSION_NEEDED, UNAVAILABLE }

data class StatusSnapshot(
    val kind: StatusKind,
    val state: ConnectivityState,
    val detail: String? = null,
    val percent: Int? = null,
) {
    fun label(context: Context): String = detail?.takeIf { it.isNotBlank() } ?: when (kind) {
        StatusKind.BLUETOOTH -> context.getString(R.string.bt_status_label_text)
        StatusKind.WIFI -> context.getString(R.string.wifi_status_label_text)
        StatusKind.CELLULAR -> context.getString(R.string.cellular_status_label_text)
        StatusKind.BATTERY -> context.getString(R.string.battery_status_label_text)
    }

    fun stateText(context: Context): String = if (kind == StatusKind.BATTERY) {
        percent?.let { "$it%" } ?: context.getString(R.string.status_unavailable)
    } else {
        when (state) {
            ConnectivityState.OFF -> context.getString(R.string.status_off)
            ConnectivityState.ON -> context.getString(R.string.status_on)
            ConnectivityState.CONNECTED -> context.getString(R.string.status_connected)
            ConnectivityState.DISCONNECTED -> context.getString(R.string.status_disconnected)
            ConnectivityState.PERMISSION_NEEDED -> context.getString(R.string.bt_status_permission_needed)
            ConnectivityState.UNAVAILABLE -> context.getString(R.string.status_unavailable)
        }
    }

    fun active(): Boolean = state == ConnectivityState.ON || state == ConnectivityState.CONNECTED

    /** Short uppercase text for the dot-matrix row inside the circular tile. */
    fun shortText(): String = when (kind) {
        StatusKind.BATTERY -> percent?.let { "$it%" } ?: "NA%"

        StatusKind.CELLULAR -> if (active()) "DATA" else "OFF"

        StatusKind.BLUETOOTH,
        StatusKind.WIFI,
        -> if (active()) "ON" else "OFF"
    }
}

object BluetoothStatusState {
    @SuppressLint("MissingPermission")
    fun read(context: Context): StatusSnapshot {
        if (!BluetoothAccess.isGranted(context)) {
            return StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.PERMISSION_NEEDED)
        }
        val manager = context.getSystemService(BluetoothManager::class.java)
        val adapter = manager?.adapter
            ?: return StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.UNAVAILABLE)
        val enabled = try {
            adapter.isEnabled
        } catch (_: SecurityException) {
            return StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.PERMISSION_NEEDED)
        }
        if (!enabled) return StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.OFF)
        val name = connectedDeviceName(manager)
        return if (name != null) {
            StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.CONNECTED, name)
        } else {
            StatusSnapshot(StatusKind.BLUETOOTH, ConnectivityState.ON)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectedDeviceName(manager: BluetoothManager): String? {
        val profiles = intArrayOf(
            BluetoothProfile.HEADSET,
            BluetoothProfile.A2DP,
            BluetoothProfile.GATT,
            BluetoothProfile.GATT_SERVER,
        )
        for (profile in profiles) {
            val devices = try {
                manager.getConnectedDevices(profile)
            } catch (_: RuntimeException) {
                null
            }
            devices?.firstOrNull { it.name?.isNotBlank() == true }?.let { return it.name }
        }
        return null
    }
}

object WifiStatusState {
    @Suppress("DEPRECATION")
    fun read(context: Context): StatusSnapshot {
        val manager = context.applicationContext.getSystemService(WifiManager::class.java)
            ?: return StatusSnapshot(StatusKind.WIFI, ConnectivityState.UNAVAILABLE)
        val state = try {
            manager.wifiState
        } catch (_: SecurityException) {
            return StatusSnapshot(StatusKind.WIFI, ConnectivityState.UNAVAILABLE)
        }
        when (state) {
            WifiManager.WIFI_STATE_DISABLED,
            WifiManager.WIFI_STATE_DISABLING,
            -> return StatusSnapshot(StatusKind.WIFI, ConnectivityState.OFF)

            WifiManager.WIFI_STATE_ENABLED,
            WifiManager.WIFI_STATE_ENABLING,
            -> Unit

            else -> return StatusSnapshot(StatusKind.WIFI, ConnectivityState.UNAVAILABLE)
        }
        val info = try {
            manager.connectionInfo
        } catch (_: RuntimeException) {
            null
        } ?: return StatusSnapshot(StatusKind.WIFI, ConnectivityState.ON)
        val connected = info.supplicantState == SupplicantState.COMPLETED ||
            info.networkId != -1
        return if (connected) {
            StatusSnapshot(StatusKind.WIFI, ConnectivityState.CONNECTED, readableSsid(info.ssid))
        } else {
            StatusSnapshot(StatusKind.WIFI, ConnectivityState.DISCONNECTED)
        }
    }

    private fun readableSsid(raw: String?): String? {
        val value = raw?.trim()?.trim('"') ?: return null
        if (value.isBlank()) return null
        if (value.equals("<unknown ssid>", ignoreCase = true)) return null
        if (value.equals("0x", ignoreCase = true)) return null
        return value
    }
}

object CellularStatusState {
    fun read(context: Context): StatusSnapshot {
        val manager = context.getSystemService(ConnectivityManager::class.java)
            ?: return StatusSnapshot(StatusKind.CELLULAR, ConnectivityState.UNAVAILABLE)
        val network = try {
            manager.activeNetwork
        } catch (_: SecurityException) {
            null
        } ?: return StatusSnapshot(StatusKind.CELLULAR, ConnectivityState.OFF)
        val capabilities = try {
            manager.getNetworkCapabilities(network)
        } catch (_: SecurityException) {
            null
        } ?: return StatusSnapshot(StatusKind.CELLULAR, ConnectivityState.OFF)
        if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            return StatusSnapshot(StatusKind.CELLULAR, ConnectivityState.OFF)
        }
        val online = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        return StatusSnapshot(
            StatusKind.CELLULAR,
            if (online) ConnectivityState.CONNECTED else ConnectivityState.ON,
        )
    }
}

object BatteryStatusState {
    fun read(context: Context): StatusSnapshot {
        val snapshot = Battery2State.snapshot(context)
        return StatusSnapshot(
            StatusKind.BATTERY,
            if (snapshot.charging) ConnectivityState.ON else ConnectivityState.OFF,
            percent = snapshot.level.coerceIn(0, 100),
        )
    }
}

/**
 * Original programmatic control-tile glyphs. The reference collection's
 * red/white circular tiles are recreated here from primitives; no font or
 * bitmap asset from that collection is bundled. Each tile is one large filled
 * circle (93% of the cell) with a single centred glyph and no status text.
 */
internal object StatusTileRenderer {
    private val WHITE = 0xFFFFFFFF.toInt()
    private val BLACK = 0xFF000000.toInt()
    private val NOTHING_RED = 0xFFD71921.toInt()

    data class TileLayout(
        val centerX: Float,
        val centerY: Float,
        val radius: Float,
        val glyphCenterY: Float,
        val textCenterY: Float,
    )

    fun layout(width: Int, height: Int): TileLayout {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val side = min(safeWidth, safeHeight).toFloat()
        val centerX = safeWidth / 2f
        val centerY = safeHeight / 2f
        val radius = side * 0.465f
        return TileLayout(
            centerX = centerX,
            centerY = centerY,
            radius = radius,
            glyphCenterY = centerY,
            textCenterY = centerY,
        )
    }

    fun circleColor(snapshot: StatusSnapshot): Int = when {
        snapshot.kind == StatusKind.BATTERY -> WHITE
        snapshot.active() -> NOTHING_RED
        else -> WHITE
    }

    fun glyphColor(snapshot: StatusSnapshot): Int = when {
        snapshot.kind == StatusKind.BATTERY -> BLACK
        snapshot.active() -> WHITE
        else -> BLACK
    }

    /** Only the battery tile carries text; every other tile is glyph-only. */
    fun tileText(snapshot: StatusSnapshot): String =
        if (snapshot.kind == StatusKind.BATTERY) {
            snapshot.percent?.let { "$it%" } ?: "NA%"
        } else {
            ""
        }

    fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        style: WidgetStyle,
        snapshot: StatusSnapshot,
    ): Bitmap {
        val width = widthPx.coerceAtLeast(1)
        val height = heightPx.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val tile = layout(width, height)
        val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = circleColor(snapshot)
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(6f, 0f, 3f, 0x66000000)
            }
        }
        canvas.drawCircle(tile.centerX, tile.centerY, tile.radius, circlePaint)
        val text = tileText(snapshot)
        if (text.isNotEmpty()) {
            drawDotText(
                canvas,
                text,
                tile.centerX,
                tile.centerY,
                tile.radius * 1.35f,
                tile.radius * 0.72f,
                glyphColor(snapshot),
                style,
            )
        } else {
            drawGlyph(
                canvas,
                snapshot.kind,
                tile.centerX,
                tile.glyphCenterY,
                tile.radius * 0.92f,
                glyphColor(snapshot),
                style,
            )
        }
        return bitmap
    }

    private fun drawGlyph(
        canvas: Canvas,
        kind: StatusKind,
        cx: Float,
        cy: Float,
        size: Float,
        color: Int,
        style: WidgetStyle,
    ) {
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            this.style = Paint.Style.STROKE
            strokeWidth = max(2f, size * 0.075f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            if (style == WidgetStyle.TRANSPARENT) {
                setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
            }
        }
        when (kind) {
            StatusKind.BLUETOOTH -> {
                val top = cy - size / 2f
                val bottom = cy + size / 2f
                val mid = cy
                val right = cx + size * 0.30f
                canvas.drawLine(cx, top, cx, bottom, stroke)
                canvas.drawLine(cx, top, right, top + size * 0.22f, stroke)
                canvas.drawLine(right, top + size * 0.22f, cx, mid, stroke)
                canvas.drawLine(cx, bottom, right, bottom - size * 0.22f, stroke)
                canvas.drawLine(right, bottom - size * 0.22f, cx, mid, stroke)
            }

            StatusKind.WIFI -> {
                val centerY = cy + size * 0.24f
                for (radius in floatArrayOf(size * 0.50f, size * 0.35f, size * 0.20f)) {
                    canvas.drawArc(
                        cx - radius,
                        centerY - radius,
                        cx + radius,
                        centerY + radius,
                        225f,
                        90f,
                        false,
                        stroke,
                    )
                }
                val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.color = color
                    if (style == WidgetStyle.TRANSPARENT) {
                        setShadowLayer(4f, 0f, 2f, 0x99000000.toInt())
                    }
                }
                canvas.drawCircle(cx, centerY, max(2f, size * 0.055f), dot)
            }

            StatusKind.CELLULAR -> {
                val barWidth = size * 0.11f
                val gap = size * 0.07f
                val totalWidth = barWidth * 4f + gap * 3f
                var x = cx - totalWidth / 2f + barWidth / 2f
                val baseY = cy + size * 0.28f
                val heights = floatArrayOf(0.28f, 0.44f, 0.60f, 0.76f)
                heights.forEach { fraction ->
                    val top = baseY - size * fraction
                    canvas.drawLine(x, baseY, x, top, stroke)
                    x += barWidth + gap
                }
            }

            StatusKind.BATTERY -> {
                val bodyWidth = size * 0.62f
                val bodyHeight = size * 0.34f
                val body = RectF(
                    cx - bodyWidth / 2f,
                    cy - bodyHeight / 2f,
                    cx + bodyWidth / 2f,
                    cy + bodyHeight / 2f,
                )
                val corner = bodyHeight * 0.18f
                canvas.drawRoundRect(body, corner, corner, stroke)
                val nubWidth = size * 0.07f
                val nubHeight = bodyHeight * 0.42f
                val nub = RectF(
                    body.right,
                    cy - nubHeight / 2f,
                    body.right + nubWidth,
                    cy + nubHeight / 2f,
                )
                canvas.drawRoundRect(nub, nubWidth * 0.3f, nubWidth * 0.3f, stroke)
            }
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
}

abstract class BaseStatusWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_status_tile
    protected abstract fun readStatus(context: Context): StatusSnapshot
    protected abstract val contentDescriptionRes: Int

    protected open fun contentDescription(
        context: Context,
        snapshot: StatusSnapshot,
    ): String = context.getString(contentDescriptionRes, snapshot.stateText(context))

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val snapshot = readStatus(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.status_tile_bitmap,
            R.id.status_tile_fallback,
            render = { widthPx, heightPx ->
                StatusTileRenderer.render(context, widthPx, heightPx, style, snapshot)
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                R.drawable.bg_widget_none,
            )
            views.setTextColor(
                R.id.status_tile_fallback,
                UpstreamNtDraw.ink(context, style),
            )
            views.setTextViewText(
                R.id.status_tile_fallback,
                context.getString(
                    R.string.status_tile_fallback_format,
                    snapshot.label(context),
                    snapshot.stateText(context),
                ),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.status_tile_bitmap,
                    contentDescription(context, snapshot),
                )
            }
        }
    }
}

class BluetoothStatusWidgetProvider : BaseStatusWidgetProvider() {
    override val tapAction: String = Settings.ACTION_BLUETOOTH_SETTINGS
    override val contentDescriptionRes: Int = R.string.bt_status_content_description

    override fun readStatus(context: Context): StatusSnapshot = BluetoothStatusState.read(context)

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            BluetoothDevice.ACTION_ACL_CONNECTED,
            BluetoothDevice.ACTION_ACL_DISCONNECTED,
            android.bluetooth.BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED,
            android.bluetooth.BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED,
            -> {
                refreshWidgets(context)
                return
            }
        }
        super.onReceive(context, intent)
    }
}

class WifiStatusWidgetProvider : BaseStatusWidgetProvider() {
    override val contentDescriptionRes: Int = R.string.wifi_status_content_description

    override fun readStatus(context: Context): StatusSnapshot = WifiStatusState.read(context)

    override fun tapIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel = Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (context.packageManager.resolveActivity(panel, 0) != null) return panel
        }
        return Intent(Settings.ACTION_WIFI_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

class CellularStatusWidgetProvider : BaseStatusWidgetProvider() {
    override val contentDescriptionRes: Int = R.string.cellular_status_content_description

    override fun readStatus(context: Context): StatusSnapshot = CellularStatusState.read(context)

    override fun tapIntent(context: Context): Intent? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panel = Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (context.packageManager.resolveActivity(panel, 0) != null) return panel
        }
        return Intent(Settings.ACTION_DATA_ROAMING_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

class BatteryStatusWidgetProvider : BaseStatusWidgetProvider() {
    override val contentDescriptionRes: Int = R.string.battery_status_content_description
    override val tapAction: String = Intent.ACTION_POWER_USAGE_SUMMARY
    override val refreshesBatteryAlarm: Boolean = true

    override fun readStatus(context: Context): StatusSnapshot = BatteryStatusState.read(context)

    override fun contentDescription(
        context: Context,
        snapshot: StatusSnapshot,
    ): String = context.getString(
        R.string.battery_status_content_description,
        snapshot.percent?.let { "$it%" } ?: context.getString(R.string.status_unavailable),
    )
}
