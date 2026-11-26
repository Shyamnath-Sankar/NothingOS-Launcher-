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
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Parses a `Retry-After` value with the caller's clock. Numeric values are
 * relative; an HTTP-date is absolute. Missing, zero, negative, malformed or
 * overflowing values return null so the caller can apply a bounded fallback.
 */
object RetryAfterParser {
    fun parse(value: String?, now: Instant): Instant? {
        val raw = value?.trim().orEmpty()
        if (raw.isEmpty()) return null
        raw.toLongOrNull()?.let { seconds ->
            if (seconds <= 0L) return null
            return runCatching { now.plusSeconds(seconds) }.getOrNull()
        }
        return runCatching {
            ZonedDateTime.parse(raw, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant()
        }.getOrNull() ?: runCatching { Instant.parse(raw) }.getOrNull()
    }
}

/**
 * The only weather transport call site. It is built by [WeatherWorkFactory]
 * behind the owner's injected load seam: the explicit opt-in UI, privacy
 * notice and visible HOME lifecycle already gate every call. The build policy
 * selects this repository for every build; the network-off
 * [NoNetworkWeatherWork] remains an explicit offline test double.
 *
 * The repository is safe to call repeatedly: one in-flight request per
 * instance, a persisted global attempt floor that no location, manual refresh,
 * error or recreated instance can bypass, conditional revalidation, bounded
 * `Retry-After` handling and a final session-generation check before any result
 * is committed.
 *
 * The owner must still cancel this coroutine when HOME pauses or the screen
 * turns off and must revoke the session generation. Cancelling the coroutine
 * cancels the in-flight call, but the source code cannot make bytes that have
 * already left the device disappear.
 *
 * Production wiring must inject a persisted [WeatherThrottleStore] (for example
 * [FileWeatherThrottleStore]); the default in-memory store protects only one
 * instance and a recreated repository would otherwise lose the floor.
 */
class MetWeatherRepository(
    private val transport: WeatherHttpTransport,
    private val cacheStore: WeatherCacheStore,
    private val sessionProvider: WeatherSessionProvider,
    private val throttleStore: WeatherThrottleStore,
    private val clock: () -> Instant = { Instant.now() },
    private val parser: MetLocationForecastParser = MetLocationForecastParser(),
    private val minimumInterval: Duration = WeatherRefreshPolicy.MIN_REFRESH_INTERVAL,
    private val forecastEndpoint: String = FORECAST_ENDPOINT,
) {
    private val mutex = Mutex()

    /**
     * A provider boundary that could not be persisted is still enforced for
     * this instance. Without it a later load would only see the shorter local
     * attempt floor and could shorten the server's long delay.
     */
    private var localRetryBoundary: Instant? = null
    private var localRetryPersisted: Boolean = true

    suspend fun load(session: WeatherSession): WeatherLoadResult = mutex.withLock {
        val location = session.location
        if (!session.isActive || location == null) return@withLock WeatherLoadResult.Disabled
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return@withLock WeatherLoadResult.Cancelled

        val now = clock()
        val cacheResult = readCache(location.cacheKey)
        val cached = cacheResult.entry
        val cachedForecast = cached?.let { parseCached(it, now) }
        val lastSuccessStale = cachedForecast?.let { WeatherFreshness.isStale(it, now) } ?: false

        val decision = WeatherRefreshPolicy.decide(
            cachedRetrievedAt = cached?.retrievedAt,
            cacheExpiresAt = cached?.expiresAt,
            now = now,
            cachedRevalidatedAt = cached?.revalidatedAt,
        )
        if (decision == WeatherRefreshPolicy.Decision.USE_CACHE && cachedForecast != null) {
            return@withLock WeatherLoadResult.Success(
                forecast = cachedForecast,
                stale = WeatherFreshness.isStale(cachedForecast, now),
                cacheUpdated = false,
            )
        }

        val retainedBoundary = localRetryBoundary
        if (retainedBoundary != null) {
            if (now.isBefore(retainedBoundary)) {
                return@withLock serveCacheOrUnavailable(
                    reason = WeatherFailureReason.THROTTLED,
                    cachedForecast = cachedForecast,
                    retryAt = retainedBoundary,
                    lastSuccessStale = lastSuccessStale,
                    now = now,
                    retryPersisted = localRetryPersisted,
                )
            }
            localRetryBoundary = null
            localRetryPersisted = true
        }

        val claim = try {
            throttleStore.claim(now, minimumInterval)
        } catch (failure: Exception) {
            WeatherAttemptDecision.StorageFailure(now.plus(minimumInterval))
        }
        when (claim) {
            is WeatherAttemptDecision.Denied -> return@withLock serveCacheOrUnavailable(
                reason = WeatherFailureReason.THROTTLED,
                cachedForecast = cachedForecast,
                retryAt = claim.retryAt,
                lastSuccessStale = lastSuccessStale,
                now = now,
            )

            is WeatherAttemptDecision.StorageFailure -> return@withLock serveCacheOrUnavailable(
                reason = WeatherFailureReason.CACHE_STORAGE,
                cachedForecast = cachedForecast,
                retryAt = claim.retryAt,
                lastSuccessStale = lastSuccessStale,
                now = now,
                retryPersisted = false,
            )

            WeatherAttemptDecision.Allowed -> Unit
        }

        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return@withLock WeatherLoadResult.Cancelled

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
                lastSuccessStale = lastSuccessStale,
            )
        }

        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return@withLock WeatherLoadResult.Cancelled

        when (response.code) {
            HTTP_NOT_MODIFIED -> onNotModified(
                session = session,
                cached = cached,
                cachedForecast = cachedForecast,
                cacheReadFailed = cacheResult.failed,
                lastSuccessStale = lastSuccessStale,
                response = response,
                now = now,
            )

            HTTP_OK -> onFreshBody(
                session = session,
                location = location,
                cachedForecast = cachedForecast,
                lastSuccessStale = lastSuccessStale,
                response = response,
                now = now,
            )

            HTTP_FORBIDDEN -> onRefused(
                session = session,
                reason = WeatherFailureReason.FORBIDDEN,
                response = response,
                cachedForecast = cachedForecast,
                lastSuccessStale = lastSuccessStale,
                now = now,
                fallback = BACKOFF_FORBIDDEN,
            )

            HTTP_TOO_MANY_REQUESTS -> onRefused(
                session = session,
                reason = WeatherFailureReason.RATE_LIMITED,
                response = response,
                cachedForecast = cachedForecast,
                lastSuccessStale = lastSuccessStale,
                now = now,
                fallback = Duration.ofSeconds(DEFAULT_RATE_LIMIT_BACKOFF_SECONDS),
            )

            else -> WeatherLoadResult.Unavailable(
                reason = WeatherFailureReason.HTTP_ERROR,
                lastSuccess = cachedForecast,
                lastSuccessStale = lastSuccessStale,
            )
        }
    }

    /**
     * A manual refresh is intentionally the same call. The persisted attempt
     * floor and the cache policy are the only authority, so a user tap cannot
     * skip either boundary.
     */
    suspend fun refresh(session: WeatherSession): WeatherLoadResult = load(session)

    private suspend fun onNotModified(
        session: WeatherSession,
        cached: WeatherCacheEntry?,
        cachedForecast: WeatherForecast?,
        cacheReadFailed: Boolean,
        lastSuccessStale: Boolean,
        response: WeatherHttpResponse,
        now: Instant,
    ): WeatherLoadResult {
        if (cached == null || cachedForecast == null) {
            return WeatherLoadResult.Unavailable(
                reason = if (cacheReadFailed) {
                    WeatherFailureReason.CACHE_STORAGE
                } else {
                    WeatherFailureReason.CACHE_MISS
                },
                lastSuccess = null,
                lastSuccessStale = lastSuccessStale,
            )
        }
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        val updated = cached.copy(
            revalidatedAt = now,
            expiresAt = response.expiresAt ?: cached.expiresAt,
            lastModified = response.lastModified ?: cached.lastModified,
        )
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        val written = runCatching { cacheStore.write(updated) }.getOrDefault(false)
        val forecast = cachedForecast.copy(revalidatedAt = now)
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        return WeatherLoadResult.Success(
            forecast = forecast,
            stale = WeatherFreshness.isStale(forecast, now),
            cacheUpdated = written,
        )
    }

    private suspend fun onFreshBody(
        session: WeatherSession,
        location: WeatherCoordinates,
        cachedForecast: WeatherForecast?,
        lastSuccessStale: Boolean,
        response: WeatherHttpResponse,
        now: Instant,
    ): WeatherLoadResult {
        val body = response.body ?: return WeatherLoadResult.Unavailable(
            reason = WeatherFailureReason.MALFORMED,
            lastSuccess = cachedForecast,
            lastSuccessStale = lastSuccessStale,
        )
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        return when (
            val parsed = parser.parse(
                body = body,
                locationKey = location.cacheKey,
                retrievedAt = now,
                now = now,
            )
        ) {
            is WeatherParseResult.Success -> {
                currentCoroutineContext().ensureActive()
                if (!isCurrent(session)) return WeatherLoadResult.Cancelled
                val entry = WeatherCacheEntry(
                    locationKey = location.cacheKey,
                    body = body,
                    retrievedAt = now,
                    expiresAt = response.expiresAt,
                    lastModified = response.lastModified,
                    revalidatedAt = null,
                )
                currentCoroutineContext().ensureActive()
                if (!isCurrent(session)) return WeatherLoadResult.Cancelled
                val written = runCatching { cacheStore.write(entry) }.getOrDefault(false)
                currentCoroutineContext().ensureActive()
                if (!isCurrent(session)) return WeatherLoadResult.Cancelled
                WeatherLoadResult.Success(
                    forecast = parsed.forecast,
                    stale = WeatherFreshness.isStale(parsed.forecast, now),
                    cacheUpdated = written,
                )
            }

            is WeatherParseResult.Failure -> WeatherLoadResult.Unavailable(
                reason = parsed.reason.toFailureReason(),
                lastSuccess = cachedForecast,
                lastSuccessStale = lastSuccessStale,
            )
        }
    }

    private suspend fun onRefused(
        session: WeatherSession,
        reason: WeatherFailureReason,
        response: WeatherHttpResponse,
        cachedForecast: WeatherForecast?,
        lastSuccessStale: Boolean,
        now: Instant,
        fallback: Duration,
    ): WeatherLoadResult {
        val serverRetryAt = retryBoundary(response.retryAfter, now, fallback)
        val persisted = runCatching { throttleStore.recordRetryNotBefore(serverRetryAt) }
            .getOrDefault(false)
        val effectiveRetryAt = listOf(serverRetryAt, now.plus(minimumInterval)).maxOrNull()
            ?: serverRetryAt
        localRetryBoundary = listOfNotNull(localRetryBoundary, effectiveRetryAt).maxOrNull()
        localRetryPersisted = persisted
        currentCoroutineContext().ensureActive()
        if (!isCurrent(session)) return WeatherLoadResult.Cancelled
        return WeatherLoadResult.Unavailable(
            reason = reason,
            lastSuccess = cachedForecast,
            retryAt = effectiveRetryAt,
            lastSuccessStale = lastSuccessStale,
            retryPersisted = persisted,
        )
    }

    private fun serveCacheOrUnavailable(
        reason: WeatherFailureReason,
        cachedForecast: WeatherForecast?,
        retryAt: Instant,
        lastSuccessStale: Boolean,
        now: Instant,
        retryPersisted: Boolean = true,
    ): WeatherLoadResult = if (cachedForecast != null) {
        WeatherLoadResult.Success(
            forecast = cachedForecast,
            stale = WeatherFreshness.isStale(cachedForecast, now),
            cacheUpdated = false,
        )
    } else {
        WeatherLoadResult.Unavailable(
            reason = reason,
            lastSuccess = null,
            retryAt = retryAt,
            lastSuccessStale = lastSuccessStale,
            retryPersisted = retryPersisted,
        )
    }

    private fun readCache(locationKey: String): CacheRead = try {
        CacheRead(entry = cacheStore.read(locationKey), failed = false)
    } catch (failure: Exception) {
        CacheRead(entry = null, failed = true)
    }

    private fun parseCached(entry: WeatherCacheEntry, now: Instant): WeatherForecast? = (
        parser.parse(entry.body, entry.locationKey, retrievedAt = entry.retrievedAt, now = now)
            as? WeatherParseResult.Success
        )?.forecast?.copy(revalidatedAt = entry.revalidatedAt)

    private fun retryBoundary(raw: String?, now: Instant, fallback: Duration): Instant = RetryAfterParser.parse(raw, now) ?: now.plus(fallback)

    private fun isCurrent(session: WeatherSession): Boolean = sessionProvider.current() == session

    private fun forecastUrl(location: WeatherCoordinates): String = "$forecastEndpoint?lat=${location.latitudeText}&lon=${location.longitudeText}"

    private fun WeatherParseFailure.toFailureReason(): WeatherFailureReason = when (this) {
        WeatherParseFailure.EMPTY,
        WeatherParseFailure.TOO_LARGE,
        WeatherParseFailure.MALFORMED,
        -> WeatherFailureReason.MALFORMED

        WeatherParseFailure.NO_RELEVANT_PERIOD -> WeatherFailureReason.NO_RELEVANT_PERIOD
    }

    private data class CacheRead(
        val entry: WeatherCacheEntry?,
        val failed: Boolean,
    )

    companion object {
        const val FORECAST_ENDPOINT: String =
            "https://api.met.no/weatherapi/locationforecast/2.0/compact"
        const val HTTP_OK: Int = 200
        const val HTTP_NOT_MODIFIED: Int = 304
        const val HTTP_FORBIDDEN: Int = 403
        const val HTTP_TOO_MANY_REQUESTS: Int = 429

        const val DEFAULT_RATE_LIMIT_BACKOFF_SECONDS: Long = 60L
        val BACKOFF_FORBIDDEN: Duration = Duration.ofHours(1)
    }
}
