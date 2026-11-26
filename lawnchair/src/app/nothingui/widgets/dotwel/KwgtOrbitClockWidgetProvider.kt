package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import android.util.TypedValue
import android.widget.RemoteViews
import com.android.launcher3.R
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Separate native provider for KWGT Nothing_Digital_Clock ("KWGT Orbit Clock").
 *
 * The actual source is a 277 circle with a 164 inner disc, a central `hh:mm`
 * TextModule, a 205 hour orbit and a 245 minute orbit drawn as thin 0.5
 * strokes, plus a red 12 hour dot and a 12 minute dot. It is reproduced with a
 * platform [android.widget.AnalogClock] whose static vector dial carries the
 * outer circle, inner circle and both orbits, and whose transparent 277 hand
 * vectors carry the dots at 12 o'clock. The platform clock rotates the dots
 * itself; a live [android.widget.TextClock] supplies the central time.
 *
 * The source stores `config_rotate_mode` values `CLOCK_HOUR_SMOOTH` and
 * `CLOCK_MINUTE`. Its formula values `CLOCK_SECOND` carry toggle 0 and are
 * inactive, so no seconds hand is added and there is no API 31 restriction.
 *
 * The source rotate offset 90 with the horizontal-stack right paddings 204/245
 * puts the dots at radius 102/122.5 on the 9 o'clock side before rotation. The
 * native 12-o'clock dot vectors plus the platform clockwise rotation absorb
 * that mapping: at the upstream preview 02:11 the red hour dot is around 2 and
 * the minute dot just after 2.
 *
 * One layout exists per Dotwel style: black uses the source `#1B1B1D` outer
 * circle with a white inner disc and dark central ink; translucent uses a
 * `#A6FFFFFF` outer circle with a dark inner disc and white ink; transparent
 * keeps the white inner disc and orbits without a filled outer card. The hour
 * dot stays the source red `#D71921` in every style.
 *
 * The central time is re-bound on every update. RemoteViews can otherwise keep
 * the previous layout's text colour when the same view id is reused across a
 * style change, which made translucent time dark on the dark inner disc. The
 * size and 3/-4 offsets are also re-bound from the actual host size using the
 * source 46/277 proportion, because AnalogClock only downscales its intrinsic
 * 277 dial while a fixed sp size would drift out of the inner disc on resize.
 */
class KwgtOrbitClockWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_kwgt_orbit_black
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val views = RemoteViews(context.packageName, layoutFor(style))
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(appWidgetId)
        val host = WidgetSizing.currentHostSize(context, options)
        val metrics = timeMetrics(
            hostWidthDp = host.width,
            hostHeightDp = host.height,
            density = context.resources.displayMetrics.density,
        )
        views.setTextColor(R.id.kwgt_orbit_time, timeInk(style))
        views.setTextViewTextSize(
            R.id.kwgt_orbit_time,
            TypedValue.COMPLEX_UNIT_PX,
            metrics.textSizePx,
        )
        views.setViewPadding(
            R.id.kwgt_orbit_time,
            metrics.padLeft,
            metrics.padTop,
            metrics.padRight,
            metrics.padBottom,
        )
        views.setCharSequence(R.id.kwgt_orbit_time, "setFormat12Hour", FORMAT_12)
        views.setCharSequence(R.id.kwgt_orbit_time, "setFormat24Hour", FORMAT_24)
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
        private const val FORMAT_12 = "hh:mm"
        private const val FORMAT_24 = "HH:mm"
        private const val SOURCE_CANVAS = 277f
        private const val SOURCE_TIME_SIZE = 46f
        private const val SOURCE_OFFSET_X = 3f
        private const val SOURCE_OFFSET_Y = 4f

        internal data class TimeMetrics(
            val textSizePx: Float,
            val offsetXPx: Float,
            val offsetYPx: Float,
            val padLeft: Int,
            val padTop: Int,
            val padRight: Int,
            val padBottom: Int,
        )

        internal fun timeInk(style: WidgetStyle): Int = when (style) {
            WidgetStyle.TRANSLUCENT -> 0xFFFFFFFF.toInt()
            WidgetStyle.BLACK, WidgetStyle.TRANSPARENT -> 0xFF1B1B1D.toInt()
        }

        internal fun timeMetrics(
            hostWidthDp: Float,
            hostHeightDp: Float,
            density: Float,
        ): TimeMetrics {
            val contentWidthDp = (hostWidthDp - WidgetSizing.CONTENT_INSET_DP * 2f)
                .coerceAtLeast(1f)
            val contentHeightDp = (hostHeightDp - WidgetSizing.CONTENT_INSET_DP * 2f)
                .coerceAtLeast(1f)
            val sidePx = min(contentWidthDp, contentHeightDp) * density
            val offsetX = sidePx * SOURCE_OFFSET_X / SOURCE_CANVAS
            val offsetY = -sidePx * SOURCE_OFFSET_Y / SOURCE_CANVAS
            return TimeMetrics(
                textSizePx = sidePx * SOURCE_TIME_SIZE / SOURCE_CANVAS,
                offsetXPx = offsetX,
                offsetYPx = offsetY,
                padLeft = (offsetX * 2f).roundToInt().coerceAtLeast(0),
                padTop = (offsetY * 2f).roundToInt().coerceAtLeast(0),
                padRight = (-offsetX * 2f).roundToInt().coerceAtLeast(0),
                padBottom = (-offsetY * 2f).roundToInt().coerceAtLeast(0),
            )
        }

        fun layoutFor(style: WidgetStyle): Int = when (style) {
            WidgetStyle.BLACK -> R.layout.widget_kwgt_orbit_black
            WidgetStyle.TRANSLUCENT -> R.layout.widget_kwgt_orbit_translucent
            WidgetStyle.TRANSPARENT -> R.layout.widget_kwgt_orbit_transparent
        }
    }
}
