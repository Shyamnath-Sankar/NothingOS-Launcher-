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
import java.io.InputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap

/**
 * The raw MET body and its HTTP validators. Keeping the body instead of a
 * pre-rendered label lets a 304 re-validate the exact payload without
 * inventing a new forecast time. [retrievedAt] stays the original body fetch;
 * [revalidatedAt] records a later successful 304.
 */
data class WeatherCacheEntry(
    val locationKey: String,
    val body: String,
    val retrievedAt: Instant,
    val expiresAt: Instant?,
    val lastModified: String?,
    val revalidatedAt: Instant? = null,
)

interface WeatherCacheStore {
    fun read(locationKey: String): WeatherCacheEntry?

    /** @return true only when the entry was durably replaced. */
    fun write(entry: WeatherCacheEntry): Boolean
}

class InMemoryWeatherCacheStore : WeatherCacheStore {
    private val entries = ConcurrentHashMap<String, WeatherCacheEntry>()

    override fun read(locationKey: String): WeatherCacheEntry? = entries[locationKey]

    override fun write(entry: WeatherCacheEntry): Boolean {
        entries[entry.locationKey] = entry
        return true
    }
}

/**
 * Atomic app-private file cache. The directory is supplied by the caller, so
 * this class never reaches for a Context or a shared external location.
 *
 * Reads are bounded before allocating the body, malformed metadata or an
 * oversized file is treated as absent, and a failed write leaves the previous
 * entry untouched. No method throws IO: a storage problem is reported through
 * the return value so the repository can stay honest.
 */
class FileWeatherCacheStore(
    private val directory: File,
    private val maxFileBytes: Long = MAX_FILE_BYTES,
) : WeatherCacheStore {
    override fun read(locationKey: String): WeatherCacheEntry? {
        if (!isValidKey(locationKey)) return null
        return runCatching {
            val file = fileFor(locationKey)
            if (!file.isFile) return@runCatching null
            if (file.length() <= 0L || file.length() > maxFileBytes) return@runCatching null
            val bytes = readBounded(file.inputStream(), maxFileBytes) ?: return@runCatching null
            val entry = decode(bytes.toString(Charsets.UTF_8)) ?: return@runCatching null
            entry.takeIf { it.locationKey == locationKey }
        }.getOrNull()
    }

    override fun write(entry: WeatherCacheEntry): Boolean {
        if (!isValidKey(entry.locationKey)) return false
        if (entry.body.isBlank() || entry.body.length > MAX_BODY_CHARS) return false
        val header = entry.lastModified?.let(::singleLine)
        if (header != null && header.length > MAX_HEADER_CHARS) return false
        return runCatching {
            if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
                return@runCatching false
            }
            val bytes = encode(entry).toByteArray(Charsets.UTF_8)
            if (bytes.size > maxFileBytes) return@runCatching false
            val target = fileFor(entry.locationKey)
            val temporary = File.createTempFile("${target.name}.", ".tmp", directory)
            try {
                temporary.writeBytes(bytes)
                moveIntoPlace(temporary, target)
                true
            } finally {
                if (temporary.exists()) temporary.delete()
            }
        }.getOrDefault(false)
    }

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

    private fun fileFor(locationKey: String): File {
        val name = Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(locationKey.toByteArray(Charsets.UTF_8))
        return File(directory, "$name.weather")
    }

    private fun encode(entry: WeatherCacheEntry): String = buildString {
        append(FORMAT_VERSION).append('\n')
        append(entry.locationKey).append('\n')
        append(entry.retrievedAt).append('\n')
        append(entry.revalidatedAt?.toString() ?: NONE).append('\n')
        append(entry.expiresAt?.toString() ?: NONE).append('\n')
        append(entry.lastModified?.let(::singleLine) ?: NONE).append('\n')
        append(entry.body)
    }

    private fun decode(text: String): WeatherCacheEntry? {
        val parts = text.split('\n', limit = METADATA_LINES + 1)
        if (parts.size != METADATA_LINES + 1) return null
        if (parts[0] != FORMAT_VERSION) return null
        val locationKey = parts[1].takeIf(::isValidKey) ?: return null
        val retrievedAt = runCatching { Instant.parse(parts[2]) }.getOrNull() ?: return null
        val revalidatedAt = parts[3].takeUnless { it == NONE }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() ?: return null }
        val expiresAt = parts[4].takeUnless { it == NONE }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() ?: return null }
        val lastModified = parts[5].takeUnless { it == NONE }
        if (lastModified != null && lastModified.length > MAX_HEADER_CHARS) return null
        val body = parts[6]
        if (body.isBlank() || body.length > MAX_BODY_CHARS) return null
        return WeatherCacheEntry(
            locationKey = locationKey,
            body = body,
            retrievedAt = retrievedAt,
            expiresAt = expiresAt,
            lastModified = lastModified,
            revalidatedAt = revalidatedAt,
        )
    }

    private fun singleLine(value: String): String = value.replace('\n', ' ').replace('\r', ' ')

    /** Mirrors the key constraints enforced by [decode] before a write is declared durable. */
    private fun isValidKey(value: String): Boolean =
        value.isNotBlank() && value.length <= MAX_KEY_CHARS &&
            value.none { it == '\n' || it == '\r' }

    private companion object {
        const val FORMAT_VERSION = "v1"
        const val NONE = "-"
        const val METADATA_LINES = 6
        const val MAX_BODY_CHARS = 512 * 1024
        const val MAX_KEY_CHARS = 256
        const val MAX_HEADER_CHARS = 512
        const val MAX_FILE_BYTES = 512L * 1024L + 4096L
    }
}

internal fun readBounded(input: InputStream, limit: Long): ByteArray? = input.use { stream ->
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8 * 1024)
    var total = 0L
    while (true) {
        val read = stream.read(buffer)
        if (read < 0) break
        total += read
        if (total > limit) return@use null
        output.write(buffer, 0, read)
    }
    output.toByteArray()
}

/**
 * A refresh may happen only after both a global three-hour minimum and the
 * server's `Expires` boundary. A manual refresh calls the same path, so it
 * cannot bypass either gate. A later 304 revalidation counts as the newest
 * evidence even though the body's [WeatherCacheEntry.retrievedAt] is older.
 */
object WeatherRefreshPolicy {
    val MIN_REFRESH_INTERVAL: Duration = Duration.ofHours(3)

    enum class Decision {
        USE_CACHE,
        FETCH,
    }

    fun decide(
        cachedRetrievedAt: Instant?,
        cacheExpiresAt: Instant?,
        now: Instant,
        cachedRevalidatedAt: Instant? = null,
    ): Decision {
        val evidenceAt = listOfNotNull(cachedRetrievedAt, cachedRevalidatedAt).maxOrNull()
            ?: return Decision.FETCH
        if (Duration.between(evidenceAt, now) < MIN_REFRESH_INTERVAL) return Decision.USE_CACHE
        if (cacheExpiresAt != null && now.isBefore(cacheExpiresAt)) return Decision.USE_CACHE
        return Decision.FETCH
    }

    fun isStale(cachedRetrievedAt: Instant?, now: Instant): Boolean = cachedRetrievedAt == null ||
        Duration.between(cachedRetrievedAt, now) >= MIN_REFRESH_INTERVAL
}

/**
 * Freshness is not the same as "we read it recently". A forecast whose only
 * available period is already old is reported stale even if the payload was
 * fetched or revalidated seconds ago.
 */
object WeatherFreshness {
    val MAX_EVIDENCE_AGE: Duration = Duration.ofHours(3)
    val MAX_PAST_VALIDITY: Duration = Duration.ofMinutes(90)

    fun isStale(forecast: WeatherForecast, now: Instant): Boolean {
        if (!forecast.evidenceAt.isAfter(now.minus(MAX_EVIDENCE_AGE))) return true
        return forecast.validAt.isBefore(now.minus(MAX_PAST_VALIDITY))
    }
}
