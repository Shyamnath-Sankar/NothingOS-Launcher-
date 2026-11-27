package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Real system battery snapshot used by KWGT Battery2. Level comes from the
 * existing [BatteryState] path; charging and the charging-time estimate come
 * from [BatteryManager]. No permission, service or fabricated value is used.
 */
object Battery2State {
    data class Snapshot(
        val level: Int,
        val charging: Boolean,
        val remainingMillis: Long?,
    )

    fun snapshot(context: Context): Snapshot {
        val manager = context.getSystemService(BatteryManager::class.java)
        val remaining = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager?.computeChargeTimeRemaining()?.takeIf { it > 0L }
        } else {
            null
        }
        return Snapshot(
            level = BatteryState.level(context).coerceIn(0, 100),
            charging = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))?.getIntExtra(BatteryManager.EXTRA_STATUS, -1).let { it == BatteryManager.BATTERY_STATUS_CHARGING || it == BatteryManager.BATTERY_STATUS_FULL },
            remainingMillis = remaining,
        )
    }
}

/**
 * Separate native provider for the KWGT `Nothing_Battery2` preset.
 *
 * Everything is drawn by [KwgtBattery2Renderer] into one bitmap, so the layout
 * only needs an ImageView and a truthful text fallback. The provider refreshes
 * on the system battery broadcast, power connect/disconnect, boot, resize,
 * periodic widget updates and app refresh. It does not need Alarms & reminders
 * access, a service or a minute scheduler.
 *
 * The tap tries `ACTION_POWER_USAGE_SUMMARY` and falls back to a known Settings
 * screen when no activity resolves, instead of leaving a dead tap target.
 */
class KwgtBattery2WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_battery2
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
        val estimate = KwgtBattery2Renderer.estimate(
            snapshot.level,
            snapshot.charging,
            snapshot.remainingMillis,
        )
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_battery2_bitmap,
            R.id.kwgt_battery2_fallback,
            render = { widthPx, heightPx ->
                KwgtBattery2Renderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    snapshot.level,
                    estimate,
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
                R.id.kwgt_battery2_fallback,
                UpstreamNtDraw.ink(context, style),
            )
            views.setTextViewText(
                R.id.kwgt_battery2_fallback,
                fallbackText(context, snapshot.level, estimate),
            )
            views.setOnClickPendingIntent(
                R.id.widget_root,
                batteryPendingIntent(context, appWidgetId),
            )
            val spoken = spokenStatus(context, estimate)
            val description = context.getString(
                R.string.kwgt_battery2_content_description,
                snapshot.level,
                spoken,
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_kwgt_battery2_bitmap,
                    description,
                )
            } else {
                views.setContentDescription(
                    R.id.kwgt_battery2_fallback,
                    description,
                )
            }
        }
    }

    private fun fallbackText(
        context: Context,
        level: Int,
        estimate: KwgtBattery2Renderer.Estimate,
    ): String = when (estimate.kind) {
        KwgtBattery2Renderer.EstimateKind.FULL -> context.getString(
            R.string.kwgt_battery2_fallback_full,
            level,
        )

        KwgtBattery2Renderer.EstimateKind.TO_FULL -> context.getString(
            R.string.kwgt_battery2_fallback_to_full,
            level,
            estimate.valueText,
        )

        KwgtBattery2Renderer.EstimateKind.UNAVAILABLE -> context.getString(
            R.string.kwgt_battery2_fallback_unknown,
            level,
        )
    }

    private fun spokenStatus(
        context: Context,
        estimate: KwgtBattery2Renderer.Estimate,
    ): String = when (estimate.kind) {
        KwgtBattery2Renderer.EstimateKind.FULL -> context.getString(
            R.string.kwgt_battery2_status_full,
        )

        KwgtBattery2Renderer.EstimateKind.TO_FULL -> context.getString(
            R.string.kwgt_battery2_status_charging,
            context.getString(
                R.string.kwgt_battery2_time_spoken,
                estimate.hours,
                estimate.minutes,
            ),
        )

        KwgtBattery2Renderer.EstimateKind.UNAVAILABLE -> context.getString(
            R.string.kwgt_battery2_status_unknown,
        )
    }

    private fun batteryPendingIntent(
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
