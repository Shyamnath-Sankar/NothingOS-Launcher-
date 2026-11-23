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
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap

/**
 * The raw MET body and its HTTP validators. Keeping the body instead of a
 * pre-rendered label lets a 304 re-validate the exact payload without
 * inventing a new forecast time.
 */
data class WeatherCacheEntry(
    val locationKey: String,
    val body: String,
    val retrievedAt: Instant,
    val expiresAt: Instant?,
    val lastModified: String?,
)

interface WeatherCacheStore {
    fun read(locationKey: String): WeatherCacheEntry?
    fun write(entry: WeatherCacheEntry)
}

class InMemoryWeatherCacheStore : WeatherCacheStore {
    private val entries = ConcurrentHashMap<String, WeatherCacheEntry>()

    override fun read(locationKey: String): WeatherCacheEntry? = entries[locationKey]

    override fun write(entry: WeatherCacheEntry) {
        entries[entry.locationKey] = entry
    }
}

/**
 * Atomic app-private file cache. The directory is supplied by the caller, so
 * this class never reaches for a Context or a shared external location.
 */
class FileWeatherCacheStore(private val directory: File) : WeatherCacheStore {
    override fun read(locationKey: String): WeatherCacheEntry? {
        val file = fileFor(locationKey)
        if (!file.isFile) return null
        return runCatching { decode(file.readText()) }
            .getOrNull()
            ?.takeIf { it.locationKey == locationKey }
    }

    override fun write(entry: WeatherCacheEntry) {
        directory.mkdirs()
        val target = fileFor(entry.locationKey)
        val temporary = File(directory, "${target.name}.tmp")
        temporary.writeText(encode(entry))
        runCatching {
            Files.move(
                temporary.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        }.recoverCatching {
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }.getOrThrow()
    }

    private fun fileFor(locationKey: String): File {
        val name = Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(locationKey.toByteArray(Charsets.UTF_8))
        return File(directory, "$name.weather")
    }

    private fun encode(entry: WeatherCacheEntry): String = buildString {
        append(entry.locationKey).append('\n')
        append(entry.retrievedAt).append('\n')
        append(entry.expiresAt?.toString() ?: NONE).append('\n')
        append(entry.lastModified ?: NONE).append('\n')
        append(entry.body)
    }

    private fun decode(text: String): WeatherCacheEntry? {
        val parts = text.split('\n', limit = METADATA_LINES + 1)
        if (parts.size != METADATA_LINES + 1) return null
        if (parts[0].isBlank()) return null
        val retrievedAt = runCatching { Instant.parse(parts[1]) }.getOrNull() ?: return null
        val expiresAt = parts[2].takeUnless { it == NONE }
            ?.let { runCatching { Instant.parse(it) }.getOrNull() ?: return null }
        val lastModified = parts[3].takeUnless { it == NONE }
        if (parts[4].isBlank()) return null
        return WeatherCacheEntry(
            locationKey = parts[0],
            body = parts[4],
            retrievedAt = retrievedAt,
            expiresAt = expiresAt,
            lastModified = lastModified,
        )
    }

    private companion object {
        const val NONE = "-"
        const val METADATA_LINES = 4
    }
}

/**
 * A refresh may happen only after both a global three-hour minimum and the
 * server's `Expires` boundary. A manual refresh calls the same path, so it
 * cannot bypass either gate.
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
    ): Decision {
        if (cachedRetrievedAt == null) return Decision.FETCH
        if (Duration.between(cachedRetrievedAt, now) < MIN_REFRESH_INTERVAL) return Decision.USE_CACHE
        if (cacheExpiresAt != null && now.isBefore(cacheExpiresAt)) return Decision.USE_CACHE
        return Decision.FETCH
    }

    fun isStale(cachedRetrievedAt: Instant?, now: Instant): Boolean = cachedRetrievedAt == null ||
        Duration.between(cachedRetrievedAt, now) >= MIN_REFRESH_INTERVAL
}
