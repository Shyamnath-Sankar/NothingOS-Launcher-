package app.nothingui.widgets.dotwel

import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.min

/**
 * Dotwel's original 5x7 circular-dot digit geometry. This is a deliberate font
 * substitution for the upstream Ndot font files, which are not redistributed.
 * The fitted row proportions and centre positions come from the translated
 * NtDigital/NtWorld composition; the glyph matrix itself is original to Dotwel.
 */
object DotGlyphFont {
    const val COLUMNS = 5
    const val ROWS = 7
    private const val DIGIT_GAP = 1
    private const val GLYPH_RADIUS_RATIO = 0.40f

    private val glyphs: Map<Char, Array<String>> = mapOf(
        '0' to arrayOf("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
        '1' to arrayOf("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
        '2' to arrayOf("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
        '3' to arrayOf("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
        '4' to arrayOf("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
        '5' to arrayOf("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
        '6' to arrayOf("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
        '7' to arrayOf("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
        '8' to arrayOf("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
        '9' to arrayOf("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
        ':' to arrayOf("00000", "00100", "00100", "00000", "00100", "00100", "00000"),
        '%' to arrayOf("11001", "11011", "00110", "00100", "01100", "11011", "10011"),
        ' ' to arrayOf("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
        'A' to arrayOf("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
        'B' to arrayOf("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
        'C' to arrayOf("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
        'D' to arrayOf("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
        'E' to arrayOf("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
        'F' to arrayOf("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
        'G' to arrayOf("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
        'H' to arrayOf("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
        'I' to arrayOf("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
        'J' to arrayOf("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
        'K' to arrayOf("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
        'L' to arrayOf("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
        'M' to arrayOf("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
        'N' to arrayOf("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
        'O' to arrayOf("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
        'P' to arrayOf("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
        'Q' to arrayOf("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
        'R' to arrayOf("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
        'S' to arrayOf("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
        'T' to arrayOf("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
        'U' to arrayOf("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
        'V' to arrayOf("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
        'W' to arrayOf("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
        'X' to arrayOf("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
        'Y' to arrayOf("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
        'Z' to arrayOf("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    )

    /**
     * Actual drawn bounds of [text] in pitch units. Useful when a caller has to
     * fit the visible ink, not the full 5x7 advance grid, into a fixed box.
     */
    data class Metrics(
        val columns: Int,
        val rows: Int,
        val minColumn: Int,
        val maxColumn: Int,
        val minRow: Int,
        val maxRow: Int,
    ) {
        val centerColumn: Float get() = (minColumn + maxColumn) / 2f
        val centerRow: Float get() = (minRow + maxRow) / 2f
        val inkWidthUnits: Float get() = (maxColumn - minColumn) + 2f * GLYPH_RADIUS_RATIO
        val inkHeightUnits: Float get() = (maxRow - minRow) + 2f * GLYPH_RADIUS_RATIO
    }

    fun metrics(text: String): Metrics {
        val columns = columnsFor(text)
        if (columns <= 0) {
            return Metrics(0, ROWS, 0, 0, 0, ROWS - 1)
        }
        var minColumn = Int.MAX_VALUE
        var maxColumn = Int.MIN_VALUE
        var minRow = Int.MAX_VALUE
        var maxRow = Int.MIN_VALUE
        var cursor = 0
        text.forEach { character ->
            val glyph = glyphs[character]
            if (glyph != null) {
                glyph.forEachIndexed { row, line ->
                    line.forEachIndexed { column, dot ->
                        if (dot == '1') {
                            val absoluteColumn = cursor + column
                            if (absoluteColumn < minColumn) minColumn = absoluteColumn
                            if (absoluteColumn > maxColumn) maxColumn = absoluteColumn
                            if (row < minRow) minRow = row
                            if (row > maxRow) maxRow = row
                        }
                    }
                }
            }
            cursor += COLUMNS + DIGIT_GAP
        }
        if (minColumn == Int.MAX_VALUE) {
            return Metrics(columns, ROWS, 0, columns - 1, 0, ROWS - 1)
        }
        return Metrics(columns, ROWS, minColumn, maxColumn, minRow, maxRow)
    }

    fun columnsFor(text: String): Int = if (text.isEmpty()) {
        0
    } else {
        COLUMNS * text.length + DIGIT_GAP * (text.length - 1)
    }

    /** Equivalent of NtDraw.fit for the "00" reference at a chosen row height. */
    fun fitPitch(text: String, maxWidth: Float, maxHeight: Float): Float {
        val columns = columnsFor(text).coerceAtLeast(1)
        val byWidth = maxWidth / columns.toFloat()
        val byHeight = maxHeight / ROWS.toFloat()
        return min(byWidth, byHeight).coerceAtLeast(0f)
    }

    fun drawLeft(
        canvas: Canvas,
        text: String,
        left: Float,
        centerY: Float,
        pitch: Float,
        paint: Paint,
    ) {
        if (pitch <= 0f) return
        val columns = columnsFor(text)
        if (columns <= 0) return
        draw(canvas, text, left + pitch * 0.5f, centerY, pitch, paint)
    }

    fun drawCentered(
        canvas: Canvas,
        text: String,
        centerX: Float,
        centerY: Float,
        pitch: Float,
        paint: Paint,
    ) {
        if (pitch <= 0f) return
        val columns = columnsFor(text)
        if (columns <= 0) return
        draw(canvas, text, centerX - (columns - 1) * pitch / 2f, centerY, pitch, paint)
    }

    /**
     * Like [drawCentered] but centres the actual lit-dot bounds instead of the
     * full advance box. Digital3 needs this because leading/trailing columns in
     * a 5x7 glyph are often empty.
     */
    fun drawCenteredInk(
        canvas: Canvas,
        text: String,
        centerX: Float,
        centerY: Float,
        pitch: Float,
        paint: Paint,
    ) {
        if (pitch <= 0f) return
        val bounds = metrics(text)
        if (bounds.columns <= 0) return
        val startX = centerX - bounds.centerColumn * pitch
        val startY = centerY - bounds.centerRow * pitch
        drawAt(canvas, text, startX, startY, pitch, paint)
    }

    private fun draw(
        canvas: Canvas,
        text: String,
        startX: Float,
        centerY: Float,
        pitch: Float,
        paint: Paint,
    ) {
        val startY = centerY - (ROWS - 1) * pitch / 2f
        drawAt(canvas, text, startX, startY, pitch, paint)
    }

    private fun drawAt(
        canvas: Canvas,
        text: String,
        startX: Float,
        startY: Float,
        pitch: Float,
        paint: Paint,
    ) {
        val radius = pitch * GLYPH_RADIUS_RATIO
        var cursor = 0
        text.forEach { character ->
            val glyph = glyphs[character] ?: return@forEach
            glyph.forEachIndexed { row, line ->
                line.forEachIndexed { column, dot ->
                    if (dot == '1') {
                        canvas.drawCircle(
                            startX + (cursor + column) * pitch,
                            startY + row * pitch,
                            radius,
                            paint,
                        )
                    }
                }
            }
            cursor += COLUMNS + DIGIT_GAP
        }
    }
}
