/*
 * Copyright 2026 the DotWel Launcher project contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app.nothingui.widgets.dotwel

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path

/** Original geometric weather symbols, not copied upstream icon files. */
object DotwelWeatherIcons : NtWxRenderer.IconDrawer {
    override fun draw(
        canvas: Canvas,
        code: Int,
        isDay: Boolean,
        cx: Float,
        cy: Float,
        side: Float,
        color: Int,
    ) {
        val saved = canvas.save()
        canvas.translate(cx - side / 2, cy - side / 2)
        canvas.scale(side / 100, side / 100)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = 4f
            strokeCap = Paint.Cap.ROUND
        }
        if (code <= 1) {
            if (isDay) {
                canvas.drawCircle(50f, 50f, 19f, paint)
                for (index in 0..7) {
                    val restore = canvas.save()
                    canvas.rotate(index * 45f, 50f, 50f)
                    canvas.drawLine(50f, 16f, 50f, 24f, paint)
                    canvas.restoreToCount(restore)
                }
            } else {
                val moon = Path().apply {
                    moveTo(63f, 18f)
                    cubicTo(9f, 17f, 12f, 86f, 68f, 80f)
                    cubicTo(33f, 71f, 29f, 39f, 63f, 18f)
                }
                canvas.drawPath(moon, paint)
            }
        } else {
            val cloud = Path().apply {
                moveTo(24f, 67f)
                cubicTo(2f, 65f, 8f, 37f, 29f, 40f)
                cubicTo(35f, 14f, 72f, 18f, 74f, 43f)
                cubicTo(99f, 39f, 103f, 68f, 78f, 68f)
                close()
            }
            canvas.drawPath(cloud, paint)
            when (code) {
                in 51..67, in 80..82 -> for (index in 0..2) {
                    canvas.drawLine(31f + index * 19, 77f, 26f + index * 19, 88f, paint)
                }

                in 71..77, in 85..86 -> for (index in 0..2) {
                    canvas.drawLine(28f + index * 20, 78f, 38f + index * 20, 88f, paint)
                    canvas.drawLine(38f + index * 20, 78f, 28f + index * 20, 88f, paint)
                }

                in 95..99 -> canvas.drawPath(
                    Path().apply {
                        moveTo(52f, 70f)
                        lineTo(43f, 83f)
                        lineTo(55f, 83f)
                        lineTo(47f, 96f)
                    },
                    paint,
                )

                45, 48 -> {
                    canvas.drawLine(18f, 78f, 84f, 78f, paint)
                    canvas.drawLine(26f, 88f, 74f, 88f, paint)
                }
            }
        }
        canvas.restoreToCount(saved)
    }
}
