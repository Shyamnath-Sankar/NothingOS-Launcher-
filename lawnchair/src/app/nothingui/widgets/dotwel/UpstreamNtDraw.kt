package app.nothingui.widgets.dotwel

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.min

/**
 * Kotlin translation of the author-written renderer helpers in
 * AwesomeAWidgets commit 0fae60722764bda790f89bd94119c6dab854d90e,
 * AAWidgets/smali_classes3/com/awesomeandro/widgetsplus/nothing/NtDraw.smali:
 * SCHEME/color, surface, fit, center, paint and shadow.
 *
 * MIT License, Copyright (c) 2026 Sameer Al Sahab. See
 * docs/upstream/awesomeawidgets-NOTICE.md and the bundled MIT text.
 *
 * Deliberate substitutions: the upstream Ndot/NType/Lettera/Inter font files are
 * not redistributable here. Dot digits remain Dotwel's original geometric glyphs
 * and text uses the Android platform families. NtDraw.size is intentionally not
 * translated; Dotwel keeps its corrected host-size mapping in WidgetSizing.
 */
object UpstreamNtDraw {
    private val SCHEME: Array<IntArray> = arrayOf(
        intArrayOf(
            0xFF12151D.toInt(),
            0xFFE9EAF2.toInt(),
            0xFF7C7F8A.toInt(),
            0xFFE8202A.toInt(),
        ),
        intArrayOf(
            0xA6FFFFFF.toInt(),
            0xFF1B1D1F.toInt(),
            0xFF5F626C.toInt(),
            0xFFD71921.toInt(),
        ),
        intArrayOf(
            0x00000000,
            0xFFFFFFFF.toInt(),
            0xFFD4D6DD.toInt(),
            0xFFFF3B30.toInt(),
        ),
    )

    private const val KEY_BG = 0
    private const val KEY_INK = 1
    private const val KEY_MUTED = 2
    private const val KEY_ACCENT = 3

    private const val PAINT_FLAGS = Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG

    fun color(context: Context, style: WidgetStyle, key: String): Int {
        val scheme = SCHEME[style.id.coerceIn(0, SCHEME.lastIndex)]
        val index = when (key) {
            "nt_bg" -> KEY_BG
            "nt_ink" -> KEY_INK
            "nt_muted" -> KEY_MUTED
            else -> KEY_ACCENT
        }
        return scheme[index]
    }

    fun ink(context: Context, style: WidgetStyle): Int = color(context, style, "nt_ink")

    fun muted(context: Context, style: WidgetStyle): Int = color(context, style, "nt_muted")

    fun accent(context: Context, style: WidgetStyle): Int = color(context, style, "nt_accent")

    fun background(context: Context, style: WidgetStyle): Int = color(context, style, "nt_bg")

    fun paint(context: Context, style: WidgetStyle, typeface: Typeface?, color: Int): Paint {
        val paint = Paint(PAINT_FLAGS)
        paint.typeface = typeface
        paint.color = color
        shadow(style, paint)
        return paint
    }

    fun shadow(style: WidgetStyle, paint: Paint) {
        if (style == WidgetStyle.TRANSPARENT) {
            paint.setShadowLayer(5f, 0f, 2f, 0x99000000.toInt())
        }
    }

    /** Translated from NtDraw.fit: measure at 100sp and scale to the two bounds. */
    fun fit(paint: Paint, text: String, maxWidth: Float, maxHeight: Float): Float {
        paint.textSize = 100f
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        if (bounds.width() <= 0) return 20f
        if (bounds.height() <= 0) return 100f
        return 100f * min(
            maxWidth / bounds.width().toFloat(),
            maxHeight / bounds.height().toFloat(),
        )
    }

    /**
     * Translated from NtDraw.center. The baseline is corrected with the reference
     * text's exact vertical centre, not the drawn string's own bounds.
     */
    fun center(
        canvas: Canvas,
        paint: Paint,
        text: String,
        reference: String,
        x: Float,
        y: Float,
    ) {
        val bounds = Rect()
        paint.getTextBounds(reference, 0, reference.length, bounds)
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(text, x, y - bounds.exactCenterY(), paint)
    }

    /**
     * Translated from NtDraw.surface. Returns a transparent bitmap when the
     * scheme's background alpha is zero, exactly like the upstream early return.
     */
    fun surface(context: Context, width: Int, height: Int, style: WidgetStyle): Bitmap {
        val bitmap = Bitmap.createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val background = background(context, style)
        if (Color.alpha(background) == 0) return bitmap
        val canvas = Canvas(bitmap)
        val radius = min(width, height) * 0.22f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()),
            radius,
            radius,
            paint,
        )
        return bitmap
    }

    fun drawSurface(canvas: Canvas, width: Int, height: Int, context: Context, style: WidgetStyle) {
        val background = background(context, style)
        if (Color.alpha(background) == 0) return
        val radius = min(width, height) * 0.22f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = background }
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()),
            radius,
            radius,
            paint,
        )
    }
}
