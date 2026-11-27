package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Canvas

object WidgetSurface {
    fun drawBackground(
        canvas: Canvas,
        width: Int,
        height: Int,
        context: Context,
        style: WidgetStyle,
    ) {
        UpstreamNtDraw.drawSurface(canvas, width, height, context, style)
    }
}
