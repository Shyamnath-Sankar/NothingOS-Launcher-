package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Reads the real system battery level. The Android sticky battery snapshot is preferred;
 * BATTERY_PROPERTY_CAPACITY is the fallback. This keeps framework and HAL disagreement from overriding the system broadcast level. No permission,
 * fake charge state or separate service is involved.
 */
object BatteryState {
    fun level(context: Context): Int {
        val sticky = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val rawLevel = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (rawLevel >= 0 && scale > 0) {
            return (rawLevel * 100 / scale).coerceIn(0, 100)
        }
        val manager = context.getSystemService(BatteryManager::class.java)
        val capacity = manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        return capacity.takeIf { it in 0..100 } ?: 0
    }
}

class BatteryWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_battery
    override val tapAction: String = Intent.ACTION_POWER_USAGE_SUMMARY
    override val refreshesBatteryAlarm: Boolean = true

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val level = BatteryState.level(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_battery_bitmap,
            R.id.battery_fallback,
            render = { widthPx, heightPx ->
                KwgtBatteryRenderer.render(context, widthPx, heightPx, style, level)
            },
        ) decorate@{ views, usedBitmap ->
            views.setTextColor(R.id.battery_fallback, UpstreamNtDraw.ink(context, style))
            views.setTextViewText(
                R.id.battery_fallback,
                context.getString(R.string.battery_fallback_format, level),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_battery_bitmap,
                    context.getString(R.string.battery_content_description, level),
                )
            }
        }
    }
}

class BatteryMiniWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_battery
    override val tapAction: String = Intent.ACTION_POWER_USAGE_SUMMARY
    override val refreshesBatteryAlarm: Boolean = true

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val level = BatteryState.level(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_battery_bitmap,
            R.id.battery_fallback,
            render = { widthPx, heightPx ->
                KwgtBatteryMiniRenderer.render(context, widthPx, heightPx, style, level)
            },
        ) decorate@{ views, usedBitmap ->
            views.setTextColor(R.id.battery_fallback, UpstreamNtDraw.ink(context, style))
            views.setTextViewText(
                R.id.battery_fallback,
                context.getString(R.string.battery_fallback_format, level),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_battery_bitmap,
                    context.getString(R.string.battery_mini_content_description, level),
                )
            }
        }
    }
}
