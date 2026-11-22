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

package app.nothingui.widgets

import android.content.Context
import android.graphics.Point
import android.os.Build
import android.util.Size
import android.view.WindowManager
import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * API 37 widget bitmap budget.
 *
 * Android 17 rejects a widget RemoteViews payload whose summed image memory exceeds
 * `6 × width × height` bytes of the active display. The display bounds come from
 * [WindowManager.currentWindowMetrics] on API 30+ (never from `resources.displayMetrics`), with a
 * real-size display fallback on API 26–29. Art is decoded at the widget's own size and clamped to a
 * small maximum, so a 2×2 widget never ships a fixed giant bitmap.
 */
object NothingUiWidgetBudget {

    private const val MAX_DIMENSION_PX = 512
    private const val BYTES_PER_PIXEL = 4L
    private const val CAP_FACTOR = 6L

    fun capBytes(context: Context): Long {
        val (width, height) = displaySize(context)
        return CAP_FACTOR * width.coerceAtLeast(1).toLong() * height.coerceAtLeast(1).toLong()
    }

    fun boundedSize(context: Context, widthDp: Int, heightDp: Int): Size {
        val density = context.resources.displayMetrics.density
        var width = ceil(widthDp * density).toInt().coerceIn(1, MAX_DIMENSION_PX)
        var height = ceil(heightDp * density).toInt().coerceIn(1, MAX_DIMENSION_PX)
        val cap = capBytes(context)
        val bytes = width.toLong() * height * BYTES_PER_PIXEL
        if (bytes > cap) {
            val scale = sqrt(cap.toDouble() / bytes.toDouble()).toFloat()
            width = (width * scale).toInt().coerceAtLeast(1)
            height = (height * scale).toInt().coerceAtLeast(1)
        }
        return Size(width, height)
    }

    @Suppress("DEPRECATION")
    private fun displaySize(context: Context): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowManager = context.getSystemService(WindowManager::class.java)
            if (windowManager != null) {
                runCatching {
                    val bounds = windowManager.currentWindowMetrics.bounds
                    return bounds.width() to bounds.height()
                }
            }
        }
        val point = Point()
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager.defaultDisplay.getRealSize(point)
        return point.x to point.y
    }
}
