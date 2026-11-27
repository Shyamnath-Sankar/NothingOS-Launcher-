package app.nothingui.widgets.dotwel

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
 * Separate native provider for KWGT Nothing_Digital4 ("KWGT Split Clock").
 *
 * The source composition is a rounded square with a thin red centre divider,
 * a red 12-hour `hh` on the left and an ink `mm` on the right. With optional
 * exact-alarm access this provider draws the dot-glyph bitmap and refreshes it
 * from the shared [MinuteTickScheduler]. Without that access it shows the same
 * split composition using two live platform TextClocks and a static red line,
 * so no stale bitmap time is ever presented as live.
 *
 * The source has no AM/PM layer and uses `df(hh)`/`df(mm)`. Both the styled
 * bitmap and every fallback therefore force a 12-hour hh/mm readout.
 */
class KwgtDigital4WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_digital4
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
        if (!MinuteTickScheduler.hasExactAccess(context)) {
            return plainSplitViews(context, appWidgetId, style)
        }
        val now = Calendar.getInstance()
        val spoken = SimpleDateFormat("hh:mm", Locale.getDefault()).format(now.time)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_digital4_bitmap,
            R.id.kwgt_digital4_fallback,
            render = { widthPx, heightPx ->
                KwgtDigital4Renderer.render(
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
            views.setContentDescription(
                if (usedBitmap) {
                    R.id.widget_kwgt_digital4_bitmap
                } else {
                    R.id.kwgt_digital4_fallback
                },
                context.getString(
                    if (usedBitmap) {
                        R.string.kwgt_digital4_content_description
                    } else {
                        R.string.kwgt_digital4_live_content_description
                    },
                    spoken,
                ),
            )
        }
    }

    private fun plainSplitViews(
        context: Context,
        appWidgetId: Int,
        style: WidgetStyle,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setViewVisibility(R.id.widget_kwgt_digital4_bitmap, View.GONE)
        views.setViewVisibility(R.id.kwgt_digital4_fallback, View.VISIBLE)
        bindFallbackColors(views, context, style)
        val spoken = SimpleDateFormat("hh:mm", Locale.getDefault())
            .format(Calendar.getInstance().time)
        views.setContentDescription(
            R.id.kwgt_digital4_fallback,
            context.getString(R.string.kwgt_digital4_live_content_description, spoken),
        )
        return views
    }

    private fun bindFallbackColors(
        views: RemoteViews,
        context: Context,
        style: WidgetStyle,
    ) {
        views.setTextColor(R.id.kwgt_digital4_hour, KwgtDigital4Renderer.RED)
        views.setTextColor(R.id.kwgt_digital4_minute, UpstreamNtDraw.ink(context, style))
    }
}
