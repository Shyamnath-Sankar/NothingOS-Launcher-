package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for KWGT Nothing_Future_Clock ("KWGT Future Clock").
 *
 * The source is a wide rounded band with three circular discs side by side. Each
 * disc is a CIRCLE of diameter `h / 2` (where the background height is the host
 * height / 1.5) painted BLACK with a SWEEP gradient to the hour `#D71921`,
 * minute `#CBCBCB` or second `#6C696E` global. The source rotates the hour with
 * `CLOCK_HOUR_SMOOTH`, the minute with `CLOCK_MINUTE` and the second with the
 * active `CLOCK_SECOND` formula, each with a 180 degree offset.
 *
 * This port uses one platform [android.widget.AnalogClock] per disc. The
 * matching sweep-gradient circle is the single visible hand drawable; the dial
 * and the other hands are transparent 277 x 277 vectors so no layer gets a
 * different intrinsic scale. The platform rotation supplies the clock angles,
 * and a 180 degree vector group rotation supplies the source offset exactly:
 * the Android sweep shader starts at 3 o'clock and turns clockwise, the same
 * direction as the native clock canvas rotation.
 *
 * Live labels are platform [android.widget.TextClock] views with the source
 * fixed 12-hour `hh' hr'`, `mm' min'` and `ss' sec'` text in both format slots.
 * They update with the OS clock cadence without an app service, alarm or exact
 * alarm access.
 *
 * Only the `layout-v31` files wire `android:hand_second`. The receiver is
 * disabled below API 31 with the existing `kwgt_analog_seconds_available` bool,
 * and the catalog marks the entry unavailable there rather than silently
 * dropping the seconds disc.
 */
class KwgtFutureWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_future_black
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
            WidgetStyle.BLACK -> R.layout.widget_kwgt_future_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_future_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_future_transparent
        }
    }
}
