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

import java.util.Locale
import kotlin.math.roundToInt

/**
 * Pure, bounded formatting for the real app data-volume storage reading.
 *
 * The device widget reads [android.os.StatFs] on the launcher's own data directory, which is the
 * app data volume. This object never invents a value: a missing, negative, zero or inconsistent
 * reading is reported as [UNKNOWN_PERCENT] / [isKnown] false, and the widget renders a neutral
 * unknown label instead of a guessed percentage. All percentages are clamped to 0..100 so a
 * hostile or rounding-prone filesystem cannot overflow the bounded progress bar.
 */
object NothingUiDeviceStorage {

    const val UNKNOWN_PERCENT = -1
    const val UNKNOWN_MARKER = "--"

    private val UNITS = arrayOf("B", "KB", "MB", "GB", "TB", "PB")
    private const val STEP = 1024.0

    fun isKnown(total: Long, available: Long): Boolean =
        total > 0L && available >= 0L && available <= total

    fun formatSize(bytes: Long, locale: Locale = Locale.getDefault()): String {
        if (bytes < 0L) return UNKNOWN_MARKER
        var value = bytes.toDouble()
        var unit = 0
        while (value >= STEP && unit < UNITS.lastIndex) {
            value /= STEP
            unit++
        }
        val pattern = if (unit == 0) "%.0f %s" else "%.1f %s"
        return String.format(locale, pattern, value, UNITS[unit])
    }

    fun usedPercent(total: Long, available: Long): Int {
        if (!isKnown(total, available)) return UNKNOWN_PERCENT
        val used = total - available
        val percent = (used.toDouble() / total.toDouble() * 100.0).roundToInt()
        return percent.coerceIn(0, 100)
    }

    fun progress(total: Long, available: Long): Int {
        val percent = usedPercent(total, available)
        return if (percent == UNKNOWN_PERCENT) 0 else percent
    }
}
