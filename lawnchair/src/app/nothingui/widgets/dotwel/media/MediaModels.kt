package app.nothingui.widgets.dotwel.media

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.provider.Settings

/**
 * Runtime-only snapshot of the active media session and the most recent
 * notification. Nothing in this model is written to disk except the explicit
 * masking preference. Cover art and notification text live in process memory
 * and are cleared on listener disconnect/revoke.
 */
data class MediaSnapshot(
    val accessGranted: Boolean,
    val hasSession: Boolean,
    val title: String?,
    val artist: String?,
    val album: String?,
    val packageName: String?,
    val appLabel: String?,
    val albumArt: Bitmap?,
    val isPlaying: Boolean,
    val playbackState: Int,
    val positionMillis: Long,
    val durationMillis: Long,
    val canPlayPause: Boolean,
    val canSkipPrevious: Boolean,
    val canSkipNext: Boolean,
    val capturedAtMillis: Long,
    val notification: MediaNotification?,
    val volumeFraction: Float? = null,
    val canAdjustVolume: Boolean = false,
) {
    val hasMetadata: Boolean
        get() = !title.isNullOrBlank() || !artist.isNullOrBlank()

    val hasPlayback: Boolean
        get() = hasSession && hasMetadata

    companion object {
        fun noAccess(): MediaSnapshot = MediaSnapshot(
            accessGranted = false,
            hasSession = false,
            title = null,
            artist = null,
            album = null,
            packageName = null,
            appLabel = null,
            albumArt = null,
            isPlaying = false,
            playbackState = 0,
            positionMillis = 0L,
            durationMillis = 0L,
            canPlayPause = false,
            canSkipPrevious = false,
            canSkipNext = false,
            capturedAtMillis = 0L,
            notification = null,
        )
    }
}

data class MediaNotification(
    val title: String?,
    val text: String?,
    val appLabel: String?,
    val postedAtMillis: Long,
)

/**
 * The only persisted media value is whether notification body text may be
 * displayed. It defaults to masked and is excluded from backup/transfer.
 */
object MediaPrefs {
    internal const val PREFS = "dotwel_media"
    private const val KEY_SHOW_NOTIFICATION_TEXT = "show_notification_text"

    private fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun showNotificationText(context: Context): Boolean = prefs(context).getBoolean(KEY_SHOW_NOTIFICATION_TEXT, false)

    fun setShowNotificationText(context: Context, show: Boolean) {
        prefs(context).edit().putBoolean(KEY_SHOW_NOTIFICATION_TEXT, show).apply()
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }
}

object MediaAccess {
    /**
     * Notification access can only be granted by the Android system settings
     * screen. This app never enables it programmatically.
     */
    fun isGranted(context: Context): Boolean {
        val flat = runCatching {
            Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            )
        }.getOrNull() ?: return false
        if (flat.isBlank()) return false
        val expected = ComponentName(context, MediaNotificationService::class.java)
        return flat.split(':').any { entry ->
            val parsed = runCatching { ComponentName.unflattenFromString(entry) }.getOrNull()
            parsed == expected
        }
    }
}
