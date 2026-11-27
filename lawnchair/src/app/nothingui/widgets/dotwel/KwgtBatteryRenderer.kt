package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap

/**
 * Battery Gauge surface. The source Nothing_Battery geometry is kept in
 * `assets/kwgt/nothing_battery.sanitized.json` for provenance, but the visible
 * surface now follows the reference battery family: a white #FFFFFF card, the
 * charge state in gray dot-matrix, the real level in black dot-matrix and a
 * bottom-right circular progress filled with the reference red #D71921. No
 * value is invented and the real level still comes from [BatteryState].
 */
object KwgtBatteryRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        level: Int,
        includeBackground: Boolean = false,
    ): Bitmap = ReferenceBatterySurface.render(
        context,
        BatterySurfaceKind.CIRCLE_PROGRESS,
        width,
        height,
        level,
        BatteryState.isCharging(context),
        style,
    )
}
