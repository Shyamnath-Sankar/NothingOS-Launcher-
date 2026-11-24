package app.lawnchair.backup

import android.annotation.SuppressLint
import android.app.WallpaperManager
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.graphics.drawable.toBitmap
import app.lawnchair.LawnchairProto.BackupInfo
import app.lawnchair.data.AppDatabase
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
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
        val inventory = withContext(Dispatchers.IO) {
            openArchive().use { BackupArchive.scanArchive(it, LIMITS) }
        }
        if (BackupArchive.INFO_FILE_NAME !in inventory.relevantEntryNames) {
            throw BackupArchive.ValidationException("The backup is missing its metadata")
        }
        withContext(Dispatchers.IO) {
            openArchive().use { input ->
                ZipInputStream(input.buffered()).use { zip ->
                    var entry: ZipEntry?
                    while (true) {
                        entry = zip.nextEntry ?: break
                        when (entry.name) {
                            BackupArchive.INFO_FILE_NAME ->
                                info = BackupInfo.newBuilder().mergeFrom(zip).build()
                            BackupArchive.SCREENSHOT_FILE_NAME ->
                                tmpScreenshot = BitmapFactory.decodeStream(zip)
                            BackupArchive.WALLPAPER_FILE_NAME ->
                                tmpWallpaper = BitmapFactory.decodeStream(zip)
                        }
                    }
                }
            }
        }
        validateInfo(info)
        validateArchiveContents(info, inventory)
        val size = max(info.previewWidth, info.previewHeight).coerceAtMost(4000)
        screenshot = tmpScreenshot?.scaleDownTo(size)
        wallpaper = tmpWallpaper?.scaleDownToDisplaySize(context)
    }

    suspend fun restore(selectedContents: Int) {
        val inventory = withContext(Dispatchers.IO) {
            openArchive().use { BackupArchive.scanArchive(it, LIMITS) }
        }
        validateArchiveContents(info, inventory)
        val plan = BackupArchive.restorePlan(
            selectedContents,
            info.contents and BackupArchive.SUPPORTED_CONTENTS,
            inventory.relevantEntryNames,
        )
        val stagingRoot = File(context.cacheDir, STAGING_ROOT)
        if (!stagingRoot.exists() && !stagingRoot.mkdirs()) {
            throw BackupArchive.ValidationException("Could not create the backup staging directory")
        }
        val runDirectory = File(
            stagingRoot,
            "run-${System.currentTimeMillis()}-${STAGING_COUNTER.incrementAndGet()}",
        )
        try {
            val staged = withContext(Dispatchers.IO) {
                openArchive().use {
                    BackupArchive.extractSelected(it, runDirectory, plan, LIMITS)
                }
            }
            val stagedInfo = withContext(Dispatchers.IO) {
                readStagedInfo(staged.file(BackupArchive.INFO_FILE_NAME))
            }
            validateInfo(stagedInfo)
            if ((stagedInfo.contents and BackupArchive.SUPPORTED_CONTENTS) !=
                (info.contents and BackupArchive.SUPPORTED_CONTENTS)
            ) {
                throw BackupArchive.ValidationException("The backup changed before restore")
            }
            withContext(Dispatchers.IO) {
                applyRestore(staged, stagedInfo, plan)
            }
        } finally {
            BackupArchive.deleteStaging(stagingRoot, runDirectory)
            runCatching {
                if (stagingRoot.listFiles()?.isEmpty() == true) stagingRoot.delete()
            }
        }
    }

    private fun applyRestore(
        staged: BackupArchive.StagedRestore,
        stagedInfo: BackupInfo,
        plan: BackupArchive.RestorePlan,
    ) {
        var removedDatabases: BackupArchive.RemovedDatabases? = null
        var installedRestore: BackupArchive.InstalledRestore? = null
        var installedPreferences: BackupArchive.InstalledRestore? = null
        try {
            if (plan.restoreLayout) {
                val launcherDb = staged.file(BackupArchive.LAUNCHER_DB_FILE_NAME)
                validateSqliteDatabase(launcherDb, "launcher database")
                staged.files[BackupArchive.PREFS_DB_FILE_NAME]?.let {
                    validateSqliteDatabase(it, "preferences database")
                }
                val databaseDirectory = context.getDatabasePath(BackupArchive.LAUNCHER_DB_FILE_NAME)
                    .parentFile
                    ?: throw BackupArchive.ValidationException("The launcher database directory is unavailable")
                val rollbackDirectory = File(staged.directory, ROLLBACK_DIRECTORY)
                removedDatabases = BackupArchive.removeLauncherDatabases(
                    databaseDirectory,
                    GRID_DATABASE_NAMES,
                    File(rollbackDirectory, "databases"),
                )
                val restoredDatabase = context.getDatabasePath(BackupArchive.RESTORED_DB_FILE_NAME)
                installedRestore = BackupArchive.installStaged(
                    staged,
                    mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to restoredDatabase),
                    File(rollbackDirectory, "launcher-db"),
                )
                if (stagedInfo.gridState.gridSize.isNotBlank()) {
                    DeviceGridState(stagedInfo.gridState).writeToPrefs(context, true)
                }
                val restored = RestoreDbTask.performRestore(context, ModelDbController(context))
                if (!restored) {
                    throw BackupArchive.ValidationException(
                        "RestoreDbTask could not apply the launcher database",
                    )
                }
                if (staged.files[BackupArchive.PREFS_DB_FILE_NAME] != null) {
                    closePreferencesDatabase()
                }
                val preferenceTargets = buildMap {
                    staged.files[BackupArchive.PREFS_FILE_NAME]?.let {
                        put(BackupArchive.PREFS_FILE_NAME, prefsFile(context))
                    }
                    staged.files[BackupArchive.PREFS_DB_FILE_NAME]?.let {
                        put(BackupArchive.PREFS_DB_FILE_NAME, prefsDbFile(context))
                    }
                    staged.files[BackupArchive.PREFS_DATASTORE_FILE_NAME]?.let {
                        put(BackupArchive.PREFS_DATASTORE_FILE_NAME, prefsDataStoreFile(context))
                    }
                }
                if (preferenceTargets.isNotEmpty()) {
                    installedPreferences = BackupArchive.installStaged(
                        staged,
                        preferenceTargets,
                        File(rollbackDirectory, "preferences"),
                    )
                }
            }
            if (plan.restoreWallpaper) {
                val bitmap = BitmapFactory.decodeFile(
                    staged.file(BackupArchive.WALLPAPER_FILE_NAME).path,
                ) ?: throw BackupArchive.ValidationException("The backup wallpaper could not be decoded")
                WallpaperManager.getInstance(context).setBitmap(bitmap)
            }
            installedPreferences?.discard()
            installedRestore?.discard()
            removedDatabases?.discard()
        } catch (t: Throwable) {
            installedPreferences?.rollback()
            if (plan.restoreLayout) {
                deleteGridDatabaseFiles()
            }
            removedDatabases?.rollback()
            installedRestore?.rollback()
            throw t
        }
    }

    private fun readStagedInfo(file: File): BackupInfo {
        return try {
            file.inputStream().buffered().use { input ->
                BackupInfo.newBuilder().mergeFrom(input).build()
            }
        } catch (t: Throwable) {
            throw BackupArchive.ValidationException("The backup metadata could not be read", t)
        }
    }

    private fun validateInfo(backupInfo: BackupInfo) {
        val gridState = backupInfo.gridState
        BackupArchive.validateMetadata(
            backupInfo.backupVersion,
            backupInfo.contents,
            gridState.gridSize,
            gridState.hotseatCount,
        )
    }

    private fun validateArchiveContents(
        backupInfo: BackupInfo,
        inventory: BackupArchive.Inventory,
    ) {
        if (BackupArchive.INFO_FILE_NAME !in inventory.relevantEntryNames) {
            throw BackupArchive.ValidationException("The backup is missing its metadata")
        }
        if (BackupArchive.hasFlag(backupInfo.contents, BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS) &&
            BackupArchive.LAUNCHER_DB_FILE_NAME !in inventory.relevantEntryNames
        ) {
            throw BackupArchive.ValidationException("The backup is missing the launcher database")
        }
        if (BackupArchive.hasFlag(backupInfo.contents, BackupArchive.INCLUDE_WALLPAPER) &&
            BackupArchive.WALLPAPER_FILE_NAME !in inventory.relevantEntryNames
        ) {
            throw BackupArchive.ValidationException("The backup is missing the selected wallpaper")
        }
    }

    private fun validateSqliteDatabase(file: File, label: String) {
        val database = try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (t: Throwable) {
            throw BackupArchive.ValidationException("The staged $label is not a valid database", t)
        }
        try {
            database.rawQuery("pragma integrity_check", null).use { cursor ->
                if (!cursor.moveToFirst() || cursor.getString(0) != "ok") {
                    throw BackupArchive.ValidationException("The staged $label failed its integrity check")
                }
            }
            database.rawQuery(
                "select name from sqlite_master where type = 'table' and name = 'favorites'",
                null,
            ).use { cursor ->
                if (!cursor.moveToFirst()) {
                    throw BackupArchive.ValidationException("The staged $label has no favorites table")
                }
            }
        } finally {
            database.close()
        }
    }

    private fun closePreferencesDatabase() {
        runCatching { AppDatabase.INSTANCE.get(context).close() }
    }

    private fun deleteGridDatabaseFiles() {
        val directory = context.getDatabasePath(BackupArchive.LAUNCHER_DB_FILE_NAME).parentFile
            ?: return
        GRID_DATABASE_NAMES.forEach { name ->
            BackupArchive.DATABASE_SIDECARS.forEach { suffix ->
                runCatching { File(directory, "$name$suffix").delete() }
            }
        }
    }

    private fun openArchive(): InputStream {
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IOException("The backup file could not be opened")
        return input.buffered()
    }

    companion object {
        private const val PREFS_FILE_NAME = BackupArchive.PREFS_FILE_NAME
        private const val PREFS_DB_FILE_NAME = BackupArchive.PREFS_DB_FILE_NAME
        private const val PREFS_DATASTORE_FILE_NAME = BackupArchive.PREFS_DATASTORE_FILE_NAME

        const val INFO_FILE_NAME = BackupArchive.INFO_FILE_NAME
        const val WALLPAPER_FILE_NAME = BackupArchive.WALLPAPER_FILE_NAME
        const val SCREENSHOT_FILE_NAME = BackupArchive.SCREENSHOT_FILE_NAME
        const val LAUNCHER_DB_FILE_NAME = BackupArchive.LAUNCHER_DB_FILE_NAME
        const val RESTORED_DB_FILE_NAME = BackupArchive.RESTORED_DB_FILE_NAME

        const val INCLUDE_LAYOUT_AND_SETTINGS = BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS
        const val INCLUDE_WALLPAPER = BackupArchive.INCLUDE_WALLPAPER

        const val MIME_TYPE = "application/zip"
        val EXTRA_MIME_TYPES = arrayOf(MIME_TYPE, "application/x-zip", "application/octet-stream")

        val contentOptions = listOf(
            INCLUDE_LAYOUT_AND_SETTINGS to R.string.backup_content_layout_and_settings,
            INCLUDE_WALLPAPER to R.string.backup_content_wallpaper,
        )

        private const val STAGING_ROOT = "backup-restore"
        private const val ROLLBACK_DIRECTORY = "rollback"
        private val STAGING_COUNTER = AtomicLong()
        private val LIMITS = BackupArchive.Limits()
        private val GRID_DATABASE_NAMES: Set<String> = LauncherFiles.GRID_DB_FILES.toSet()

        fun generateBackupFileName(): String {
            val fileName = "Lawnchair_Backup ${SimpleDateFormat.getDateTimeInstance().format(Date())}"
            return "$fileName.lawnchairbackup"
        }

        fun getFiles(context: Context): Map<String, File> {
            return mapOf(
                LAUNCHER_DB_FILE_NAME to launcherDbFile(context),
                PREFS_FILE_NAME to prefsFile(context),
                PREFS_DB_FILE_NAME to prefsDbFile(context),
                PREFS_DATASTORE_FILE_NAME to prefsDataStoreFile(context),
            )
        }

        @SuppressLint("MissingPermission")
        suspend fun create(context: Context, contents: Int, screenshotBitmap: Bitmap, fileUri: Uri) {
            val wallpaperBitmap = if (BackupArchive.hasFlag(contents, INCLUDE_WALLPAPER)) {
                WallpaperManager.getInstance(context).drawable?.toBitmap()
            } else {
                null
            }
            val existingLayoutEntries = getFiles(context)
                .filterValues { it.isFile }
                .keys
            val plan = BackupArchive.exportPlan(contents, existingLayoutEntries, wallpaperBitmap != null)
            val idp = LauncherAppState.getIDP(context)
            val createdAt = Timestamp.newBuilder()
                .setSeconds(System.currentTimeMillis() / 1000)
            val colorHints = if (plan.includeWallpaper) {
                WallpaperManagerCompat.INSTANCE.get(context).wallpaperColors?.colorHints ?: 0
            } else {
                0
            }
            val wallpaperSupportsDarkText =
                (colorHints and WallpaperColorsCompat.HINT_SUPPORTS_DARK_TEXT) != 0
            val backupInfo = BackupInfo.newBuilder()
                .setLawnchairVersion(BuildConfig.VERSION_CODE)
                .setBackupVersion(BackupArchive.BACKUP_VERSION)
                .setCreatedAt(createdAt)
                .setContents(plan.contents)
                .setGridState(DeviceGridState(idp).toProtoMessage())
                .setPreviewWidth(screenshotBitmap.width)
                .setPreviewHeight(screenshotBitmap.height)
                .setPreviewDarkText(wallpaperSupportsDarkText)
                .build()

            withContext(Dispatchers.IO) {
                if (plan.requiresPreferenceCheckpoint) {
                    AppDatabase.INSTANCE.get(context).checkpoint()
                    checkpointLauncherDatabase(context)
                }
                val temporaryRoot = File(context.cacheDir, "backup-create")
                if (!temporaryRoot.exists() && !temporaryRoot.mkdirs()) {
                    throw IOException("Could not create the backup staging directory")
                }
                val temporaryFile = File(
                    temporaryRoot,
                    "create-${System.currentTimeMillis()}-${STAGING_COUNTER.incrementAndGet()}.lawnchairbackup",
                )
                try {
                    writeArchive(temporaryFile, backupInfo, plan, screenshotBitmap, wallpaperBitmap, context)
                    copyToDestination(fileUri, temporaryFile, context)
                } finally {
                    runCatching { temporaryFile.delete() }
                    runCatching {
                        if (temporaryRoot.listFiles()?.isEmpty() == true) temporaryRoot.delete()
                    }
                }
            }
        }

        private fun writeArchive(
            destination: File,
            backupInfo: BackupInfo,
            plan: BackupArchive.ExportPlan,
            screenshotBitmap: Bitmap,
            wallpaperBitmap: Bitmap?,
            context: Context,
        ) {
            FileOutputStream(destination).buffered().use { output ->
                ZipOutputStream(output).use { zip ->
                    zip.putNextEntry(ZipEntry(INFO_FILE_NAME))
                    backupInfo.writeTo(zip)
                    if (plan.includeWallpaper && wallpaperBitmap != null) {
                        zip.putNextEntry(ZipEntry(WALLPAPER_FILE_NAME))
                        wallpaperBitmap.compress(Bitmap.CompressFormat.PNG, 100, zip)
                    }
                    if (plan.includeScreenshot) {
                        zip.putNextEntry(ZipEntry(SCREENSHOT_FILE_NAME))
                        screenshotBitmap.compress(Bitmap.CompressFormat.PNG, 85, zip)
                    }
                    if (plan.includeLayout) {
                        val files = getFiles(context)
                        plan.layoutEntries.forEach { entryName ->
                            val file = files[entryName] ?: return@forEach
                            if (!file.isFile) return@forEach
                            zip.putNextEntry(ZipEntry(entryName))
                            file.inputStream().use { it.copyTo(zip) }
                        }
                    }
                }
            }
        }

        private fun copyToDestination(fileUri: Uri, source: File, context: Context) {
            val descriptor = context.contentResolver.openFileDescriptor(fileUri, "w")
                ?: throw IOException("The backup destination could not be opened")
            descriptor.use {
                FileOutputStream(descriptor.fileDescriptor).use { output ->
                    source.inputStream().use { input -> input.copyTo(output) }
                    output.flush()
                    descriptor.fileDescriptor.sync()
                }
            }
        }

        private fun checkpointLauncherDatabase(context: Context) {
            val databaseFile = context.getDatabasePath(LauncherAppState.getIDP(context).dbFile)
            if (!databaseFile.isFile) return
            val database = try {
                SQLiteDatabase.openDatabase(
                    databaseFile.path,
                    null,
                    SQLiteDatabase.OPEN_READWRITE,
                )
            } catch (t: Throwable) {
                throw BackupArchive.ValidationException("Could not open the launcher database", t)
            }
            try {
                database.rawQuery("pragma wal_checkpoint(full)", null).use { it.moveToFirst() }
            } catch (t: Throwable) {
                throw BackupArchive.ValidationException("Could not checkpoint the launcher database", t)
            } finally {
                database.close()
            }
        }

        private fun launcherDbFile(context: Context): File {
            return context.getDatabasePath(LauncherAppState.getIDP(context).dbFile)
        }

        private fun prefsFile(context: Context): File {
            val dir = context.cacheDir.parent
            return File(dir, "shared_prefs/$PREFS_FILE_NAME")
        }

        private fun prefsDbFile(context: Context): File {
            return context.getDatabasePath(PREFS_DB_FILE_NAME)
        }

        private fun prefsDataStoreFile(context: Context): File {
            return File(context.filesDir, "datastore/$PREFS_DATASTORE_FILE_NAME")
        }
    }
}
