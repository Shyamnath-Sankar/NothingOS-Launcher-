package app.nothingui.widgets.dotwel

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

object MinuteTickScheduler {
    const val ACTION_TICK = "app.nothingui.widgets.dotwel.action.CLOCK_TICK"
    private const val REQUEST_CODE = 0x0C10

    private val MINUTE_PROVIDERS = listOf(
        ClockWidgetProvider::class.java,
        AnalogBoldWidgetProvider::class.java,
        AnalogScaleWidgetProvider::class.java,
        WorldWidgetProvider::class.java,
        KwgtDateTimeWidgetProvider::class.java,
        KwgtDateTime2WidgetProvider::class.java,
        KwgtDigital4WidgetProvider::class.java,
        KwgtDigital3WidgetProvider::class.java,
        NothingMasterWidgetProvider::class.java,
        KwgtDigital2WidgetProvider::class.java,
        KwgtInterstellarEnduranceProvider::class.java,
        KwgtInterstellarEnduranceAnalogProvider::class.java,
        KwgtInterstellarEnduranceAnalog2Provider::class.java,
    )

    fun hasExactAccess(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
        return alarmManager.canScheduleExactAlarms()
    }

    fun schedule(context: Context) {
        if (!hasPlacedMinuteWidgets(context)) {
            cancel(context)
            return
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val now = System.currentTimeMillis()
        val triggerAt = now - (now % 60_000L) + 60_000L
        val pendingIntent = tickPendingIntent(context)
        try {
            if (hasExactAccess(context)) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC, triggerAt, pendingIntent)
            } else {
                // No SCHEDULE_EXACT_ALARM in this build: use a bounded inexact window
                // so clocks still refresh instead of freezing on the last bitmap.
                alarmManager.setWindow(AlarmManager.RTC, triggerAt, 60_000L, pendingIntent)
            }
        } catch (_: SecurityException) {
            alarmManager.setWindow(AlarmManager.RTC, triggerAt, 60_000L, pendingIntent)
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(tickPendingIntent(context))
    }

    private fun hasPlacedMinuteWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return MINUTE_PROVIDERS.any { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider)).isNotEmpty()
        }
    }

    private fun tickPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MinuteTickReceiver::class.java).apply {
            action = ACTION_TICK
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
