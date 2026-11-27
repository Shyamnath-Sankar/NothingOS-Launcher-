package app.nothingui.widgets.dotwel

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Locale
import java.util.TimeZone

object WorldPrefs {
    private const val PREFS = "dotwel_world"
    private const val PREVIEW = "preview_zones"
    private const val PENDING_PREFIX = "pending_"
    private const val PENDING_TS_PREFIX = "pending_ts_"
    private const val ZONES_PREFIX = "zones_"
    private const val PENDING_TTL_MS = 10 * 60 * 1000L

    val choices: List<NtWorldRenderer.Zone> = listOf(
        NtWorldRenderer.Zone("London", "Europe/London"),
        NtWorldRenderer.Zone("New York", "America/New_York"),
        NtWorldRenderer.Zone("Los Angeles", "America/Los_Angeles"),
        NtWorldRenderer.Zone("Berlin", "Europe/Berlin"),
        NtWorldRenderer.Zone("Paris", "Europe/Paris"),
        NtWorldRenderer.Zone("Dubai", "Asia/Dubai"),
        NtWorldRenderer.Zone("Mumbai", "Asia/Kolkata"),
        NtWorldRenderer.Zone("Singapore", "Asia/Singapore"),
        NtWorldRenderer.Zone("Tokyo", "Asia/Tokyo"),
        NtWorldRenderer.Zone("Seoul", "Asia/Seoul"),
        NtWorldRenderer.Zone("Sydney", "Australia/Sydney"),
        NtWorldRenderer.Zone("Sao Paulo", "America/Sao_Paulo"),
    )

    fun localChoice(): NtWorldRenderer.Zone {
        val zone = TimeZone.getDefault()
        return NtWorldRenderer.Zone("Local", zone.id)
    }

    /**
     * Safe default used when a World widget is placed straight from the system
     * widget picker instead of the in-app zone dialog. It reflects the device's
     * real timezone plus UTC, so no unselected city ever appears as if chosen.
     */
    fun defaultZones(): List<NtWorldRenderer.Zone> = listOf(localChoice(), NtWorldRenderer.Zone("UTC", "UTC"))
        .distinctBy { it.zoneId }
        .take(2)

    fun zones(context: Context, appWidgetId: Int): List<NtWorldRenderer.Zone> {
        val key = "$ZONES_PREFIX$appWidgetId"
        val stored = prefs(context).getString(key, null)
        if (stored != null) return parse(stored).ifEmpty { defaultZones() }
        val defaults = defaultZones()
        prefs(context).edit().putString(key, encode(defaults)).apply()
        return defaults
    }

    fun setZones(context: Context, appWidgetId: Int, zones: List<NtWorldRenderer.Zone>) {
        prefs(context).edit().putString("$ZONES_PREFIX$appWidgetId", encode(zones)).apply()
    }

    fun remove(context: Context, appWidgetId: Int) {
        prefs(context).edit().remove("$ZONES_PREFIX$appWidgetId").apply()
    }

    fun setPending(context: Context, token: String, zones: List<NtWorldRenderer.Zone>) {
        pruneExpired(context)
        prefs(context).edit()
            .putString(PENDING_PREFIX + token, encode(zones))
            .putLong(PENDING_TS_PREFIX + token, System.currentTimeMillis())
            .putString(PREVIEW, encode(zones))
            .apply()
    }

    fun takePending(context: Context, token: String): List<NtWorldRenderer.Zone>? {
        val key = PENDING_PREFIX + token
        val stored = prefs(context).getString(key, null)
        prefs(context).edit()
            .remove(key)
            .remove(PENDING_TS_PREFIX + token)
            .apply()
        return stored?.let { parse(it) }
    }

    fun clearPending(context: Context, token: String) {
        prefs(context).edit()
            .remove(PENDING_PREFIX + token)
            .remove(PENDING_TS_PREFIX + token)
            .apply()
    }

    fun previewZones(context: Context): List<NtWorldRenderer.Zone> = prefs(context).getString(PREVIEW, null)?.let { parse(it).ifEmpty { null } }
        ?: defaultZones()

    private fun pruneExpired(context: Context) {
        val prefs = prefs(context)
        val now = System.currentTimeMillis()
        val editor = prefs.edit()
        var pruning = false
        prefs.all.forEach { (key, value) ->
            if (key.startsWith(PENDING_TS_PREFIX) &&
                value is Long &&
                now - value > PENDING_TTL_MS
            ) {
                val token = key.removePrefix(PENDING_TS_PREFIX)
                editor.remove(PENDING_PREFIX + token)
                editor.remove(key)
                pruning = true
            }
        }
        if (pruning) editor.apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun encode(zones: List<NtWorldRenderer.Zone>): String = zones.take(2).joinToString(";") { "${it.label}|${it.zoneId}" }

    private fun parse(value: String): List<NtWorldRenderer.Zone> = value.split(";").mapNotNull { entry ->
        val parts = entry.split("|")
        if (parts.size != 2 || parts[1].isBlank()) {
            null
        } else {
            NtWorldRenderer.Zone(parts[0], parts[1])
        }
    }
}

class WorldWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_world
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { WorldPrefs.remove(context, it) }
        super.onDeleted(context, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == MinuteTickScheduler.ACTION_TICK) {
            refreshWidgets(context)
            MinuteTickScheduler.schedule(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val zones = WorldPrefs.zones(context, appWidgetId)
        if (!MinuteTickScheduler.hasExactAccess(context)) {
            return liveWorldViews(context, appWidgetId, style, zones)
        }
        val views = buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_world_bitmap,
            R.id.world_fallback,
            render = { widthPx, heightPx ->
                NtWorldRenderer.render(context, widthPx, heightPx, style, zones, false)
            },
        ) decorate@{ remote, _ ->
            remote.setTextColor(R.id.world_fallback, UpstreamNtDraw.ink(context, style))
        }
        return views
    }

    private fun liveWorldViews(
        context: Context,
        appWidgetId: Int,
        style: WidgetStyle,
        zones: List<NtWorldRenderer.Zone>,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setViewVisibility(R.id.widget_world_bitmap, View.GONE)
        views.setViewVisibility(R.id.world_fallback, View.GONE)
        views.setViewVisibility(R.id.world_live, View.VISIBLE)
        val ink = UpstreamNtDraw.ink(context, style)
        val muted = UpstreamNtDraw.muted(context, style)
        bindLiveZone(views, zones.getOrNull(0), R.id.world_label_a, R.id.world_clock_a, ink, muted)
        bindLiveZone(views, zones.getOrNull(1), R.id.world_label_b, R.id.world_clock_b, ink, muted)
        return views
    }

    private fun bindLiveZone(
        views: RemoteViews,
        zone: NtWorldRenderer.Zone?,
        labelId: Int,
        clockId: Int,
        ink: Int,
        muted: Int,
    ) {
        if (zone == null) {
            views.setViewVisibility(labelId, View.GONE)
            views.setViewVisibility(clockId, View.GONE)
            return
        }
        views.setViewVisibility(labelId, View.VISIBLE)
        views.setViewVisibility(clockId, View.VISIBLE)
        views.setTextViewText(labelId, zone.label.uppercase(Locale.getDefault()))
        views.setTextColor(labelId, muted)
        views.setTextColor(clockId, ink)
        views.setString(clockId, "setTimeZone", zone.zoneId)
    }
}
