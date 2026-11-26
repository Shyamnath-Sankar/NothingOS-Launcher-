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

import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BackupArchiveTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `round trip preserves every entry and writes a manifest`() {
        val archive = temporaryFolder.newFile("backup.zip")
        val entries = linkedMapOf(
            "launcher.db" to "database".toByteArray(),
            "preferences.xml" to "<prefs/>".toByteArray(),
            "preferences.preferences_pb" to byteArrayOf(1, 2, 3, 4),
        )

        BackupArchive.write(archive, entries.map { ArchiveSource.fromBytes(it.key, it.value) })

        val manifest = BackupArchive.validate(archive, entries.keys)
        assertEquals(entries.keys, manifest.entries.keys)
        entries.forEach { (name, bytes) ->
            assertEquals(bytes.size.toLong(), manifest.entries.getValue(name).size)
        }
        val staging = temporaryFolder.newFolder("staging")
        BackupArchive.extract(archive, manifest, staging)
        entries.forEach { (name, bytes) ->
            assertArrayEquals(bytes, File(staging, name).readBytes())
        }
        assertTrue(manifest.entries.keys.containsAll(entries.keys))
    }

    @Test
    fun `write never modifies the source files`() {
        val source = temporaryFolder.newFile("launcher.db").apply { writeBytes("original".toByteArray()) }
        val before = source.readBytes()
        val beforeModified = source.lastModified()
        val archive = temporaryFolder.newFile("backup.zip")

        BackupArchive.write(archive, listOf(ArchiveSource.fromFile("launcher.db", source)))

        assertArrayEquals(before, source.readBytes())
        assertEquals(beforeModified, source.lastModified())
    }

    @Test
    fun `validate rejects an archive without a manifest`() {
        val archive = temporaryFolder.newFile("backup.zip")
        writeZip(archive, mapOf("launcher.db" to "database".toByteArray()))

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, setOf("launcher.db"))
        }
    }

    @Test
    fun `validate rejects an archive missing a required entry`() {
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("launcher.db", "database".toByteArray())),
        )

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, setOf("launcher.db", "preferences.xml"))
        }
    }

    @Test
    fun `validate rejects a checksum mismatch`() {
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("launcher.db", "database".toByteArray())),
        )
        rewriteZip(archive) { entries ->
            entries["launcher.db"] = "tampered".toByteArray()
            entries
        }

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, setOf("launcher.db"))
        }
    }

    @Test
    fun `validate rejects a truncated archive`() {
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("launcher.db", ByteArray(4096) { 7 })),
        )
        val bytes = archive.readBytes()
        archive.writeBytes(bytes.copyOf(bytes.size / 2))

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, setOf("launcher.db"))
        }
    }

    @Test
    fun `validate rejects an entry that is not listed in the manifest`() {
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("launcher.db", "database".toByteArray())),
        )
        rewriteZip(archive) { entries ->
            entries["unexpected.txt"] = "surprise".toByteArray()
            entries
        }

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, setOf("launcher.db"))
        }
    }

    @Test
    fun `validate rejects a manifest entry that escapes the staging directory`() {
        val archive = temporaryFolder.newFile("backup.zip")
        writeZip(
            archive,
            mapOf(
                BackupArchive.MANIFEST_ENTRY to (
                    BackupArchive.FORMAT_HEADER + "\n" +
                        "00".repeat(32) + "\t4\t../evil\n"
                    ).toByteArray(),
            ),
        )

        assertThrows(BackupArchiveException::class.java) {
            BackupArchive.validate(archive, emptySet())
        }
    }

    @Test
    fun `a corrupt archive leaves every target untouched`() {
        val work = temporaryFolder.newFolder("work")
        val target = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("original".toByteArray())
        }
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("preferences.xml", "restored".toByteArray())),
        )
        rewriteZip(archive) { entries ->
            entries["preferences.xml"] = "tampered".toByteArray()
            entries
        }

        assertThrows(BackupArchiveException::class.java) {
            BackupRestoreEngine.restore(
                archive = archive,
                workDir = temporaryFolder.newFolder("restore-work"),
                targets = linkedMapOf("preferences.xml" to target),
                requiredEntries = setOf("preferences.xml"),
            )
        }

        assertArrayEquals("original".toByteArray(), target.readBytes())
    }

    @Test
    fun `a partial archive leaves every target untouched`() {
        val work = temporaryFolder.newFolder("work")
        val first = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("first-original".toByteArray())
        }
        val second = File(work, "live/preferences").apply {
            writeBytes("second-original".toByteArray())
        }
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(
                ArchiveSource.fromBytes("preferences.xml", "first-restored".toByteArray()),
                ArchiveSource.fromBytes("preferences", "second-restored".toByteArray()),
            ),
        )
        rewriteZip(archive) { entries ->
            entries.remove("preferences")
            entries
        }

        assertThrows(BackupArchiveException::class.java) {
            BackupRestoreEngine.restore(
                archive = archive,
                workDir = temporaryFolder.newFolder("restore-work"),
                targets = linkedMapOf(
                    "preferences.xml" to first,
                    "preferences" to second,
                ),
                requiredEntries = setOf("preferences.xml", "preferences"),
            )
        }

        assertArrayEquals("first-original".toByteArray(), first.readBytes())
        assertArrayEquals("second-original".toByteArray(), second.readBytes())
    }

    @Test
    fun `a valid archive is applied to every target`() {
        val work = temporaryFolder.newFolder("work")
        val first = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("first-original".toByteArray())
        }
        val second = File(work, "live/preferences").apply {
            writeBytes("second-original".toByteArray())
        }
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(
                ArchiveSource.fromBytes("preferences.xml", "first-restored".toByteArray()),
                ArchiveSource.fromBytes("preferences", "second-restored".toByteArray()),
            ),
        )

        val transaction = BackupRestoreEngine.restore(
            archive = archive,
            workDir = temporaryFolder.newFolder("restore-work"),
            targets = linkedMapOf(
                "preferences.xml" to first,
                "preferences" to second,
            ),
            requiredEntries = setOf("preferences.xml", "preferences"),
        )

        assertArrayEquals("first-restored".toByteArray(), first.readBytes())
        assertArrayEquals("second-restored".toByteArray(), second.readBytes())
        transaction.commit()
    }

    @Test
    fun `a failure during the swap rolls back every already replaced target`() {
        val work = temporaryFolder.newFolder("work")
        val first = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("first-original".toByteArray())
        }
        val brokenParent = File(work, "broken").apply { writeBytes("not-a-directory".toByteArray()) }
        val second = File(brokenParent, "preferences")
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(
                ArchiveSource.fromBytes("preferences.xml", "first-restored".toByteArray()),
                ArchiveSource.fromBytes("preferences", "second-restored".toByteArray()),
            ),
        )

        assertThrows(Exception::class.java) {
            BackupRestoreEngine.restore(
                archive = archive,
                workDir = temporaryFolder.newFolder("restore-work"),
                targets = linkedMapOf(
                    "preferences.xml" to first,
                    "preferences" to second,
                ),
                requiredEntries = setOf("preferences.xml", "preferences"),
            )
        }

        assertArrayEquals("first-original".toByteArray(), first.readBytes())
        assertFalse(second.exists())
    }

    @Test
    fun `restore never deletes unrelated files beside a target`() {
        val work = temporaryFolder.newFolder("work")
        val target = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("original".toByteArray())
        }
        val unrelated = File(work, "live/launcher.db").apply {
            writeBytes("keep-me".toByteArray())
        }
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(ArchiveSource.fromBytes("preferences.xml", "restored".toByteArray())),
        )

        val transaction = BackupRestoreEngine.restore(
            archive = archive,
            workDir = temporaryFolder.newFolder("restore-work"),
            targets = linkedMapOf("preferences.xml" to target),
            requiredEntries = setOf("preferences.xml"),
        )
        transaction.commit()

        assertArrayEquals("restored".toByteArray(), target.readBytes())
        assertArrayEquals("keep-me".toByteArray(), unrelated.readBytes())
    }

    @Test
    fun `rollback restores originals and removes targets that did not exist`() {
        val work = temporaryFolder.newFolder("work")
        val existing = File(work, "live/preferences.xml").apply {
            parentFile.mkdirs()
            writeBytes("original".toByteArray())
        }
        val absent = File(work, "live/preferences.preferences_pb")
        val archive = temporaryFolder.newFile("backup.zip")
        BackupArchive.write(
            archive,
            listOf(
                ArchiveSource.fromBytes("preferences.xml", "restored".toByteArray()),
                ArchiveSource.fromBytes("preferences.preferences_pb", "new".toByteArray()),
            ),
        )

        val transaction = BackupRestoreEngine.restore(
            archive = archive,
            workDir = temporaryFolder.newFolder("restore-work"),
            targets = linkedMapOf(
                "preferences.xml" to existing,
                "preferences.preferences_pb" to absent,
            ),
            requiredEntries = setOf("preferences.xml"),
        )

        assertArrayEquals("restored".toByteArray(), existing.readBytes())
        assertArrayEquals("new".toByteArray(), absent.readBytes())

        transaction.rollback()

        assertArrayEquals("original".toByteArray(), existing.readBytes())
        assertFalse(absent.exists())
    }

    private fun writeZip(file: File, entries: Map<String, ByteArray>) {
        file.parentFile?.mkdirs()
        ZipOutputStream(file.outputStream().buffered()).use { zip ->
            entries.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
    }

    private fun rewriteZip(file: File, transform: (MutableMap<String, ByteArray>) -> Map<String, ByteArray>) {
        val entries = linkedMapOf<String, ByteArray>()
        ZipFile(file).use { zip ->
            zip.entries().asSequence().filter { !it.isDirectory }.forEach { entry ->
                entries[entry.name] = zip.getInputStream(entry).use { it.readBytes() }
            }
        }
        val rewritten = transform(entries)
        val buffer = ByteArrayOutputStream()
        ZipOutputStream(buffer).use { zip ->
            rewritten.forEach { (name, bytes) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        file.writeBytes(buffer.toByteArray())
    }
}
