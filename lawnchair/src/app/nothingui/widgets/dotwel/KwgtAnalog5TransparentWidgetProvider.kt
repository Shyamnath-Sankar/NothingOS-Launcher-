package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Separate native provider for KWGT Nothing_Analog_5_Transparent.
 *
 * This is not an alias of [KwgtAnalog5WidgetProvider]. It reads the actual
 * transparent source preset: minute ticks use the `style_size = side * 1.05`
 * ring, the outer clip corner is `side / 5`, the first CLEAR overlay corner is
 * `side / 6.5`, and both CLEAR overlays are real even-odd holes instead of a
 * background-coloured fill. The source has no `bg` or `h` global, so the
 * wallpaper/foreground contrast is selected manually per Dotwel style and all
 * three layouts are transparent with no filled dial card.
 *
 * The static tick dial is drawn by a 277 vector, and the platform
 * [android.widget.AnalogClock] rotates the red `#D71921` hour pill and the
 * foreground minute pill itself. No bitmap time, minute alarm, extra
 * permission, service or new dependency is used.
 */
class KwgtAnalog5TransparentWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_analog5clear_black
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
            WidgetStyle.BLACK -> R.layout.widget_kwgt_analog5clear_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_analog5clear_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_analog5clear_transparent
        }
    }
}
