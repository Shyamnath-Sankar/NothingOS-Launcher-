package app.lawnchair.backup

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
import com.android.launcher3.model.ModelDbController
import com.android.launcher3.provider.RestoreDbTask
import com.google.protobuf.Timestamp
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.UUID
import java.util.zip.ZipInputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

sealed interface BackupOperationResult {
    data object Success : BackupOperationResult
    data class Failure(val cause: Throwable? = null) : BackupOperationResult
    data object Unavailable : BackupOperationResult
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

    suspend fun restore(selectedContents: Int): BackupOperationResult = withContext(Dispatchers.IO) {
        val contents = selectedContents and info.contents
        if (contents == 0) {
            return@withContext BackupOperationResult.Failure()
        }

        val workDir = File(context.noBackupFilesDir, "backup-restore-${UUID.randomUUID()}")
        if (!workDir.mkdirs()) {
            return@withContext BackupOperationResult.Failure()
        }
        val archive = File(workDir, "backup.zip")
        var transaction: RestoreTransaction? = null
        var previousWallpaper: Bitmap? = null
        var wallpaperChanged = false
        var liveDbBackups: Map<File, File> = emptyMap()
        try {
            copyUriToFile(uri, archive)

            val requiredEntries = mutableSetOf(INFO_FILE_NAME)
            if (contents.hasFlag(INCLUDE_LAYOUT_AND_SETTINGS)) {
                requiredEntries += LAUNCHER_DB_FILE_NAME
            }
            val manifest = BackupArchive.validate(archive, requiredEntries)

            val targets = if (contents.hasFlag(INCLUDE_LAYOUT_AND_SETTINGS)) {
                linkedMapOf(
                    LAUNCHER_DB_FILE_NAME to context.getDatabasePath(RESTORED_DB_FILE_NAME),
                    PREFS_FILE_NAME to prefsFile(context),
                    PREFS_DB_FILE_NAME to prefsDbFile(context),
                    PREFS_DATASTORE_FILE_NAME to prefsDataStoreFile(context),
                )
            } else {
                emptyMap()
            }
            val restoreTransaction = BackupRestoreEngine.restore(
                archive,
                workDir,
                targets,
                requiredEntries,
            )
            transaction = restoreTransaction

            if (contents.hasFlag(INCLUDE_WALLPAPER)) {
                val wallpaperBytes = BackupArchive.readEntry(archive, manifest, WALLPAPER_FILE_NAME)
                if (wallpaperBytes != null) {
                    val bitmap = BitmapFactory.decodeByteArray(wallpaperBytes, 0, wallpaperBytes.size)
                        ?: throw BackupArchiveException("Backup wallpaper is invalid")
                    val wallpaperManager = WallpaperManager.getInstance(context)
                    previousWallpaper = runCatching { wallpaperManager.drawable?.toBitmap() }.getOrNull()
                    wallpaperManager.setBitmap(bitmap)
                    wallpaperChanged = true
                }
            }

            if (contents.hasFlag(INCLUDE_LAYOUT_AND_SETTINGS)) {
                // Written after the zip has been extracted: the backed up preferences file is one
                // of the restored entries, so writing the grid state first would let it be
                // overwritten.
                DeviceGridState(info.gridState).writeToPrefs(context, true)

                liveDbBackups = backUpLiveDatabases(context, workDir)
                val dbController = ModelDbController(context)
                if (!RestoreDbTask.performRestore(context, dbController)) {
                    throw BackupArchiveException("Launcher database restore failed")
                }
            }

            restoreTransaction.commit()
            BackupOperationResult.Success
        } catch (t: Throwable) {
            transaction?.rollback()
            if (wallpaperChanged && previousWallpaper != null) {
                runCatching {
                    WallpaperManager.getInstance(context).setBitmap(previousWallpaper)
                }
            }
            liveDbBackups.forEach { (live, backup) ->
                runCatching { backup.copyTo(live, overwrite = true) }
            }
            BackupOperationResult.Failure(t)
        } finally {
            workDir.deleteRecursively()
        }
    }

    private suspend fun readZip(handlers: Map<String, suspend (InputStream) -> Unit>) {
        withContext(Dispatchers.IO) {
            val pfd = context.contentResolver.openFileDescriptor(uri, "r")!!
            pfd.use {
                FileInputStream(it.fileDescriptor).use { inStream ->
                    ZipInputStream(inStream).use { zipIs ->
                        var entry = zipIs.nextEntry
                        while (entry != null) {
                            handlers[entry.name]?.invoke(zipIs)
                            entry = zipIs.nextEntry
                        }
                    }
                }
            }
        }
    }

    private fun copyUriToFile(uri: Uri, destination: File) {
        val input = context.contentResolver.openInputStream(uri)
            ?: throw BackupArchiveException("Could not open backup file")
        input.use { source ->
            destination.outputStream().buffered().use { out -> source.copyTo(out) }
        }
    }

    private fun backUpLiveDatabases(context: Context, workDir: File): Map<File, File> {
        val backupDir = File(workDir, "live-databases")
        if (!backupDir.mkdirs()) return emptyMap()
        val backups = linkedMapOf<File, File>()
        LauncherFiles.GRID_DB_FILES.forEach { dbName ->
            val live = context.getDatabasePath(dbName)
            if (live.isFile) {
                val backup = File(backupDir, dbName)
                live.copyTo(backup, overwrite = true)
                backups[live] = backup
            }
        }
        return backups
    }

    companion object {
        private const val BACKUP_VERSION = 1
        private const val PREFS_FILE_NAME = "${LauncherFiles.SHARED_PREFERENCES_KEY}.xml"
        private const val PREFS_DB_FILE_NAME = "preferences"
        private const val PREFS_DATASTORE_FILE_NAME = "preferences.preferences_pb"

        const val INFO_FILE_NAME = "info.pb"
        const val WALLPAPER_FILE_NAME = "wallpaper.png"
        const val SCREENSHOT_FILE_NAME = "screenshot.png"
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

        suspend fun create(
            context: Context,
            contents: Int,
            screenshotBitmap: Bitmap,
            fileUri: Uri,
        ): BackupOperationResult = withContext(Dispatchers.IO) {
            val workDir = File(context.noBackupFilesDir, "backup-create-${UUID.randomUUID()}")
            if (!workDir.mkdirs()) {
                return@withContext BackupOperationResult.Failure()
            }
            val archive = File(workDir, "backup.zip")
            try {
                val idp = LauncherAppState.getIDP(context)
                val createdAt = Timestamp.newBuilder()
                    .setSeconds(System.currentTimeMillis() / 1000)
                val colorHints = WallpaperManagerCompat.INSTANCE.get(context).wallpaperColors?.colorHints ?: 0
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

                val sources = mutableListOf<ArchiveSource>()
                sources += ArchiveSource.fromBytes(INFO_FILE_NAME, info.toByteArray())

                if (contents.hasFlag(INCLUDE_WALLPAPER)) {
                    val wallpaperBitmap = WallpaperManager.getInstance(context).drawable?.toBitmap()
                    if (wallpaperBitmap != null) {
                        sources += ArchiveSource.fromBytes(
                            WALLPAPER_FILE_NAME,
                            wallpaperBitmap.toPngBytes(),
                        )
                    }
                }
                if (contents.hasFlag(INCLUDE_LAYOUT_AND_SETTINGS)) {
                    sources += ArchiveSource.fromBytes(
                        SCREENSHOT_FILE_NAME,
                        screenshotBitmap.toPngBytes(),
                    )
                }

                getFiles(context, forRestore = false).forEach { (name, file) ->
                    if (file.isFile) {
                        sources += ArchiveSource.fromFile(name, file)
                    }
                }

                BackupArchive.write(archive, sources)

                val output = context.contentResolver.openOutputStream(fileUri, "w")
                    ?: throw BackupArchiveException("Could not open backup destination")
                output.use { destination ->
                    archive.inputStream().use { source -> source.copyTo(destination) }
                }
                BackupOperationResult.Success
            } catch (t: Throwable) {
                BackupOperationResult.Failure(t)
            } finally {
                workDir.deleteRecursively()
            }
        }

        private fun Bitmap.toPngBytes(): ByteArray {
            val output = ByteArrayOutputStream()
            compress(Bitmap.CompressFormat.PNG, 100, output)
            return output.toByteArray()
        }

        private fun launcherDbFile(context: Context, forRestore: Boolean): File {
            val dbName = if (forRestore) {
                RESTORED_DB_FILE_NAME
            } else {
                LauncherAppState.getIDP(context).dbFile
            }
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
