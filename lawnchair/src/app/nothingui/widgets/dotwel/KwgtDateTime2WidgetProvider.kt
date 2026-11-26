package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Native provider for the KWGT Nothing_Date_Time2 preset. The upper-left date
 * stack and lower-right hour/minute disc composition are drawn as a bitmap only
 * while optional exact-alarm access is available. Without that access the same
 * regions show live platform TextClock values, so no analog disc can appear
 * frozen at an old minute.
 */
class KwgtDateTime2WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_datetime2

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
        if (!MinuteTickScheduler.hasExactAccess(context)) {
            return plainDateTime2Views(context, appWidgetId, style)
        }
        val now = Calendar.getInstance()
        val spoken = SimpleDateFormat(
            "EEEE, MMMM d hh:mm a",
            Locale.getDefault(),
        ).format(now.time)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_datetime2_bitmap,
            R.id.kwgt_datetime2_fallback,
            render = { widthPx, heightPx ->
                KwgtDateTime2Renderer.render(
                    context,
                    widthPx,
                    heightPx,
                    style,
                    now,
                    includeBackground = true,
                )
            },
        ) decorate@{ views, usedBitmap ->
            bindFallbackColors(views, context, style)
            bindClicks(context, views, appWidgetId)
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap) R.drawable.bg_widget_none else style.backgroundRes,
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_kwgt_datetime2_bitmap,
                    context.getString(R.string.kwgt_datetime2_content_description, spoken),
                )
            }
        }
    }

    private fun plainDateTime2Views(
        context: Context,
        appWidgetId: Int,
        style: WidgetStyle,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setViewVisibility(R.id.widget_kwgt_datetime2_bitmap, View.GONE)
        views.setViewVisibility(R.id.kwgt_datetime2_fallback, View.VISIBLE)
        bindFallbackColors(views, context, style)
        bindClicks(context, views, appWidgetId)
        views.setContentDescription(
            R.id.kwgt_datetime2_fallback,
            context.getString(R.string.kwgt_datetime2_live_content_description),
        )
        return views
    }

    private fun bindFallbackColors(
        views: RemoteViews,
        context: Context,
        style: WidgetStyle,
    ) {
        val ink = UpstreamNtDraw.ink(context, style)
        views.setTextColor(R.id.kwgt2_weekday, ink)
        views.setTextColor(R.id.kwgt2_day, 0xFFD71921.toInt())
        views.setTextColor(R.id.kwgt2_hour, ink)
        views.setTextColor(R.id.kwgt2_minute, ink)
    }

    private fun bindClicks(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
    ) {
        views.setOnClickPendingIntent(
            R.id.kwgt2_date_tap,
            activityIntent(
                context,
                appWidgetId * 4 + 1,
                Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CALENDAR),
            ),
        )
        views.setOnClickPendingIntent(
            R.id.kwgt2_time_tap,
            activityIntent(
                context,
                appWidgetId * 4 + 2,
                Intent(AlarmClock.ACTION_SHOW_ALARMS),
            ),
        )
        views.setOnClickPendingIntent(
            R.id.widget_root,
            activityIntent(
                context,
                appWidgetId * 4 + 3,
                Intent(context, app.lawnchair.LawnchairLauncher::class.java),
            ),
        )
    }

    private fun activityIntent(context: Context, requestCode: Int, intent: Intent): PendingIntent {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
