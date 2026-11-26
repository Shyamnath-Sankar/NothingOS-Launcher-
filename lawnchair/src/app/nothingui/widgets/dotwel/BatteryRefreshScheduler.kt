package app.nothingui.widgets.dotwel

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/**
 * Bounded, best-effort background refresh for the battery readouts.
 *
 * Android does not deliver manifest `ACTION_BATTERY_CHANGED` receivers while the
 * process is dead, so a placed battery widget could otherwise freeze at its last
 * snapshot until the host's inexact `updatePeriodMillis` fires. This scheduler
 * uses a non-wakeup `ELAPSED_REALTIME` window: roughly [REFRESH_PERIOD_MILLIS]
 * after each refresh, with [REFRESH_FLEX_MILLIS] of delivery slack (so a delivery
 * may arrive up to ~25 minutes later). It is inexact on purpose: no exact-alarm
 * permission, no foreground service and no wake lock are used, and Doze may
 * defer it further.
 *
 * Only the four providers that show battery data are scheduled. If none is
 * placed the alarm is cancelled, so no battery-only polling continues after the
 * last widget is removed.
 */
object BatteryRefreshScheduler {
    const val ACTION_REFRESH =
        "app.nothingui.widgets.dotwel.action.BATTERY_REFRESH"
    const val REFRESH_PERIOD_MILLIS = 15 * 60 * 1000L
    const val REFRESH_FLEX_MILLIS = 10 * 60 * 1000L

    private const val REQUEST_CODE = 0x0BA2

    val providers: List<Class<out BaseWidgetProvider>> = listOf(
        BatteryWidgetProvider::class.java,
        BatteryMiniWidgetProvider::class.java,
        KwgtBattery2WidgetProvider::class.java,
        KwgtCleanInfoWidgetProvider::class.java,
        IosBatteryWidgetProvider::class.java,
        BatteryStatusWidgetProvider::class.java,
    )

    fun nextTriggerElapsed(nowElapsed: Long): Long = nowElapsed + REFRESH_PERIOD_MILLIS

    fun isRefreshAction(action: String?): Boolean = action == ACTION_REFRESH

    fun hasBatteryWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return providers.any { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider)).isNotEmpty()
        }
    }

    fun schedule(context: Context) {
        if (!hasBatteryWidgets(context)) {
            cancel(context)
            return
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = nextTriggerElapsed(SystemClock.elapsedRealtime())
        val pendingIntent = refreshPendingIntent(context)
        try {
            alarmManager.setWindow(
                AlarmManager.ELAPSED_REALTIME,
                triggerAt,
                REFRESH_FLEX_MILLIS,
                pendingIntent,
            )
        } catch (_: RuntimeException) {
            alarmManager.set(AlarmManager.ELAPSED_REALTIME, triggerAt, pendingIntent)
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(refreshPendingIntent(context))
    }

    private fun refreshPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, BatteryRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/**
 * Internal alarm target. It refreshes only the battery-capable providers and
 * re-arms the next inexact window; it never schedules another alarm directly.
 */
class BatteryRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BatteryRefreshScheduler.isRefreshAction(intent.action)) return
        WidgetUpdater.updateBatteryProviders(context)
        BatteryRefreshScheduler.schedule(context)
    }
}
