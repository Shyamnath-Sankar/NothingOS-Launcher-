package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import kotlin.math.min

/**
 * Kotlin translation of the NtQuotes.build() drawing block from AwesomeAWidgets
 * commit 0fae60722764bda790f89bd94119c6dab854d90e: 0.11*min-side margin, an
 * accent quote mark at 0.26*min, and a 0.13*min body that shrinks by 6% until it
 * fits the remaining height. Quote text comes from the upstream author data file
 * assets/nt_quotes.csv; Ndot/NType are substituted with platform families.
 */
object NtQuotesRenderer {
    fun render(
        context: Context,
        width: Int,
        height: Int,
        style: WidgetStyle,
        quote: String,
        includeBackground: Boolean = true,
    ): Bitmap {
        val bitmap = if (includeBackground) {
            UpstreamNtDraw.surface(context, width, height, style)
        } else {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
        val canvas = Canvas(bitmap)
        val minimumSide = min(width, height).toFloat()
        val margin = minimumSide * 0.11f

        val markPaint = UpstreamNtDraw.paint(
            context,
            style,
            Typeface.create("serif", Typeface.BOLD),
            UpstreamNtDraw.accent(context, style),
        )
        markPaint.textSize = minimumSide * 0.26f
        markPaint.textAlign = android.graphics.Paint.Align.LEFT
        canvas.drawText(
            "\u201C",
            margin,
            margin + minimumSide * 0.17f,
            markPaint,
        )

        val body = TextPaint(
            android.graphics.Paint.ANTI_ALIAS_FLAG or
                android.graphics.Paint.SUBPIXEL_TEXT_FLAG,
        ).apply {
            typeface = Typeface.create("serif", Typeface.NORMAL)
            color = UpstreamNtDraw.ink(context, style)
            UpstreamNtDraw.shadow(style, this)
        }
        val bodyWidth = (width - margin * 2f).toInt().coerceAtLeast(1)
        val bodyTop = margin + markPaint.textSize
        val bodyHeight = (height - bodyTop - margin).coerceAtLeast(1f)
        var textSize = minimumSide * 0.13f
        val floor = minimumSide * 0.045f
        var layout = buildLayout(quote, body, textSize, bodyWidth)
        while (layout.height > bodyHeight && textSize > floor) {
            textSize *= 0.94f
            layout = buildLayout(quote, body, textSize, bodyWidth)
        }
        canvas.save()
        canvas.translate(margin, bodyTop)
        canvas.clipRect(0f, 0f, bodyWidth.toFloat(), bodyHeight)
        layout.draw(canvas)
        canvas.restore()
        return bitmap
    }

    private fun buildLayout(
        quote: String,
        paint: TextPaint,
        textSize: Float,
        width: Int,
    ): StaticLayout {
        paint.textSize = textSize
        return StaticLayout.Builder.obtain(quote, 0, quote.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1.05f)
            .setIncludePad(false)
            .build()
    }
}
