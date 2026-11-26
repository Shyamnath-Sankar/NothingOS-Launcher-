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

import java.io.File
import java.io.OutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

const val BACKUP_INFO_ENTRY_NAME = "info.pb"
const val BACKUP_WALLPAPER_ENTRY_NAME = "wallpaper.png"
const val BACKUP_SCREENSHOT_ENTRY_NAME = "screenshot.png"

/** Writes one payload into an archive entry. */
fun interface BackupEntryWriter {
    fun writeTo(output: OutputStream)
}

class BackupArchiveEntry(
    val name: String,
    val writer: BackupEntryWriter,
)

/**
 * Builds the payload list for a backup archive: the optional wallpaper and screenshot first, then
 * the launcher files that actually exist. Missing files are skipped instead of failing the backup.
 */
fun buildBackupEntries(
    includeLayoutAndSettings: Boolean,
    includeWallpaper: Boolean,
    screenshotWriter: BackupEntryWriter,
    wallpaperWriter: BackupEntryWriter?,
    files: Map<String, File>,
): List<BackupArchiveEntry> {
    val entries = ArrayList<BackupArchiveEntry>()
    if (includeWallpaper && wallpaperWriter != null) {
        entries += BackupArchiveEntry(BACKUP_WALLPAPER_ENTRY_NAME, wallpaperWriter)
    }
    if (includeLayoutAndSettings) {
        entries += BackupArchiveEntry(BACKUP_SCREENSHOT_ENTRY_NAME, screenshotWriter)
    }
    files.forEach { (name, file) ->
        if (file.isFile) {
            entries += BackupArchiveEntry(name) { output ->
                file.inputStream().use { it.copyTo(output) }
            }
        }
    }
    return entries
}

/**
 * Writes the existing backup format: a zip whose first entry is the serialized `BackupInfo`
 * protobuf, followed by the requested payload entries.
 */
object BackupArchiveWriter {
    fun write(
        output: OutputStream,
        infoBytes: ByteArray,
        entries: List<BackupArchiveEntry>,
    ) {
        ZipOutputStream(output.buffered()).use { zip ->
            zip.putNextEntry(ZipEntry(BACKUP_INFO_ENTRY_NAME))
            zip.write(infoBytes)
            zip.closeEntry()
            entries.forEach { entry ->
                zip.putNextEntry(ZipEntry(entry.name))
                entry.writer.writeTo(zip)
                zip.closeEntry()
            }
        }
    }
}
