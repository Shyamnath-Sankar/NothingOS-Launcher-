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
import java.io.FileInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Raised when a backup archive is missing, malformed, truncated, or fails an integrity check.
 * Callers must treat this as a hard failure: nothing on disk may be changed when it is thrown.
 */
class BackupArchiveException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** A single payload that should be written into a backup archive. */
class ArchiveSource private constructor(
    val name: String,
    private val opener: () -> InputStream,
) {
    fun open(): InputStream = opener()

    companion object {
        fun fromFile(name: String, file: File): ArchiveSource {
            require(file.isFile) { "Not a file: $file" }
            return ArchiveSource(name) { FileInputStream(file) }
        }

        fun fromBytes(name: String, bytes: ByteArray): ArchiveSource {
            return ArchiveSource(name) { bytes.inputStream() }
        }
    }
}

data class ArchiveEntryInfo(
    val name: String,
    val size: Long,
    val sha256: String,
)

data class ArchiveManifest(
    val entries: Map<String, ArchiveEntryInfo>,
)

/**
 * Pure-JVM backup archive format with an integrity manifest.
 *
 * The archive is a zip whose last entry is [MANIFEST_ENTRY]. The manifest lists the SHA-256 and
 * size of every payload entry. Reading is two-phase: [validate] proves the whole archive is
 * complete and intact without touching any destination, then [extract] copies the already
 * validated payloads into a private staging directory while re-checking each digest.
 */
object BackupArchive {
    const val MANIFEST_ENTRY = "manifest.txt"
    const val FORMAT_HEADER = "lawnchair-backup-manifest/v1"

    private const val MAX_ENTRIES = 64
    private const val MAX_ENTRY_BYTES = 512L * 1024 * 1024
    private const val MAX_TOTAL_BYTES = 1024L * 1024 * 1024
    private const val MAX_MANIFEST_BYTES = 1024L * 1024
    private const val BUFFER_SIZE = 8192

    private val SAFE_NAME = Regex("^[A-Za-z0-9][A-Za-z0-9._-]*$")
    private val SHA256 = Regex("^[0-9a-f]{64}$")

    fun write(output: File, sources: List<ArchiveSource>) {
        val names = sources.map { it.name }
        require(names.size <= MAX_ENTRIES) { "Too many entries" }
        require(names.size == names.toSet().size) { "Duplicate entry name" }
        names.forEach { require(isSafeName(it)) { "Unsafe entry name: $it" } }
        require(MANIFEST_ENTRY !in names) { "Reserved entry name: $MANIFEST_ENTRY" }

        output.parentFile?.mkdirs()
        val manifest = StringBuilder(FORMAT_HEADER).append('\n')
        ZipOutputStream(output.outputStream().buffered()).use { zip ->
            var total = 0L
            sources.forEach { source ->
                val digest = MessageDigest.getInstance("SHA-256")
                var size = 0L
                zip.putNextEntry(ZipEntry(source.name))
                source.open().use { input ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        size += read
                        total += read
                        if (size > MAX_ENTRY_BYTES || total > MAX_TOTAL_BYTES) {
                            throw BackupArchiveException("Backup entry too large: ${source.name}")
                        }
                        digest.update(buffer, 0, read)
                        zip.write(buffer, 0, read)
                    }
                }
                zip.closeEntry()
                manifest.append(toHex(digest.digest()))
                    .append('\t')
                    .append(size)
                    .append('\t')
                    .append(source.name)
                    .append('\n')
            }
            val manifestBytes = manifest.toString().toByteArray(Charsets.UTF_8)
            zip.putNextEntry(ZipEntry(MANIFEST_ENTRY))
            zip.write(manifestBytes)
            zip.closeEntry()
        }
    }

    fun validate(archive: File, requiredEntries: Set<String>): ArchiveManifest {
        if (!archive.isFile) {
            throw BackupArchiveException("Backup archive is missing")
        }
        try {
            ZipFile(archive).use { zip ->
                val manifestEntry = zip.getEntry(MANIFEST_ENTRY)
                    ?: throw BackupArchiveException("Backup manifest is missing")
                val manifestBytes = zip.getInputStream(manifestEntry).use {
                    it.readBounded(MAX_MANIFEST_BYTES)
                }
                val manifest = parseManifest(manifestBytes)

                requiredEntries.forEach { required ->
                    if (required !in manifest.entries) {
                        throw BackupArchiveException("Backup is missing required entry: $required")
                    }
                }

                val actualNames = zip.entries().asSequence()
                    .filter { !it.isDirectory }
                    .map { it.name }
                    .toList()
                if (actualNames.size != actualNames.toSet().size) {
                    throw BackupArchiveException("Backup contains duplicate entries")
                }
                val payloadNames = actualNames.filter { it != MANIFEST_ENTRY }.toSet()
                if (payloadNames != manifest.entries.keys) {
                    throw BackupArchiveException("Backup contents do not match the manifest")
                }

                var total = 0L
                manifest.entries.values.forEach { info ->
                    val entry = zip.getEntry(info.name)
                        ?: throw BackupArchiveException("Backup entry is missing: ${info.name}")
                    val digest = MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    zip.getInputStream(entry).use { input ->
                        val buffer = ByteArray(BUFFER_SIZE)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            size += read
                            total += read
                            if (size > MAX_ENTRY_BYTES || total > MAX_TOTAL_BYTES) {
                                throw BackupArchiveException("Backup entry too large: ${info.name}")
                            }
                            digest.update(buffer, 0, read)
                        }
                    }
                    if (size != info.size) {
                        throw BackupArchiveException("Backup entry size mismatch: ${info.name}")
                    }
                    if (toHex(digest.digest()) != info.sha256) {
                        throw BackupArchiveException("Backup entry checksum mismatch: ${info.name}")
                    }
                }
                return manifest
            }
        } catch (e: BackupArchiveException) {
            throw e
        } catch (e: Exception) {
            throw BackupArchiveException("Backup archive could not be read", e)
        }
    }

    fun readEntry(archive: File, manifest: ArchiveManifest, name: String): ByteArray? {
        val info = manifest.entries[name] ?: return null
        try {
            ZipFile(archive).use { zip ->
                val entry = zip.getEntry(name)
                    ?: throw BackupArchiveException("Backup entry is missing: $name")
                val bytes = zip.getInputStream(entry).use { it.readBounded(MAX_ENTRY_BYTES) }
                val digest = toHex(MessageDigest.getInstance("SHA-256").digest(bytes))
                if (bytes.size.toLong() != info.size || digest != info.sha256) {
                    throw BackupArchiveException("Backup entry failed verification: $name")
                }
                return bytes
            }
        } catch (e: BackupArchiveException) {
            throw e
        } catch (e: Exception) {
            throw BackupArchiveException("Backup archive could not be read", e)
        }
    }

    fun extract(archive: File, manifest: ArchiveManifest, destination: File) {
        if (!destination.isDirectory && !destination.mkdirs()) {
            throw BackupArchiveException("Could not create staging directory")
        }
        try {
            ZipFile(archive).use { zip ->
                manifest.entries.values.forEach { info ->
                    val entry = zip.getEntry(info.name)
                        ?: throw BackupArchiveException("Backup entry is missing: ${info.name}")
                    val target = File(destination, info.name)
                    if (!isInside(destination, target)) {
                        throw BackupArchiveException("Backup entry escapes staging: ${info.name}")
                    }
                    val temp = File(destination, ".${info.name}.tmp")
                    val digest = MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    try {
                        zip.getInputStream(entry).use { input ->
                            temp.outputStream().buffered().use { output ->
                                val buffer = ByteArray(BUFFER_SIZE)
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    size += read
                                    if (size > MAX_ENTRY_BYTES) {
                                        throw BackupArchiveException("Backup entry too large: ${info.name}")
                                    }
                                    digest.update(buffer, 0, read)
                                    output.write(buffer, 0, read)
                                }
                            }
                        }
                        if (size != info.size || toHex(digest.digest()) != info.sha256) {
                            throw BackupArchiveException("Backup entry failed verification: ${info.name}")
                        }
                        if (!temp.renameTo(target)) {
                            throw BackupArchiveException("Could not stage backup entry: ${info.name}")
                        }
                    } catch (e: Throwable) {
                        temp.delete()
                        throw e
                    }
                }
            }
        } catch (e: BackupArchiveException) {
            throw e
        } catch (e: Exception) {
            throw BackupArchiveException("Backup archive could not be extracted", e)
        }
    }

    private fun parseManifest(bytes: ByteArray): ArchiveManifest {
        val text = bytes.toString(Charsets.UTF_8)
        val lines = text.split('\n')
        if (lines.isEmpty() || lines.first() != FORMAT_HEADER) {
            throw BackupArchiveException("Unsupported backup manifest")
        }
        val entries = linkedMapOf<String, ArchiveEntryInfo>()
        lines.drop(1).filter { it.isNotEmpty() }.forEach { line ->
            val parts = line.split('\t')
            if (parts.size != 3) {
                throw BackupArchiveException("Malformed backup manifest line")
            }
            val (sha256, sizeText, name) = parts
            if (!SHA256.matches(sha256)) {
                throw BackupArchiveException("Malformed backup checksum")
            }
            if (!isSafeName(name) || name == MANIFEST_ENTRY) {
                throw BackupArchiveException("Unsafe backup entry name: $name")
            }
            val size = sizeText.toLongOrNull()
                ?: throw BackupArchiveException("Malformed backup entry size")
            if (size < 0 || size > MAX_ENTRY_BYTES) {
                throw BackupArchiveException("Backup entry size out of range: $name")
            }
            if (entries.put(name, ArchiveEntryInfo(name, size, sha256)) != null) {
                throw BackupArchiveException("Duplicate backup manifest entry: $name")
            }
        }
        if (entries.size > MAX_ENTRIES) {
            throw BackupArchiveException("Too many backup entries")
        }
        return ArchiveManifest(entries)
    }

    private fun InputStream.readBounded(limit: Long): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(BUFFER_SIZE)
        var total = 0L
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            total += read
            if (total > limit) {
                throw BackupArchiveException("Backup manifest is too large")
            }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private fun isSafeName(name: String): Boolean {
        if (name.isEmpty() || name.length > 128) return false
        if (name.contains('/') || name.contains('\\') || name.contains("..")) return false
        return SAFE_NAME.matches(name)
    }

    private fun isInside(parent: File, child: File): Boolean {
        val parentPath = parent.canonicalPath + File.separator
        return child.canonicalPath.startsWith(parentPath)
    }

    private fun toHex(bytes: ByteArray): String {
        val builder = StringBuilder(bytes.size * 2)
        bytes.forEach { builder.append("%02x".format(it)) }
        return builder.toString()
    }
}

/**
 * Restores already-validated archive entries into live locations.
 *
 * Every existing target is copied into a private rollback directory before the staged replacement
 * is moved into place. A failure at any point restores every target that was already swapped, so a
 * partial restore can never leave the launcher with half-new, half-old user data.
 */
class RestoreTransaction internal constructor(
    private val workDir: File,
    private val targets: Map<String, File>,
) {
    private class Applied(
        val target: File,
        val backup: File?,
    )

    private val rollbackDir = File(workDir, "rollback")
    private val applied = mutableListOf<Applied>()
    private var finished = false

    internal fun apply(stagingDir: File, manifest: ArchiveManifest) {
        check(!finished) { "Transaction already finished" }
        if (!rollbackDir.isDirectory && !rollbackDir.mkdirs()) {
            throw BackupArchiveException("Could not create rollback directory")
        }
        targets.forEach { (name, target) ->
            if (name !in manifest.entries) return@forEach
            val staged = File(stagingDir, name)
            if (!staged.isFile) {
                throw BackupArchiveException("Staged entry is missing: $name")
            }
            val parent = target.parentFile
            if (parent == null || (!parent.isDirectory && !parent.mkdirs())) {
                throw BackupArchiveException("Could not create target directory for $name")
            }
            val backup = if (target.exists()) {
                File(rollbackDir, name).also { it.parentFile?.mkdirs() }
                    .also { target.copyTo(it, overwrite = true) }
            } else {
                null
            }
            val temp = File(parent, ".${target.name}.restore-tmp")
            try {
                staged.copyTo(temp, overwrite = true)
                if (!temp.renameTo(target)) {
                    throw BackupArchiveException("Could not replace target: $name")
                }
            } catch (e: Throwable) {
                temp.delete()
                throw e
            }
            applied.add(Applied(target, backup))
        }
    }

    fun commit() {
        if (finished) return
        finished = true
        applied.clear()
        rollbackDir.deleteRecursively()
    }

    fun rollback() {
        if (finished) return
        finished = true
        applied.asReversed().forEach { entry ->
            val backup = entry.backup
            if (backup != null && backup.isFile) {
                backup.copyTo(entry.target, overwrite = true)
            } else if (backup == null) {
                entry.target.delete()
            }
        }
        applied.clear()
        rollbackDir.deleteRecursively()
    }
}

object BackupRestoreEngine {
    /**
     * Validates the archive, extracts it into a private staging directory, and swaps every mapped
     * entry into place. Returns an uncommitted [RestoreTransaction]; the caller must call [commit]
     * after its own finalisation succeeds, or [rollback] on any later failure.
     *
     * If validation, extraction or the swap fails, this throws and every live target is unchanged.
     */
    fun restore(
        archive: File,
        workDir: File,
        targets: Map<String, File>,
        requiredEntries: Set<String>,
    ): RestoreTransaction {
        val manifest = BackupArchive.validate(archive, requiredEntries)
        val stagingDir = File(workDir, "staging")
        BackupArchive.extract(archive, manifest, stagingDir)
        val transaction = RestoreTransaction(workDir, targets)
        try {
            transaction.apply(stagingDir, manifest)
        } catch (e: Throwable) {
            transaction.rollback()
            throw e
        }
        return transaction
    }
}
