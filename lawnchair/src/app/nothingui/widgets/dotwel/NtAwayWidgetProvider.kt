package app.nothingui.widgets.dotwel

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.PowerManager
import android.os.SystemClock
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Calendar

/** NtAway.sample state machine. Samples are estimates, never usage-access history. */
object NtAwayState {
    data class Sample(
        val wasOn: Boolean = true,
        val lastOn: Long = 0,
        val day: Int = 0,
        val total: Long = 0,
        val longest: Long = 0,
        val last: Long = 0,
        val sampledAt: Long = 0,
    )
    fun day(now: Long): Int = Calendar.getInstance().run {
        timeInMillis = now
        get(Calendar.YEAR) * 1000 + get(Calendar.DAY_OF_YEAR)
    }
    fun update(old: Sample, on: Boolean, now: Long): Sample {
        val elapsed = (now - (old.lastOn.takeIf { it > 0 } ?: now)).coerceAtLeast(0)
        var result = old
        if (on) {
            if (!old.wasOn && elapsed >= 60_000) {
                val same = old.day == day(now)
                result = result.copy(
                    day = day(now),
                    total = (if (same) old.total else 0) + elapsed,
                    longest = maxOf(if (same) old.longest else 0, elapsed),
                    last = elapsed,
                )
            }
            result = result.copy(lastOn = now)
        }
        return result.copy(wasOn = on, sampledAt = now)
    }
    fun format(duration: Long): String {
        val minutes = duration.coerceAtLeast(0) / 60_000
        return if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"
    }
}

class NtAwayWidgetProvider : BaseWidgetProvider() {
    override val layoutRes = R.layout.widget_weather_temp
    private fun prefs(context: Context) = context.getSharedPreferences("nt_away", Context.MODE_PRIVATE)
    private fun sample(context: Context): NtAwayState.Sample {
        val p = prefs(context)
        val old = NtAwayState.Sample(
            p.getBoolean("wasOn", true),
            p.getLong("lastOn", 0),
            p.getInt("day", 0),
            p.getLong("total", 0),
            p.getLong("longest", 0),
            p.getLong("last", 0),
            p.getLong("sampledAt", 0),
        )
        val on = context.getSystemService(PowerManager::class.java)?.isInteractive ?: true
        val state = NtAwayState.update(old, on, System.currentTimeMillis())
        p.edit().putBoolean("wasOn", state.wasOn).putLong("lastOn", state.lastOn).putInt("day", state.day)
            .putLong("total", state.total).putLong("longest", state.longest).putLong("last", state.last)
            .putLong("sampledAt", state.sampledAt).apply()
        return state
    }
    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val state = sample(context)
        val mode = Math.floorMod(prefs(context).getInt("mode", 0), 3)
        val today = state.day == NtAwayState.day(System.currentTimeMillis())
        val value = when (mode) {
            1 -> if (today) state.longest else 0
            2 -> if (today) state.total else 0
            else -> if (state.wasOn) state.last else (state.sampledAt - state.lastOn).coerceAtLeast(0)
        }
        val label = arrayOf("Away", "Longest", "Today")[mode]
        val views = buildBitmapViews(
            context,
            appWidgetId,
            R.id.weather_temp_bitmap,
            R.id.weather_temp_fallback,
            render = { w, h ->
                NtAwayRenderer.render(context, w, h, WidgetPrefs.style(context), value, label)
            },
        ) { v, _ ->
            val next = Intent(context, NtAwayWidgetProvider::class.java).setAction(NEXT)
            v.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getBroadcast(
                    context,
                    0,
                    next,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        schedule(context)
        return views
    }
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NEXT) {
            val p = prefs(context)
            p.edit().putInt("mode", Math.floorMod(p.getInt("mode", 0) + 1, 3)).apply()
            refreshWidgets(context)
            return
        }
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            refreshWidgets(context)
            schedule(context)
            return
        }
        if (intent.action == TICK) {
            refreshWidgets(context)
            schedule(context)
            return
        }
        super.onReceive(context, intent)
    }
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        schedule(context)
        prefs(context).edit().clear().apply()
    }
    companion object {
        private const val NEXT = "app.nothingui.widgets.dotwel.AWAY_NEXT"
        private const val TICK = "app.nothingui.widgets.dotwel.AWAY_SAMPLE"
        fun schedule(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val alarm = context.getSystemService(AlarmManager::class.java) ?: return
            val pending = PendingIntent.getBroadcast(
                context,
                0x0A17,
                Intent(context, NtAwayWidgetProvider::class.java).setAction(TICK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (manager.getAppWidgetIds(ComponentName(context, NtAwayWidgetProvider::class.java)).isEmpty()) {
                alarm.cancel(pending)
                return
            }
            // No service/wake lock. Android can defer this non-wakeup inexact sample.
            alarm.setWindow(AlarmManager.ELAPSED_REALTIME, SystemClock.elapsedRealtime() + 60_000, 60_000, pending)
        }
    }
}

/** Shared source layout, also used for an honest empty gallery preview. */
object NtAwayRenderer {
    fun render(context: Context, w: Int, h: Int, style: WidgetStyle, value: Long = 0, label: String = "Away"): android.graphics.Bitmap {
        val bitmap = UpstreamNtDraw.surface(context, w, h, style)
        val canvas = Canvas(bitmap)
        val pad = minOf(w, h) * .16f
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = UpstreamNtDraw.ink(context, style)
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        }
        p.textSize = minOf(h * .4f, UpstreamNtDraw.fit(p, "00h 00m", w - pad * 2, h * .5f))
        canvas.drawText(NtAwayState.format(value), pad, h * .52f, p)
        p.color = UpstreamNtDraw.muted(context, style)
        p.textSize = h * .16f
        canvas.drawText("$label · sampled", pad, h * .80f, p)
        return bitmap
    }
}
