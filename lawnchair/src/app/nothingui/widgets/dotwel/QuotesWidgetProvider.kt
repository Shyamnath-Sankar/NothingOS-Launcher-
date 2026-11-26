package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Calendar
import java.util.Locale

object QuoteData {
    private const val ASSET = "nt_quotes.csv"
    private var cache: List<String>? = null

    fun quotes(context: Context): List<String> {
        cache?.let { return it }
        val loaded = try {
            context.assets.open(ASSET).bufferedReader(Charsets.UTF_8).useLines { lines ->
                lines.mapNotNull { line ->
                    val comma = line.indexOf(',')
                    if (comma < 0 || comma + 1 >= line.length) {
                        null
                    } else {
                        var value = line.substring(comma + 1).trim()
                        if (value.endsWith(",")) value = value.dropLast(1)
                        if (value.length > 1 && value.startsWith("\"") && value.endsWith("\"")) {
                            value = value.substring(1, value.length - 1).replace("\"\"", "\"")
                        }
                        value.takeIf { it.isNotEmpty() }
                    }
                }.toList()
            }
        } catch (_: Exception) {
            listOf("Less, but better.")
        }
        val result = loaded.ifEmpty { listOf("Less, but better.") }
        cache = result
        return result
    }
}

object QuotePrefs {
    private const val PREFS = "dotwel_quotes"
    private const val KEY_OFFSET = "offset"

    fun offset(context: Context): Int = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getInt(KEY_OFFSET, 0)

    fun advance(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putInt(KEY_OFFSET, prefs.getInt(KEY_OFFSET, 0) + 1).apply()
    }

    fun quoteForToday(context: Context): String {
        val quotes = QuoteData.quotes(context)
        val calendar = Calendar.getInstance()
        val dayKey = calendar.get(Calendar.YEAR) * 366 + calendar.get(Calendar.DAY_OF_YEAR)
        val index = ((dayKey + offset(context)) % quotes.size + quotes.size) % quotes.size
        return quotes[index]
    }
}

class QuotesWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_quotes

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_NEXT) {
            QuotePrefs.advance(context)
            refreshWidgets(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val quote = QuotePrefs.quoteForToday(context)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            appWidgetId,
            Intent(context, QuotesWidgetProvider::class.java).apply {
                action = ACTION_NEXT
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val views = buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_quotes_bitmap,
            R.id.quotes_fallback,
            render = { widthPx, heightPx ->
                NtQuotesRenderer.render(context, widthPx, heightPx, style, quote, false)
            },
        ) decorate@{ remote, _ ->
            remote.setTextColor(R.id.quotes_fallback, UpstreamNtDraw.ink(context, style))
            remote.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
        return views
    }

    companion object {
        const val ACTION_NEXT = "app.nothingui.widgets.dotwel.action.QUOTE_NEXT"
    }
}
