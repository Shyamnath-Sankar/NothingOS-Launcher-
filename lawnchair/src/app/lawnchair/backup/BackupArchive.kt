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

    /**
     * Tables that the current Room [app.lawnchair.data.AppDatabase] schema may
     * contain. This is the actual shipped schema, not a guess: the JVM test
     * reads `schemas/app.lawnchair.data.AppDatabase/3.json` and fails when this
     * set drifts.
     */
    val PREFERENCES_KNOWN_TABLES: Set<String> =
        setOf("IconOverride", "Wallpapers", "Folders", "FolderItems")

    val PREFERENCES_V2_TABLES: Set<String> =
        setOf("Wallpapers", "Folders", "FolderItems")

    val LAUNCHER_REQUIRED_TABLE = "favorites"
    val LAUNCHER_REQUIRED_COLUMNS: Set<String> = setOf(
        "_id",
        "itemType",
        "container",
        "screen",
        "cellX",
        "cellY",
        "profileId",
    )

    fun hasFlag(contents: Int, flag: Int): Boolean = contents and flag != 0

    data class Limits(
        val maxEntryBytes: Long = MAX_ENTRY_BYTES,
        val maxTotalBytes: Long = MAX_TOTAL_BYTES,
        val maxEntries: Int = MAX_ENTRIES,
    )

    class ValidationException(message: String, cause: Throwable? = null) : Exception(message, cause)

    /**
     * A schema-level view of a staged database. It is intentionally free of
     * Android types so validation and its failure cases run as plain JVM tests.
     */
    data class DatabaseSnapshot(
        val integrityOk: Boolean,
        val userVersion: Int,
        val tables: Set<String>,
        val columns: Map<String, Set<String>>,
    )

    /**
     * The row returned by `pragma wal_checkpoint(...)`. `busy != 0` means a
     * reader/writer prevented a complete checkpoint; `log != checkpointed`
     * means not every WAL frame reached the main database file.
     */
    data class CheckpointResult(
        val busy: Int,
        val log: Int,
        val checkpointed: Int,
    ) {
        val complete: Boolean get() = busy == 0 && log == checkpointed
    }

    /**
     * Abstraction over the real database so the consistency policy is testable
     * without Android. [checkpoint] is a real checkpoint, not a plan flag.
     */
    interface DatabaseSnapshotSource {
        fun checkpoint(): CheckpointResult
        fun walBytes(): Long
        fun <T> withExclusiveWriter(block: () -> T): T
        fun copyMainTo(destination: File)
    }

    data class RollbackReport(
        val attempted: Int,
        val failures: List<String>,
    ) {
        val succeeded: Boolean get() = failures.isEmpty()
    }

    internal class RollbackJournal {
        private val steps = mutableListOf<Pair<String, () -> Unit>>()

        val size: Int get() = steps.size

        fun record(label: String, undo: () -> Unit) {
            steps += label to undo
        }

        fun rollback(): RollbackReport {
            val failures = mutableListOf<String>()
            steps.asReversed().forEach { (label, undo) ->
                try {
                    undo()
                } catch (t: Throwable) {
                    failures += "$label: ${t.message ?: t::class.java.simpleName}"
                }
            }
            return RollbackReport(steps.size, failures)
        }
    }

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

    class InstalledRestore internal constructor(
        private val installedNames: List<String>,
        private val journal: RollbackJournal,
        private val rollbackDirectory: File,
    ) {
        val installedEntryNames: Set<String> get() = installedNames.toSet()

        /** Deletes the rollback copy only after a successful restore. */
        fun discard(): Boolean =
            runCatching { rollbackDirectory.deleteRecursively() }.getOrDefault(false)

        /**
         * Attempts every undo step. The rollback directory is retained when any
         * step fails so the only previous copy is never discarded.
         */
        fun rollback(): RollbackReport {
            val report = journal.rollback()
            if (report.succeeded) {
                runCatching { rollbackDirectory.deleteRecursively() }
            }
            return report
        }
    }

    class RemovedDatabases internal constructor(
        private val journal: RollbackJournal,
        private val rollbackDirectory: File,
    ) {
        fun rollback(): RollbackReport {
            val report = journal.rollback()
            if (report.succeeded) {
                runCatching { rollbackDirectory.deleteRecursively() }
            }
            return report
        }

        fun discard(): Boolean =
            runCatching { rollbackDirectory.deleteRecursively() }.getOrDefault(false)
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

    /** The launcher database must be a real Launcher3 favorites database. */
    fun validateLauncherDatabase(snapshot: DatabaseSnapshot) {
        if (!snapshot.integrityOk) {
            throw ValidationException("The staged launcher database failed its integrity check")
        }
        if (LAUNCHER_REQUIRED_TABLE !in snapshot.tables) {
            throw ValidationException("The staged launcher database has no favorites table")
        }
        val columns = snapshot.columns[LAUNCHER_REQUIRED_TABLE].orEmpty()
        val missing = LAUNCHER_REQUIRED_COLUMNS - columns
        if (missing.isNotEmpty()) {
            throw ValidationException(
                "The staged launcher database is missing favorites columns: " +
                    missing.sorted().joinToString(", "),
            )
        }
    }

    /**
     * The preferences database is the actual Room [app.lawnchair.data.AppDatabase]
     * schema, not the launcher favorites table. Version 1 shipped only
     * `IconOverride`; versions 2 and 3 added the wallpaper and folder tables.
     */
    fun validatePreferencesDatabase(snapshot: DatabaseSnapshot) {
        if (!snapshot.integrityOk) {
            throw ValidationException("The staged preferences database failed its integrity check")
        }
        if (snapshot.userVersion !in MIN_PREFERENCES_VERSION..MAX_PREFERENCES_VERSION) {
            throw ValidationException(
                "The staged preferences database has unsupported schema version " +
                    snapshot.userVersion,
            )
        }
        if ("IconOverride" !in snapshot.tables) {
            throw ValidationException("The staged preferences database has no IconOverride table")
        }
        val unknown = snapshot.tables - PREFERENCES_KNOWN_TABLES
        if (unknown.isNotEmpty()) {
            throw ValidationException(
                "The staged preferences database has unknown tables: " +
                    unknown.sorted().joinToString(", "),
            )
        }
        if (snapshot.userVersion >= 2) {
            val missing = PREFERENCES_V2_TABLES - snapshot.tables
            if (missing.isNotEmpty()) {
                throw ValidationException(
                    "The staged preferences database is missing Room tables: " +
                        missing.sorted().joinToString(", "),
                )
            }
        }
    }

    /**
     * Produces a database file that can be copied without a racing writer.
     *
     * A real `wal_checkpoint(TRUNCATE)` must report a complete checkpoint, then
     * an exclusive writer lock is held while the main file is copied. The WAL is
     * re-checked under that lock: a writer that slipped in makes the snapshot
     * fail instead of exporting a stale or mixed database.
     */
    fun snapshotDatabase(source: DatabaseSnapshotSource, destination: File) {
        val checkpoint = source.checkpoint()
        if (!checkpoint.complete) {
            throw ValidationException(
                "The database WAL checkpoint was incomplete " +
                    "(busy=${checkpoint.busy}, log=${checkpoint.log}, " +
                    "checkpointed=${checkpoint.checkpointed})",
            )
        }
        source.withExclusiveWriter {
            if (source.walBytes() > 0L) {
                throw ValidationException(
                    "The database WAL was not empty after the checkpoint; refusing an " +
                        "inconsistent snapshot",
                )
            }
            destination.parentFile?.mkdirs()
            source.copyMainTo(destination)
            if (!destination.isFile || destination.length() == 0L) {
                throw ValidationException("The database snapshot is empty")
            }
        }
    }

    fun scanArchive(input: InputStream, limits: Limits = Limits()): Inventory {
        val seen = mutableSetOf<String>()
        val relevant = linkedSetOf<String>()
        var count = 0
        var total = 0L
        try {
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
        } catch (validation: ValidationException) {
            throw validation
        } catch (t: Throwable) {
            throw ValidationException("The backup archive could not be read", t)
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
        try {
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
        } catch (validation: ValidationException) {
            throw validation
        } catch (t: Throwable) {
            throw ValidationException("The backup could not be extracted", t)
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
        mover: (File, File) -> Unit = ::move,
    ): RemovedDatabases {
        if (!rollbackDirectory.exists() && !rollbackDirectory.mkdirs()) {
            throw ValidationException("Could not create the backup rollback directory")
        }
        val journal = RollbackJournal()
        try {
            for (databaseName in candidateDatabaseNames) {
                for (suffix in DATABASE_SIDECARS) {
                    val original = File(databaseDirectory, "$databaseName$suffix")
                    if (!original.isFile) continue
                    val previous = File(rollbackDirectory, "$databaseName$suffix")
                    journal.record("restore $databaseName$suffix") {
                        if (previous.exists()) {
                            original.parentFile?.mkdirs()
                            mover(previous, original)
                        }
                    }
                    mover(original, previous)
                }
            }
        } catch (t: Throwable) {
            val report = journal.rollback()
            if (!report.succeeded) {
                throw ValidationException(
                    "Could not remove the launcher databases and rollback was incomplete: " +
                        report.failures.joinToString("; "),
                    t,
                )
            }
            throw t
        }
        return RemovedDatabases(journal, rollbackDirectory)
    }

    fun installStaged(
        staged: StagedRestore,
        targets: Map<String, File>,
        rollbackDirectory: File,
        mover: (File, File) -> Unit = ::move,
    ): InstalledRestore {
        if (!rollbackDirectory.exists() && !rollbackDirectory.mkdirs()) {
            throw ValidationException("Could not create the backup rollback directory")
        }
        val journal = RollbackJournal()
        val installed = mutableListOf<String>()
        try {
            targets.forEach { (entryName, target) ->
                val source = staged.files[entryName] ?: return@forEach
                val previous = File(rollbackDirectory, "$entryName.previous")
                if (target.exists()) {
                    // Register the undo before moving the only existing copy.
                    journal.record("restore previous $entryName") {
                        if (previous.exists()) {
                            target.parentFile?.mkdirs()
                            mover(previous, target)
                        }
                    }
                    mover(target, previous)
                }
                // Register deletion before the replacement can partially appear.
                journal.record("remove installed $entryName") {
                    Files.deleteIfExists(target.toPath())
                }
                target.parentFile?.mkdirs()
                mover(source, target)
                installed += entryName
            }
        } catch (t: Throwable) {
            val report = journal.rollback()
            if (!report.succeeded) {
                throw ValidationException(
                    "Could not install the backup and rollback was incomplete: " +
                        report.failures.joinToString("; "),
                    t,
                )
            }
            throw t
        }
        return InstalledRestore(installed, journal, rollbackDirectory)
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
    private const val MIN_PREFERENCES_VERSION = 1
    private const val MAX_PREFERENCES_VERSION = 3
    private val GRID_SIZE_PATTERN = Regex("\\d{1,3},\\d{1,3}")
}
