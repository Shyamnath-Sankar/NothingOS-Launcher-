/*
 * Copyright (c) 2026 oceansde012
 *
 * Adapted from dotline-widgets, file app/src/main/java/io/github/oceansde012/dotline/DotText.kt,
 * commit b53a12aaf09f3572582dbd2c4278ea65f6a83306
 * (https://github.com/oceansde012/dotline-widgets).
 *
 * Licensed under the MIT License. The full license text and the statement of changes are kept in
 * licenses/third-party/dotline-widgets-MIT.txt and NOTICE.md.
 *
 * Changes for DotWel Launcher:
 * - package renamed to app.nothingui.widgets;
 * - the Nd palette dependency was removed, so callers pass lit/matrix/accent/off colors from our
 *   own NothingUi palette tokens;
 * - the cache key now includes the matrix color;
 * - bar() takes explicit accent and off colors instead of reading Nd;
 * - no app/providers/MediaTracker/Ticker/services/fonts/assets were copied.
 */

package app.nothingui.widgets

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * Dot-matrix text drawn by us, never by a font: a 7-row dot glyph set (digits, A-Z, common
 * punctuation) rendered with round dots on a grid. Lit dots use the given colour; the unlit matrix
 * can be faintly visible behind them. Dot diameter = 0.62 of the pitch.
 */
object DotText {
    const val ROWS = 7
    const val DOT = 0.62f
    private const val GAP = 1
    private const val SPACE_W = 3
    private const val MAX_BYTES = 340_000

    private val SRC = """
0 .###./#...#/#...#/#...#/#...#/#...#/.###.
1 ..#../.##../..#../..#../..#../..#../.###.
2 .###./#...#/....#/...#./..#../.#.../#####
3 .###./#...#/....#/..##./....#/#...#/.###.
4 ...#./..##./.#.#./#..#./#####/...#./...#.
5 #####/#..../####./....#/....#/#...#/.###.
6 ..##./.#.../#..../####./#...#/#...#/.###.
7 #####/....#/...#./..#../.#.../.#.../.#...
8 .###./#...#/#...#/.###./#...#/#...#/.###.
9 .###./#...#/#...#/.####/....#/...#./.##..
A .###./#...#/#...#/#####/#...#/#...#/#...#
B ####./#...#/#...#/####./#...#/#...#/####.
C .###./#...#/#..../#..../#..../#...#/.###.
D ###../#..#./#...#/#...#/#...#/#..#./###..
E #####/#..../#..../####./#..../#..../#####
F #####/#..../#..../####./#..../#..../#....
G .###./#...#/#..../#.###/#...#/#...#/.####
H #...#/#...#/#...#/#####/#...#/#...#/#...#
I .###./..#../..#../..#../..#../..#../.###.
J ..###/...#./...#./...#./...#./#..#./.##..
K #...#/#..#./#.#../##.../#.#../#..#./#...#
L #..../#..../#..../#..../#..../#..../#####
M #...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#
N #...#/##..#/#.#.#/#..##/#...#/#...#/#...#
O .###./#...#/#...#/#...#/#...#/#...#/.###.
P ####./#...#/#...#/####./#..../#..../#....
Q .###./#...#/#...#/#...#/#.#.#/#..#./.##.#
R ####./#...#/#...#/####./#.#../#..#./#...#
S .####/#..../#..../.###./....#/....#/####.
T #####/..#../..#../..#../..#../..#../..#..
U #...#/#...#/#...#/#...#/#...#/#...#/.###.
V #...#/#...#/#...#/#...#/#...#/.#.#./..#..
W #...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#
X #...#/#...#/.#.#./..#../.#.#./#...#/#...#
Y #...#/#...#/.#.#./..#../..#../..#../..#..
Z #####/....#/...#./..#../.#.../#..../#####
: ./././#/././#/.
. ./././././././#
, ./././././.#/#.
- .../.../.../###/.../.../...
+ ...../..#../..#../#####/..#../..#../.....
% ##..#/##.#./...#./..#../.#.../.#.##/#..##
° ###/#.#/###/.../.../.../...
/ ....#/....#/...#./..#../.#.../#..../#....
! #/#/#/#/#/./#
? .###./#...#/....#/...#./..#../...../..#..
( ..#/.#./#../#../#../.#./..#
) #../.#./..#/..#/..#/.#./#..
' #/#/././././.
_ ...../...../...../...../...../...../#####
= ...../...../#####/...../#####/...../.....
· ./././#/././.
~ ...#.../..###../.#####./.#####./.#####./#######/..###..
"""

    private val glyphs: Map<Char, Array<String>> = HashMap<Char, Array<String>>().also { map ->
        for (line in SRC.lines()) {
            if (line.length < 4) continue
            map[line[0]] = line.substring(2).split('/').toTypedArray()
        }
    }

    const val BELL = '~'

    private fun glyph(char: Char): Array<String>? = glyphs[char.uppercaseChar()] ?: glyphs[char]

    private fun width(char: Char): Int = if (char == ' ') SPACE_W else glyph(char)?.get(0)?.length ?: 0

    fun cols(text: String): Int {
        var count = 0
        var first = true
        for (char in text) {
            val glyphWidth = width(char)
            if (glyphWidth == 0) continue
            if (!first) count += GAP
            count += glyphWidth
            first = false
        }
        return count.coerceAtLeast(1)
    }

    fun pitchFor(text: String, boxW: Float, boxH: Float): Float = minOf(boxW / cols(text), boxH / ROWS).coerceAtLeast(0.5f)

    class Art(val bmp: Bitmap, val wDp: Float, val hDp: Float)

    private val cache = object : LinkedHashMap<String, Art>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Art>?) = size > 40
    }

    fun scaleFor(wDp: Float, hDp: Float, density: Float): Float {
        val area = (wDp * hDp * 4f).coerceAtLeast(1f)
        return minOf(density, sqrt(MAX_BYTES / area))
    }

    @Synchronized
    fun art(
        text: String,
        pitchDp: Float,
        density: Float,
        lit: Int,
        matrixColor: Int,
        matrix: Boolean = true,
    ): Art {
        val key = "$text|${(pitchDp * 100).toInt()}|${(density * 100).toInt()}|$lit|$matrixColor|$matrix"
        cache[key]?.let { return it }
        val columns = cols(text)
        val wDp = columns * pitchDp
        val hDp = ROWS * pitchDp
        val scale = scaleFor(wDp, hDp, density)
        val pitch = pitchDp * scale
        val bitmap = Bitmap.createBitmap(
            ceil(columns * pitch).toInt().coerceAtLeast(1),
            ceil(ROWS * pitch).toInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = pitch * DOT / 2f
        if (matrix) {
            paint.color = matrixColor
            for (col in 0 until columns) {
                for (row in 0 until ROWS) {
                    canvas.drawCircle((col + 0.5f) * pitch, (row + 0.5f) * pitch, radius, paint)
                }
            }
        }
        paint.color = lit
        var x = 0
        var first = true
        for (char in text) {
            val glyphWidth = width(char)
            if (glyphWidth == 0) continue
            if (!first) x += GAP
            first = false
            val glyph = glyph(char)
            if (glyph != null) {
                for (row in 0 until minOf(ROWS, glyph.size)) {
                    for (col in 0 until glyphWidth) {
                        if (glyph[row][col] == '#') {
                            if (matrix) {
                                val centerX = (x + col + 0.5f) * pitch
                                val centerY = (row + 0.5f) * pitch
                                paint.xfermode = CLEAR
                                canvas.drawCircle(centerX, centerY, radius + 0.5f, paint)
                                paint.xfermode = null
                            }
                            canvas.drawCircle(
                                (x + col + 0.5f) * pitch,
                                (row + 0.5f) * pitch,
                                radius,
                                paint,
                            )
                        }
                    }
                }
            }
            x += glyphWidth
        }
        return Art(bitmap, wDp, hDp).also { cache[key] = it }
    }

    private val CLEAR = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR)

    @Synchronized
    fun bar(
        n: Int,
        lit: Int,
        litColor: Int,
        accentIndex: Int,
        accentColor: Int,
        offColor: Int,
        pitchDp: Float,
        density: Float,
    ): Art {
        val key = "bar|$n|$lit|$litColor|$accentIndex|$accentColor|$offColor|" +
            "${(pitchDp * 100).toInt()}|${(density * 100).toInt()}"
        cache[key]?.let { return it }
        val wDp = n * pitchDp
        val scale = scaleFor(wDp, pitchDp, density)
        val pitch = pitchDp * scale
        val bitmap = Bitmap.createBitmap(
            ceil(n * pitch).toInt().coerceAtLeast(1),
            ceil(pitch).toInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = pitch * DOT / 2f
        for (index in 0 until n) {
            paint.color = when {
                index == accentIndex -> accentColor
                index < lit -> litColor
                else -> offColor
            }
            canvas.drawCircle((index + 0.5f) * pitch, pitch / 2f, radius, paint)
        }
        return Art(bitmap, wDp, pitchDp).also { cache[key] = it }
    }
}
