package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for KWGT Nothing_Analog_5 ("KWGT Analog5").
 *
 * The source composition is a 277 square dial built from a rounded background,
 * a clipped 60-tick minute ring, two rounded background overlays, a 12-tick
 * hour ring, and filled rounded pill hands with no seconds layer. It is
 * reproduced with a platform [android.widget.AnalogClock] in the RemoteViews
 * layout, using vector resources for the static dial and both hands. The
 * platform clock rotates the hour and minute hands itself, so no bitmap time,
 * minute alarm, extra permission, service or AnalogClock runtime setter is used.
 *
 * One layout exists per Dotwel style: black uses the source `#1B1B1D` dial with
 * white ticks and minute hand, translucent uses a white `#A6` dial with dark
 * ticks and minute hand, and transparent uses no filled dial with white ticks
 * and minute hand. The source `primary` red `#D71921` hour hand is unchanged in
 * every style.
 */
class KwgtAnalog5WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_analog5_black
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
            WidgetStyle.BLACK -> R.layout.widget_kwgt_analog5_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_analog5_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_analog5_transparent
        }
    }
}
