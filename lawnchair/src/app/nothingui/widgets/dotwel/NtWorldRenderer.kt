package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.format.DateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.min

/**
 * Kotlin translation of NtWorld.build() from AwesomeAWidgets commit
 * 0fae60722764bda790f89bd94119c6dab854d90e: 0.12*min-side margin, two rows of
 * 0.22*row-height muted labels with the time fitted to half the row height and
 * drawn at 0.88*row-height. Ndot55/Ndot77 are substituted with platform
 * condensed/sans families; per-widget zones come from WorldPrefs.
 */
object NtWorldRenderer {
    data class Zone(val label: String, val zoneId: String)

    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        zones: List<Zone>,
        includeBackground: Boolean = true,
    ): Bitmap {
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, width, height, style)
        } else {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        val is24Hour = DateFormat.is24HourFormat(context)
        val margin = min(width, height) * 0.12f
        val rowHeight = (height - margin * 2f) / 2f

        val timePaint = UpstreamNtDraw.paint(
            context,
            style,
            Typeface.create("sans-serif-condensed", Typeface.BOLD),
            UpstreamNtDraw.ink(context, style),
        )
        timePaint.textAlign = Paint.Align.LEFT
        timePaint.textSize = UpstreamNtDraw.fit(
            timePaint,
            "00:00",
            width - margin * 2f,
            rowHeight * 0.5f,
        )

        val labelPaint = UpstreamNtDraw.paint(
            context,
            style,
            Typeface.create("sans-serif", Typeface.NORMAL),
            UpstreamNtDraw.muted(context, style),
        )
        labelPaint.textAlign = Paint.Align.LEFT
        labelPaint.textSize = rowHeight * 0.22f

        zones.take(2).forEachIndexed { index, zone ->
            val calendar = Calendar.getInstance(TimeZone.getTimeZone(zone.zoneId))
            val hour = if (is24Hour) {
                calendar.get(Calendar.HOUR_OF_DAY)
            } else {
                calendar.get(Calendar.HOUR).let { if (it == 0) 12 else it }
            }
            val minute = calendar.get(Calendar.MINUTE)
            val time = String.format(Locale.US, "%02d:%02d", hour, minute)
            val rowTop = index * rowHeight + margin
            canvas.drawText(
                zone.label.uppercase(Locale.getDefault()),
                margin,
                rowTop + rowHeight * 0.26f,
                labelPaint,
            )
            canvas.drawText(
                time,
                margin,
                rowTop + rowHeight * 0.88f,
                timePaint,
            )
        }
        return bitmap
    }
}
