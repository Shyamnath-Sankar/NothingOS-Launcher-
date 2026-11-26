package app.lawnchair.backup

import android.annotation.SuppressLint
import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.graphics.drawable.toBitmap
import app.lawnchair.LawnchairProto.BackupInfo
import app.lawnchair.util.hasFlag
import app.lawnchair.util.scaleDownTo
import app.lawnchair.util.scaleDownToDisplaySize
import app.lawnchair.wallpaper.WallpaperColorsCompat
import app.lawnchair.wallpaper.WallpaperManagerCompat
import com.android.launcher3.BuildConfig
import com.android.launcher3.LauncherAppState
import com.android.launcher3.LauncherFiles
import com.android.launcher3.R
import com.android.launcher3.model.DeviceGridState
import com.google.protobuf.Timestamp
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class BackupOperationResult {
    SUCCESS,
    FAILURE,
    UNAVAILABLE,
}

class LawnchairBackup(
    private val context: Context,
    private val uri: Uri,
) {
    lateinit var info: BackupInfo
    var screenshot: Bitmap? = null
    var wallpaper: Bitmap? = null

    suspend fun readInfoAndPreview() {
        var tmpScreenshot: Bitmap? = null
        var tmpWallpaper: Bitmap? = null
        readZip(
            mapOf(
                INFO_FILE_NAME to { info = BackupInfo.newBuilder().mergeFrom(it).build() },
                SCREENSHOT_FILE_NAME to { tmpScreenshot = BitmapFactory.decodeStream(it) },
                WALLPAPER_FILE_NAME to { tmpWallpaper = BitmapFactory.decodeStream(it) },
            ),
        )
        val size = max(info.previewWidth, info.previewHeight).coerceAtMost(4000)
        screenshot = tmpScreenshot?.scaleDownTo(size)
        wallpaper = tmpWallpaper?.scaleDownToDisplaySize(context)
    }

    @Suppress("UNUSED_PARAMETER")
    suspend fun restore(selectedContents: Int): BackupOperationResult {
        // Restore is disabled in this build: it can destroy user data on failure. Existing
        // backup files and launcher data are intentionally left untouched.
        return BackupOperationResult.UNAVAILABLE
    }

    private suspend fun readZip(handlers: Map<String, suspend (InputStream) -> Unit>) {
        withContext(Dispatchers.IO) {
            val pfd = context.contentResolver.openFileDescriptor(uri, "r")!!
            pfd.use {
                FileInputStream(it.fileDescriptor).use { inStream ->
                    ZipInputStream(inStream).use { zipIs ->
                        var entry: ZipEntry?
                        while (true) {
                            entry = zipIs.nextEntry
                            if (entry == null) break
                            handlers[entry.name]?.invoke(zipIs)
                        }
                    }
                }
            }
        }
    }

    companion object {
        private const val BACKUP_VERSION = 1
        private const val PREFS_FILE_NAME = "${LauncherFiles.SHARED_PREFERENCES_KEY}.xml"
        private const val PREFS_DB_FILE_NAME = "preferences"
        private const val PREFS_DATASTORE_FILE_NAME = "preferences.preferences_pb"

        const val INFO_FILE_NAME = BACKUP_INFO_ENTRY_NAME
        const val WALLPAPER_FILE_NAME = BACKUP_WALLPAPER_ENTRY_NAME
        const val SCREENSHOT_FILE_NAME = BACKUP_SCREENSHOT_ENTRY_NAME
        const val LAUNCHER_DB_FILE_NAME = "launcher.db"
        const val RESTORED_DB_FILE_NAME = "restored.db"

        const val INCLUDE_LAYOUT_AND_SETTINGS = 1 shl 0
        const val INCLUDE_WALLPAPER = 1 shl 1

        const val MIME_TYPE = "application/zip"
        val EXTRA_MIME_TYPES = arrayOf(MIME_TYPE, "application/x-zip", "application/octet-stream")

        val contentOptions = listOf(
            INCLUDE_LAYOUT_AND_SETTINGS to R.string.backup_content_layout_and_settings,
            INCLUDE_WALLPAPER to R.string.backup_content_wallpaper,
        )

        fun generateBackupFileName(): String {
            val fileName = "Lawnchair_Backup ${SimpleDateFormat.getDateTimeInstance().format(Date())}"
            return "$fileName.lawnchairbackup"
        }

        fun getFiles(context: Context, forRestore: Boolean): Map<String, File> {
            return mapOf(
                LAUNCHER_DB_FILE_NAME to launcherDbFile(context, forRestore),
                PREFS_FILE_NAME to prefsFile(context),
                PREFS_DB_FILE_NAME to prefsDbFile(context),
                PREFS_DATASTORE_FILE_NAME to prefsDataStoreFile(context),
            )
        }

        @SuppressLint("MissingPermission")
        suspend fun create(
            context: Context,
            contents: Int,
            screenshotBitmap: Bitmap,
            fileUri: Uri,
        ): BackupOperationResult {
            val includeLayoutAndSettings = contents.hasFlag(INCLUDE_LAYOUT_AND_SETTINGS)
            val includeWallpaper = contents.hasFlag(INCLUDE_WALLPAPER)
            return try {
                withContext(Dispatchers.IO) {
                    val idp = LauncherAppState.getIDP(context)
                    val createdAt = Timestamp.newBuilder()
                        .setSeconds(System.currentTimeMillis() / 1000)
                    val colorHints =
                        WallpaperManagerCompat.INSTANCE.get(context).wallpaperColors?.colorHints ?: 0
                    val wallpaperSupportsDarkText =
                        (colorHints and WallpaperColorsCompat.HINT_SUPPORTS_DARK_TEXT) != 0
                    val info = BackupInfo.newBuilder()
                        .setLawnchairVersion(BuildConfig.VERSION_CODE)
                        .setBackupVersion(BACKUP_VERSION)
                        .setCreatedAt(createdAt)
                        .setContents(contents)
                        .setGridState(DeviceGridState(idp).toProtoMessage())
                        .setPreviewWidth(screenshotBitmap.width)
                        .setPreviewHeight(screenshotBitmap.height)
                        .setPreviewDarkText(wallpaperSupportsDarkText)
                        .build()

                    val wallpaperBitmap = if (includeWallpaper) {
                        WallpaperManager.getInstance(context).drawable?.toBitmap()
                    } else {
                        null
                    }
                    val entries = buildBackupEntries(
                        includeLayoutAndSettings = includeLayoutAndSettings,
                        includeWallpaper = includeWallpaper,
                        screenshotWriter = BackupEntryWriter { output ->
                            screenshotBitmap.compress(Bitmap.CompressFormat.PNG, 85, output)
                        },
                        wallpaperWriter = wallpaperBitmap?.let { bitmap ->
                            BackupEntryWriter { output ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                            }
                        },
                        files = getFiles(context, forRestore = false),
                    )

                    val pfd = context.contentResolver.openFileDescriptor(fileUri, "w")
                        ?: return@withContext BackupOperationResult.FAILURE
                    pfd.use {
                        BackupArchiveWriter.write(
                            FileOutputStream(it.fileDescriptor),
                            info.toByteArray(),
                            entries,
                        )
                    }
                    BackupOperationResult.SUCCESS
                }
            } catch (_: Exception) {
                BackupOperationResult.FAILURE
            }
        }

        private fun launcherDbFile(context: Context, forRestore: Boolean): File {
            val dbName = if (forRestore) RESTORED_DB_FILE_NAME else LauncherAppState.getIDP(context).dbFile
            return context.getDatabasePath(dbName)
        }

        private fun prefsFile(context: Context): File {
            val dir = context.cacheDir.parent
            return File(dir, "shared_prefs/$PREFS_FILE_NAME")
        }

        private fun prefsDbFile(context: Context): File {
            return context.getDatabasePath(PREFS_DB_FILE_NAME)
        }

        private fun prefsDataStoreFile(context: Context): File {
            return File(context.filesDir, "datastore/${PREFS_DATASTORE_FILE_NAME}")
        }
    }
}
