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

import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherCachePolicyTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")

    @Test
    fun aMissingCacheAlwaysFetches() {
        assertEquals(
            WeatherRefreshPolicy.Decision.FETCH,
            WeatherRefreshPolicy.decide(cachedRetrievedAt = null, cacheExpiresAt = null, now = now),
        )
    }

    @Test
    fun theThreeHourMinimumWinsEvenWhenExpiresHasPassed() {
        val retrievedAt = now.minus(Duration.ofMinutes(30))

        assertEquals(
            WeatherRefreshPolicy.Decision.USE_CACHE,
            WeatherRefreshPolicy.decide(
                cachedRetrievedAt = retrievedAt,
                cacheExpiresAt = now.minus(Duration.ofMinutes(10)),
                now = now,
            ),
        )
    }

    @Test
    fun aLaterExpiresBoundaryDelaysTheRefreshBeyondThreeHours() {
        assertEquals(
            WeatherRefreshPolicy.Decision.USE_CACHE,
            WeatherRefreshPolicy.decide(
                cachedRetrievedAt = now.minus(Duration.ofHours(3)),
                cacheExpiresAt = now.plus(Duration.ofHours(1)),
                now = now,
            ),
        )
    }

    @Test
    fun bothBoundariesMustPassBeforeFetching() {
        assertEquals(
            WeatherRefreshPolicy.Decision.FETCH,
            WeatherRefreshPolicy.decide(
                cachedRetrievedAt = now.minus(Duration.ofHours(3)),
                cacheExpiresAt = now.minus(Duration.ofMinutes(1)),
                now = now,
            ),
        )
    }

    @Test
    fun withoutExpiresOnlyTheThreeHourMinimumApplies() {
        assertEquals(
            WeatherRefreshPolicy.Decision.USE_CACHE,
            WeatherRefreshPolicy.decide(
                cachedRetrievedAt = now.minus(Duration.ofHours(2)).minus(Duration.ofMinutes(59)),
                cacheExpiresAt = null,
                now = now,
            ),
        )
        assertEquals(
            WeatherRefreshPolicy.Decision.FETCH,
            WeatherRefreshPolicy.decide(
                cachedRetrievedAt = now.minus(Duration.ofHours(3)),
                cacheExpiresAt = null,
                now = now,
            ),
        )
    }

    @Test
    fun stalenessStartsAtTheMinimumBoundary() {
        assertFalse(WeatherRefreshPolicy.isStale(now.minus(Duration.ofMinutes(59)), now))
        assertTrue(WeatherRefreshPolicy.isStale(now.minus(Duration.ofHours(3)), now))
        assertTrue(WeatherRefreshPolicy.isStale(null, now))
    }
}
