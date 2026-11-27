package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Native provider for KWGT Nothing_Digital2.
 *
 * The source stack has a previous relative minute, a central time module with
 * no expression, and a next relative minute. The central value is a live
 * TextClock repaired from the preview/source intent; the surrounding relative
 * labels are redrawn by [MinuteTickScheduler] when the optional exact-alarm
 * access is present. Without it the central clock stays live and the relative
 * labels are hidden instead of displaying stale minutes.
 */
class KwgtDigital2WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_digital2
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun onUpdate(
        context: Context,
        appWidgetManager: android.appwidget.AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: android.appwidget.AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            MinuteTickScheduler.ACTION_TICK,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            -> {
                refreshWidgets(context)
                MinuteTickScheduler.schedule(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        return buildTargetBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_digital2_bitmap,
            R.id.kwgt_digital2_clock,
            render = { widthPx, heightPx ->
                KwgtDigital2Renderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    includeBackground = true,
                    includeShiftedMinutes = MinuteTickScheduler.hasExactAccess(context),
                )
            },
            decorateTarget = { views, _, target ->
                val contentWidth = (target.hostSize.width - WidgetSizing.CONTENT_INSET_DP * 2).coerceAtLeast(1f)
                val contentHeight = (target.hostSize.height - WidgetSizing.CONTENT_INSET_DP * 2).coerceAtLeast(1f)
                val side = minOf(contentWidth, contentHeight)
                val density = context.resources.displayMetrics.density
                val palette = KwgtDigital2Renderer.palette(style)
                views.setViewVisibility(R.id.kwgt_digital2_clock, View.VISIBLE)
                views.setInt(
                    R.id.widget_root,
                    "setBackgroundResource",
                    R.drawable.bg_widget_none,
                )
                views.setTextColor(R.id.kwgt_digital2_clock, palette.foreground)
                views.setTextViewTextSize(
                    R.id.kwgt_digital2_clock,
                    android.util.TypedValue.COMPLEX_UNIT_PX,
                    side * density / 3.5f,
                )
                views.setViewPadding(
                    R.id.kwgt_digital2_clock,
                    0,
                    0,
                    (((contentWidth - side) / 2f + side / 8.5f) * density).toInt(),
                    0,
                )
                views.setCharSequence(
                    R.id.kwgt_digital2_clock,
                    "setFormat12Hour",
                    if (DateFormat.is24HourFormat(context)) "HH:mm" else "hh:mm",
                )
                views.setCharSequence(
                    R.id.kwgt_digital2_clock,
                    "setFormat24Hour",
                    if (DateFormat.is24HourFormat(context)) "HH:mm" else "hh:mm",
                )
            },
        )
    }
}
