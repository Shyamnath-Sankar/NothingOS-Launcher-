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
import java.time.Duration
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherThrottleTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")
    private val threeHours: Duration = Duration.ofHours(3)

    @Test
    fun theNextAllowedBoundaryIsTheLaterOfTheAttemptFloorAndTheServerRequest() {
        val gate = WeatherAttemptGate(
            lastAttemptAt = now,
            retryNotBefore = now.plus(Duration.ofHours(5)),
        )

        assertEquals(
            now.plus(Duration.ofHours(5)),
            gate.nextAllowedAt(threeHours),
        )
        assertEquals(
            now.plus(Duration.ofHours(3)),
            WeatherAttemptGate(lastAttemptAt = now).nextAllowedAt(threeHours),
        )
        assertNull(WeatherAttemptGate().nextAllowedAt(threeHours))
    }

    @Test
    fun theInMemoryStoreRecordsAnAttemptBeforeItIsUsed() {
        val store = InMemoryWeatherThrottleStore()

        assertEquals(WeatherAttemptDecision.Allowed, store.claim(now, threeHours))
        assertEquals(
            WeatherAttemptDecision.Denied(now.plus(threeHours)),
            store.claim(now.plus(Duration.ofMinutes(1)), threeHours),
        )
        assertEquals(now, store.snapshot()!!.lastAttemptAt)
    }

    @Test
    fun aLaterServerBoundaryWinsAndIsNeverShortened() {
        val store = InMemoryWeatherThrottleStore()
        store.claim(now, Duration.ofSeconds(10))
        assertTrue(store.recordRetryNotBefore(now.plus(Duration.ofHours(8))))
        assertTrue(store.recordRetryNotBefore(now.plus(Duration.ofHours(2))))

        assertEquals(
            WeatherAttemptDecision.Denied(now.plus(Duration.ofHours(8))),
            store.claim(now.plus(Duration.ofHours(1)), Duration.ofSeconds(10)),
        )
        assertEquals(now.plus(Duration.ofHours(8)), store.snapshot()!!.retryNotBefore)
    }

    @Test
    fun theFileStorePersistsTheAttemptFloorForARecreatedInstance() {
        val directory = Files.createTempDirectory("weather-throttle").toFile()
        try {
            val first = FileWeatherThrottleStore(directory)
            assertEquals(WeatherAttemptDecision.Allowed, first.claim(now, threeHours))

            val recreated = FileWeatherThrottleStore(directory)
            assertEquals(
                WeatherAttemptDecision.Denied(now.plus(threeHours)),
                recreated.claim(now.plus(Duration.ofMinutes(5)), threeHours),
            )
            assertEquals(now, recreated.snapshot()!!.lastAttemptAt)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun anUnreadableFileFailsClosedInsteadOfAllowingABypass() {
        val directory = Files.createTempDirectory("weather-throttle").toFile()
        try {
            File(directory, "request-gate").writeText("corrupt")
            val store = FileWeatherThrottleStore(directory)

            assertEquals(
                WeatherAttemptDecision.StorageFailure(now.plus(threeHours)),
                store.claim(now, threeHours),
            )
            assertNull(store.snapshot())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun aCorruptGateMakesRecordingTheServerBoundaryFailClosedWithoutReplacingIt() {
        val directory = Files.createTempDirectory("weather-throttle").toFile()
        try {
            val stateFile = File(directory, "request-gate")
            stateFile.writeText("corrupt")
            val store = FileWeatherThrottleStore(directory)

            assertFalse(store.recordRetryNotBefore(now.plus(Duration.ofHours(8))))
            assertEquals("corrupt", stateFile.readText())
            assertNull(store.snapshot())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun concurrentClaimsFromTwoStoreInstancesAllowExactlyOneAttempt() {
        val directory = Files.createTempDirectory("weather-throttle").toFile()
        try {
            val first = FileWeatherThrottleStore(directory)
            val second = FileWeatherThrottleStore(directory)
            val start = CountDownLatch(1)
            val allowed = AtomicInteger()
            val storageFailures = AtomicInteger()
            val thrown = AtomicInteger()
            val workers = (1..12).map { index ->
                thread(isDaemon = true, name = "weather-claim-$index") {
                    start.await()
                    try {
                        when ((if (index % 2 == 0) first else second).claim(now, threeHours)) {
                            WeatherAttemptDecision.Allowed -> allowed.incrementAndGet()
                            is WeatherAttemptDecision.Denied -> Unit
                            is WeatherAttemptDecision.StorageFailure -> storageFailures.incrementAndGet()
                        }
                    } catch (_: Exception) {
                        thrown.incrementAndGet()
                    }
                }
            }

            start.countDown()
            workers.forEach { it.join(10_000) }

            assertEquals("exactly one claim may win", 1, allowed.get())
            assertEquals("locked instances must not fail on each other", 0, storageFailures.get())
            assertEquals("claims must not throw out of the store", 0, thrown.get())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun aMissingFileAllowsTheFirstAttempt() {
        val directory = Files.createTempDirectory("weather-throttle").toFile()
        try {
            val store = FileWeatherThrottleStore(directory)

            assertEquals(WeatherAttemptDecision.Allowed, store.claim(now, threeHours))
        } finally {
            directory.deleteRecursively()
        }
    }
}
