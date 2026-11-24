package app.lawnchair.backup

import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.ZipInputStream

object BackupArchive {
    const val BACKUP_VERSION = 1
    const val LEGACY_BACKUP_VERSION = 0
    const val INCLUDE_LAYOUT_AND_SETTINGS = 1 shl 0
    const val INCLUDE_WALLPAPER = 1 shl 1
    const val SUPPORTED_CONTENTS = INCLUDE_LAYOUT_AND_SETTINGS or INCLUDE_WALLPAPER

    const val INFO_FILE_NAME = "info.pb"
    const val WALLPAPER_FILE_NAME = "wallpaper.png"
    const val SCREENSHOT_FILE_NAME = "screenshot.png"
    const val LAUNCHER_DB_FILE_NAME = "launcher.db"
    const val RESTORED_DB_FILE_NAME = "restored.db"
    const val PREFS_FILE_NAME = "com.android.launcher3.prefs.xml"
    const val PREFS_DB_FILE_NAME = "preferences"
    const val PREFS_DATASTORE_FILE_NAME = "preferences.preferences_pb"

    val LAYOUT_ENTRY_NAMES: Set<String> = setOf(
        LAUNCHER_DB_FILE_NAME,
        PREFS_FILE_NAME,
        PREFS_DB_FILE_NAME,
        PREFS_DATASTORE_FILE_NAME,
    )

    val RELEVANT_ENTRY_NAMES: Set<String> = LAYOUT_ENTRY_NAMES + setOf(
        INFO_FILE_NAME,
        WALLPAPER_FILE_NAME,
        SCREENSHOT_FILE_NAME,
    )

    val DATABASE_SIDECARS: List<String> = listOf("", "-wal", "-shm", "-journal")

    const val MAX_ENTRY_BYTES = 512L * 1024L * 1024L
    const val MAX_TOTAL_BYTES = 768L * 1024L * 1024L
    const val MAX_ENTRIES = 64

    fun hasFlag(contents: Int, flag: Int): Boolean = contents and flag != 0

    data class Limits(
        val maxEntryBytes: Long = MAX_ENTRY_BYTES,
        val maxTotalBytes: Long = MAX_TOTAL_BYTES,
        val maxEntries: Int = MAX_ENTRIES,
    )

    class ValidationException(message: String, cause: Throwable? = null) : Exception(message, cause)

    data class ExportPlan(
        val contents: Int,
        val layoutEntries: Set<String>,
    ) {
        val includeLayout: Boolean get() = hasFlag(contents, INCLUDE_LAYOUT_AND_SETTINGS)
        val includeWallpaper: Boolean get() = hasFlag(contents, INCLUDE_WALLPAPER)
        val includeScreenshot: Boolean get() = includeLayout
        val requiresPreferenceCheckpoint: Boolean get() = includeLayout
        val requiresLauncherDatabaseCheckpoint: Boolean get() = includeLayout

        val entryNames: Set<String>
            get() = buildSet {
                add(INFO_FILE_NAME)
                if (includeLayout) {
                    addAll(layoutEntries)
                    add(SCREENSHOT_FILE_NAME)
                }
                if (includeWallpaper) {
                    add(WALLPAPER_FILE_NAME)
                }
            }
    }

    data class RestorePlan(
        val contents: Int,
        val layoutEntries: Set<String>,
    ) {
        val restoreLayout: Boolean get() = hasFlag(contents, INCLUDE_LAYOUT_AND_SETTINGS)
        val restoreWallpaper: Boolean get() = hasFlag(contents, INCLUDE_WALLPAPER)

        val entryNames: Set<String>
            get() = buildSet {
                add(INFO_FILE_NAME)
                if (restoreLayout) {
                    addAll(layoutEntries)
                }
                if (restoreWallpaper) {
                    add(WALLPAPER_FILE_NAME)
                }
            }
    }

    data class Inventory(
        val entryNames: Set<String>,
        val relevantEntryNames: Set<String>,
    )

    data class StagedRestore(
        val directory: File,
        val files: Map<String, File>,
    ) {
        fun file(name: String): File = files[name]
            ?: throw ValidationException("Backup does not contain the required $name entry")

        val layoutEntries: Set<String> get() = files.keys intersect LAYOUT_ENTRY_NAMES
    }

    data class InstalledFile(
        val entryName: String,
        val target: File,
        val previous: File?,
    )

    class InstalledRestore internal constructor(
        private val installed: List<InstalledFile>,
        private val rollbackDirectory: File,
    ) {
        val installedEntryNames: Set<String> get() = installed.map { it.entryName }.toSet()

        fun discard() {
            runCatching { rollbackDirectory.deleteRecursively() }
        }

        fun rollback() {
            installed.asReversed().forEach { file ->
                runCatching { Files.deleteIfExists(file.target.toPath()) }
                file.previous?.let { previous ->
                    if (previous.exists()) {
                        file.target.parentFile?.mkdirs()
                        move(previous, file.target)
                    }
                }
            }
            runCatching { rollbackDirectory.deleteRecursively() }
        }
    }

    class RemovedDatabases internal constructor(
        private val moved: List<Pair<File, File>>,
        private val rollbackDirectory: File,
    ) {
        fun rollback() {
            moved.asReversed().forEach { (original, previous) ->
                if (previous.exists()) {
                    original.parentFile?.mkdirs()
                    move(previous, original)
                }
            }
            runCatching { rollbackDirectory.deleteRecursively() }
        }

        fun discard() {
            runCatching { rollbackDirectory.deleteRecursively() }
        }
    }

    fun exportPlan(
        requested: Int,
        existingLayoutEntries: Set<String>,
        wallpaperAvailable: Boolean,
    ): ExportPlan {
        var contents = requested and SUPPORTED_CONTENTS
        if (!wallpaperAvailable) {
            contents = contents and INCLUDE_WALLPAPER.inv()
        }
        if (contents == 0) {
            throw ValidationException("No supported backup contents were selected")
        }
        val layoutEntries = if (hasFlag(contents, INCLUDE_LAYOUT_AND_SETTINGS)) {
            val selected = existingLayoutEntries intersect LAYOUT_ENTRY_NAMES
            if (LAUNCHER_DB_FILE_NAME !in selected) {
                throw ValidationException("The launcher database is not available for backup")
            }
            selected
        } else {
            emptySet()
        }
        return ExportPlan(contents, layoutEntries)
    }

    fun restorePlan(
        requested: Int,
        archiveSupportedContents: Int,
        archiveRelevantEntries: Set<String>,
    ): RestorePlan {
        val contents = requested and archiveSupportedContents and SUPPORTED_CONTENTS
        if (contents == 0) {
            throw ValidationException("No selected content is supported by this backup")
        }
        val layoutEntries = if (hasFlag(contents, INCLUDE_LAYOUT_AND_SETTINGS)) {
            if (LAUNCHER_DB_FILE_NAME !in archiveRelevantEntries) {
                throw ValidationException("The backup is missing the launcher database")
            }
            LAYOUT_ENTRY_NAMES intersect archiveRelevantEntries
        } else {
            emptySet()
        }
        if (hasFlag(contents, INCLUDE_WALLPAPER) && WALLPAPER_FILE_NAME !in archiveRelevantEntries) {
            throw ValidationException("The backup is missing the selected wallpaper")
        }
        return RestorePlan(contents, layoutEntries)
    }

    fun validateMetadata(
        backupVersion: Int,
        contents: Int,
        gridSize: String,
        hotseatCount: Int,
    ) {
        if (backupVersion != BACKUP_VERSION && backupVersion != LEGACY_BACKUP_VERSION) {
            throw ValidationException("Unsupported backup version $backupVersion")
        }
        if (contents and SUPPORTED_CONTENTS == 0) {
            throw ValidationException("The backup does not contain any supported content")
        }
        if (gridSize.isBlank()) {
            if (backupVersion != LEGACY_BACKUP_VERSION) {
                throw ValidationException("The backup has malformed grid metadata")
            }
        } else if (!GRID_SIZE_PATTERN.matches(gridSize)) {
            throw ValidationException("The backup has malformed grid metadata")
        }
        if (hotseatCount < 0 || hotseatCount > MAX_HOTSEAT_COUNT) {
            throw ValidationException("The backup has malformed hotseat metadata")
        }
    }

    fun scanArchive(input: InputStream, limits: Limits = Limits()): Inventory {
        val seen = mutableSetOf<String>()
        val relevant = linkedSetOf<String>()
        var count = 0
        var total = 0L
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name ?: throw ValidationException("Backup entry has no name")
                validateEntryName(name)
                count++
                if (count > limits.maxEntries) {
                    throw ValidationException("The backup contains too many entries")
                }
                val size = drainBounded(zip, limits.maxEntryBytes, limits.maxTotalBytes - total)
                total += size
                if (!seen.add(name) && name in RELEVANT_ENTRY_NAMES) {
                    throw ValidationException("The backup contains a duplicate $name entry")
                }
                if (name in RELEVANT_ENTRY_NAMES) {
                    relevant.add(name)
                }
            }
        }
        if (INFO_FILE_NAME !in relevant) {
            throw ValidationException("The backup is missing its metadata")
        }
        return Inventory(seen.toSet(), relevant.toSet())
    }

    fun extractSelected(
        input: InputStream,
        stageDirectory: File,
        plan: RestorePlan,
        limits: Limits = Limits(),
    ): StagedRestore {
        if (!stageDirectory.exists() && !stageDirectory.mkdirs()) {
            throw ValidationException("Could not create the backup staging directory")
        }
        val wanted = plan.entryNames
        val written = linkedMapOf<String, File>()
        var total = 0L
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name ?: throw ValidationException("Backup entry has no name")
                validateEntryName(name)
                if (name !in wanted) {
                    total += drainBounded(zip, limits.maxEntryBytes, limits.maxTotalBytes - total)
                    continue
                }
                if (name in written) {
                    throw ValidationException("The backup contains a duplicate $name entry")
                }
                val destination = File(stageDirectory, name)
                val size = stageEntry(zip, destination, limits.maxEntryBytes, limits.maxTotalBytes - total)
                total += size
                written[name] = destination
            }
        }
        wanted.forEach { name ->
            val file = written[name]
            if (file == null || !file.isFile || file.length() == 0L) {
                throw ValidationException("The backup is missing the required $name entry")
            }
        }
        return StagedRestore(stageDirectory, written)
    }

    fun removeLauncherDatabases(
        databaseDirectory: File,
        candidateDatabaseNames: Set<String>,
        rollbackDirectory: File,
    ): RemovedDatabases {
        if (!rollbackDirectory.exists() && !rollbackDirectory.mkdirs()) {
            throw ValidationException("Could not create the backup rollback directory")
        }
        val moved = mutableListOf<Pair<File, File>>()
        candidateDatabaseNames.forEach { databaseName ->
            DATABASE_SIDECARS.forEach { suffix ->
                val original = File(databaseDirectory, "$databaseName$suffix")
                if (!original.isFile) return@forEach
                val previous = File(rollbackDirectory, "$databaseName$suffix")
                move(original, previous)
                moved += original to previous
            }
        }
        return RemovedDatabases(moved, rollbackDirectory)
    }

    fun installStaged(
        staged: StagedRestore,
        targets: Map<String, File>,
        rollbackDirectory: File,
    ): InstalledRestore {
        if (!rollbackDirectory.exists() && !rollbackDirectory.mkdirs()) {
            throw ValidationException("Could not create the backup rollback directory")
        }
        val installed = mutableListOf<InstalledFile>()
        try {
            targets.forEach { (entryName, target) ->
                val source = staged.files[entryName] ?: return@forEach
                val previous = if (target.exists()) {
                    val copy = File(rollbackDirectory, "$entryName.previous")
                    move(target, copy)
                    copy
                } else {
                    null
                }
                target.parentFile?.mkdirs()
                move(source, target)
                installed += InstalledFile(entryName, target, previous)
            }
        } catch (t: Throwable) {
            InstalledRestore(installed, rollbackDirectory).rollback()
            throw t
        }
        return InstalledRestore(installed, rollbackDirectory)
    }

    fun deleteStaging(root: File, runDirectory: File) {
        val canonicalRoot = runCatching { root.canonicalFile }.getOrNull() ?: return
        val canonicalRun = runCatching { runDirectory.canonicalFile }.getOrNull() ?: return
        if (canonicalRun == canonicalRoot) return
        if (!canonicalRun.path.startsWith(canonicalRoot.path + File.separator)) return
        canonicalRun.deleteRecursively()
    }

    private fun validateEntryName(name: String) {
        if (name.isEmpty() || name.length > MAX_ENTRY_NAME_LENGTH) {
            throw ValidationException("The backup contains an invalid entry name")
        }
        if (name.startsWith("/") || name.contains('\\') || name.contains('\u0000')) {
            throw ValidationException("The backup contains an unsafe entry name")
        }
        val parts = name.split('/')
        if (parts.any { it == ".." || it == "." }) {
            throw ValidationException("The backup contains a path traversal entry")
        }
    }

    private fun drainBounded(input: InputStream, maxEntryBytes: Long, maxRemainingTotalBytes: Long): Long {
        if (maxRemainingTotalBytes <= 0L) {
            throw ValidationException("The backup exceeds the allowed size")
        }
        val buffer = ByteArray(BUFFER_SIZE)
        var count = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            count += read
            if (count > maxEntryBytes) {
                throw ValidationException("A backup entry exceeds the allowed size")
            }
            if (count > maxRemainingTotalBytes) {
                throw ValidationException("The backup exceeds the allowed size")
            }
        }
        return count
    }

    private fun stageEntry(
        input: InputStream,
        destination: File,
        maxEntryBytes: Long,
        maxRemainingTotalBytes: Long,
    ): Long {
        if (maxRemainingTotalBytes <= 0L) {
            throw ValidationException("The backup exceeds the allowed size")
        }
        val buffer = ByteArray(BUFFER_SIZE)
        var count = 0L
        destination.outputStream().buffered().use { output ->
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                count += read
                if (count > maxEntryBytes) {
                    throw ValidationException("A backup entry exceeds the allowed size")
                }
                if (count > maxRemainingTotalBytes) {
                    throw ValidationException("The backup exceeds the allowed size")
                }
                output.write(buffer, 0, read)
            }
        }
        return count
    }

    private fun move(source: File, target: File) {
        val path = source.toPath()
        val targetPath = target.toPath()
        runCatching {
            Files.move(path, targetPath, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        }.getOrElse {
            Files.move(path, targetPath, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private const val BUFFER_SIZE = 16 * 1024
    private const val MAX_ENTRY_NAME_LENGTH = 255
    private const val MAX_HOTSEAT_COUNT = 20
    private val GRID_SIZE_PATTERN = Regex("\\d{1,3},\\d{1,3}")
}
