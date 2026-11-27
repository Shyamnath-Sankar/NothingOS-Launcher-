package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Calendar

/**
 * Separate native provider for KWGT Nothing_Mini_Calender.
 *
 * This is deliberately not an alias of [DateWidgetProvider]: it owns a five-day
 * strip, its own layout/metadata, provider class, pin result and preview kind.
 * It is date-only, so it never asks for Alarms &amp; reminders access and never
 * starts a minute scheduler. Android's updatePeriodMillis is always inexact and
 * may be deferred; the strip is also rebuilt on DATE_CHANGED, TIME_SET,
 * TIMEZONE_CHANGED, BOOT_COMPLETED, app refresh and every resize/options change.
 */
class KwgtMiniCalendarWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_mini_calendar

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
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
        val now = Calendar.getInstance()
        val range = KwgtMiniCalendarDates.rangeDescription(now)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_mini_calendar_bitmap,
            R.id.kwgt_mini_calendar_fallback,
            render = { widthPx, heightPx ->
                KwgtMiniCalendarRenderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    now,
                    includeBackground = false,
                )
            },
        ) decorate@{ views, usedBitmap ->
            views.setTextColor(
                R.id.kwgt_mini_calendar_fallback,
                UpstreamNtDraw.ink(context, style),
            )
            bindClicks(context, views, appWidgetId)
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_kwgt_mini_calendar_bitmap,
                    context.getString(
                        R.string.kwgt_mini_calendar_content_description,
                        range,
                    ),
                )
            } else {
                views.setContentDescription(
                    R.id.kwgt_mini_calendar_fallback,
                    context.getString(R.string.kwgt_mini_calendar_content_description, range),
                )
            }
        }
    }

    private fun bindClicks(context: Context, views: RemoteViews, appWidgetId: Int) {
        val calendar = Intent.makeMainSelectorActivity(
            Intent.ACTION_MAIN,
            Intent.CATEGORY_APP_CALENDAR,
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            calendar,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
    }
}
