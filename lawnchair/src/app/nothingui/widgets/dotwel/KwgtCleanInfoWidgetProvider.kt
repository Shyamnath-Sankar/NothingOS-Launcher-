package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import android.util.TypedValue
import android.widget.RemoteViews
import com.android.launcher3.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Separate native provider for KWGT `Clean_Time_Date_Info` ("KWGT Clean Info").
 *
 * The widget is a 553x248 wide card: a rounded surface, a bottom-left weekday
 * and uppercase month/day stack, an intentional oversized ghost `h:mm` back
 * layer, and a top-left battery body plus nub with the real battery percentage.
 *
 * Time, weekday and date are live platform TextClocks, so no frozen bitmap time
 * is ever drawn and optional Alarms & reminders access is not needed. The only
 * bitmap is the static card/battery background. The percentage is read from the
 * real system [BatteryState] path and refreshed on the system battery broadcast.
 *
 * Use [BaseWidgetProvider.buildTargetBitmapViews] so each exact host size gets
 * its own RemoteViews variant and native text is sized in true host content
 * pixels rather than the downsampled background raster.
 */
class KwgtCleanInfoWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_clean_info
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS
    override val refreshesBatteryAlarm: Boolean = true

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_BATTERY_CHANGED,
            -> {
                refreshWidgets(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val level = BatteryState.level(context)
        return buildTargetBitmapViews(
            context,
            appWidgetId,
            R.id.kwgt_clean_info_bg,
            R.id.kwgt_clean_info_bg_fallback,
            render = { widthPx, heightPx ->
                KwgtCleanInfoRenderer.renderBackground(
                    context,
                    widthPx,
                    heightPx,
                    style,
                )
            },
            decorateTarget = { views, usedBitmap, target ->
                bindContent(context, views, style, target, level, usedBitmap)
            },
        )
    }

    private fun bindContent(
        context: Context,
        views: RemoteViews,
        style: WidgetStyle,
        target: WidgetSizing.Target,
        level: Int,
        usedBitmap: Boolean,
    ) {
        val density = context.resources.displayMetrics.density
        val layout = KwgtCleanInfoRenderer.layoutForHost(
            hostWidthDp = target.hostSize.width,
            hostHeightDp = target.hostSize.height,
            density = density,
        )
        val palette = KwgtCleanInfoRenderer.palette(context, style)
        val width = layout.width
        val height = layout.height

        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            if (usedBitmap || style == WidgetStyle.TRANSPARENT) {
                R.drawable.bg_widget_none
            } else {
                style.backgroundRes
            },
        )

        views.setTextColor(R.id.kwgt_clean_info_time, palette.timeInk)
        views.setTextViewTextSize(
            R.id.kwgt_clean_info_time,
            TypedValue.COMPLEX_UNIT_PX,
            layout.timeTextSize,
        )
        views.setViewPadding(
            R.id.kwgt_clean_info_time,
            0,
            0,
            layout.rightPad.roundToInt().coerceIn(0, width.toInt()),
            0,
        )

        views.setTextColor(R.id.kwgt_clean_info_weekday, palette.foreground)
        views.setTextViewTextSize(
            R.id.kwgt_clean_info_weekday,
            TypedValue.COMPLEX_UNIT_PX,
            layout.weekdayTextSize,
        )
        views.setTextColor(R.id.kwgt_clean_info_date, palette.foreground)
        views.setTextViewTextSize(
            R.id.kwgt_clean_info_date,
            TypedValue.COMPLEX_UNIT_PX,
            layout.dateTextSize,
        )
        views.setViewPadding(
            R.id.kwgt_clean_info_left,
            layout.leftPad.roundToInt().coerceIn(0, width.toInt()),
            0,
            0,
            layout.bottomPad.roundToInt().coerceIn(0, height.toInt()),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutMargin(
                R.id.kwgt_clean_info_date,
                RemoteViews.MARGIN_TOP,
                -layout.stackMargin,
                TypedValue.COMPLEX_UNIT_PX,
            )
        }

        views.setTextViewText(
            R.id.kwgt_clean_info_battery,
            KwgtCleanInfoRenderer.batteryText(level),
        )
        views.setTextColor(R.id.kwgt_clean_info_battery, palette.batteryInk)
        views.setTextViewTextSize(
            R.id.kwgt_clean_info_battery,
            TypedValue.COMPLEX_UNIT_PX,
            layout.batteryTextSize,
        )
        val body = layout.batteryBody
        views.setViewPadding(
            R.id.kwgt_clean_info_battery,
            body.left.roundToInt().coerceIn(0, width.toInt()),
            body.top.roundToInt().coerceIn(0, height.toInt()),
            (width - body.right).roundToInt().coerceIn(0, width.toInt()),
            (height - body.bottom).roundToInt().coerceIn(0, height.toInt()),
        )
        views.setContentDescription(
            R.id.kwgt_clean_info_battery,
            context.getString(R.string.kwgt_clean_info_battery_description, level),
        )

        val spoken = SimpleDateFormat("h:mm a", Locale.getDefault())
            .format(Calendar.getInstance().time)
        views.setContentDescription(
            R.id.widget_root,
            context.getString(R.string.kwgt_clean_info_content_description, spoken),
        )
    }
}
