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

import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NothingUiHomeClockTest {

    private fun calendarAt(
        hour: Int,
        minute: Int,
        day: Int = 21,
        month: Int = Calendar.NOVEMBER,
        year: Int = 2026,
    ): Calendar {
        return GregorianCalendar(TimeZone.getTimeZone("UTC"), Locale.US).apply {
            clear()
            set(year, month, day, hour, minute, 0)
        }
    }

    @Test
    fun formatClockUsesTwentyFourHourPattern() {
        assertEquals(
            "09:41",
            NothingUiHomeClock.formatClock(calendarAt(9, 41), is24Hour = true, Locale.US),
        )
    }

    @Test
    fun formatClockUsesTwelveHourPattern() {
        assertEquals(
            "9:41",
            NothingUiHomeClock.formatClock(calendarAt(9, 41), is24Hour = false, Locale.US),
        )
    }

    @Test
    fun formatDateUsesUppercaseDayAndMonth() {
        assertEquals(
            "SAT 21 NOV",
            NothingUiHomeClock.formatDate(calendarAt(9, 41), Locale.US),
        )
    }

    @Test
    fun formatDateUsesTheProvidedLocale() {
        val us = NothingUiHomeClock.formatDate(calendarAt(9, 41), Locale.US)
        val france = NothingUiHomeClock.formatDate(calendarAt(9, 41), Locale.FRANCE)
        assertTrue(france.contains("21"))
        assertNotEquals(us, france)
    }

    @Test
    fun accessibilityLabelCombinesClockAndDate() {
        assertEquals(
            "09:41, SAT 21 NOV",
            NothingUiHomeClock.accessibilityLabel("09:41", "SAT 21 NOV"),
        )
    }
}
