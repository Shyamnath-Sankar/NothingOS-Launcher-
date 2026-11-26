package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.min

/**
 * Kotlin translation of NtDate.build() from AwesomeAWidgets commit
 * 0fae60722764bda790f89bd94119c6dab854d90e. Day number is fitted to
 * (width - 2*margin) x 0.62*height and centred at 0.6*height with the "00"
 * reference baseline; the abbreviated weekday is 0.15*min side, right aligned,
 * and drawn 0.85 of its text size below the top margin.
 *
 * NType/Lettera font files are substituted with the Android platform serif.
 */
object NtDateRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        date: Calendar = Calendar.getInstance(),
        includeBackground: Boolean = true,
    ): Bitmap {
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, width, height, style)
        } else {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        drawDate(canvas, width, height, context, style, date)
        return bitmap
    }

    private fun drawDate(
        canvas: Canvas,
        width: Int,
        height: Int,
        context: Context,
        style: WidgetStyle,
        date: Calendar,
    ) {
        val locale = Locale.getDefault()
        val day = SimpleDateFormat("d", locale).format(date.time)
        val weekday = SimpleDateFormat("EEE", locale).format(date.time)
        val serif = Typeface.create("serif", Typeface.NORMAL)
        val minimumSide = min(width, height).toFloat()
        val margin = minimumSide * 0.1f

        val dayPaint = UpstreamNtDraw.paint(
            context,
            style,
            serif,
            UpstreamNtDraw.ink(context, style),
        )
        dayPaint.textSize = UpstreamNtDraw.fit(
            dayPaint,
            "00",
            width - margin * 2f,
            height * 0.62f,
        )
        UpstreamNtDraw.center(
            canvas,
            dayPaint,
            day,
            "00",
            width / 2f,
            height * 0.6f,
        )

        val weekdayPaint = UpstreamNtDraw.paint(
            context,
            style,
            serif,
            UpstreamNtDraw.accent(context, style),
        )
        weekdayPaint.textSize = minimumSide * 0.15f
        weekdayPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(
            weekday,
            width - margin,
            margin + weekdayPaint.textSize * 0.85f,
            weekdayPaint,
        )
    }
}
