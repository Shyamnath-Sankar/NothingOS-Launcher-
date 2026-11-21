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

package app.nothingui.home

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Pure clock/date formatting for the NothingUI home header.
 *
 * Kept free of Android framework types so the formatting can be unit-tested on the JVM.
 */
object NothingUiHomeClock {

    fun formatClock(now: Calendar, is24Hour: Boolean, locale: Locale): String {
        val pattern = if (is24Hour) "HH:mm" else "h:mm"
        return SimpleDateFormat(pattern, locale).format(now.time)
    }

    fun formatDate(now: Calendar, locale: Locale): String {
        return SimpleDateFormat("EEE d MMM", locale).format(now.time).uppercase(locale)
    }

    fun accessibilityLabel(clock: String, date: String): String = "$clock, $date"
}
