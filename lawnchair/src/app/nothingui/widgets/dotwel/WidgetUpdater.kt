package app.nothingui.widgets.dotwel

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Leading/trailing throttle used by the media update bridge. It never runs more
 * than once per [intervalMillis] while still allowing one trailing run so the
 * final media state is applied after a burst.
 */
internal class MediaUpdateThrottle(
    private val intervalMillis: Long,
    private val clock: () -> Long = { SystemClock.uptimeMillis() },
) {
    private var lastRunAt: Long? = null

    @Synchronized
    fun nextDelayMillis(): Long {
        val last = lastRunAt ?: return 0L
        val elapsed = clock() - last
        return if (elapsed >= intervalMillis) 0L else intervalMillis - elapsed
    }

    @Synchronized
    fun markRun() {
        lastRunAt = clock()
    }
}

object WidgetUpdater {
    private const val MEDIA_UPDATE_INTERVAL_MILLIS = 500L

    private val mediaProviders = listOf(
        Material3ExpandedMediaProvider::class.java,
        Material3MediaOutputProvider::class.java,
        MiniMediaPlayerProvider::class.java,
        MinimalMediaPlayerProvider::class.java,
        MinimalMediaPlayer2Provider::class.java,
        MinimalMediaPlayer3Provider::class.java,
        NothingMasterWidgetProvider::class.java,
        NothingMediaPlayerProvider::class.java,
        NothingMediaPlayer2Provider::class.java,
        NothingMediaPlayer3Provider::class.java,
        UniversalMediaPlayerProvider::class.java,
        MaterialNotificationWidgetProvider::class.java,
    )

    private val headphonesProviders = listOf(
        BluetoothHeadphonesWideWidgetProvider::class.java,
        BluetoothHeadphonesSquareWidgetProvider::class.java,
        BluetoothBatteryLevelsWidgetProvider::class.java,
    )

    private val mediaHandler = Handler(Looper.getMainLooper())
    private val mediaThrottle = MediaUpdateThrottle(MEDIA_UPDATE_INTERVAL_MILLIS)
    private val mediaScheduleLock = Any()

    @Volatile
    private var mediaUpdatePending = false

    val providers: List<Class<out BaseWidgetProvider>> = listOf(
        ClockWidgetProvider::class.java,
        DateWidgetProvider::class.java,
        AnalogBoldWidgetProvider::class.java,
        AnalogScaleWidgetProvider::class.java,
        WorldWidgetProvider::class.java,
        QuotesWidgetProvider::class.java,
        BluetoothStatusWidgetProvider::class.java,
        WifiStatusWidgetProvider::class.java,
        CellularStatusWidgetProvider::class.java,
        BatteryStatusWidgetProvider::class.java,
        BluetoothHeadphonesWideWidgetProvider::class.java,
        BluetoothHeadphonesSquareWidgetProvider::class.java,
        BluetoothBatteryLevelsWidgetProvider::class.java,
        BatteryWidgetProvider::class.java,
        BatteryMiniWidgetProvider::class.java,
        KwgtBattery2WidgetProvider::class.java,
        KwgtDateTimeWidgetProvider::class.java,
        KwgtDateTime2WidgetProvider::class.java,
        KwgtDigital4WidgetProvider::class.java,
        KwgtDigital3WidgetProvider::class.java,
        KwgtGradientClockWidgetProvider::class.java,
        KwgtAnalog2WidgetProvider::class.java,
        KwgtFutureWidgetProvider::class.java,
        KwgtAnalog3WidgetProvider::class.java,
        KwgtAnalogSecondsWidgetProvider::class.java,
        KwgtAnalog5WidgetProvider::class.java,
        KwgtAnalog5TransparentWidgetProvider::class.java,
        KwgtOrbitClockWidgetProvider::class.java,
        KwgtMiniCalendarWidgetProvider::class.java,
        KwgtCleanInfoWidgetProvider::class.java,
        IosBatteryWidgetProvider::class.java,
        NtAwayWidgetProvider::class.java,
        NtPhotoCircleProvider::class.java,
        NtPhotoRectProvider::class.java,
        KwgtDigital2WidgetProvider::class.java,
        KwgtInterstellarEnduranceProvider::class.java,
        KwgtInterstellarEnduranceAnalogProvider::class.java,
        KwgtInterstellarEnduranceAnalog2Provider::class.java,
        Material3ExpandedMediaProvider::class.java,
        Material3MediaOutputProvider::class.java,
        MiniMediaPlayerProvider::class.java,
        MinimalMediaPlayerProvider::class.java,
        MinimalMediaPlayer2Provider::class.java,
        MinimalMediaPlayer3Provider::class.java,
        NothingMasterWidgetProvider::class.java,
        NothingMediaPlayerProvider::class.java,
        NothingMediaPlayer2Provider::class.java,
        NothingMediaPlayer3Provider::class.java,
        UniversalMediaPlayerProvider::class.java,
        MaterialNotificationWidgetProvider::class.java,
    ) + WeatherWidgetUpdater.providers

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        providers.forEach { provider ->
            updateProvider(context, manager, provider)
        }
        MinuteTickScheduler.schedule(context)
        BatteryRefreshScheduler.schedule(context)
    }

    fun updateMediaProviders(context: Context) {
        val app = context.applicationContext
        if (!hasPlacedMediaWidgets(app)) return
        val delay = synchronized(mediaScheduleLock) {
            if (mediaUpdatePending) return
            mediaUpdatePending = true
            mediaThrottle.nextDelayMillis()
        }
        mediaHandler.postDelayed({
            synchronized(mediaScheduleLock) {
                mediaUpdatePending = false
                mediaThrottle.markRun()
            }
            if (!hasPlacedMediaWidgets(app)) return@postDelayed
            val manager = AppWidgetManager.getInstance(app)
            mediaProviders.forEach { updateProvider(app, manager, it) }
        }, delay)
    }

    internal fun hasPlacedMediaWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return mediaProviders.any { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider)).isNotEmpty()
        }
    }

    fun updateBatteryProviders(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        BatteryRefreshScheduler.providers.forEach { provider ->
            updateProvider(context, manager, provider)
        }
    }

    fun updateConnectivityProviders(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        updateProvider(context, manager, WifiStatusWidgetProvider::class.java)
        updateProvider(context, manager, CellularStatusWidgetProvider::class.java)
    }

    fun updateHeadphonesProviders(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        headphonesProviders.forEach { provider ->
            updateProvider(context, manager, provider)
        }
    }

    private fun updateProvider(
        context: Context,
        manager: AppWidgetManager,
        provider: Class<out BaseWidgetProvider>,
    ) {
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isEmpty()) return
        val intent = Intent(context, provider).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }
}

class MinuteTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != MinuteTickScheduler.ACTION_TICK) return
        WidgetUpdater.updateAll(context)
    }
}
