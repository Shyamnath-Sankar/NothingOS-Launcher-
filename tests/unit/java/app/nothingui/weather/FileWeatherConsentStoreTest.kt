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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FileWeatherConsentStoreTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val location = (
        WeatherConsentPolicy.parseLocation("Home", "51.5074", "-0.1278")
            as WeatherLocationInput.Valid
        ).location

    @Test
    fun aMissingFileIsTheExplicitlyDisabledDefault() {
        val store = store()

        val state = store.read()

        assertFalse(state.enabled)
        assertFalse(state.isActive)
        assertEquals(WeatherConsentState.DISABLED, state)
    }

    @Test
    fun anEnabledStateRoundTripsIncludingTheNormalizedLocationAndGeneration() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)

        val result = store.compareAndSet(expectedGeneration = 0L, next = enabled)

        assertEquals(WeatherConsentWriteResult.Committed(enabled), result)
        assertEquals(enabled, store.read())
    }

    @Test
    fun aDisabledStateClearsThePersistedLabelAndCoordinates() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)
        store.compareAndSet(expectedGeneration = 0L, next = enabled)
        val disabled = WeatherConsentPolicy.disable(enabled)

        val result = store.compareAndSet(expectedGeneration = enabled.generation, next = disabled)

        assertEquals(WeatherConsentWriteResult.Committed(disabled), result)
        val reloaded = store.read()
        assertFalse(reloaded.enabled)
        assertEquals(disabled.generation, reloaded.generation)
        assertEquals(null, reloaded.location)
        val raw = stateFile().readText()
        assertFalse(raw.contains("Home"))
        assertFalse(raw.contains("51.5074"))
        assertFalse(raw.contains("-0.1278"))
    }

    @Test
    fun aStaleGenerationCannotOverwriteANewerDecision() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)
        store.compareAndSet(expectedGeneration = 0L, next = enabled)
        val disabled = WeatherConsentPolicy.disable(enabled)
        store.compareAndSet(expectedGeneration = enabled.generation, next = disabled)

        val stale = store.compareAndSet(
            expectedGeneration = 0L,
            next = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location),
        )

        assertEquals(WeatherConsentWriteResult.Conflict(disabled), stale)
        assertEquals(disabled, store.read())
    }

    @Test
    fun corruptOversizedAndUnsupportedRecordsFailClosedToDisabled() {
        val store = store()
        store.directory().mkdirs()

        listOf(
            "not json",
            "[]",
            "{\"version\":2,\"enabled\":false,\"generation\":0}",
            "{\"version\":1,\"enabled\":\"yes\",\"generation\":0}",
            "{\"version\":1,\"enabled\":false,\"generation\":-1}",
            "{\"version\":1,\"enabled\":true,\"label\":\"Home\",\"latitude\":\"999\",\"longitude\":\"0\",\"generation\":1}",
            "{\"version\":1,\"enabled\":true,\"label\":\"\",\"latitude\":\"0\",\"longitude\":\"0\",\"generation\":1}",
            "{\"version\":1,\"enabled\":false,\"label\":\"Home\",\"latitude\":\"0\",\"longitude\":\"0\",\"generation\":1}",
            "{\"version\":1,\"enabled\":false,\"generation\":0,\"extra\":true}",
            "x".repeat(9000),
        ).forEach { raw ->
            stateFile().writeText(raw)
            assertEquals("$raw must fail closed", WeatherConsentState.DISABLED, store.read())
        }
    }

    @Test
    fun aNextStateMustStrictlyIncreaseTheExpectedGeneration() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)
        store.compareAndSet(expectedGeneration = 0L, next = enabled)
        val sameGeneration = enabled.copy(generation = enabled.generation)

        val result = store.compareAndSet(
            expectedGeneration = enabled.generation,
            next = sameGeneration,
        )

        assertEquals(WeatherConsentWriteResult.StorageFailure, result)
        assertEquals(enabled, store.read())
    }

    @Test
    fun aLowerGenerationCannotReplaceANewerStoredDecision() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)
        store.compareAndSet(expectedGeneration = 0L, next = enabled)
        val newer = WeatherConsentPolicy.disable(enabled)
        store.compareAndSet(expectedGeneration = enabled.generation, next = newer)

        val result = store.compareAndSet(
            expectedGeneration = 0L,
            next = WeatherConsentState.DISABLED,
        )

        assertEquals(WeatherConsentWriteResult.Conflict(newer), result)
        assertEquals(newer, store.read())
    }

    @Test
    fun generationExhaustionFailsClosedAndKeepsTheLastDecision() {
        val store = store()
        val exhausted = WeatherConsentState(
            enabled = true,
            location = location,
            generation = Long.MAX_VALUE,
        )
        assertEquals(
            WeatherConsentWriteResult.Committed(exhausted),
            store.compareAndSet(expectedGeneration = 0L, next = exhausted),
        )

        val result = store.compareAndSet(
            expectedGeneration = Long.MAX_VALUE,
            next = WeatherConsentPolicy.disable(exhausted),
        )

        assertEquals(WeatherConsentWriteResult.StorageFailure, result)
        assertEquals(exhausted, store.read())
    }

    @Test
    fun aCorruptRecordCannotBeOverwrittenByAnEnableWithoutFreshConsent() {
        val store = store()
        store.directory().mkdirs()
        val corrupt = "{\"version\":1,\"enabled\":true,\"label\":\"Home\",\"latitude\":\"999\",\"longitude\":\"0\",\"generation\":7}"
        stateFile().writeText(corrupt)

        val result = store.compareAndSet(
            expectedGeneration = 0L,
            next = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location),
        )

        assertEquals(WeatherConsentWriteResult.StorageFailure, result)
        assertEquals(corrupt, stateFile().readText())
        assertEquals(WeatherConsentState.DISABLED, store.read())
    }

    @Test
    fun aCorruptRecordCanStillBeDurablyDisabled() {
        val store = store()
        store.directory().mkdirs()
        stateFile().writeText("not json")
        val disabled = WeatherConsentState(enabled = false, location = null, generation = 1L)

        val result = store.compareAndSet(expectedGeneration = 0L, next = disabled)

        assertEquals(WeatherConsentWriteResult.Committed(disabled), result)
        assertEquals(disabled, store.read())
    }

    @Test
    fun anUnwritableDirectoryIsReportedAsStorageFailureAndNeverClaimsSuccess() {
        val notADirectory = temporaryFolder.newFile("blocked")
        val store = FileWeatherConsentStore(notADirectory)

        val result = store.compareAndSet(
            expectedGeneration = 0L,
            next = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location),
        )

        assertEquals(WeatherConsentWriteResult.StorageFailure, result)
        assertEquals(WeatherConsentState.DISABLED, store.read())
    }

    @Test
    fun aWriteLeavesNoTemporaryFileBehind() {
        val store = store()
        store.compareAndSet(
            expectedGeneration = 0L,
            next = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location),
        )

        val leftovers = store.directory().listFiles()
            ?.filter { it.name.endsWith(".tmp") }
            .orEmpty()

        assertTrue("unexpected temp files: $leftovers", leftovers.isEmpty())
    }

    @Test
    fun concurrentWritersChooseExactlyOneWinnerForTheSameGeneration() {
        val store = store()
        val enabled = WeatherConsentPolicy.enable(WeatherConsentState.DISABLED, location)
        val threads = 8
        val ready = CountDownLatch(threads)
        val start = CountDownLatch(1)
        val committed = AtomicInteger()
        val conflicts = AtomicInteger()
        val executor = Executors.newFixedThreadPool(threads)
        try {
            repeat(threads) {
                executor.execute {
                    ready.countDown()
                    start.await()
                    when (
                        store.compareAndSet(expectedGeneration = 0L, next = enabled)
                    ) {
                        is WeatherConsentWriteResult.Committed -> committed.incrementAndGet()
                        is WeatherConsentWriteResult.Conflict -> conflicts.incrementAndGet()
                        WeatherConsentWriteResult.StorageFailure -> Unit
                    }
                }
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()
            executor.shutdown()
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS))
        } finally {
            executor.shutdownNow()
        }

        assertEquals(1, committed.get())
        assertEquals(threads - 1, conflicts.get())
        assertEquals(enabled, store.read())
    }

    private fun store(): FileWeatherConsentStore = FileWeatherConsentStore(temporaryFolder.root)

    private fun stateFile(): File = File(temporaryFolder.root, "consent-state.json")

    private fun FileWeatherConsentStore.directory(): File = temporaryFolder.root
}
