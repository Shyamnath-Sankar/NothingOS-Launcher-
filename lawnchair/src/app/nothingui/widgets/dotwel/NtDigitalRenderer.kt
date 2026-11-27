package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.text.format.DateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Kotlin translation of NtDigital.build() from AwesomeAWidgets commit
 * 0fae60722764bda790f89bd94119c6dab854d90e. Upstream draws the hour and minute
 * at 0.27/0.73 of the height, fits a "00" reference to 0.76 of the width and
 * 0.37 of the height, and centres each row with the reference bounds baseline.
 * Ndot is substituted with Dotwel's original circular-dot glyphs.
 */
object NtDigitalRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        time: Calendar = Calendar.getInstance(),
        includeBackground: Boolean = true,
    ): Bitmap {
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, width, height, style)
        } else {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        drawTime(canvas, width, height, context, style, time)
        return bitmap
    }

    private fun drawTime(
        canvas: Canvas,
        width: Int,
        height: Int,
        context: Context,
        style: WidgetStyle,
        time: Calendar,
    ) {
        val is24Hour = DateFormat.is24HourFormat(context)
        var hour = if (is24Hour) {
            time.get(Calendar.HOUR_OF_DAY)
        } else {
            time.get(Calendar.HOUR)
        }
        if (!is24Hour && hour == 0) hour = 12
        val minute = time.get(Calendar.MINUTE)
        val hours = String.format(Locale.US, "%02d", hour)
        val minutes = String.format(Locale.US, "%02d", minute)

        val pitch = DotGlyphFont.fitPitch(
            "00",
            width * 0.76f,
            height * 0.37f,
        )
        if (pitch <= 0f) return

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = UpstreamNtDraw.ink(context, style)
            UpstreamNtDraw.shadow(style, this)
        }
        DotGlyphFont.drawCentered(
            canvas,
            hours,
            width / 2f,
            height * 0.27f,
            pitch,
            paint,
        )
        DotGlyphFont.drawCentered(
            canvas,
            minutes,
            width / 2f,
            height * 0.73f,
            pitch,
            paint,
        )
    }
}
