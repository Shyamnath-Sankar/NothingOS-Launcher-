package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for KWGT Nothing_Analog_ ("KWGT Analog Seconds").
 *
 * The source composition is a 277 dial with a filled hour capsule, a filled
 * minute capsule and a source `CLOCK_SECOND` circle positioned at radius
 * `(277 / 1.145) / 2` from the centre. It is reproduced with a platform
 * [android.widget.AnalogClock]. Only the `values-v31` layout wires
 * `android:hand_second`; Android 12+ rotates that full-viewport drawable itself,
 * so no bitmap time, alarm, service or runtime AnalogClock setter is used.
 *
 * The provider receiver is disabled below API 31 via the
 * `kwgt_analog_seconds_available` bool, and the app catalog marks it
 * unavailable there rather than silently dropping the second hand.
 */
class KwgtAnalogSecondsWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_analog_seconds_black
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
            WidgetStyle.BLACK -> R.layout.widget_kwgt_analog_seconds_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_analog_seconds_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_analog_seconds_transparent
        }
    }
}
