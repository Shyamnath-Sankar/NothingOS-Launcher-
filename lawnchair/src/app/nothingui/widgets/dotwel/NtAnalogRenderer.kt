package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import java.util.Calendar
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Programmatic analog composition adapted from the two AwesomeAWidgets
 * NtAnalogBold/NtAnalogScale provider layouts (commit
 * 0fae60722764bda790f89bd94119c6dab854d90e): a circular palette surface, a
 * tick ring for the Scale variant, and bold/thin hour and minute hands.
 *
 * The upstream dial and hand drawables are deliberately not copied. Their
 * geometry is replaced with original Canvas drawing so no unverified artwork is
 * redistributed. The palette and opaque/translucent/transparent treatment come
 * from the translated NtDraw.SCHEME.
 */
object NtAnalogRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        time: Calendar = Calendar.getInstance(),
        bold: Boolean,
        includeBackground: Boolean = true,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = UpstreamNtDraw.background(context, style)
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = min(width, height) * 0.5f
        if (includeBackground && Color.alpha(background) != 0) {
            val surfacePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
            canvas.drawCircle(centerX, centerY, radius, surfacePaint)
        }

        val ink = UpstreamNtDraw.ink(context, style)
        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            strokeCap = Paint.Cap.ROUND
            UpstreamNtDraw.shadow(style, this)
        }
        val dialRadius = radius * 0.86f

        if (!bold) {
            for (index in 0 until 60) {
                val angle = Math.toRadians(index * 6.0 - 90.0)
                val major = index % 5 == 0
                val inner = dialRadius * if (major) 0.84f else 0.91f
                tickPaint.strokeWidth = dialRadius * if (major) 0.018f else 0.008f
                canvas.drawLine(
                    centerX + (cos(angle) * inner).toFloat(),
                    centerY + (sin(angle) * inner).toFloat(),
                    centerX + (cos(angle) * dialRadius).toFloat(),
                    centerY + (sin(angle) * dialRadius).toFloat(),
                    tickPaint,
                )
            }
        } else {
            tickPaint.strokeWidth = dialRadius * 0.022f
            for (index in 0 until 4) {
                val angle = Math.toRadians(index * 90.0 - 90.0)
                canvas.drawLine(
                    centerX + (cos(angle) * dialRadius * 0.80f).toFloat(),
                    centerY + (sin(angle) * dialRadius * 0.80f).toFloat(),
                    centerX + (cos(angle) * dialRadius * 0.96f).toFloat(),
                    centerY + (sin(angle) * dialRadius * 0.96f).toFloat(),
                    tickPaint,
                )
            }
        }

        val hour = time.get(Calendar.HOUR)
        val minute = time.get(Calendar.MINUTE)
        val second = time.get(Calendar.SECOND)
        val handPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            strokeCap = Paint.Cap.ROUND
            UpstreamNtDraw.shadow(style, this)
        }
        val hourAngle = (hour + minute / 60f) * 30f - 90f
        handPaint.strokeWidth = dialRadius * if (bold) 0.11f else 0.055f
        drawHand(canvas, centerX, centerY, dialRadius * 0.52f, hourAngle, handPaint)

        val minuteAngle = minute * 6f - 90f
        handPaint.strokeWidth = dialRadius * if (bold) 0.085f else 0.035f
        drawHand(canvas, centerX, centerY, dialRadius * 0.78f, minuteAngle, handPaint)

        handPaint.strokeWidth = dialRadius * 0.012f
        handPaint.color = UpstreamNtDraw.accent(context, style)
        drawHand(canvas, centerX, centerY, dialRadius * 0.84f, second * 6f - 90f, handPaint)

        handPaint.color = ink
        canvas.drawCircle(centerX, centerY, dialRadius * 0.028f, handPaint)
        return bitmap
    }

    private fun drawHand(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        length: Float,
        angleDegrees: Float,
        paint: Paint,
    ) {
        val angle = Math.toRadians(angleDegrees.toDouble())
        canvas.drawLine(
            centerX,
            centerY,
            centerX + (cos(angle) * length).toFloat(),
            centerY + (sin(angle) * length).toFloat(),
            paint,
        )
    }
}
