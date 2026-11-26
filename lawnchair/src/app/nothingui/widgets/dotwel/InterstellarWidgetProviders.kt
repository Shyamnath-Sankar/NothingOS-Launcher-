package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import android.widget.RemoteViews
import com.android.launcher3.R

/**
 * Shared native provider for the three MIT AumGupta Interstellar Endurance
 * source presets. Geometry is compiled offline from the original Kustom JSON by
 * tools/compile_endurance.py into generated 277dp raster layers with true
 * CLEAR subtraction; no upstream bitmap artwork is used.
 *
 * The platform [android.widget.AnalogClock] rotates the source layer drawables:
 * variants 1/2 use a transparent seconds clock for the source CLOCK_SECOND
 * spacecraft plus a separate transparent hour/minute clock, preserving source
 * z-order (seconds below hour/minute). Variant 3 bakes the source static DEG180
 * spacecraft into the dial and uses native hour/minute hands. Android rotates
 * those hands itself, so true OS time survives process death without a polling
 * service. Seconds variants are gated to API 31 where RemoteViews supports the
 * `hand_second` drawable; variant 3 works on the app's supported API 26+.
 */
abstract class BaseInterstellarWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_interstellar
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS
    protected abstract val variant: InterstellarShapeCompiler.Variant
    protected open val needsSecondsLayer: Boolean = true

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val views = RemoteViews(
            context.packageName,
            InterstellarShapeCompiler.layoutFor(variant, style),
        )
        views.setInt(R.id.widget_root, "setBackgroundResource", style.backgroundRes)
        val pendingIntent = PendingIntent.getActivity(
            context,
            appWidgetId,
            Intent(AlarmClock.ACTION_SHOW_ALARMS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        if (needsSecondsLayer && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            views.setTextViewText(
                R.id.widget_message,
                context.getString(R.string.interstellar_pre31),
            )
            views.setTextColor(
                R.id.widget_message,
                UpstreamNtDraw.muted(context, style),
            )
        }
        return views
    }
}

class KwgtInterstellarEnduranceProvider : BaseInterstellarWidgetProvider() {
    override val variant: InterstellarShapeCompiler.Variant =
        InterstellarShapeCompiler.Variant.ENDURANCE
}

class KwgtInterstellarEnduranceAnalogProvider : BaseInterstellarWidgetProvider() {
    override val variant: InterstellarShapeCompiler.Variant =
        InterstellarShapeCompiler.Variant.ANALOG
}

class KwgtInterstellarEnduranceAnalog2Provider : BaseInterstellarWidgetProvider() {
    override val variant: InterstellarShapeCompiler.Variant =
        InterstellarShapeCompiler.Variant.ANALOG_2
    override val needsSecondsLayer: Boolean = false
}
