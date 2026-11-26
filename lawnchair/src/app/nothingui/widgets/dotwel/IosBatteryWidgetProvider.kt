package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for the KWGT `iOS_Battery_Widget` preset.
 *
 * The real level and charging state come from the existing [Battery2State]
 * snapshot. Everything is drawn by [IosBatteryRenderer] into one bitmap, so the
 * layout only needs an ImageView and a truthful text fallback. Refresh uses the
 * same lifecycle as the other battery widgets: the dynamic
 * `ACTION_BATTERY_CHANGED` listener while the process lives, power connect /
 * disconnect and boot broadcasts, the inexact non-wakeup
 * [BatteryRefreshScheduler] window (~15 min with 10 min delivery flex, Doze may
 * defer it) and the app Refresh action. No service, exact alarm, network,
 * dependency or notification/media access is used.
 *
 * The tap opens the system battery settings, falling back to Battery Saver or
 * the main Settings screen when no power-usage activity resolves.
 */
class IosBatteryWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_ios_battery
    override val tapAction: String? = null
    override val refreshesBatteryAlarm: Boolean = true

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BATTERY_CHANGED,
            Intent.ACTION_POWER_CONNECTED,
            Intent.ACTION_POWER_DISCONNECTED,
            Intent.ACTION_BOOT_COMPLETED,
            -> {
                refreshWidgets(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val snapshot = Battery2State.snapshot(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_ios_battery_bitmap,
            R.id.ios_battery_fallback,
            render = { widthPx, heightPx ->
                IosBatteryRenderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    snapshot.level,
                    snapshot.charging,
                    includeBackground = true,
                )
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap || style == WidgetStyle.TRANSPARENT) {
                    R.drawable.bg_widget_none
                } else {
                    style.backgroundRes
                },
            )
            views.setTextColor(
                R.id.ios_battery_fallback,
                UpstreamNtDraw.ink(context, style),
            )
            views.setTextViewText(
                R.id.ios_battery_fallback,
                fallbackText(context, snapshot.level, snapshot.charging),
            )
            views.setOnClickPendingIntent(
                R.id.widget_root,
                batterySettingsPendingIntent(context, appWidgetId),
            )
            val description = context.getString(
                if (snapshot.charging) {
                    R.string.ios_battery_content_description_charging
                } else {
                    R.string.ios_battery_content_description
                },
                snapshot.level,
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_ios_battery_bitmap,
                    description,
                )
            } else {
                views.setContentDescription(
                    R.id.ios_battery_fallback,
                    description,
                )
            }
        }
    }

    private fun fallbackText(
        context: Context,
        level: Int,
        charging: Boolean,
    ): String = context.getString(
        if (charging) {
            R.string.ios_battery_fallback_charging
        } else {
            R.string.ios_battery_fallback
        },
        level,
    )

    private fun batterySettingsPendingIntent(
        context: Context,
        appWidgetId: Int,
    ): PendingIntent {
        val manager = context.packageManager
        val summary = Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val target = if (summary.resolveActivity(manager) != null) {
            summary
        } else {
            val saver = Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (saver.resolveActivity(manager) != null) {
                saver
            } else {
                Intent(Settings.ACTION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            target,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
