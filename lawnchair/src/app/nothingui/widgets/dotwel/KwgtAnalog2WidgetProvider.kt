package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for KWGT Nothing_Analog_2 ("KWGT Analog2").
 *
 * The source is a 277 filled circular dial with a sharp rectangular hour hand,
 * a sharp rectangular minute hand, a red seconds hand, a 12-tick hour ring, a
 * 60-tick minute ring and a red centre circle. It is reproduced with a platform
 * [android.widget.AnalogClock] plus a transparent, full-viewport overlay vector
 * for the two tick rings and the centre circle. The overlay is above the clock
 * because the source paints the ticks and centre after the hands; the clock
 * still rotates the hour, minute and second hands itself.
 *
 * Only the `values-v31` layouts wire `android:hand_second`. Android 12+ rotates
 * that full-viewport drawable itself, so no bitmap time, alarm, service,
 * permission or runtime AnalogClock setter is used. The receiver is disabled
 * below API 31 via `kwgt_analog_seconds_available`, and the catalog marks this
 * entry unavailable there rather than silently dropping the seconds hand.
 *
 * One layout exists per Dotwel style: black uses the source `#1B1B1D` dial with
 * white ink, translucent uses a `#A6FFFFFF` dial with dark ink, and transparent
 * uses no filled dial with white ink. The red seconds hand and red centre stay
 * `#D71921` in every style.
 */
class KwgtAnalog2WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_analog2_black
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, layoutFor(WidgetPrefs.style(context)))
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            Intent(AlarmClock.ACTION_SHOW_ALARMS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        return views
    }

    companion object {
        fun layoutFor(style: WidgetStyle): Int = when (style) {
            WidgetStyle.BLACK -> R.layout.widget_kwgt_analog2_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_analog2_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_analog2_transparent
        }
    }
}
