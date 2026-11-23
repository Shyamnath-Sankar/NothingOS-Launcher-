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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The only weather transport call site. It is deliberately not wired to any
 * widget, worker or settings screen yet: the production network path stays
 * disabled until an explicit opt-in UI, privacy notice and a visible HOME
 * lifecycle gate exist.
 *
 * The repository is safe to call repeatedly: one in-flight request per
 * location, a three-hour cache floor, conditional revalidation, bounded
 * 403/429 backoff and a final session-generation check before any result is
 * committed. It never schedules a retry by itself.
 */
class MetWeatherRepository(
    private val transport: WeatherHttpTransport,
    private val cacheStore: WeatherCacheStore,
    private val sessionProvider: WeatherSessionProvider,
    private val clock: () -> Instant = { Instant.now() },
    private val parser: MetLocationForecastParser = MetLocationForecastParser(),
) {
    private val mutex = Mutex()

    @Volatile
    private var backoffUntil: Instant? = null

    suspend fun load(session: WeatherSession): WeatherLoadResult = mutex.withLock {
        val location = session.location
        if (!session.isActive || location == null) return@withLock WeatherLoadResult.Disabled
        if (!isCurrent(session)) return@withLock WeatherLoadResult.Cancelled

        val now = clock()
        val cached = cacheStore.read(location.cacheKey)
        val cachedForecast = cached?.let { parseCached(it, now) }
        val activeBackoff = backoffUntil
        if (activeBackoff != null && now.isBefore(activeBackoff)) {
            return@withLock WeatherLoadResult.Unavailable(
                reason = WeatherFailureReason.RATE_LIMITED,
                lastSuccess = cachedForecast,
                retryAt = activeBackoff,
            )
        }

        val decision = WeatherRefreshPolicy.decide(
            cachedRetrievedAt = cached?.retrievedAt,
            cacheExpiresAt = cached?.expiresAt,
            now = now,
        )
        if (decision == WeatherRefreshPolicy.Decision.USE_CACHE && cached != null && cachedForecast != null) {
            return@withLock WeatherLoadResult.Success(
                forecast = cachedForecast,
                stale = WeatherRefreshPolicy.isStale(cached.retrievedAt, now),
            )
        }

        val request = WeatherHttpRequest(
            url = forecastUrl(location),
            ifModifiedSince = cached?.lastModified?.takeIf { cachedForecast != null },
        )
        val response = try {
            transport.get(request)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            return@withLock WeatherLoadResult.Unavailable(
                reason = WeatherFailureReason.NETWORK,
                lastSuccess = cachedForecast,
            )
        }

        when (response.code) {
            HTTP_NOT_MODIFIED -> onNotModified(session, cached, cachedForecast, response, now)

            HTTP_OK -> onFreshBody(session, location, cachedForecast, response, now)

            HTTP_FORBIDDEN -> {
                val retryAt = now.plus(BACKOFF_FORBIDDEN)
                backoffUntil = retryAt
                WeatherLoadResult.Unavailable(WeatherFailureReason.FORBIDDEN, cachedForecast, retryAt)
            }

            HTTP_TOO_MANY_REQUESTS -> {
                val retryAt = now.plusSeconds(normalizedRetryAfter(response.retryAfterSeconds))
                backoffUntil = retryAt
                WeatherLoadResult.Unavailable(WeatherFailureReason.RATE_LIMITED, cachedForecast, retryAt)
            }

            else -> WeatherLoadResult.Unavailable(WeatherFailureReason.HTTP_ERROR, cachedForecast)
        }
    }

    /**
     * A manual refresh is intentionally the same call. The cache policy is the
     * only authority, so a user tap cannot skip the three-hour floor.
     */
    suspend fun refresh(session: WeatherSession): WeatherLoadResult = load(session)

    private fun onNotModified(
        session: WeatherSession,
        cached: WeatherCacheEntry?,
        cachedForecast: WeatherForecast?,
        response: WeatherHttpResponse,
        now: Instant,
    ): WeatherLoadResult {
        if (cached == null || cachedForecast == null) {
            return WeatherLoadResult.Unavailable(WeatherFailureReason.CACHE_MISS)
        }
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        cacheStore.write(
            cached.copy(
                retrievedAt = now,
                expiresAt = response.expiresAt ?: cached.expiresAt,
                lastModified = response.lastModified ?: cached.lastModified,
            ),
        )
        return WeatherLoadResult.Success(
            forecast = cachedForecast.copy(retrievedAt = now),
            stale = false,
        )
    }

    private fun onFreshBody(
        session: WeatherSession,
        location: WeatherCoordinates,
        cachedForecast: WeatherForecast?,
        response: WeatherHttpResponse,
        now: Instant,
    ): WeatherLoadResult {
        val body = response.body
            ?: return WeatherLoadResult.Unavailable(WeatherFailureReason.MALFORMED, cachedForecast)
        return when (val parsed = parser.parse(body, location.cacheKey, retrievedAt = now, now = now)) {
            is WeatherParseResult.Success -> {
                if (!isCurrent(session)) return WeatherLoadResult.Cancelled
                cacheStore.write(
                    WeatherCacheEntry(
                        locationKey = location.cacheKey,
                        body = body,
                        retrievedAt = now,
                        expiresAt = response.expiresAt,
                        lastModified = response.lastModified,
                    ),
                )
                WeatherLoadResult.Success(forecast = parsed.forecast, stale = false)
            }

            is WeatherParseResult.Failure -> WeatherLoadResult.Unavailable(
                reason = parsed.reason.toFailureReason(),
                lastSuccess = cachedForecast,
            )
        }
    }

    private fun parseCached(entry: WeatherCacheEntry, now: Instant): WeatherForecast? = (
        parser.parse(entry.body, entry.locationKey, retrievedAt = entry.retrievedAt, now = now)
            as? WeatherParseResult.Success
        )?.forecast

    private fun isCurrent(session: WeatherSession): Boolean = sessionProvider.current() == session

    private fun forecastUrl(location: WeatherCoordinates): String = "$FORECAST_ENDPOINT?lat=${location.latitudeText}&lon=${location.longitudeText}"

    private fun normalizedRetryAfter(seconds: Long?): Long {
        if (seconds == null || seconds <= 0L) return DEFAULT_RATE_LIMIT_BACKOFF_SECONDS
        return seconds.coerceAtMost(MAX_RATE_LIMIT_BACKOFF_SECONDS)
    }

    private fun WeatherParseFailure.toFailureReason(): WeatherFailureReason = when (this) {
        WeatherParseFailure.EMPTY,
        WeatherParseFailure.TOO_LARGE,
        WeatherParseFailure.MALFORMED,
        -> WeatherFailureReason.MALFORMED

        WeatherParseFailure.NO_RELEVANT_PERIOD -> WeatherFailureReason.NO_RELEVANT_PERIOD
    }

    companion object {
        const val FORECAST_ENDPOINT: String =
            "https://api.met.no/weatherapi/locationforecast/2.0/compact"
        const val HTTP_OK: Int = 200
        const val HTTP_NOT_MODIFIED: Int = 304
        const val HTTP_FORBIDDEN: Int = 403
        const val HTTP_TOO_MANY_REQUESTS: Int = 429

        const val DEFAULT_RATE_LIMIT_BACKOFF_SECONDS: Long = 60L
        const val MAX_RATE_LIMIT_BACKOFF_SECONDS: Long = 6L * 60L * 60L
        val BACKOFF_FORBIDDEN: Duration = Duration.ofHours(1)
    }
}
