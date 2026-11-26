package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Separate native provider for KWGT Nothing_Digital3 ("KWGT Digital3 Dot Clock").
 *
 * The source composition is a rounded square with a 4 by 4 dot matrix. The
 * left cells hold the red `hh` and `mm` values, the next accent cell holds `aa`,
 * and the remaining dots use the source minute thresholds to switch between
 * `accent` and `accent2`. With optional exact-alarm access this provider draws
 * the full dot bitmap and refreshes it from the shared [MinuteTickScheduler].
 *
 * Without that access it draws the same dot matrix without any baked-in time
 * text and overlays three live platform TextClocks in the author cells, so a
 * frozen bitmap hour or minute is never presented as live. The dot colours are
 * refreshed on each normal widget update; the text itself stays live.
 *
 * The source has no 24-hour variant and uses `df(hh)`, `df(mm)` and `df(aa)`.
 * Both the styled bitmap and the fallback therefore force a 12-hour readout.
 */
class KwgtDigital3WidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_digital3
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
        return buildTargetBitmapViews(
            context,
            appWidgetId,
            R.id.widget_kwgt_digital3_bitmap,
            R.id.kwgt_digital3_live,
            render = { widthPx, heightPx ->
                if (!exactAccess) {
                    null
                } else {
                    KwgtDigital3Renderer.render(
                        context,
                        widthPx,
                        heightPx,
                        style,
                        Calendar.getInstance(),
                        includeBackground = true,
                    )
                }
            },
            decorateTarget = { views, usedBitmap, target ->
                val fallbackSurface = if (usedBitmap) {
                    false
                } else {
                    bindLiveFallback(views, context, style, target)
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
                val spoken = SimpleDateFormat("hh:mm a", Locale.getDefault())
                    .format(Calendar.getInstance().time)
                views.setContentDescription(
                    if (usedBitmap) {
                        R.id.widget_kwgt_digital3_bitmap
                    } else {
                        R.id.kwgt_digital3_live
                    },
                    context.getString(
                        if (usedBitmap) {
                            R.string.kwgt_digital3_content_description
                        } else {
                            R.string.kwgt_digital3_live_content_description
                        },
                        spoken,
                    ),
                )
            },
        )
    }

    /**
     * Draws the time-free dot matrix behind three live TextClocks and binds the
     * source ink colours. The bitmap keeps its raster pixel budget, but every
     * native cell is placed in true host content pixels so fitCenter stretching
     * of the square raster can never shrink or shift the live overlays.
     * Returns whether the dot bitmap was applied.
     */
    private fun bindLiveFallback(
        views: RemoteViews,
        context: Context,
        style: WidgetStyle,
        target: WidgetSizing.Target,
    ): Boolean {
        val density = context.resources.displayMetrics.density
        val geometry = KwgtDigital3Renderer.liveFallbackGeometry(
            hostWidthDp = target.hostSize.width,
            hostHeightDp = target.hostSize.height,
            density = density,
            rasterWidthPx = target.widthPx,
            rasterHeightPx = target.heightPx,
        )
        val bitmap = try {
            KwgtDigital3Renderer.renderDots(
                context,
                target.widthPx,
                target.heightPx,
                style,
                Calendar.getInstance(),
                includeBackground = true,
            )
        } catch (_: OutOfMemoryError) {
            null
        } catch (_: RuntimeException) {
            null
        }
        if (bitmap != null) {
            views.setViewVisibility(R.id.kwgt_digital3_live_bg, View.VISIBLE)
            views.setImageViewBitmap(R.id.kwgt_digital3_live_bg, bitmap)
        } else {
            views.setViewVisibility(R.id.kwgt_digital3_live_bg, View.GONE)
        }

        val palette = KwgtDigital3Renderer.palette(style)
        bindClockCell(
            views,
            R.id.kwgt_digital3_hour,
            geometry.hour,
            geometry.host.width,
            geometry.host.height,
            palette.foreground,
        )
        bindClockCell(
            views,
            R.id.kwgt_digital3_minute,
            geometry.minute,
            geometry.host.width,
            geometry.host.height,
            palette.foreground,
        )
        bindClockCell(
            views,
            R.id.kwgt_digital3_ampm,
            geometry.ampm,
            geometry.host.width,
            geometry.host.height,
            palette.contrastInk,
        )
        return bitmap != null
    }

    /**
     * Allocates the TextClock to its own fixed source cell in true host content
     * pixels. S+ gets explicit layout width/height/margins; padding is only the
     * pre-API-31 fallback, using the same host-space cell.
     */
    private fun bindClockCell(
        views: RemoteViews,
        viewId: Int,
        cell: KwgtDigital3Renderer.LiveCell,
        hostWidth: Float,
        hostHeight: Float,
        color: Int,
    ) {
        views.setTextColor(viewId, color)
        views.setTextViewTextSize(
            viewId,
            TypedValue.COMPLEX_UNIT_PX,
            cell.textSizePx,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutWidth(
                viewId,
                cell.width,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewLayoutHeight(
                viewId,
                cell.height,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewLayoutMargin(
                viewId,
                RemoteViews.MARGIN_LEFT,
                cell.left,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewLayoutMargin(
                viewId,
                RemoteViews.MARGIN_TOP,
                cell.top,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewLayoutMargin(
                viewId,
                RemoteViews.MARGIN_RIGHT,
                0f,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewLayoutMargin(
                viewId,
                RemoteViews.MARGIN_BOTTOM,
                0f,
                TypedValue.COMPLEX_UNIT_PX,
            )
            views.setViewPadding(viewId, 0, 0, 0, 0)
        } else {
            views.setViewPadding(
                viewId,
                cell.left.roundToInt().coerceIn(0, hostWidth.toInt()),
                cell.top.roundToInt().coerceIn(0, hostHeight.toInt()),
                (hostWidth - (cell.left + cell.width)).roundToInt()
                    .coerceIn(0, hostWidth.toInt()),
                (hostHeight - (cell.top + cell.height)).roundToInt()
                    .coerceIn(0, hostHeight.toInt()),
            )
        }
    }
}
