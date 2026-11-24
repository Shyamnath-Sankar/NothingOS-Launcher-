package app.lawnchair.backup

import android.annotation.SuppressLint
import android.app.WallpaperManager
import android.content.Context
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
import com.android.launcher3.LauncherPrefs
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
        // The recovery directory is a sibling of the run directory. Staging
        // cleanup never deletes it, so a failed rollback keeps its only copy.
        val recoveryDirectory = File(stagingRoot, "recovery-${runDirectory.name}")
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
                applyRestore(staged, stagedInfo, plan, recoveryDirectory)
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
        recoveryDirectory: File,
    ) {
        // -------- PREFLIGHT: nothing below may touch live state. --------
        var launcherSnapshot: BackupArchive.DatabaseSnapshot? = null
        var preferencesSnapshot: BackupArchive.DatabaseSnapshot? = null
        var restoredPreferences: Map<String, Any>? = null
        var wallpaperBitmap: Bitmap? = null

        if (plan.restoreLayout) {
            launcherSnapshot = AndroidDatabaseSnapshot.read(
                staged.file(BackupArchive.LAUNCHER_DB_FILE_NAME),
            )
            BackupArchive.validateLauncherDatabase(launcherSnapshot)
            staged.files[BackupArchive.PREFS_DB_FILE_NAME]?.let { preferencesDatabase ->
                preferencesSnapshot = AndroidDatabaseSnapshot.read(preferencesDatabase)
                BackupArchive.validatePreferencesDatabase(preferencesSnapshot)
            }
            staged.files[BackupArchive.PREFS_FILE_NAME]?.let { preferencesFile ->
                restoredPreferences = BackupPreferences.parse(preferencesFile)
            }
        }
        if (plan.restoreWallpaper) {
            wallpaperBitmap = BitmapFactory.decodeFile(
                staged.file(BackupArchive.WALLPAPER_FILE_NAME).path,
            ) ?: throw BackupArchive.ValidationException(
                "The backup wallpaper could not be decoded",
            )
        }

        // Best effort only. If the prior wallpaper cannot be read, a later
        // layout failure cannot silently claim it was restored.
        val priorWallpaper = if (plan.restoreWallpaper) {
            runCatching { WallpaperManager.getInstance(context).drawable?.toBitmap() }.getOrNull()
        } else {
            null
        }

        // -------- MUTATION PHASE: every step has an undo or a safe restart boundary. --------
        var removedDatabases: BackupArchive.RemovedDatabases? = null
        var installedRestore: BackupArchive.InstalledRestore? = null
        var installedPreferencesDatabase: BackupArchive.InstalledRestore? = null
        var installedDataStore: BackupArchive.InstalledRestore? = null
        var priorPreferences: Map<String, Any>? = null
        var preferencesApplied = false
        var preferencesDatabaseClosed = false
        var liveDatabaseName: String? = null
        var wallpaperApplied = false

        try {
            // Apply wallpaper before the irreversible layout commit. A failure
            // here leaves layout and preferences untouched.
            if (plan.restoreWallpaper) {
                val bitmap = wallpaperBitmap
                    ?: throw BackupArchive.ValidationException(
                        "The backup wallpaper could not be decoded",
                    )
                WallpaperManager.getInstance(context).setBitmap(bitmap)
                wallpaperApplied = true
            }

            if (plan.restoreLayout) {
                // Restore preferences first. The intended grid state is written
                // afterwards so the restored XML can never erase it.
                if (restoredPreferences != null) {
                    priorPreferences = snapshotSharedPreferences()
                    applySharedPreferences(restoredPreferences)
                    preferencesApplied = true
                }
                if (stagedInfo.gridState.gridSize.isNotBlank()) {
                    DeviceGridState(stagedInfo.gridState).writeToPrefs(context, true)
                }

                liveDatabaseName = currentLauncherDbName()
                val databaseDirectory = context
                    .getDatabasePath(BackupArchive.LAUNCHER_DB_FILE_NAME)
                    .parentFile
                    ?: throw BackupArchive.ValidationException(
                        "The launcher database directory is unavailable",
                    )
                removedDatabases = BackupArchive.removeLauncherDatabases(
                    databaseDirectory,
                    GRID_DATABASE_NAMES,
                    File(recoveryDirectory, "databases"),
                )
                val restoredDatabase = context.getDatabasePath(
                    BackupArchive.RESTORED_DB_FILE_NAME,
                )
                installedRestore = BackupArchive.installStaged(
                    staged,
                    mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to restoredDatabase),
                    File(recoveryDirectory, "launcher-db"),
                )
                val restored = RestoreDbTask.performRestore(context, ModelDbController(context))
                if (!restored) {
                    throw BackupArchive.ValidationException(
                        "RestoreDbTask could not apply the launcher database",
                    )
                }
                // RestoreDbTask may consume migration keys; re-assert the
                // intended grid state after preferences are installed.
                if (stagedInfo.gridState.gridSize.isNotBlank()) {
                    DeviceGridState(stagedInfo.gridState).writeToPrefs(context, true)
                }

                if (preferencesSnapshot != null) {
                    closePreferencesDatabaseIfInitialized()
                    preferencesDatabaseClosed = true
                    installedPreferencesDatabase = BackupArchive.installStaged(
                        staged,
                        mapOf(
                            BackupArchive.PREFS_DB_FILE_NAME to
                                prefsDbFile(context),
                        ),
                        File(recoveryDirectory, "preferences-db"),
                    )
                    // Drop the closed Room singleton so a later access cannot
                    // reuse a closed instance.
                    AppDatabase.INSTANCE.reset()
                    preferencesDatabaseClosed = false
                }
                // DataStore is installed last. The successful restore path is
                // immediately followed by restartLauncher(), which kills the
                // process; the restarted process reopens this file. No
                // preference edit is allowed in that window.
                if (staged.files[BackupArchive.PREFS_DATASTORE_FILE_NAME] != null) {
                    installedDataStore = BackupArchive.installStaged(
                        staged,
                        mapOf(
                            BackupArchive.PREFS_DATASTORE_FILE_NAME to
                                prefsDataStoreFile(context),
                        ),
                        File(recoveryDirectory, "preferences-datastore"),
                    )
                }
            }

            installedDataStore?.discard()
            installedPreferencesDatabase?.discard()
            installedRestore?.discard()
            removedDatabases?.discard()
        } catch (t: Throwable) {
            val rollbackFailures = mutableListOf<String>()

            installedDataStore?.rollback()?.let { report ->
                if (!report.succeeded) {
                    rollbackFailures += "preferences datastore: ${report.failures.joinToString("; ")}"
                }
            }
            installedPreferencesDatabase?.rollback()?.let { report ->
                if (!report.succeeded) {
                    rollbackFailures += "preferences database: ${report.failures.joinToString("; ")}"
                }
            }
            if (preferencesDatabaseClosed) {
                AppDatabase.INSTANCE.reset()
            }
            // Delete only the live database this invocation created. Never
            // bulk-delete every grid file in the catch path.
            liveDatabaseName?.let { deleteLauncherDatabase(it) }
            removedDatabases?.rollback()?.let { report ->
                if (!report.succeeded) {
                    rollbackFailures += "launcher databases: ${report.failures.joinToString("; ")}"
                }
            }
            installedRestore?.rollback()?.let { report ->
                if (!report.succeeded) {
                    rollbackFailures += "restored database: ${report.failures.joinToString("; ")}"
                }
            }
            if (preferencesApplied && priorPreferences != null) {
                runCatching { applySharedPreferences(priorPreferences) }
                    .onFailure { rollbackFailures += "shared preferences: ${it.message ?: it}" }
            }
            if (wallpaperApplied) {
                val restoredWallpaper = priorWallpaper
                if (restoredWallpaper == null) {
                    rollbackFailures += "wallpaper: the prior wallpaper could not be captured"
                } else {
                    runCatching {
                        WallpaperManager.getInstance(context).setBitmap(restoredWallpaper)
                    }.onFailure { rollbackFailures += "wallpaper: ${it.message ?: it}" }
                }
            }

            if (rollbackFailures.isEmpty()) {
                throw t
            }
            throw BackupArchive.ValidationException(
                "The restore failed and rollback was incomplete: " +
                    rollbackFailures.joinToString("; "),
                t,
            )
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

    private fun currentLauncherDbName(): String {
        @Suppress("DEPRECATION")
        val configured = LauncherPrefs.get(context).get(LauncherPrefs.DB_FILE)
        return if (configured.isNotBlank()) configured else LauncherAppState.getIDP(context).dbFile
    }

    private fun deleteLauncherDatabase(databaseName: String) {
        val directory = context.getDatabasePath(databaseName).parentFile ?: return
        BackupArchive.DATABASE_SIDECARS.forEach { suffix ->
            runCatching { File(directory, "$databaseName$suffix").delete() }
        }
    }

    @Suppress("DEPRECATION")
    private fun snapshotSharedPreferences(): Map<String, Any> {
        val preferences = LauncherPrefs.getPrefs(context)
        return preferences.all.mapValues { (_, value) ->
            if (value is Set<*>) value.map { it.toString() }.toSet() else value as Any
        }
    }

    @Suppress("DEPRECATION")
    private fun applySharedPreferences(values: Map<String, Any>) {
        val preferences = LauncherPrefs.getPrefs(context)
        val editor = preferences.edit().clear()
        values.forEach { (key, value) ->
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Float -> editor.putFloat(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Set<*> -> editor.putStringSet(key, value.map { it.toString() }.toSet())
                else -> throw BackupArchive.ValidationException(
                    "The restored preferences contain an unsupported value for $key",
                )
            }
        }
        if (!editor.commit()) {
            throw BackupArchive.ValidationException("The restored preferences could not be committed")
        }
    }

    private fun closePreferencesDatabaseIfInitialized() {
        val database = AppDatabase.INSTANCE.peek() ?: return
        database.close()
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
            val wallpaperBitmap = if (BackupArchive.hasFlag(contents, BackupArchive.INCLUDE_WALLPAPER)) {
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
                val temporaryRoot = File(context.cacheDir, "backup-create")
                if (!temporaryRoot.exists() && !temporaryRoot.mkdirs()) {
                    throw IOException("Could not create the backup staging directory")
                }
                val temporaryFile = File(
                    temporaryRoot,
                    "create-${System.currentTimeMillis()}-${STAGING_COUNTER.incrementAndGet()}.lawnchairbackup",
                )
                try {
                    val snapshots = snapshotLayoutEntries(context, plan, temporaryRoot)
                    writeArchive(temporaryFile, backupInfo, plan, screenshotBitmap, wallpaperBitmap, snapshots)
                    copyToDestination(fileUri, temporaryFile, context)
                } finally {
                    runCatching { temporaryFile.delete() }
                    runCatching {
                        if (temporaryRoot.listFiles()?.isEmpty() == true) temporaryRoot.delete()
                    }
                }
            }
        }

        /**
         * Copies every exported layout entry before the archive is written. The
         * databases use the real checkpoint/lock policy in
         * [BackupArchive.snapshotDatabase]; a busy or incomplete WAL fails the
         * export instead of shipping a stale or mixed file.
         */
        private fun snapshotLayoutEntries(
            context: Context,
            plan: BackupArchive.ExportPlan,
            temporaryRoot: File,
        ): Map<String, File> {
            val liveFiles = getFiles(context)
            val snapshots = linkedMapOf<String, File>()
            plan.layoutEntries.forEach { entryName ->
                val liveFile = liveFiles[entryName] ?: return@forEach
                if (!liveFile.isFile) return@forEach
                val snapshot = File(temporaryRoot, "snapshot-$entryName")
                if (entryName == LAUNCHER_DB_FILE_NAME || entryName == PREFS_DB_FILE_NAME) {
                    BackupArchive.snapshotDatabase(
                        AndroidDatabaseSnapshot.source(liveFile),
                        snapshot,
                    )
                } else {
                    liveFile.copyTo(snapshot, overwrite = true)
                }
                snapshots[entryName] = snapshot
            }
            return snapshots
        }

        private fun writeArchive(
            destination: File,
            backupInfo: BackupInfo,
            plan: BackupArchive.ExportPlan,
            screenshotBitmap: Bitmap,
            wallpaperBitmap: Bitmap?,
            layoutSnapshots: Map<String, File>,
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
                        plan.layoutEntries.forEach { entryName ->
                            val file = layoutSnapshots[entryName] ?: return@forEach
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
