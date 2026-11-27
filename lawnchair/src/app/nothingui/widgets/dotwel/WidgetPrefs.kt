package app.nothingui.widgets.dotwel

import android.content.Context
import android.content.SharedPreferences
import com.android.launcher3.R

enum class WidgetStyle(val id: Int, val backgroundRes: Int) {
    BLACK(0, R.drawable.bg_widget_black),
    TRANSLUCENT(1, R.drawable.bg_widget_translucent),
    TRANSPARENT(2, R.drawable.bg_widget_transparent),
    ;

    companion object {
        fun fromId(id: Int): WidgetStyle = values().firstOrNull { it.id == id } ?: BLACK
    }
}

object WidgetPrefs {
    private const val PREFS = "dotwel_settings"
    private const val KEY_STYLE = "widget_style"

    private fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun style(context: Context): WidgetStyle = WidgetStyle.fromId(prefs(context).getInt(KEY_STYLE, WidgetStyle.BLACK.id))

    fun setStyle(context: Context, style: WidgetStyle) {
        prefs(context).edit().putInt(KEY_STYLE, style.id).apply()
    }
}
