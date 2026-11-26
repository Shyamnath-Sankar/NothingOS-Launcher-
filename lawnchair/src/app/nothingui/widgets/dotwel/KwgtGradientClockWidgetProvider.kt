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
import kotlin.math.roundToInt

/**
 * Separate native provider for KWGT Nothing_Digital ("KWGT Gradient Clock").
 *
 * The source composition is a rounded square with three right-edge red gradient
 * circles, a centred 12-hour `hh` in foreground ink, and a red minute chip with
 * `mm` at the right edge. With optional exact-alarm access this provider draws
 * the dot-glyph bitmap and refreshes it from the shared [MinuteTickScheduler].
 * Without that access it shows the same static gradient surface using two live
 * platform TextClocks, so no stale bitmap time is ever presented as live.
 *
 * The source has no AM/PM layer and uses `df(hh)`/`df(mm)`. Both the styled
 * bitmap and every fallback therefore force a 12-hour hh/mm readout.
 */
class KwgtGradientClockWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_gradient_clock
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
        val exactAccess = MinuteTickScheduler.hasExactAccess(context)
        var renderWidth = 0
        var renderHeight = 0
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_gradient_bitmap,
            R.id.kwgt_gradient_live,
            render = { widthPx, heightPx ->
                renderWidth = widthPx
                renderHeight = heightPx
                if (!exactAccess) {
                    null
                } else {
                    KwgtGradientClockRenderer.render(
                        context,
                        widthPx,
                        heightPx,
                        style,
                        Calendar.getInstance(),
                        includeBackground = true,
                    )
                }
            },
        ) decorate@{ views, usedBitmap ->
            val fallbackSurface = if (usedBitmap) {
                false
            } else {
                bindLiveFallback(views, context, style, renderWidth, renderHeight)
            }
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap || fallbackSurface) {
                    R.drawable.bg_widget_none
                } else {
                    style.backgroundRes
                },
            )
            val spoken = SimpleDateFormat("hh:mm", Locale.getDefault())
                .format(Calendar.getInstance().time)
            views.setContentDescription(
                if (usedBitmap) {
                    R.id.widget_kwgt_gradient_bitmap
                } else {
                    R.id.kwgt_gradient_live
                },
                context.getString(
                    if (usedBitmap) {
                        R.string.kwgt_gradient_content_description
                    } else {
                        R.string.kwgt_gradient_live_content_description
                    },
                    spoken,
                ),
            )
        }
    }

    /**
     * Draws the time-free gradient surface behind the live TextClocks and binds
     * the source ink colours. Returns whether the static bitmap was applied so
     * the root surface is not painted twice.
     */
    private fun bindLiveFallback(
        views: RemoteViews,
        context: Context,
        style: WidgetStyle,
        widthPx: Int,
        heightPx: Int,
    ): Boolean {
        val density = context.resources.displayMetrics.density
        val width = widthPx.takeIf { it > 0 }
            ?: (110f * density).roundToInt().coerceAtLeast(48)
        val height = heightPx.takeIf { it > 0 }
            ?: (110f * density).roundToInt().coerceAtLeast(48)
        val bitmap = try {
            KwgtGradientClockRenderer.renderStaticBackground(
                context,
                width,
                height,
                style,
            )
        } catch (_: OutOfMemoryError) {
            null
        } catch (_: RuntimeException) {
            null
        }
        if (bitmap != null) {
            views.setViewVisibility(R.id.kwgt_gradient_live_bg, View.VISIBLE)
            views.setImageViewBitmap(R.id.kwgt_gradient_live_bg, bitmap)
        } else {
            views.setViewVisibility(R.id.kwgt_gradient_live_bg, View.GONE)
        }
        views.setTextColor(
            R.id.kwgt_gradient_hour,
            UpstreamNtDraw.ink(context, style),
        )
        views.setTextColor(
            R.id.kwgt_gradient_minute,
            KwgtGradientClockRenderer.minuteInk(context, style),
        )
        return bitmap != null
    }
}
