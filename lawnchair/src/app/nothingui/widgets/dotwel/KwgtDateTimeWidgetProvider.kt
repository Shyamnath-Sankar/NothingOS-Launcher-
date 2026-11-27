package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Native provider for the KWGT Nothing_Date_Time preset. With optional exact
 * alarm access it draws the converted four-line dot composition. Without that
 * access it shows four live platform TextClock rows in the same left stack, so
 * the fallback never freezes a fake time. No new permission or service is used.
 */
class KwgtDateTimeWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_datetime
    override val tapCategory: String = Intent.CATEGORY_APP_CALENDAR

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
            return plainDateTimeViews(context, appWidgetId, style)
        }
        val now = Calendar.getInstance()
        val spoken = SimpleDateFormat(
            "EEEE, MMMM d hh:mm a",
            Locale.getDefault(),
        ).format(now.time)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_datetime_bitmap,
            R.id.kwgt_datetime_fallback,
            render = { widthPx, heightPx ->
                KwgtDateTimeRenderer.render(
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
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap) R.drawable.bg_widget_none else style.backgroundRes,
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_kwgt_datetime_bitmap,
                    context.getString(R.string.kwgt_datetime_content_description, spoken),
                )
            }
        }
    }

    private fun plainDateTimeViews(
        context: Context,
        appWidgetId: Int,
        style: WidgetStyle,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setViewVisibility(R.id.widget_kwgt_datetime_bitmap, View.GONE)
        views.setViewVisibility(R.id.kwgt_datetime_fallback, View.VISIBLE)
        bindFallbackColors(views, context, style)
        return views
    }

    private fun bindFallbackColors(
        views: RemoteViews,
        context: Context,
        style: WidgetStyle,
    ) {
        val ink = UpstreamNtDraw.ink(context, style)
        views.setTextColor(R.id.kwgt_weekday, ink)
        views.setTextColor(R.id.kwgt_time, 0xFFD71921.toInt())
        views.setTextColor(R.id.kwgt_month, ink)
        views.setTextColor(R.id.kwgt_day, ink)
        views.setTextColor(R.id.kwgt_day_suffix, ink)
        val day = Calendar.getInstance().get(Calendar.DAY_OF_MONTH)
        views.setTextViewText(
            R.id.kwgt_day_suffix,
            KwgtDateTimeRenderer.ordinalSuffix(day),
        )
    }
}
