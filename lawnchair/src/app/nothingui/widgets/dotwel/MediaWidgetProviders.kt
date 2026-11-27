package app.nothingui.widgets.dotwel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import app.nothingui.widgets.dotwel.media.MediaActionReceiver
import app.nothingui.widgets.dotwel.media.MediaRenderers
import app.nothingui.widgets.dotwel.media.MediaSessionRepository
import app.nothingui.widgets.dotwel.media.MediaSnapshot
import app.nothingui.widgets.dotwel.media.MediaTransportAction
import app.nothingui.widgets.dotwel.media.MediaWidgetKind
import com.android.launcher3.R

/**
 * Shared real-data media provider. It never invents a song, artwork, progress or
 * playback state. This build does not declare a notification listener, so media
 * widgets render an honest unavailable state and taps open the launcher.
 */
abstract class BaseMediaWidgetProvider : BaseWidgetProvider() {
    override val layoutRes: Int = R.layout.widget_media
    protected abstract val mediaKind: MediaWidgetKind
    protected open val minuteRefresh: Boolean = false

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        if (minuteRefresh) MinuteTickScheduler.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        if (minuteRefresh) MinuteTickScheduler.schedule(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        if (minuteRefresh) MinuteTickScheduler.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        if (minuteRefresh) MinuteTickScheduler.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        if (minuteRefresh) MinuteTickScheduler.schedule(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            MinuteTickScheduler.ACTION_TICK,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            -> {
                refreshWidgets(context)
                if (minuteRefresh) MinuteTickScheduler.schedule(context)
                return
            }
        }
        super.onReceive(context, intent)
    }

    override fun buildViews(context: Context, appWidgetId: Int): RemoteViews {
        val snapshot = MediaSessionRepository.snapshot(context)
        val hasContent = when (mediaKind) {
            MediaWidgetKind.NOTIFICATION ->
                snapshot.accessGranted &&
                    (snapshot.notification != null || snapshot.hasPlayback)

            else -> snapshot.accessGranted && snapshot.hasPlayback
        }
        if (!hasContent && mediaKind != MediaWidgetKind.NOTHING_MASTER) {
            return emptyViews(context, appWidgetId, snapshot)
        }
        return buildTargetBitmapViews(
            context,
            appWidgetId,
            R.id.widget_media_bitmap,
            R.id.media_message,
            render = { widthPx, heightPx ->
                MediaRenderers.render(
                    context,
                    mediaKind,
                    widthPx,
                    heightPx,
                    WidgetPrefs.style(context),
                    snapshot,
                )
            },
        ) { views, usedBitmap, target ->
            bindLive(views, context, appWidgetId, snapshot, usedBitmap)
            bindGeometry(views, context, target)
        }
    }

    private fun bindGeometry(views: RemoteViews, context: Context, target: WidgetSizing.Target) {
        if (android.os.Build.VERSION.SDK_INT < 31) {
            // Pre31 RemoteViews cannot position arbitrary bitmap-aligned hit targets.
            // Do not leave invisible controls in the wrong place; root still opens player.
            views.setViewVisibility(R.id.media_overlay, View.GONE)
            views.setViewVisibility(R.id.media_clear, View.GONE)
            return
        }
        val width = (target.hostSize.width - 16f).coerceAtLeast(1f)
        val height = (target.hostSize.height - 16f).coerceAtLeast(1f)
        val controls = app.nothingui.widgets.dotwel.media.MediaTouchGeometry.design(mediaKind)
        fun place(id: Int, box: app.nothingui.widgets.dotwel.media.MediaTouchGeometry.Box?) {
            if (box == null) {
                views.setViewVisibility(id, View.GONE)
                return
            }
            val b = app.nothingui.widgets.dotwel.media.MediaTouchGeometry.map(box, mediaKind, width, height)
            views.setViewLayoutWidth(id, (b.right - b.left).coerceAtLeast(1f), android.util.TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutHeight(id, (b.bottom - b.top).coerceAtLeast(1f), android.util.TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutMargin(id, RemoteViews.MARGIN_LEFT, b.left, android.util.TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutMargin(id, RemoteViews.MARGIN_TOP, b.top, android.util.TypedValue.COMPLEX_UNIT_DIP)
        }
        place(R.id.media_previous, controls.previous)
        place(R.id.media_play_pause, controls.play)
        place(R.id.media_next, controls.next)
        place(R.id.media_clear, controls.clear)
        place(R.id.media_volume_up, controls.volumeUp)
        place(R.id.media_volume_down, controls.volumeDown)
    }

    private fun bindLive(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        snapshot: MediaSnapshot,
        usedBitmap: Boolean,
    ) {
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.bg_widget_none)
        views.setViewVisibility(R.id.media_message, View.GONE)
        views.setViewVisibility(R.id.media_overlay, View.VISIBLE)
        bindRootClick(views, context, appWidgetId, snapshot)
        bindTransport(views, context, appWidgetId, snapshot)
        views.setViewVisibility(
            R.id.media_clear,
            if (mediaKind == MediaWidgetKind.NOTIFICATION &&
                snapshot.notification != null
            ) {
                View.VISIBLE
            } else {
                View.GONE
            },
        )
        if (usedBitmap) {
            views.setContentDescription(
                R.id.widget_media_bitmap,
                mediaDescription(context, snapshot),
            )
        }
    }

    private fun emptyViews(
        context: Context,
        appWidgetId: Int,
        snapshot: MediaSnapshot,
    ): RemoteViews {
        val views = baseViews(context, appWidgetId)
        views.setInt(
            R.id.widget_root,
            "setBackgroundResource",
            WidgetPrefs.style(context).backgroundRes,
        )
        views.setViewVisibility(R.id.widget_media_bitmap, View.GONE)
        views.setViewVisibility(R.id.media_overlay, View.GONE)
        views.setViewVisibility(R.id.media_clear, View.GONE)
        views.setViewVisibility(R.id.media_message, View.VISIBLE)
        views.setTextColor(
            R.id.media_message,
            UpstreamNtDraw.muted(context, WidgetPrefs.style(context)),
        )
        views.setTextViewText(R.id.media_message, emptyMessage(context, snapshot))
        val intent = Intent(context, app.lawnchair.LawnchairLauncher::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return views
    }

    private fun emptyMessage(context: Context, snapshot: MediaSnapshot): String = context.getString(R.string.media_empty_unavailable)

    private fun bindRootClick(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        snapshot: MediaSnapshot,
    ) {
        MediaSessionRepository.sessionActivity(context)?.let { pending ->
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            return
        }
        val playerIntent = MediaSessionRepository.playerIntent(context)
        val intent = playerIntent ?: Intent(context, app.lawnchair.LawnchairLauncher::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    private fun bindTransport(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        snapshot: MediaSnapshot,
    ) {
        bindTransportButton(
            views,
            context,
            appWidgetId,
            R.id.media_previous,
            MediaTransportAction.PREVIOUS,
            snapshot.canSkipPrevious,
        )
        bindTransportButton(
            views,
            context,
            appWidgetId,
            R.id.media_play_pause,
            MediaTransportAction.PLAY_PAUSE,
            snapshot.canPlayPause,
        )
        bindTransportButton(
            views,
            context,
            appWidgetId,
            R.id.media_next,
            MediaTransportAction.NEXT,
            snapshot.canSkipNext,
        )
        bindTransportButton(views, context, appWidgetId, R.id.media_volume_up, MediaTransportAction.VOLUME_UP, snapshot.canAdjustVolume)
        bindTransportButton(views, context, appWidgetId, R.id.media_volume_down, MediaTransportAction.VOLUME_DOWN, snapshot.canAdjustVolume)
        views.setViewVisibility(
            R.id.media_clear,
            if (mediaKind == MediaWidgetKind.NOTIFICATION) View.VISIBLE else View.GONE,
        )
        val clear = Intent(context, MediaActionReceiver::class.java).apply {
            action = MediaActionReceiver.ACTION_CLEAR_NOTIFICATION
        }
        views.setOnClickPendingIntent(
            R.id.media_clear,
            PendingIntent.getBroadcast(
                context,
                appWidgetId * 10 + 9,
                clear,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    private fun bindTransportButton(
        views: RemoteViews,
        context: Context,
        appWidgetId: Int,
        viewId: Int,
        action: MediaTransportAction,
        enabled: Boolean,
    ) {
        if (!enabled) {
            views.setViewVisibility(viewId, View.INVISIBLE)
            return
        }
        views.setViewVisibility(viewId, View.VISIBLE)
        val intent = Intent(context, MediaActionReceiver::class.java).apply {
            this.action = MediaActionReceiver.ACTION
            putExtra(MediaActionReceiver.EXTRA_TRANSPORT, action.name)
        }
        views.setOnClickPendingIntent(
            viewId,
            PendingIntent.getBroadcast(
                context,
                appWidgetId * 10 + action.ordinal + 1,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    private fun mediaDescription(context: Context, snapshot: MediaSnapshot): String {
        val title = snapshot.notification?.title ?: snapshot.title
        val artist = snapshot.notification?.text ?: snapshot.artist
        return context.getString(
            R.string.media_content_description,
            title ?: context.getString(R.string.media_empty_no_metadata),
            artist ?: "",
        )
    }
}

class Material3ExpandedMediaProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.M3_EXPANDED
}

class Material3MediaOutputProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.M3_OUTPUT
}

class MiniMediaPlayerProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.MINI
}

class MinimalMediaPlayerProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.MINIMAL
}

class MinimalMediaPlayer2Provider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.MINIMAL_2
}

class MinimalMediaPlayer3Provider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.MINIMAL_3
}

class NothingMasterWidgetProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.NOTHING_MASTER
    override val minuteRefresh: Boolean = true
}

class NothingMediaPlayerProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.NOTHING_PLAYER
}

class NothingMediaPlayer2Provider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.NOTHING_PLAYER_2
}

class NothingMediaPlayer3Provider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.NOTHING_PLAYER_3
}

class UniversalMediaPlayerProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.UNIVERSAL
}

class MaterialNotificationWidgetProvider : BaseMediaWidgetProvider() {
    override val mediaKind: MediaWidgetKind = MediaWidgetKind.NOTIFICATION
}
