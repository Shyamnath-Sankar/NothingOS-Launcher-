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
import java.time.Duration
import java.time.Instant

/**
 * The global request boundary. It is independent of the location and of the
 * response outcome: an error counts as much as a success. [retryNotBefore] is a
 * provider-requested (or fallback) delay that is only ever moved later.
 */
data class WeatherAttemptGate(
    val lastAttemptAt: Instant? = null,
    val retryNotBefore: Instant? = null,
) {
    fun nextAllowedAt(minimumInterval: Duration): Instant? = listOfNotNull(
        lastAttemptAt?.plus(minimumInterval),
        retryNotBefore,
    ).maxOrNull()
}

sealed interface WeatherAttemptDecision {
    data object Allowed : WeatherAttemptDecision

    data class Denied(val retryAt: Instant) : WeatherAttemptDecision

    /** The persisted floor cannot be read or written, so the attempt fails closed. */
    data class StorageFailure(val retryAt: Instant) : WeatherAttemptDecision
}

interface WeatherThrottleStore {
    /**
     * Atomically records an attempt before a request is sent and reports
     * whether the caller may proceed. A missing record allows the first try;
     * an unreadable or unwritable one does not.
     */
    fun claim(now: Instant, minimumInterval: Duration): WeatherAttemptDecision

    /** Extends the provider-requested boundary; it is never shortened. */
    fun recordRetryNotBefore(until: Instant): Boolean

    fun snapshot(): WeatherAttemptGate?
}

class InMemoryWeatherThrottleStore : WeatherThrottleStore {
    private var gate = WeatherAttemptGate()

    @Synchronized
    override fun claim(now: Instant, minimumInterval: Duration): WeatherAttemptDecision {
        val next = gate.nextAllowedAt(minimumInterval)
        if (next != null && now.isBefore(next)) return WeatherAttemptDecision.Denied(next)
        gate = gate.copy(
            lastAttemptAt = now,
            retryNotBefore = gate.retryNotBefore?.takeIf { it.isAfter(now) },
        )
        return WeatherAttemptDecision.Allowed
    }

    @Synchronized
    override fun recordRetryNotBefore(until: Instant): Boolean {
        val existing = gate.retryNotBefore
        gate = gate.copy(retryNotBefore = if (existing != null && existing.isAfter(until)) existing else until)
        return true
    }

    @Synchronized
    override fun snapshot(): WeatherAttemptGate = gate
}

/**
 * App-private persisted throttle. A recreated repository reads the same floor,
 * and a file lock keeps two instances from claiming the same window.
 */
class FileWeatherThrottleStore(
    private val directory: File,
    private val maxFileBytes: Long = MAX_FILE_BYTES,
) : WeatherThrottleStore {
    override fun claim(now: Instant, minimumInterval: Duration): WeatherAttemptDecision = withLock {
        val gate = readLocked() ?: return@withLock WeatherAttemptDecision.StorageFailure(now.plus(minimumInterval))
        val next = gate.nextAllowedAt(minimumInterval)
        if (next != null && now.isBefore(next)) return@withLock WeatherAttemptDecision.Denied(next)
        val updated = gate.copy(
            lastAttemptAt = now,
            retryNotBefore = gate.retryNotBefore?.takeIf { it.isAfter(now) },
        )
        if (writeLocked(updated)) {
            WeatherAttemptDecision.Allowed
        } else {
            WeatherAttemptDecision.StorageFailure(now.plus(minimumInterval))
        }
    }

    override fun recordRetryNotBefore(until: Instant): Boolean = withLock {
        val gate = readLocked() ?: WeatherAttemptGate()
        val existing = gate.retryNotBefore
        val boundary = if (existing != null && existing.isAfter(until)) existing else until
        writeLocked(gate.copy(retryNotBefore = boundary))
    }

    override fun snapshot(): WeatherAttemptGate? = withLock { readLocked() }

    private fun readLocked(): WeatherAttemptGate? {
        if (!stateFile.isFile) return WeatherAttemptGate()
        if (stateFile.length() <= 0L || stateFile.length() > maxFileBytes) return null
        val bytes = readBounded(stateFile.inputStream(), maxFileBytes) ?: return null
        return decode(bytes.toString(Charsets.UTF_8))
    }

    private fun writeLocked(gate: WeatherAttemptGate): Boolean = runCatching {
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
            return@runCatching false
        }
        val bytes = encode(gate).toByteArray(Charsets.UTF_8)
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

    private fun <T> withLock(block: () -> T): T {
        if (!directory.isDirectory) directory.mkdirs()
        RandomAccessFile(lockFile, "rw").use { file ->
            val lock = file.channel.lock()
            try {
                return block()
            } finally {
                lock.release()
            }
        }
    }

    private fun encode(gate: WeatherAttemptGate): String = buildString {
        append(FORMAT_VERSION).append('\n')
        append(gate.lastAttemptAt?.toString() ?: NONE).append('\n')
        append(gate.retryNotBefore?.toString() ?: NONE)
    }

    private fun decode(text: String): WeatherAttemptGate? {
        val parts = text.split('\n')
        if (parts.size != METADATA_LINES || parts[0] != FORMAT_VERSION) return null
        val lastAttemptAt = parts[1].takeUnless { it == NONE }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() ?: return null }
        val retryNotBefore = parts[2].takeUnless { it == NONE }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() ?: return null }
        return WeatherAttemptGate(lastAttemptAt = lastAttemptAt, retryNotBefore = retryNotBefore)
    }

    private val stateFile: File
        get() = File(directory, STATE_NAME)

    private val lockFile: File
        get() = File(directory, "$STATE_NAME.lock")

    private companion object {
        const val STATE_NAME = "request-gate"
        const val FORMAT_VERSION = "v1"
        const val NONE = "-"
        const val METADATA_LINES = 3
        const val MAX_FILE_BYTES = 4096L
    }
}
