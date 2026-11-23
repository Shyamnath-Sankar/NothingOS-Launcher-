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
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Test

class FileWeatherCacheStoreTest {

    private val key = "51.5074,-0.1278"
    private val retrievedAt = Instant.parse("2026-11-23T08:00:00Z")

    @Test
    fun aWrittenEntryRoundTripsWithItsRevalidationEvidence() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            val entry = entry(revalidatedAt = Instant.parse("2026-11-23T12:00:00Z"))

            assertTrue(store.write(entry))
            assertEquals(entry, store.read(key))
        }
    }

    @Test
    fun aMissingEntryOrMissingDirectoryIsAbsent() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            assertNull(store.read(key))
            directory.deleteRecursively()
            assertNull(store.read(key))
        }
    }

    @Test
    fun aCorruptFileIsRejectedWithoutBeingDeleted() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            assertTrue(store.write(entry()))
            val file = singleCacheFile(directory)
            file.writeText("this is not the cache format")

            assertNull(store.read(key))
            assertTrue("corrupt file must be left for the next write", file.exists())
        }
    }

    @Test
    fun anOversizedFileIsRejectedBeforeItsBodyIsDecoded() {
        withDirectory { directory ->
            val large = FileWeatherCacheStore(directory, maxFileBytes = 512L * 1024L)
            assertTrue(large.write(entry(body = "x".repeat(4096))))

            val bounded = FileWeatherCacheStore(directory, maxFileBytes = 1024L)
            assertNull(bounded.read(key))
        }
    }

    @Test
    fun anOversizedEntryIsNotWritten() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory, maxFileBytes = 1024L)

            assertFalse(store.write(entry(body = "x".repeat(4096))))
            assertTrue(directory.listFiles().orEmpty().none { it.name.endsWith(CACHE_SUFFIX) })
        }
    }

    @Test
    fun anEntryThatWouldNotDecodeIsRejectedRatherThanReportedDurablyValid() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)

            assertFalse(
                "an oversized header would be unreadable after a successful write",
                store.write(entry().copy(lastModified = "x".repeat(4096))),
            )
            assertFalse(
                "a key with a line break would corrupt the metadata layout",
                store.write(entry().copy(locationKey = "bad\nkey")),
            )
            assertTrue(directory.listFiles().orEmpty().none { it.name.endsWith(CACHE_SUFFIX) })
        }
    }

    @Test
    fun aFailedWritePreservesThePreviousEntry() {
        assumeFalse("permissions are not enforced for root", System.getProperty("user.name") == "root")
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            val previous = entry(body = "previous")
            assertTrue(store.write(previous))

            assertTrue("test needs an unwritable directory", directory.setWritable(false))
            try {
                assertFalse(store.write(entry(body = "replacement")))
            } finally {
                directory.setWritable(true)
            }

            assertEquals(previous, store.read(key))
        }
    }

    @Test
    fun anAtomicReplacementLeavesNoTemporaryFile() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            assertTrue(store.write(entry(body = "first")))
            assertTrue(store.write(entry(body = "second")))

            assertEquals("second", store.read(key)!!.body)
            assertTrue(directory.listFiles().orEmpty().none { it.name.endsWith(".tmp") })
        }
    }

    @Test
    fun aReadFailureDoesNotThrow() {
        withDirectory { directory ->
            val store = FileWeatherCacheStore(directory)
            assertTrue(store.write(entry()))
            val file = singleCacheFile(directory)
            assumeFalse("permissions are not enforced for root", System.getProperty("user.name") == "root")
            assertTrue(file.setReadable(false))

            try {
                assertNull(store.read(key))
            } finally {
                file.setReadable(true)
            }
        }
    }

    private fun withDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("weather-cache").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun singleCacheFile(directory: File): File = directory.listFiles()
        .orEmpty()
        .single { it.name.endsWith(CACHE_SUFFIX) }

    private fun entry(
        body: String = """{"properties":{"timeseries":[]}}""",
        revalidatedAt: Instant? = null,
    ): WeatherCacheEntry = WeatherCacheEntry(
        locationKey = key,
        body = body,
        retrievedAt = retrievedAt,
        expiresAt = retrievedAt.plusSeconds(14_400),
        lastModified = "Mon, 23 Nov 2026 08:00:00 GMT",
        revalidatedAt = revalidatedAt,
    )

    private companion object {
        const val CACHE_SUFFIX = ".weather"
    }
}
