package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.provider.AlarmClock
import android.text.format.DateFormat
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.android.launcher3.R
import java.util.Calendar

abstract class BaseWidgetProvider : AppWidgetProvider() {
    protected abstract val layoutRes: Int
    protected open val tapAction: String? = null
    protected open val tapCategory: String? = null
    protected open val refreshesBatteryAlarm: Boolean = false

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
        }
        if (refreshesBatteryAlarm) BatteryRefreshScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
        if (refreshesBatteryAlarm) BatteryRefreshScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        if (refreshesBatteryAlarm) BatteryRefreshScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        if (refreshesBatteryAlarm) BatteryRefreshScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        if (refreshesBatteryAlarm) BatteryRefreshScheduler.schedule(context)
    }

    protected fun refreshWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            android.content.ComponentName(context, this::class.java),
        )
        ids.forEach { appWidgetId ->
            manager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
        }
    }

    protected open fun buildViews(context: Context, appWidgetId: Int): RemoteViews = baseViews(context, appWidgetId)

    protected fun baseViews(context: Context, appWidgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, layoutRes)
        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            WidgetPrefs.style(context).backgroundRes,
        )
        tapIntent(context)?.let { intent ->
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
        return views
    }

    protected fun buildBitmapViews(
        context: Context,
        appWidgetId: Int,
        bitmapViewId: Int,
        fallbackViewId: Int,
        render: (widthPx: Int, heightPx: Int) -> Bitmap?,
        decorate: (views: RemoteViews, usedBitmap: Boolean) -> Unit = { _, _ -> },
    ): RemoteViews {
        val manager = AppWidgetManager.getInstance(context)
        val options = manager.getAppWidgetOptions(appWidgetId)
        val exactSizes = WidgetSizing.exactSizesFromOptions(options)
        val targets = WidgetSizing.targets(context, options, exactSizes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && exactSizes.isNotEmpty()) {
            val mapping = LinkedHashMap<SizeF, RemoteViews>()
            targets.forEach { target ->
                val bitmap = safeRender(render, target.widthPx, target.heightPx)
                val views = baseViews(context, appWidgetId)
                applyBitmap(
                    views,
                    bitmapViewId,
                    fallbackViewId,
                    bitmap,
                    decorate,
                )
                mapping[target.hostSize] = views
            }
            if (mapping.isNotEmpty()) {
                @Suppress("NewApi")
                return RemoteViews(mapping)
            }
        }
        val target = targets.firstOrNull()
        val bitmap = target?.let { safeRender(render, it.widthPx, it.heightPx) }
        val views = baseViews(context, appWidgetId)
        applyBitmap(views, bitmapViewId, fallbackViewId, bitmap, decorate)
        return views
    }

    protected fun buildTargetBitmapViews(
        context: Context,
        appWidgetId: Int,
        bitmapViewId: Int,
        fallbackViewId: Int,
        render: (widthPx: Int, heightPx: Int) -> Bitmap?,
        decorateTarget: (
            views: RemoteViews,
            usedBitmap: Boolean,
            target: WidgetSizing.Target,
        ) -> Unit,
    ): RemoteViews {
        val manager = AppWidgetManager.getInstance(context)
        val options = manager.getAppWidgetOptions(appWidgetId)
        val exactSizes = WidgetSizing.exactSizesFromOptions(options)
        val targets = WidgetSizing.targets(context, options, exactSizes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && exactSizes.isNotEmpty()) {
            val mapping = LinkedHashMap<SizeF, RemoteViews>()
            targets.forEach { target ->
                val bitmap = safeRender(render, target.widthPx, target.heightPx)
                val views = baseViews(context, appWidgetId)
                applyBitmap(
                    views,
                    bitmapViewId,
                    fallbackViewId,
                    bitmap,
                    { v, used -> decorateTarget(v, used, target) },
                )
                mapping[target.hostSize] = views
            }
            if (mapping.isNotEmpty()) {
                @Suppress("NewApi")
                return RemoteViews(mapping)
            }
        }
        val target = targets.firstOrNull()
        val bitmap = target?.let { safeRender(render, it.widthPx, it.heightPx) }
        val views = baseViews(context, appWidgetId)
        if (target != null) {
            applyBitmap(
                views,
                bitmapViewId,
                fallbackViewId,
                bitmap,
                { v, used -> decorateTarget(v, used, target) },
            )
        } else {
            applyBitmap(views, bitmapViewId, fallbackViewId, bitmap)
        }
        return views
    }

    protected fun applyBitmap(
        views: RemoteViews,
        bitmapViewId: Int,
        fallbackViewId: Int,
        bitmap: Bitmap?,
        decorate: (views: RemoteViews, usedBitmap: Boolean) -> Unit = { _, _ -> },
    ) {
        if (bitmap != null) {
            views.setViewVisibility(bitmapViewId, View.VISIBLE)
            views.setImageViewBitmap(bitmapViewId, bitmap)
            views.setViewVisibility(fallbackViewId, View.GONE)
        } else {
            views.setViewVisibility(bitmapViewId, View.GONE)
            views.setViewVisibility(fallbackViewId, View.VISIBLE)
        }
        decorate(views, bitmap != null)
    }

    protected fun safeRender(
        render: (Int, Int) -> Bitmap?,
        widthPx: Int,
        heightPx: Int,
    ): Bitmap? = try {
        render(widthPx, heightPx)
    } catch (_: OutOfMemoryError) {
        null
    } catch (_: RuntimeException) {
        null
    }

    protected open fun tapIntent(context: Context): Intent? {
        tapCategory?.let { category ->
            return Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, category)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        tapAction?.let { action ->
            return Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return null
    }
}

class ClockWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_clock
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            MinuteTickScheduler.ACTION_TICK,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            -> {
                refreshWidgets(context)
                MinuteTickScheduler.schedule(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        if (!MinuteTickScheduler.hasExactAccess(context)) {
            return plainClockViews(context, appWidgetId, style)
        }
        val now = Calendar.getInstance()
        val spokenTime = DateFormat.getTimeFormat(context).format(now.time)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_clock_bitmap,
            R.id.clock_time,
            render = { widthPx, heightPx ->
                NtDigitalRenderer.render(context, widthPx, heightPx, style, now, false)
            },
        ) decorate@{ views, usedBitmap ->
            views.setTextColor(R.id.clock_time, UpstreamNtDraw.ink(context, style))
            views.setViewVisibility(
                R.id.clock_fallback_note,
                if (usedBitmap) View.GONE else View.VISIBLE,
            )
            views.setTextColor(
                R.id.clock_fallback_note,
                UpstreamNtDraw.muted(context, style),
            )
            if (usedBitmap) {
                views.setContentDescription(
                    R.id.widget_clock_bitmap,
                    context.getString(R.string.clock_content_description, spokenTime),
                )
            }
        }
    }

    private fun plainClockViews(
        context: Context,
        appWidgetId: Int,
        style: WidgetStyle,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setViewVisibility(R.id.widget_clock_bitmap, View.GONE)
        views.setViewVisibility(R.id.clock_time, View.VISIBLE)
        views.setViewVisibility(R.id.clock_fallback_note, View.GONE)
        views.setTextColor(R.id.clock_time, UpstreamNtDraw.ink(context, style))
        return views
    }
}

class DateWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_date
    override val tapCategory: String = Intent.CATEGORY_APP_CALENDAR

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> {
                refreshWidgets(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val now = Calendar.getInstance()
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_date_bitmap,
            R.id.date_fallback,
            render = { widthPx, heightPx ->
                NtDateRenderer.render(context, widthPx, heightPx, style, now, false)
            },
        ) decorate@{ views, _ ->
            views.setTextColor(R.id.date_fallback, UpstreamNtDraw.ink(context, style))
        }
    }
}

class AnalogBoldWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_analog
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == MinuteTickScheduler.ACTION_TICK) {
            refreshWidgets(context)
            MinuteTickScheduler.schedule(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val now = Calendar.getInstance()
        val drawDots = MinuteTickScheduler.hasExactAccess(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_analog_bitmap,
            R.id.analog_fallback,
            render = { widthPx, heightPx ->
                if (drawDots) {
                    NtAnalogRenderer.render(
                        context,
                        widthPx,
                        heightPx,
                        style,
                        now,
                        bold = true,
                        includeBackground = false,
                    )
                } else {
                    null
                }
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap) R.drawable.bg_widget_none else style.backgroundRes,
            )
        }
    }
}

class AnalogScaleWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_analog
    override val tapAction: String = AlarmClock.ACTION_SHOW_ALARMS

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == MinuteTickScheduler.ACTION_TICK) {
            refreshWidgets(context)
            MinuteTickScheduler.schedule(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val style = WidgetPrefs.style(context)
        val now = Calendar.getInstance()
        val drawDots = MinuteTickScheduler.hasExactAccess(context)
        return buildBitmapViews(
            context,
            appWidgetId,
            R.id.widget_analog_bitmap,
            R.id.analog_fallback,
            render = { widthPx, heightPx ->
                if (drawDots) {
                    NtAnalogRenderer.render(
                        context,
                        widthPx,
                        heightPx,
                        style,
                        now,
                        bold = false,
                        includeBackground = false,
                    )
                } else {
                    null
                }
            },
        ) decorate@{ views, usedBitmap ->
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (usedBitmap) R.drawable.bg_widget_none else style.backgroundRes,
            )
        }
    }
}
