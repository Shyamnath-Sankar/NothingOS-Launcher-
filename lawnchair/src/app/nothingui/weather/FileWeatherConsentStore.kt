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

package app.nothingui.weather

import java.io.File
import java.io.RandomAccessFile
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

sealed interface WeatherConsentWriteResult {
    data class Committed(val state: WeatherConsentState) : WeatherConsentWriteResult

    /** A newer decision (or a newer generation) already owns the store. */
    data class Conflict(val current: WeatherConsentState) : WeatherConsentWriteResult

    data object StorageFailure : WeatherConsentWriteResult
}

/**
 * The single writer for the persisted weather opt-in. Neither the label nor the
 * coordinates are stored in any backed-up preference file; production wiring
 * supplies an app-private [File] below `Context.noBackupFilesDir`.
 */
interface WeatherConsentStore {
    fun read(): WeatherConsentState

    /**
     * Applies [next] only when the stored generation still equals
     * [expectedGeneration]. This makes a disable or edit-revocation win over a
     * stale enable action instead of silently resurrecting consent.
     */
    fun compareAndSet(
        expectedGeneration: Long,
        next: WeatherConsentState,
    ): WeatherConsentWriteResult
}

/**
 * Transactional, app-private JSON store. The file is written to a temporary
 * file and atomically moved into place under a process and file lock.
 *
 * A missing record reads as [WeatherConsentState.DISABLED] with generation 0
 * and may be initialized by a fresh enable. A corrupt, oversized or otherwise
 * invalid record also reads as disabled for the fail-closed UI, but its
 * generation is unknown, so it may not be overwritten by an enable; only a
 * disable (the safe direction) is allowed until a future explicit recovery
 * flow removes the corrupt record. Every write must name the exact current
 * generation and advance it strictly, and a store already at
 * [Long.MAX_VALUE] fails closed instead of wrapping negative.
 *
 * The directory is injected so this class never reaches for a Context, shares
 * no external storage and is testable on the JVM.
 */
class FileWeatherConsentStore(
    private val directory: File,
    private val maxFileBytes: Long = MAX_FILE_BYTES,
) : WeatherConsentStore {
    override fun read(): WeatherConsentState = withStoreLock(WeatherConsentState.DISABLED) {
        when (val stored = readLocked()) {
            is StoredConsent.Valid -> stored.state
            StoredConsent.Missing, StoredConsent.Corrupt -> WeatherConsentState.DISABLED
        }
    }

    override fun compareAndSet(
        expectedGeneration: Long,
        next: WeatherConsentState,
    ): WeatherConsentWriteResult = withStoreLock(WeatherConsentWriteResult.StorageFailure) {
        val stored = readLocked()
        val current = when (stored) {
            is StoredConsent.Valid -> stored.state
            StoredConsent.Missing, StoredConsent.Corrupt -> WeatherConsentState.DISABLED
        }
        if (current.generation != expectedGeneration) {
            return@withStoreLock WeatherConsentWriteResult.Conflict(current)
        }
        if (!isAcceptableNext(stored, expectedGeneration, next)) {
            return@withStoreLock WeatherConsentWriteResult.StorageFailure
        }
        if (writeLocked(next)) {
            WeatherConsentWriteResult.Committed(next)
        } else {
            WeatherConsentWriteResult.StorageFailure
        }
    }

    private fun isAcceptableNext(
        stored: StoredConsent,
        expectedGeneration: Long,
        next: WeatherConsentState,
    ): Boolean {
        if (expectedGeneration == Long.MAX_VALUE) return false
        if (next.generation <= expectedGeneration) return false
        if (stored == StoredConsent.Corrupt && next.enabled) return false
        return true
    }

    private fun readLocked(): StoredConsent {
        val file = stateFile
        if (!file.isFile) return StoredConsent.Missing
        if (file.length() <= 0L || file.length() > maxFileBytes) return StoredConsent.Corrupt
        val text = runCatching {
            readBounded(file.inputStream(), maxFileBytes)?.toString(Charsets.UTF_8)
        }.getOrNull() ?: return StoredConsent.Corrupt
        return decode(text)?.let { StoredConsent.Valid(it) } ?: StoredConsent.Corrupt
    }

    private fun writeLocked(state: WeatherConsentState): Boolean = runCatching {
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
            return@runCatching false
        }
        val bytes = encode(state).toByteArray(Charsets.UTF_8)
        if (bytes.size > maxFileBytes) return@runCatching false
        val temporary = File.createTempFile("$STATE_NAME.", ".tmp", directory)
        try {
            temporary.writeBytes(bytes)
            moveIntoPlace(temporary, stateFile)
            true
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }.getOrDefault(false)

    private fun moveIntoPlace(temporary: File, target: File) {
        try {
            Files.move(
                temporary.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun encode(state: WeatherConsentState): String = buildJsonObject {
        put(KEY_VERSION, FORMAT_VERSION)
        put(KEY_ENABLED, state.enabled)
        put(KEY_GENERATION, state.generation)
        if (state.location == null) {
            put(KEY_LABEL, JsonNull)
            put(KEY_LATITUDE, JsonNull)
            put(KEY_LONGITUDE, JsonNull)
        } else {
            put(KEY_LABEL, state.location.label)
            put(KEY_LATITUDE, state.location.coordinates.latitudeText)
            put(KEY_LONGITUDE, state.location.coordinates.longitudeText)
        }
    }.toString()

    private fun decode(text: String): WeatherConsentState? {
        val root = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull()
            ?: return null
        if (root.keys != KEYS) return null
        val version = number(root, KEY_VERSION)?.toIntOrNull() ?: return null
        if (version != FORMAT_VERSION) return null
        val enabled = bool(root, KEY_ENABLED) ?: return null
        val generation = number(root, KEY_GENERATION)?.toLongOrNull()
            ?: return null
        if (generation < 0L) return null
        if (!enabled) {
            val noStoredLocation = listOf(KEY_LABEL, KEY_LATITUDE, KEY_LONGITUDE)
                .all { root[it] is JsonNull }
            if (!noStoredLocation) return null
            return WeatherConsentState(
                enabled = false,
                location = null,
                generation = generation,
            )
        }
        val label = string(root, KEY_LABEL) ?: return null
        val latitude = string(root, KEY_LATITUDE) ?: return null
        val longitude = string(root, KEY_LONGITUDE) ?: return null
        val location = (
            WeatherConsentPolicy.parseLocation(label, latitude, longitude)
                as? WeatherLocationInput.Valid
            )?.location ?: return null
        return WeatherConsentState(
            enabled = true,
            location = location,
            generation = generation,
        )
    }

    private sealed interface StoredConsent {
        data object Missing : StoredConsent

        data object Corrupt : StoredConsent

        data class Valid(val state: WeatherConsentState) : StoredConsent
    }

    private fun number(root: JsonObject, key: String): String? {
        val primitive = root[key] as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        return primitive.content
    }

    private fun bool(root: JsonObject, key: String): Boolean? {
        val primitive = root[key] as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        return primitive.booleanOrNull
    }

    private fun string(root: JsonObject, key: String): String? {
        val primitive = root[key] as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        return primitive.content
    }

    /**
     * A JVM file lock is owned by the whole process, so a same-process second
     * store cannot rely on [java.nio.channels.FileLock] alone. The process-wide
     * monitor serializes same-process access; the file lock still guards other
     * processes. I/O or lock failures are reported through [fallback].
     */
    private fun <T> withStoreLock(fallback: T, block: () -> T): T = try {
        synchronized(processLock) {
            if (!directory.isDirectory) directory.mkdirs()
            RandomAccessFile(lockFile, "rw").use { file ->
                val lock = file.channel.lock()
                try {
                    block()
                } finally {
                    runCatching { lock.release() }
                }
            }
        }
    } catch (_: Exception) {
        fallback
    }

    private val stateFile: File
        get() = File(directory, STATE_NAME)

    private val lockFile: File
        get() = File(directory, "$STATE_NAME.lock")

    private companion object {
        private val processLock = Any()

        const val STATE_NAME = "consent-state.json"
        const val FORMAT_VERSION = 1
        const val MAX_FILE_BYTES = 8192L

        const val KEY_VERSION = "version"
        const val KEY_ENABLED = "enabled"
        const val KEY_LABEL = "label"
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_GENERATION = "generation"

        val KEYS = setOf(
            KEY_VERSION,
            KEY_ENABLED,
            KEY_LABEL,
            KEY_LATITUDE,
            KEY_LONGITUDE,
            KEY_GENERATION,
        )
    }
}
