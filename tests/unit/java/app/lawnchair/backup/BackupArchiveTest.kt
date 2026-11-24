/*
 * Copyright 2026 the DotWel Launcher project contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app.lawnchair.backup

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class BackupArchiveTest {

    private val layoutEntries = setOf(
        BackupArchive.LAUNCHER_DB_FILE_NAME,
        BackupArchive.PREFS_FILE_NAME,
        BackupArchive.PREFS_DB_FILE_NAME,
        BackupArchive.PREFS_DATASTORE_FILE_NAME,
    )

    @Test
    fun layoutOnlyExportContainsLayoutFilesAndScreenshotButNoWallpaper() {
        val plan = BackupArchive.exportPlan(
            BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS,
            layoutEntries,
            wallpaperAvailable = false,
        )

        assertEquals(BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS, plan.contents)
        assertTrue(plan.includeLayout)
        assertFalse(plan.includeWallpaper)
        assertTrue(plan.includeScreenshot)
        assertTrue(plan.requiresPreferenceCheckpoint)
        assertTrue(plan.requiresLauncherDatabaseCheckpoint)
        assertTrue(plan.entryNames.containsAll(layoutEntries))
        assertTrue(plan.entryNames.contains(BackupArchive.SCREENSHOT_FILE_NAME))
        assertTrue(plan.entryNames.contains(BackupArchive.INFO_FILE_NAME))
        assertFalse(plan.entryNames.contains(BackupArchive.WALLPAPER_FILE_NAME))
    }

    @Test
    fun wallpaperOnlyExportContainsOnlyMetadataAndWallpaper() {
        val plan = BackupArchive.exportPlan(
            BackupArchive.INCLUDE_WALLPAPER,
            layoutEntries,
            wallpaperAvailable = true,
        )

        assertEquals(BackupArchive.INCLUDE_WALLPAPER, plan.contents)
        assertFalse(plan.includeLayout)
        assertFalse(plan.requiresPreferenceCheckpoint)
        assertFalse(plan.requiresLauncherDatabaseCheckpoint)
        assertEquals(
            setOf(BackupArchive.INFO_FILE_NAME, BackupArchive.WALLPAPER_FILE_NAME),
            plan.entryNames,
        )
    }

    @Test
    fun exportWithoutLauncherDatabaseIsRejected() {
        expectValidation {
            BackupArchive.exportPlan(
                BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS,
                setOf(BackupArchive.PREFS_FILE_NAME),
                wallpaperAvailable = false,
            )
        }
    }

    @Test
    fun exportWithUnavailableWallpaperAndNoLayoutIsRejected() {
        expectValidation {
            BackupArchive.exportPlan(
                BackupArchive.INCLUDE_WALLPAPER,
                layoutEntries,
                wallpaperAvailable = false,
            )
        }
    }

    @Test
    fun zeroExportSelectionIsRejected() {
        expectValidation { BackupArchive.exportPlan(0, layoutEntries, wallpaperAvailable = true) }
    }

    @Test
    fun zeroRestoreSelectionIsRejectedBeforeStaging() {
        expectValidation {
            BackupArchive.restorePlan(
                0,
                BackupArchive.SUPPORTED_CONTENTS,
                BackupArchive.RELEVANT_ENTRY_NAMES,
            )
        }
    }

    @Test
    fun unsupportedRestoreSelectionIsRejectedBeforeStaging() {
        expectValidation {
            BackupArchive.restorePlan(
                BackupArchive.INCLUDE_WALLPAPER,
                BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS,
                layoutEntries,
            )
        }
    }

    @Test
    fun wallpaperOnlyRestoreNeverPlansLayoutEntries() {
        val plan = BackupArchive.restorePlan(
            BackupArchive.INCLUDE_WALLPAPER,
            BackupArchive.SUPPORTED_CONTENTS,
            BackupArchive.RELEVANT_ENTRY_NAMES,
        )

        assertEquals(BackupArchive.INCLUDE_WALLPAPER, plan.contents)
        assertFalse(plan.restoreLayout)
        assertTrue(plan.restoreWallpaper)
        assertTrue(plan.layoutEntries.isEmpty())
        assertEquals(
            setOf(BackupArchive.INFO_FILE_NAME, BackupArchive.WALLPAPER_FILE_NAME),
            plan.entryNames,
        )
    }

    @Test
    fun layoutOnlyRestoreNeverPlansWallpaper() {
        val plan = BackupArchive.restorePlan(
            BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS,
            BackupArchive.SUPPORTED_CONTENTS,
            BackupArchive.RELEVANT_ENTRY_NAMES,
        )

        assertEquals(BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS, plan.contents)
        assertTrue(plan.restoreLayout)
        assertFalse(plan.restoreWallpaper)
        assertTrue(plan.layoutEntries.contains(BackupArchive.LAUNCHER_DB_FILE_NAME))
        assertFalse(plan.entryNames.contains(BackupArchive.WALLPAPER_FILE_NAME))
    }

    @Test
    fun restoreRejectsMissingLauncherDatabase() {
        expectValidation {
            BackupArchive.restorePlan(
                BackupArchive.INCLUDE_LAYOUT_AND_SETTINGS,
                BackupArchive.SUPPORTED_CONTENTS,
                setOf(BackupArchive.INFO_FILE_NAME, BackupArchive.PREFS_FILE_NAME),
            )
        }
    }

    @Test
    fun restoreRejectsMissingSelectedWallpaper() {
        expectValidation {
            BackupArchive.restorePlan(
                BackupArchive.INCLUDE_WALLPAPER,
                BackupArchive.SUPPORTED_CONTENTS,
                setOf(BackupArchive.INFO_FILE_NAME),
            )
        }
    }

    @Test
    fun scanRejectsDuplicateRelevantEntries() {
        val bytes = renameEntry(
            renameEntry(
                buildZip(
                    BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
                    "launcher.dc" to byteArrayOf(2),
                    "launcher.dd" to byteArrayOf(3),
                ),
                "launcher.dc",
                BackupArchive.LAUNCHER_DB_FILE_NAME,
            ),
            "launcher.dd",
            BackupArchive.LAUNCHER_DB_FILE_NAME,
        )

        expectValidation { BackupArchive.scanArchive(ByteArrayInputStream(bytes)) }
    }

    @Test
    fun scanRejectsTruncatedArchives() {
        val bytes = buildZip(BackupArchive.INFO_FILE_NAME to ByteArray(4096) { it.toByte() })
        val truncated = bytes.copyOf(bytes.size / 2)

        expectValidation { BackupArchive.scanArchive(ByteArrayInputStream(truncated)) }
    }

    @Test
    fun scanRejectsOversizedRelevantEntries() {
        val bytes = buildZip(BackupArchive.INFO_FILE_NAME to ByteArray(2048))

        expectValidation {
            BackupArchive.scanArchive(
                ByteArrayInputStream(bytes),
                BackupArchive.Limits(maxEntryBytes = 1024, maxTotalBytes = 100000, maxEntries = 32),
            )
        }
    }

    @Test
    fun scanRejectsPathTraversalEntryNames() {
        val bytes = buildZip(
            BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
            "../outside" to byteArrayOf(2),
        )

        expectValidation { BackupArchive.scanArchive(ByteArrayInputStream(bytes)) }
    }

    @Test
    fun scanIgnoresUnknownEntriesButKeepsTheExactAllowlist() {
        val bytes = buildZip(
            BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
            "notes.txt" to byteArrayOf(2),
        )

        val inventory = BackupArchive.scanArchive(ByteArrayInputStream(bytes))

        assertTrue(inventory.entryNames.contains("notes.txt"))
        assertEquals(setOf(BackupArchive.INFO_FILE_NAME), inventory.relevantEntryNames)
    }

    @Test
    fun extractWallpaperOnlyDoesNotStageLayoutOrPreferences() {
        val bytes = buildZip(
            BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
            BackupArchive.WALLPAPER_FILE_NAME to byteArrayOf(2),
            BackupArchive.LAUNCHER_DB_FILE_NAME to byteArrayOf(3),
            BackupArchive.PREFS_FILE_NAME to byteArrayOf(4),
            "unknown.bin" to byteArrayOf(5),
        )
        val plan = BackupArchive.restorePlan(
            BackupArchive.INCLUDE_WALLPAPER,
            BackupArchive.SUPPORTED_CONTENTS,
            BackupArchive.RELEVANT_ENTRY_NAMES,
        )
        withTempDirectory { dir ->
            val staged = BackupArchive.extractSelected(ByteArrayInputStream(bytes), dir, plan)

            assertEquals(
                setOf(BackupArchive.INFO_FILE_NAME, BackupArchive.WALLPAPER_FILE_NAME),
                staged.files.keys,
            )
            assertFalse(File(dir, BackupArchive.LAUNCHER_DB_FILE_NAME).exists())
            assertFalse(File(dir, BackupArchive.PREFS_FILE_NAME).exists())
            assertFalse(File(dir, "unknown.bin").exists())
        }
    }

    @Test
    fun extractRejectsMissingRequiredEntry() {
        val bytes = buildZip(BackupArchive.INFO_FILE_NAME to byteArrayOf(1))
        val plan = BackupArchive.restorePlan(
            BackupArchive.INCLUDE_WALLPAPER,
            BackupArchive.SUPPORTED_CONTENTS,
            BackupArchive.RELEVANT_ENTRY_NAMES,
        )

        expectValidation {
            withTempDirectory { dir ->
                BackupArchive.extractSelected(ByteArrayInputStream(bytes), dir, plan)
            }
        }
    }

    @Test
    fun truncatedExtractionFailsAndStagingIsCleaned() {
        val bytes = buildZip(
            BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
            BackupArchive.WALLPAPER_FILE_NAME to ByteArray(64 * 1024),
        )
        val truncated = bytes.copyOf(bytes.size - 200)
        val plan = BackupArchive.restorePlan(
            BackupArchive.INCLUDE_WALLPAPER,
            BackupArchive.SUPPORTED_CONTENTS,
            BackupArchive.RELEVANT_ENTRY_NAMES,
        )
        val root = Files.createTempDirectory("backup-staging-root").toFile()
        val runDirectory = File(root, "run")
        try {
            try {
                BackupArchive.extractSelected(ByteArrayInputStream(truncated), runDirectory, plan)
                fail("Expected truncated archive to fail")
            } catch (_: BackupArchive.ValidationException) {
            }

            BackupArchive.deleteStaging(root, runDirectory)

            assertFalse(runDirectory.exists())
            assertTrue(root.exists())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun deleteStagingRefusesToDeleteOutsideItsRoot() {
        val root = Files.createTempDirectory("backup-staging-root").toFile()
        val outside = Files.createTempDirectory("backup-outside").toFile()
        val sentinel = File(outside, "keep.txt").apply { writeText("keep") }
        try {
            BackupArchive.deleteStaging(root, outside)
            assertTrue(sentinel.exists())
        } finally {
            root.deleteRecursively()
            outside.deleteRecursively()
        }
    }

    @Test
    fun wallpaperOnlyInstallLeavesLiveDatabaseAndPreferencesUntouched() {
        withTempDirectory { live ->
            val launcherDb = File(live, "launcher.db").apply { writeText("layout") }
            val preferences = File(live, "preferences").apply { writeText("settings") }
            val bytes = buildZip(
                BackupArchive.INFO_FILE_NAME to byteArrayOf(1),
                BackupArchive.WALLPAPER_FILE_NAME to byteArrayOf(2),
            )
            val plan = BackupArchive.restorePlan(
                BackupArchive.INCLUDE_WALLPAPER,
                BackupArchive.SUPPORTED_CONTENTS,
                BackupArchive.RELEVANT_ENTRY_NAMES,
            )
            val stage = File(live, "stage")
            val rollback = File(live, "rollback")
            val staged = BackupArchive.extractSelected(ByteArrayInputStream(bytes), stage, plan)
            val installed = BackupArchive.installStaged(
                staged,
                mapOf(BackupArchive.WALLPAPER_FILE_NAME to File(live, "wallpaper.png")),
                rollback,
            )

            assertEquals("layout", launcherDb.readText())
            assertEquals("settings", preferences.readText())
            assertEquals(setOf(BackupArchive.WALLPAPER_FILE_NAME), installed.installedEntryNames)
        }
    }

    @Test
    fun removingLauncherDatabasesPreservesUnrelatedDatabases() {
        withTempDirectory { root ->
            val databases = File(root, "databases").apply { mkdirs() }
            val launcher = File(databases, "launcher_4_by_6.db").apply { writeText("layout") }
            val launcherWal = File(databases, "launcher_4_by_6.db-wal").apply { writeText("wal") }
            val preferences = File(databases, "preferences").apply { writeText("settings") }
            val widgetPreviews = File(databases, "widgetpreviews.db").apply { writeText("previews") }
            val rollback = File(root, "rollback")

            val removed = BackupArchive.removeLauncherDatabases(
                databases,
                setOf("launcher_4_by_6.db"),
                rollback,
            )

            assertFalse(launcher.exists())
            assertFalse(launcherWal.exists())
            assertEquals("settings", preferences.readText())
            assertEquals("previews", widgetPreviews.readText())

            removed.rollback()

            assertEquals("layout", launcher.readText())
            assertEquals("wal", launcherWal.readText())
            assertEquals("settings", preferences.readText())
        }
    }

    @Test
    fun metadataValidationAcceptsCurrentAndLegacyButRejectsUnknownAndMalformed() {
        BackupArchive.validateMetadata(BackupArchive.BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "4,6", 5)
        BackupArchive.validateMetadata(BackupArchive.LEGACY_BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "4,6", 5)
        BackupArchive.validateMetadata(BackupArchive.LEGACY_BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "", 5)

        expectValidation { BackupArchive.validateMetadata(99, BackupArchive.SUPPORTED_CONTENTS, "4,6", 5) }
        expectValidation { BackupArchive.validateMetadata(BackupArchive.BACKUP_VERSION, 0, "4,6", 5) }
        expectValidation {
            BackupArchive.validateMetadata(BackupArchive.BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "", 5)
        }
        expectValidation {
            BackupArchive.validateMetadata(BackupArchive.BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "wide", 5)
        }
        expectValidation {
            BackupArchive.validateMetadata(BackupArchive.BACKUP_VERSION, BackupArchive.SUPPORTED_CONTENTS, "4,6", -1)
        }
    }

    @Test
    fun launcherSchemaAcceptsFavoritesAndRejectsAWrongOrCorruptDatabase() {
        BackupArchive.validateLauncherDatabase(launcherSnapshot())

        expectValidation {
            BackupArchive.validateLauncherDatabase(launcherSnapshot(integrityOk = false))
        }
        expectValidation {
            BackupArchive.validateLauncherDatabase(launcherSnapshot(tables = setOf("other")))
        }
        expectValidation {
            BackupArchive.validateLauncherDatabase(
                launcherSnapshot(columns = setOf("_id", "itemType")),
            )
        }
    }

    @Test
    fun preferencesSchemaUsesTheActualRoomSchemaNotLauncherFavorites() {
        BackupArchive.validatePreferencesDatabase(preferencesSnapshot(version = 3))
        BackupArchive.validatePreferencesDatabase(
            preferencesSnapshot(version = 1, tables = setOf("IconOverride")),
        )

        // A valid launcher database is not a valid preferences database.
        expectValidation {
            BackupArchive.validatePreferencesDatabase(
                BackupArchive.DatabaseSnapshot(
                    integrityOk = true,
                    userVersion = 0,
                    tables = setOf("favorites"),
                    columns = mapOf("favorites" to BackupArchive.LAUNCHER_REQUIRED_COLUMNS),
                ),
            )
        }
        expectValidation {
            BackupArchive.validatePreferencesDatabase(preferencesSnapshot(integrityOk = false))
        }
        expectValidation {
            BackupArchive.validatePreferencesDatabase(
                preferencesSnapshot(tables = setOf("IconOverride", "unknown")),
            )
        }
        expectValidation {
            BackupArchive.validatePreferencesDatabase(
                preferencesSnapshot(version = 3, tables = setOf("IconOverride")),
            )
        }
        expectValidation {
            BackupArchive.validatePreferencesDatabase(preferencesSnapshot(version = 4))
        }
    }

    @Test
    fun preferencesSchemaConstantsMatchTheShippedRoomJson() {
        assertEquals(BackupArchive.PREFERENCES_KNOWN_TABLES, schemaTables(3))
        assertEquals(setOf("IconOverride"), schemaTables(1))
        assertTrue(
            BackupArchive.PREFERENCES_KNOWN_TABLES.containsAll(BackupArchive.PREFERENCES_V2_TABLES),
        )
    }

    @Test
    fun snapshotFailsOnBusyCheckpointWithoutCopying() {
        val source = FakeSnapshotSource(
            checkpoint = BackupArchive.CheckpointResult(busy = 1, log = 5, checkpointed = 2),
            walBytes = 0,
        )
        withTempDirectory { root ->
            val destination = File(root, "snapshot.db")
            expectValidation { BackupArchive.snapshotDatabase(source, destination) }
            assertFalse(source.copied)
            assertFalse(destination.exists())
        }
    }

    @Test
    fun snapshotFailsWhenTheWalIsNotEmptyUnderTheLock() {
        val source = FakeSnapshotSource(
            checkpoint = BackupArchive.CheckpointResult(busy = 0, log = 5, checkpointed = 5),
            walBytes = 32,
        )
        withTempDirectory { root ->
            expectValidation {
                BackupArchive.snapshotDatabase(source, File(root, "snapshot.db"))
            }
            assertFalse(source.copied)
        }
    }

    @Test
    fun snapshotCopiesOnlyAfterACompleteCheckpoint() {
        val source = FakeSnapshotSource(
            checkpoint = BackupArchive.CheckpointResult(busy = 0, log = 0, checkpointed = 0),
            walBytes = 0,
        )
        withTempDirectory { root ->
            val destination = File(root, "snapshot.db")
            BackupArchive.snapshotDatabase(source, destination)
            assertTrue(source.copied)
            assertEquals("snapshot", destination.readText())
        }
    }

    @Test
    fun installRegistersUndoBeforeMovingTheOriginal() {
        withTempDirectory { root ->
            val target = File(root, "live/launcher.db").apply {
                parentFile?.mkdirs()
                writeText("original")
            }
            val stage = File(root, "stage").apply { mkdirs() }
            val source = File(stage, BackupArchive.LAUNCHER_DB_FILE_NAME).apply {
                writeText("replacement")
            }
            val staged = BackupArchive.StagedRestore(
                stage,
                mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to source),
            )
            val failure = runCatching {
                BackupArchive.installStaged(
                    staged,
                    mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to target),
                    File(root, "rollback"),
                ) { from, to ->
                    if (from == source) throw IOException("replacement move failed")
                    Files.move(from.toPath(), to.toPath())
                }
            }.exceptionOrNull()

            assertNotNull(failure)
            assertEquals("original", target.readText())
        }
    }

    @Test
    fun installRollsBackEarlierFilesWhenALaterMoveFails() {
        withTempDirectory { root ->
            val live = File(root, "live").apply { mkdirs() }
            val targetA = File(live, "a.db").apply { writeText("original-a") }
            val targetB = File(live, "b.db").apply { writeText("original-b") }
            val stage = File(root, "stage").apply { mkdirs() }
            val sourceA = File(stage, "a.db").apply { writeText("new-a") }
            val sourceB = File(stage, "b.db").apply { writeText("new-b") }
            val staged = BackupArchive.StagedRestore(
                stage,
                linkedMapOf("a.db" to sourceA, "b.db" to sourceB),
            )
            val failure = runCatching {
                BackupArchive.installStaged(
                    staged,
                    linkedMapOf("a.db" to targetA, "b.db" to targetB),
                    File(root, "rollback"),
                ) { from, to ->
                    if (from == targetB) throw IOException("original B move failed")
                    Files.move(from.toPath(), to.toPath())
                }
            }.exceptionOrNull()

            assertNotNull(failure)
            assertEquals("original-a", targetA.readText())
            assertEquals("original-b", targetB.readText())
        }
    }

    @Test
    fun installRetainsThePreviousCopyWhenRollbackFails() {
        withTempDirectory { root ->
            val target = File(root, "live/launcher.db").apply {
                parentFile?.mkdirs()
                writeText("original")
            }
            val stage = File(root, "stage").apply { mkdirs() }
            val source = File(stage, BackupArchive.LAUNCHER_DB_FILE_NAME).apply {
                writeText("replacement")
            }
            val staged = BackupArchive.StagedRestore(
                stage,
                mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to source),
            )
            val rollback = File(root, "rollback")
            val failure = runCatching {
                BackupArchive.installStaged(
                    staged,
                    mapOf(BackupArchive.LAUNCHER_DB_FILE_NAME to target),
                    rollback,
                ) { from, to ->
                    if (from == source) throw IOException("install failed")
                    if (from.name.endsWith(".previous")) throw IOException("rollback failed")
                    Files.move(from.toPath(), to.toPath())
                }
            }.exceptionOrNull()

            assertTrue(failure is BackupArchive.ValidationException)
            val previous = File(rollback, "${BackupArchive.LAUNCHER_DB_FILE_NAME}.previous")
            assertTrue("the only previous copy must be retained", previous.exists())
            assertEquals("original", previous.readText())
            assertFalse(target.exists())
        }
    }

    @Test
    fun removeLauncherDatabasesRollsBackEarlierMovesOnFailure() {
        withTempDirectory { root ->
            val databases = File(root, "databases").apply { mkdirs() }
            val databaseA = File(databases, "launcher_a.db").apply { writeText("a") }
            val databaseB = File(databases, "launcher_b.db").apply { writeText("b") }
            val failure = runCatching {
                BackupArchive.removeLauncherDatabases(
                    databases,
                    linkedSetOf("launcher_a.db", "launcher_b.db"),
                    File(root, "rollback"),
                ) { from, to ->
                    if (from == databaseB) throw IOException("second original move failed")
                    Files.move(from.toPath(), to.toPath())
                }
            }.exceptionOrNull()

            assertNotNull(failure)
            assertEquals("a", databaseA.readText())
            assertEquals("b", databaseB.readText())
        }
    }

    @Test
    fun stagingCleanupNeverDeletesTheRecoverySibling() {
        withTempDirectory { root ->
            val run = File(root, "run").apply { mkdirs() }
            val recovery = File(root, "recovery-run").apply { mkdirs() }
            val previous = File(recovery, "launcher.db.previous").apply { writeText("original") }

            BackupArchive.deleteStaging(root, run)

            assertFalse(run.exists())
            assertTrue(previous.exists())
            assertEquals("original", previous.readText())
        }
    }

    private fun launcherSnapshot(
        integrityOk: Boolean = true,
        tables: Set<String> = setOf("favorites"),
        columns: Set<String> = BackupArchive.LAUNCHER_REQUIRED_COLUMNS,
    ): BackupArchive.DatabaseSnapshot = BackupArchive.DatabaseSnapshot(
        integrityOk = integrityOk,
        userVersion = 0,
        tables = tables,
        columns = mapOf("favorites" to columns),
    )

    private fun preferencesSnapshot(
        version: Int = 3,
        integrityOk: Boolean = true,
        tables: Set<String> = BackupArchive.PREFERENCES_KNOWN_TABLES,
    ): BackupArchive.DatabaseSnapshot = BackupArchive.DatabaseSnapshot(
        integrityOk = integrityOk,
        userVersion = version,
        tables = tables,
        columns = tables.associateWith { emptySet() },
    )

    private fun schemaTables(version: Int): Set<String> {
        val text = findSchema(version).readText()
        return Regex("\"tableName\"\\s*:\\s*\"([^\"]+)\"")
            .findAll(text)
            .map { it.groupValues[1] }
            .toSet()
    }

    private fun findSchema(version: Int): File {
        var directory: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (directory != null) {
            val candidate = File(
                directory,
                "schemas/app.lawnchair.data.AppDatabase/$version.json",
            )
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        throw AssertionError("Could not find schemas/app.lawnchair.data.AppDatabase/$version.json")
    }

    private class FakeSnapshotSource(
        private val checkpoint: BackupArchive.CheckpointResult,
        private val walBytes: Long,
    ) : BackupArchive.DatabaseSnapshotSource {
        var copied = false

        override fun checkpoint(): BackupArchive.CheckpointResult = checkpoint

        override fun walBytes(): Long = walBytes

        override fun <T> withExclusiveWriter(block: () -> T): T = block()

        override fun copyMainTo(destination: File) {
            copied = true
            destination.writeText("snapshot")
        }
    }

    private fun buildZip(vararg entries: Pair<String, ByteArray>): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return output.toByteArray()
    }

    private fun renameEntry(bytes: ByteArray, from: String, to: String): ByteArray {
        require(from.length == to.length)
        val text = String(bytes, Charsets.ISO_8859_1)
        return text.replace(from, to).toByteArray(Charsets.ISO_8859_1)
    }

    private fun expectValidation(block: () -> Unit) {
        try {
            block()
            fail("Expected a BackupArchive.ValidationException")
        } catch (_: BackupArchive.ValidationException) {
        }
    }

    private inline fun withTempDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("backup-archive-test").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}
