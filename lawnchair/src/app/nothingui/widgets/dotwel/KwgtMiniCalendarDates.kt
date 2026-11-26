package app.nothingui.widgets.dotwel

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

data class MiniCalendarDay(
    val offset: Int,
    val weekday: String,
    val day: String,
    val date: Calendar,
    val isToday: Boolean,
)

/**
 * Pure date math for the KWGT Nothing_Mini_Calender strip.
 *
 * The source preset uses r2d/r1d/today/a1d/a2d date offsets. Android/KWGT
 * resolves those relative days through calendar arithmetic, so this helper uses
 * [Calendar.add] on a cloned device-local calendar. It deliberately never adds
 * 86,400,000 milliseconds: that would land on the wrong wall-clock date across
 * month ends, leap days, DST transitions and timezone changes.
 */
object KwgtMiniCalendarDates {
    val OFFSETS = intArrayOf(-2, -1, 0, 1, 2)

    fun anchored(base: Calendar, offset: Int): Calendar {
        val date = base.clone() as Calendar
        date.add(Calendar.DAY_OF_YEAR, offset)
        return date
    }

    fun days(base: Calendar, locale: Locale = Locale.getDefault()): List<MiniCalendarDay> {
        val weekdayFormat = SimpleDateFormat("EEE", locale)
        val dayFormat = SimpleDateFormat("dd", locale)
        return OFFSETS.map { offset ->
            val date = anchored(base, offset)
            MiniCalendarDay(
                offset = offset,
                weekday = weekdayFormat.format(date.time).uppercase(locale),
                day = dayFormat.format(date.time),
                date = date,
                isToday = offset == 0,
            )
        }
    }

    fun rangeDescription(base: Calendar, locale: Locale = Locale.getDefault()): String {
        val format = SimpleDateFormat("MMM d", locale)
        val first = format.format(anchored(base, OFFSETS.first()).time)
        val last = format.format(anchored(base, OFFSETS.last()).time)
        return "$first – $last"
    }
}
