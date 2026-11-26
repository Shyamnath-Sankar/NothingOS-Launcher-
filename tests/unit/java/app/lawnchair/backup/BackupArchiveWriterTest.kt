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
import java.nio.file.Files
import java.util.zip.ZipInputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class BackupArchiveWriterTest {

    @Test
    fun infoEntryIsWrittenFirstWithTheExactSerializedBytes() {
        val infoBytes = byteArrayOf(0x08, 0x01, 0x10, 0x02)

        val entries = readZip(writeArchive(infoBytes, emptyList()))

        assertEquals(listOf(BACKUP_INFO_ENTRY_NAME), entries.keys.toList())
        assertArrayEquals(infoBytes, entries.getValue(BACKUP_INFO_ENTRY_NAME))
    }

    @Test
    fun payloadEntriesAreWrittenInOrderWithTheirExactBytes() {
        val archive = writeArchive(
            infoBytes = byteArrayOf(1),
            entries = listOf(
                BackupArchiveEntry("wallpaper.png") { it.write(byteArrayOf(2, 3)) },
                BackupArchiveEntry("screenshot.png") { it.write(byteArrayOf(4, 5, 6)) },
            ),
        )

        val entries = readZip(archive)

        assertEquals(
            listOf(BACKUP_INFO_ENTRY_NAME, "wallpaper.png", "screenshot.png"),
            entries.keys.toList(),
        )
        assertArrayEquals(byteArrayOf(2, 3), entries.getValue("wallpaper.png"))
        assertArrayEquals(byteArrayOf(4, 5, 6), entries.getValue("screenshot.png"))
    }

    @Test
    fun buildBackupEntriesOrdersWallpaperScreenshotThenFiles() {
        val directory = Files.createTempDirectory("backup-entries").toFile()
        try {
            val launcherDb = File(directory, "launcher.db").apply { writeBytes(byteArrayOf(7)) }
            val preferences = File(directory, "preferences").apply { writeBytes(byteArrayOf(8)) }

            val entries = buildBackupEntries(
                includeLayoutAndSettings = true,
                includeWallpaper = true,
                screenshotWriter = BackupEntryWriter { it.write(byteArrayOf(9)) },
                wallpaperWriter = BackupEntryWriter { it.write(byteArrayOf(10)) },
                files = linkedMapOf(
                    "launcher.db" to launcherDb,
                    "preferences" to preferences,
                ),
            )

            assertEquals(
                listOf("wallpaper.png", "screenshot.png", "launcher.db", "preferences"),
                entries.map { it.name },
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun buildBackupEntriesSkipsWallpaperWhenItIsNotRequested() {
        val entries = buildBackupEntries(
            includeLayoutAndSettings = true,
            includeWallpaper = false,
            screenshotWriter = BackupEntryWriter { it.write(byteArrayOf(1)) },
            wallpaperWriter = BackupEntryWriter { it.write(byteArrayOf(2)) },
            files = emptyMap(),
        )

        assertEquals(listOf("screenshot.png"), entries.map { it.name })
    }

    @Test
    fun buildBackupEntriesSkipsWallpaperWhenNoBitmapIsAvailable() {
        val entries = buildBackupEntries(
            includeLayoutAndSettings = false,
            includeWallpaper = true,
            screenshotWriter = BackupEntryWriter { it.write(byteArrayOf(1)) },
            wallpaperWriter = null,
            files = emptyMap(),
        )

        assertEquals(emptyList<String>(), entries.map { it.name })
    }

    @Test
    fun buildBackupEntriesSkipsScreenshotWhenLayoutIsNotRequested() {
        val entries = buildBackupEntries(
            includeLayoutAndSettings = false,
            includeWallpaper = true,
            screenshotWriter = BackupEntryWriter { it.write(byteArrayOf(1)) },
            wallpaperWriter = BackupEntryWriter { it.write(byteArrayOf(2)) },
            files = emptyMap(),
        )

        assertEquals(listOf("wallpaper.png"), entries.map { it.name })
    }

    @Test
    fun buildBackupEntriesKeepsExistingFilesAndSkipsMissingOnes() {
        val directory = Files.createTempDirectory("backup-files").toFile()
        try {
            val existing = File(directory, "launcher.db").apply { writeBytes(byteArrayOf(11, 12)) }
            val missing = File(directory, "preferences")

            val entries = buildBackupEntries(
                includeLayoutAndSettings = false,
                includeWallpaper = false,
                screenshotWriter = BackupEntryWriter { it.write(byteArrayOf(1)) },
                wallpaperWriter = null,
                files = linkedMapOf(
                    "launcher.db" to existing,
                    "preferences" to missing,
                ),
            )

            assertEquals(listOf("launcher.db"), entries.map { it.name })
            val archive = writeArchive(byteArrayOf(0), entries)
            assertArrayEquals(byteArrayOf(11, 12), readZip(archive).getValue("launcher.db"))
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun writeArchive(
        infoBytes: ByteArray,
        entries: List<BackupArchiveEntry>,
    ): ByteArray {
        val output = ByteArrayOutputStream()
        BackupArchiveWriter.write(output, infoBytes, entries)
        return output.toByteArray()
    }

    private fun readZip(archive: ByteArray): LinkedHashMap<String, ByteArray> {
        val entries = linkedMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(archive)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                entries[entry.name] = zip.readBytes()
                entry = zip.nextEntry
            }
        }
        return entries
    }
}
