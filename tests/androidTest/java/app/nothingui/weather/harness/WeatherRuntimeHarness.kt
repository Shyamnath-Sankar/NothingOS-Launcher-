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

package app.nothingui.weather.harness

import android.content.Context
import android.os.Process
import android.os.SystemClock
import app.nothingui.weather.FileWeatherCacheStore
import app.nothingui.weather.FileWeatherConsentStore
import app.nothingui.weather.FileWeatherThrottleStore
import app.nothingui.weather.MetWeatherRepository
import app.nothingui.weather.OkHttpWeatherTransport
import app.nothingui.weather.WeatherCacheStore
import app.nothingui.weather.WeatherConsentPolicy
import app.nothingui.weather.WeatherConsentState
import app.nothingui.weather.WeatherConsentWriteResult
import app.nothingui.weather.WeatherCoordinates
import app.nothingui.weather.WeatherFailureReason
import app.nothingui.weather.WeatherHomeOwner
import app.nothingui.weather.WeatherHttpRequest
import app.nothingui.weather.WeatherHttpResponse
import app.nothingui.weather.WeatherHttpTransport
import app.nothingui.weather.WeatherLoadResult
import app.nothingui.weather.WeatherLoadWork
import app.nothingui.weather.WeatherManualLocation
import app.nothingui.weather.WeatherResultSink
import app.nothingui.weather.WeatherRuntimeSessionProvider
import app.nothingui.weather.WeatherSession
import app.nothingui.weather.WeatherSessionProvider
import app.nothingui.weather.WeatherThrottleStore
import app.nothingui.weather.WeatherWorkFactory
import java.io.File
import java.io.IOException
import java.time.Duration
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

/**
 * A small, test-APK-only runtime exercise of the real Weather work graph.
 *
 * It builds the production [WeatherWorkFactory], the real
 * [MetWeatherRepository] behind it and the real [OkHttpWeatherTransport] with
 * a test-only OkHttp interceptor. The interceptor records the exact
 * MET-shaped request and returns a synthetic response, so no socket, no
 * permission, no MET endpoint and no other external traffic is used. The
 * launcher runtime is not used here: the harness injects its fake transport
 * through the same `WeatherWorkFactory` seam.
 *
 * Every case writes only below a unique `dotwel-weather-harness-test/run-*`
 * subtree of the target application's own `noBackupFilesDir`, never the test
 * APK's directory (the instrumentation runs under the target uid and cannot
 * write the test APK data directory) and never the production
 * `dotwel-weather-private` directory. Before any case runs, a checked
 * write/read/delete probe proves the process-owned storage is usable, so a
 * storage failure is reported once with an actionable message rather than as
 * six misleading network failures. Cleanup removes only the unique run
 * directory this invocation created. The owner case drives the actual
 * [WeatherHomeOwner] with synthetic lifecycle calls, not a real Launcher
 * activity transition, and is labelled as such in its report detail.
 */
object WeatherRuntimeHarness {
    const val VERSION: Int = 1

    private const val CASE_TIMEOUT_MS = 20_000L
    private const val TEMPERATURE_TOLERANCE = 0.0001
    private const val STORAGE_ROOT_DIRECTORY = "dotwel-weather-harness-test"
    private const val PRODUCTION_ROOT_DIRECTORY = "dotwel-weather-private"

    private val fixedNow: Instant = Instant.parse("2026-11-23T12:00:00Z")
    private val location: WeatherCoordinates = WeatherCoordinates.from(51.50744, -0.12783)!!
    private val session: WeatherSession = WeatherSession(
        enabled = true,
        visible = true,
        generation = 1,
        location = location,
    )
    private val enabledConsent: WeatherConsentState = WeatherConsentPolicy.enable(
        WeatherConsentState.DISABLED,
        WeatherManualLocation(label = "Harness", coordinates = location),
    )
    private val coordinatePattern = Regex("^-?\\d+\\.\\d{4}$")
    private val jsonMediaType = "application/json".toMediaType()

    private const val LAST_MODIFIED = "Mon, 23 Nov 2026 11:00:00 GMT"
    private const val LAST_MODIFIED_AFTER_REVALIDATION = "Mon, 23 Nov 2026 16:00:00 GMT"
    private const val EXPIRES_AFTER_4_HOURS = "Mon, 23 Nov 2026 16:00:00 GMT"
    private const val EXPIRES_AFTER_8_HOURS = "Mon, 23 Nov 2026 20:00:00 GMT"

    private val metBodyAt075 = """
        {
          "type": "Feature",
          "geometry": {"type": "Point", "coordinates": [10.7466, 59.9123, 0]},
          "properties": {
            "meta": {
              "updated_at": "2026-11-23T11:00:00Z",
              "units": {"air_temperature": "celsius"}
            },
            "timeseries": [
              {
                "time": "2026-11-23T13:00:00Z",
                "data": {
                  "instant": {"details": {"air_temperature": 7.5}},
                  "next_1_hours": {"summary": {"symbol_code": "cloudy"}}
                }
              }
            ]
          }
        }
    """.trimIndent()

    private val metBodyAt090 = """
        {
          "type": "Feature",
          "geometry": {"type": "Point", "coordinates": [10.7466, 59.9123, 0]},
          "properties": {
            "meta": {
              "updated_at": "2026-11-23T15:00:00Z",
              "units": {"air_temperature": "celsius"}
            },
            "timeseries": [
              {
                "time": "2026-11-23T17:00:00Z",
                "data": {
                  "instant": {"details": {"air_temperature": 9.0}},
                  "next_1_hours": {"summary": {"symbol_code": "partlycloudy_day"}}
                }
              }
            ]
          }
        }
    """.trimIndent()

    /**
     * Runs the six named cases against process-owned storage below the target
     * application's `noBackupFilesDir`. The caller must pass the target
     * application context, not the test APK context: the instrumentation
     * process runs under the target uid, so only the target app's data
     * directory is writable.
     */
    fun run(context: Context): WeatherHarnessReport {
        val storage = try {
            openStorage(context)
        } catch (failure: Throwable) {
            return WeatherHarnessReport(
                listOf(
                    WeatherHarnessCase(
                        name = "storage-preflight",
                        passed = false,
                        detail = (
                            "weather harness storage preflight failed before any case: " +
                                (failure.message ?: failure.toString())
                            ).oneLine(),
                    ),
                ),
            )
        }
        val outcomes = mutableListOf<WeatherHarnessCase>()
        var cleanupFailure: String? = null
        try {
            runCase(outcomes, "okhttp-request-shape") { caseRequestShape(storage.runRoot) }
            runCase(outcomes, "okhttp-parse-cache-expires") { caseParseCacheExpires(storage.runRoot) }
            runCase(outcomes, "okhttp-conditional-304") { caseConditional304(storage.runRoot) }
            runCase(outcomes, "throttle-persistence-across-restart") {
                caseThrottlePersistence(storage.runRoot)
            }
            runCase(outcomes, "cancel-late-response-dropped") { caseCancelLateResponse(storage.runRoot) }
            runCase(outcomes, "owner-lifecycle-seam") { caseOwnerSeam(storage.runRoot) }
        } finally {
            cleanupFailure = cleanupStorage(storage)
        }
        cleanupFailure?.let {
            outcomes += WeatherHarnessCase(name = "storage-cleanup", passed = false, detail = it.oneLine())
        }
        return WeatherHarnessReport(outcomes.toList())
    }

    private class HarnessStorage(
        val harnessRoot: File,
        val runRoot: File,
        val rootExisted: Boolean,
    )

    /**
     * Opens a unique run directory below the process-owned no-backup root and
     * proves it usable with a real write/read/delete probe. Every boundary is
     * checked so a wrong uid, a canonical-path escape or an accidental overlap
     * with production storage fails closed with a clear message.
     */
    private fun openStorage(context: Context): HarnessStorage {
        val processUid = Process.myUid()
        val targetUid = context.applicationInfo.uid
        HarnessAssert.check(
            processUid == targetUid,
            "the harness uid $processUid does not own ${context.packageName} (uid $targetUid); " +
                "the process-owned no-backup directory would not be writable",
        )
        val ownedRoot = context.noBackupFilesDir.canonicalFile
        val harnessRoot = File(ownedRoot, STORAGE_ROOT_DIRECTORY).canonicalFile
        HarnessAssert.check(
            harnessRoot.parentFile == ownedRoot && harnessRoot.name == STORAGE_ROOT_DIRECTORY,
            "the harness storage root ${harnessRoot.path} escaped its owned root ${ownedRoot.path}",
        )
        val productionRoot = File(ownedRoot, PRODUCTION_ROOT_DIRECTORY).canonicalFile
        HarnessAssert.check(
            harnessRoot != productionRoot && !isInside(harnessRoot, productionRoot),
            "the harness storage root ${harnessRoot.path} overlaps production ${productionRoot.path}",
        )
        val rootExisted = harnessRoot.isDirectory
        HarnessAssert.check(
            harnessRoot.isDirectory || harnessRoot.mkdirs() || harnessRoot.isDirectory,
            "the harness could not create its storage root ${harnessRoot.path}; " +
                "check that the instrumentation runs under the target uid",
        )
        val runRoot = File(
            harnessRoot,
            "run-${System.currentTimeMillis()}-${Process.myPid()}",
        ).canonicalFile
        HarnessAssert.check(
            runRoot.parentFile == harnessRoot,
            "the harness run directory ${runRoot.path} escaped ${harnessRoot.path}",
        )
        HarnessAssert.check(
            runRoot.isDirectory || runRoot.mkdirs() || runRoot.isDirectory,
            "the harness could not create its run directory ${runRoot.path}; " +
                "check that the instrumentation runs under the target uid",
        )
        try {
            probeStorage(runRoot)
        } catch (failure: Throwable) {
            runRoot.deleteRecursively()
            if (!rootExisted && harnessRoot.listFiles()?.isEmpty() != false) {
                harnessRoot.delete()
            }
            throw failure
        }
        return HarnessStorage(harnessRoot = harnessRoot, runRoot = runRoot, rootExisted = rootExisted)
    }

    private fun probeStorage(runRoot: File) {
        val payload = "dotwel-weather-harness-storage-probe-${System.nanoTime()}"
        val probe = File(runRoot, "storage-probe.txt")
        probe.writeText(payload)
        HarnessAssert.check(probe.isFile, "the storage probe did not create ${probe.path}")
        HarnessAssert.eq(payload, probe.readText(), "the storage probe read back")
        HarnessAssert.check(probe.delete(), "the storage probe could not delete ${probe.path}")
        HarnessAssert.check(!probe.exists(), "the storage probe survived deletion at ${probe.path}")
    }

    /**
     * Removes only this invocation's unique run directory. The shared harness
     * root is removed only when this invocation created it and it is empty, so
     * a pre-existing directory or another run's files are never deleted.
     */
    private fun cleanupStorage(storage: HarnessStorage): String? {
        storage.runRoot.deleteRecursively()
        if (storage.runRoot.exists()) {
            return "the harness could not delete its run directory ${storage.runRoot.path}"
        }
        if (!storage.rootExisted && storage.harnessRoot.listFiles()?.isEmpty() != false) {
            storage.harnessRoot.delete()
            if (storage.harnessRoot.exists()) {
                return "the harness could not remove its empty storage root ${storage.harnessRoot.path}"
            }
        }
        return null
    }

    private fun isInside(child: File, parent: File): Boolean =
        child.path.startsWith(parent.path + File.separator)

    private fun runCase(
        outcomes: MutableList<WeatherHarnessCase>,
        name: String,
        block: suspend () -> String,
    ) {
        val startedAt = SystemClock.elapsedRealtime()
        val outcome = try {
            val detail = runBlocking { withTimeout(CASE_TIMEOUT_MS) { block() } }
            WeatherHarnessCase(name = name, passed = true, detail = detail.ifBlank { "ok" })
        } catch (_: TimeoutCancellationException) {
            WeatherHarnessCase(name = name, passed = false, detail = "timeout after ${CASE_TIMEOUT_MS}ms")
        } catch (failure: Throwable) {
            val message = failure.message ?: failure.toString()
            WeatherHarnessCase(name = name, passed = false, detail = message.oneLine())
        }
        val elapsed = SystemClock.elapsedRealtime() - startedAt
        outcomes += outcome.copy(detail = "${outcome.detail} [${elapsed}ms]".oneLine())
    }

    private suspend fun caseRequestShape(root: File): String {
        val directory = caseDirectory(root, "request-shape")
        val interceptor = RecordingInterceptor(
            listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
            ),
        )
        val work = weatherWork(
            transport = transport(interceptor),
            cache = FileWeatherCacheStore(File(directory, "cache")),
            throttle = FileWeatherThrottleStore(File(directory, "throttle")),
            provider = StaticSessionProvider(session),
            clock = FakeClock(fixedNow),
        )

        val result = work.load(session)
        HarnessAssert.check(result is WeatherLoadResult.Success, "expected a parsed forecast, got $result")
        HarnessAssert.eq(1, interceptor.requests.size, "request count")

        val request = interceptor.requests.single()
        HarnessAssert.check(
            request.url.startsWith(MetWeatherRepository.FORECAST_ENDPOINT + "?"),
            "not a MET-shaped request: ${request.url}",
        )
        HarnessAssert.eq("/weatherapi/locationforecast/2.0/compact", request.path, "request path")
        HarnessAssert.eq("51.5074", request.latitude, "four-decimal latitude")
        HarnessAssert.eq("-0.1278", request.longitude, "four-decimal longitude")
        HarnessAssert.check(
            request.latitude?.let(coordinatePattern::matches) == true,
            "latitude is not a four-decimal value: ${request.latitude}",
        )
        HarnessAssert.check(
            request.longitude?.let(coordinatePattern::matches) == true,
            "longitude is not a four-decimal value: ${request.longitude}",
        )
        HarnessAssert.eq(
            "DotWelLauncher/harness-1 (+${OkHttpWeatherTransport.PROJECT_ISSUES_URL})",
            request.userAgent,
            "project User-Agent",
        )
        HarnessAssert.eq("application/json", request.accept, "Accept header")
        HarnessAssert.eq(null, request.ifModifiedSince, "first request must not be conditional")
        return "one MET-shaped fake-interceptor request; UA, path and 4dp coordinates verified"
    }

    private suspend fun caseParseCacheExpires(root: File): String {
        val directory = caseDirectory(root, "parse-cache-expires")
        val interceptor = RecordingInterceptor(
            listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt090,
                    expires = EXPIRES_AFTER_8_HOURS,
                    lastModified = LAST_MODIFIED_AFTER_REVALIDATION,
                ),
            ),
        )
        val cache = FileWeatherCacheStore(File(directory, "cache"))
        val clock = FakeClock(fixedNow)
        val work = weatherWork(
            transport = transport(interceptor),
            cache = cache,
            throttle = FileWeatherThrottleStore(File(directory, "throttle")),
            provider = StaticSessionProvider(session),
            clock = clock,
        )

        val first = work.load(session) as? WeatherLoadResult.Success
            ?: throw AssertionError("the first load did not return a forecast")
        HarnessAssert.eq(7.5, first.forecast.temperatureCelsius, "parsed temperature")
        HarnessAssert.eq("cloudy", first.forecast.symbolCode, "parsed symbol")
        HarnessAssert.check(first.cacheUpdated, "a fresh 200 must durably write the cache")
        val stored = cache.read(location.cacheKey)
            ?: throw AssertionError("the fresh response was not cached")
        HarnessAssert.eq(fixedNow, stored.retrievedAt, "cached retrievedAt")
        HarnessAssert.eq(fixedNow.plus(Duration.ofHours(4)), stored.expiresAt, "cached Expires")
        HarnessAssert.eq(LAST_MODIFIED, stored.lastModified, "cached Last-Modified")

        clock.now = fixedNow.plus(Duration.ofMinutes(30))
        val served = work.load(session) as? WeatherLoadResult.Success
            ?: throw AssertionError("the fresh cache was not served")
        HarnessAssert.eq(1, interceptor.requests.size, "a fresh cache must not request again")
        HarnessAssert.check(!served.cacheUpdated, "serving the cache is not a cache update")

        clock.now = fixedNow.plus(Duration.ofHours(3)).plus(Duration.ofMinutes(30))
        work.load(session)
        HarnessAssert.eq(
            1,
            interceptor.requests.size,
            "the server Expires boundary must keep the cache inside its window",
        )

        clock.now = fixedNow.plus(Duration.ofHours(4)).plus(Duration.ofMinutes(30))
        val refetched = work.load(session) as? WeatherLoadResult.Success
            ?: throw AssertionError("the post-Expires refetch did not parse")
        HarnessAssert.eq(2, interceptor.requests.size, "a past-Expires cache may refetch")
        HarnessAssert.eq(
            LAST_MODIFIED,
            interceptor.requests[1].ifModifiedSince,
            "the refetch must carry the cached validator",
        )
        HarnessAssert.eq(9.0, refetched.forecast.temperatureCelsius, "refetched temperature")
        val refreshed = cache.read(location.cacheKey)
            ?: throw AssertionError("the refetched response was not cached")
        HarnessAssert.eq(
            fixedNow.plus(Duration.ofHours(4)).plus(Duration.ofMinutes(30)),
            refreshed.retrievedAt,
            "refetched retrievedAt",
        )
        HarnessAssert.eq(fixedNow.plus(Duration.ofHours(8)), refreshed.expiresAt, "refetched Expires")
        return "parsed 7.5 cloudy; cache/Expires gated requests at 1 then 2 with a conditional refetch"
    }

    private suspend fun caseConditional304(root: File): String {
        val directory = caseDirectory(root, "conditional-304")
        val interceptor = RecordingInterceptor(
            listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
                FakeHttpResponse(
                    code = MetWeatherRepository.HTTP_NOT_MODIFIED,
                    body = "",
                    expires = EXPIRES_AFTER_8_HOURS,
                    lastModified = LAST_MODIFIED_AFTER_REVALIDATION,
                ),
            ),
        )
        val cache = FileWeatherCacheStore(File(directory, "cache"))
        val clock = FakeClock(fixedNow)
        val work = weatherWork(
            transport = transport(interceptor),
            cache = cache,
            throttle = FileWeatherThrottleStore(File(directory, "throttle")),
            provider = StaticSessionProvider(session),
            clock = clock,
        )

        work.load(session)
        clock.now = fixedNow.plus(Duration.ofHours(4)).plus(Duration.ofMinutes(30))
        val revalidated = work.load(session) as? WeatherLoadResult.Success
            ?: throw AssertionError("the conditional 304 did not retain a forecast")

        HarnessAssert.eq(2, interceptor.requests.size, "request count after the conditional fetch")
        HarnessAssert.eq(
            LAST_MODIFIED,
            interceptor.requests[1].ifModifiedSince,
            "If-Modified-Since must carry the previous Last-Modified",
        )
        HarnessAssert.eq(7.5, revalidated.forecast.temperatureCelsius, "the cached body must survive a 304")
        HarnessAssert.check(revalidated.cacheUpdated, "a 304 must durably revalidate the cache")
        HarnessAssert.eq(clock.now, revalidated.forecast.revalidatedAt, "revalidated forecast time")
        val stored = cache.read(location.cacheKey)
            ?: throw AssertionError("the revalidated cache entry is missing")
        HarnessAssert.eq(metBodyAt075, stored.body, "a 304 must not invent a new body")
        HarnessAssert.eq(clock.now, stored.revalidatedAt, "cached revalidatedAt")
        HarnessAssert.eq(fixedNow.plus(Duration.ofHours(8)), stored.expiresAt, "revalidated Expires")
        HarnessAssert.eq(
            LAST_MODIFIED_AFTER_REVALIDATION,
            stored.lastModified,
            "revalidated Last-Modified",
        )

        clock.now = fixedNow.plus(Duration.ofHours(5))
        work.load(session)
        HarnessAssert.eq(
            2,
            interceptor.requests.size,
            "a recent 304 must keep the refreshed cache fresh",
        )
        return "conditional If-Modified-Since request got 304; body retained, Expires/validators extended"
    }

    private suspend fun caseThrottlePersistence(root: File): String {
        val directory = caseDirectory(root, "throttle-persistence")
        val throttleDirectory = File(directory, "throttle")
        val interceptor = RecordingInterceptor(
            listOf(FakeHttpResponse(code = 429, body = "", retryAfter = "600")),
        )
        val firstWork = weatherWork(
            transport = transport(interceptor),
            cache = FileWeatherCacheStore(File(directory, "cache")),
            throttle = FileWeatherThrottleStore(throttleDirectory),
            provider = StaticSessionProvider(session),
            clock = FakeClock(fixedNow),
        )

        val limited = firstWork.load(session) as? WeatherLoadResult.Unavailable
            ?: throw AssertionError("a 429 did not produce an unavailable result")
        HarnessAssert.eq(WeatherFailureReason.RATE_LIMITED, limited.reason, "429 reason")
        HarnessAssert.eq(fixedNow.plus(Duration.ofHours(3)), limited.retryAt, "bounded retry time")

        val snapshot = FileWeatherThrottleStore(throttleDirectory).snapshot()
            ?: throw AssertionError("the persisted throttle could not be read")
        HarnessAssert.eq(fixedNow, snapshot.lastAttemptAt, "persisted last attempt")
        HarnessAssert.eq(fixedNow.plus(Duration.ofSeconds(600)), snapshot.retryNotBefore, "Retry-After")

        val movedLocation = WeatherCoordinates.from(48.8566, 2.3522)!!
        val movedSession = session.copy(generation = 2, location = movedLocation)
        val recreatedInterceptor = RecordingInterceptor(
            listOf(FakeHttpResponse(code = 200, body = metBodyAt075, expires = EXPIRES_AFTER_4_HOURS)),
        )
        val recreated = weatherWork(
            transport = transport(recreatedInterceptor),
            cache = FileWeatherCacheStore(File(directory, "cache-2")),
            throttle = FileWeatherThrottleStore(throttleDirectory),
            provider = StaticSessionProvider(movedSession),
            clock = FakeClock(fixedNow.plus(Duration.ofMinutes(5))),
        ).load(movedSession) as? WeatherLoadResult.Unavailable
            ?: throw AssertionError("the recreated work ignored the persisted throttle")

        HarnessAssert.eq(WeatherFailureReason.THROTTLED, recreated.reason, "persisted throttle reason")
        HarnessAssert.eq(fixedNow.plus(Duration.ofHours(3)), recreated.retryAt, "persisted retry boundary")
        HarnessAssert.eq(0, recreatedInterceptor.requests.size, "a persisted floor must block the request")
        return "429 Retry-After persisted; a recreated work/location sent zero requests and stayed throttled"
    }

    private suspend fun caseCancelLateResponse(root: File): String {
        val cancelDirectory = caseDirectory(root, "cancel")
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val interceptor = RecordingInterceptor(
            responses = listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
            ),
            startGate = started,
            releaseGate = release,
            cancelledGate = cancelled,
        )
        val cancelCache = FileWeatherCacheStore(File(cancelDirectory, "cache"))
        val cancelWork = weatherWork(
            transport = transport(interceptor),
            cache = cancelCache,
            throttle = FileWeatherThrottleStore(File(cancelDirectory, "throttle")),
            provider = StaticSessionProvider(session),
            clock = FakeClock(fixedNow),
        )
        coroutineScope {
            val job = launch(Dispatchers.IO) { cancelWork.load(session) }
            try {
                HarnessAssert.check(
                    started.await(5, TimeUnit.SECONDS),
                    "the real OkHttp transport never started",
                )
                job.cancelAndJoin()
                HarnessAssert.check(
                    cancelled.await(5, TimeUnit.SECONDS),
                    "the interceptor did not observe the OkHttp cancellation",
                )
                HarnessAssert.eq(1, interceptor.requests.size, "one in-flight request")
                HarnessAssert.eq(
                    null,
                    cancelCache.read(location.cacheKey),
                    "a cancelled call must not commit a cache entry",
                )
            } finally {
                release.countDown()
                job.cancel()
            }
        }

        val lateDirectory = caseDirectory(root, "late-response")
        val gate = GatedTransport(
            WeatherHttpResponse(
                code = 200,
                body = metBodyAt075,
                expiresAt = fixedNow.plus(Duration.ofHours(4)),
                lastModified = LAST_MODIFIED,
            ),
        )
        val provider = MutableSessionProvider(session)
        val lateCache = FileWeatherCacheStore(File(lateDirectory, "cache"))
        val lateWork = weatherWork(
            transport = gate,
            cache = lateCache,
            throttle = FileWeatherThrottleStore(File(lateDirectory, "throttle")),
            provider = provider,
            clock = FakeClock(fixedNow),
        )
        coroutineScope {
            val deferred = async(Dispatchers.IO) { lateWork.load(session) }
            try {
                HarnessAssert.check(gate.awaitStarted(5_000), "the gated transport never started")
                provider.session = session.copy(generation = session.generation + 1)
                gate.release()
                HarnessAssert.eq(WeatherLoadResult.Cancelled, deferred.await(), "late-response result")
                HarnessAssert.eq(
                    null,
                    lateCache.read(location.cacheKey),
                    "a late response after the session changed must not commit",
                )
            } finally {
                gate.release()
            }
        }
        return "real OkHttp call saw cancellation; a changed-generation late response was dropped"
    }

    private suspend fun caseOwnerSeam(root: File): String {
        val directory = caseDirectory(root, "owner-seam")
        val consentStore = FileWeatherConsentStore(File(directory, "consent"))
        HarnessAssert.check(
            consentStore.compareAndSet(WeatherConsentState.DISABLED.generation, enabledConsent) is
                WeatherConsentWriteResult.Committed,
            "the harness could not persist its private consent",
        )
        val interceptor = RecordingInterceptor(
            listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
            ),
        )
        val cache = FileWeatherCacheStore(File(directory, "cache"))
        val holder = AtomicReference<WeatherHomeOwner?>(null)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val results = CopyOnWriteArrayList<WeatherLoadResult>()
        val resultLatch = CountDownLatch(1)
        val work = WeatherWorkFactory.create(
            transport = transport(interceptor),
            cacheStore = cache,
            throttleStore = FileWeatherThrottleStore(File(directory, "throttle")),
            sessionProvider = WeatherRuntimeSessionProvider { holder.get() },
            clock = { fixedNow },
        )
        val owner = WeatherHomeOwner(
            consentStore = consentStore,
            work = work,
            scope = scope,
            resultSink = WeatherResultSink { result ->
                results += result
                if (result is WeatherLoadResult.Success) resultLatch.countDown()
            },
            ioDispatcher = Dispatchers.Unconfined,
        )
        holder.set(owner)
        try {
            owner.setScreenInteractive(true)
            owner.setUserPresent(true)
            owner.setHomeVisible(true)
            HarnessAssert.check(resultLatch.await(5, TimeUnit.SECONDS), "the actual owner surfaced no result")
            HarnessAssert.eq(1, interceptor.requests.size, "the owner ran exactly one gated load")
            val success = results.filterIsInstance<WeatherLoadResult.Success>().firstOrNull()
                ?: throw AssertionError("the owner result sink did not receive the forecast")
            HarnessAssert.eq(7.5, success.forecast.temperatureCelsius, "owner forecast temperature")
            HarnessAssert.check(
                cache.read(location.cacheKey) != null,
                "the owner did not commit the forecast cache",
            )
        } finally {
            owner.shutdown()
            scope.cancel()
        }

        val offDirectory = caseDirectory(root, "owner-screen-off")
        val offConsent = FileWeatherConsentStore(File(offDirectory, "consent"))
        HarnessAssert.check(
            offConsent.compareAndSet(WeatherConsentState.DISABLED.generation, enabledConsent) is
                WeatherConsentWriteResult.Committed,
            "the harness could not persist its private screen-off consent",
        )
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val offInterceptor = RecordingInterceptor(
            responses = listOf(
                FakeHttpResponse(
                    code = 200,
                    body = metBodyAt075,
                    expires = EXPIRES_AFTER_4_HOURS,
                    lastModified = LAST_MODIFIED,
                ),
            ),
            startGate = started,
            releaseGate = release,
            cancelledGate = cancelled,
        )
        val offCache = FileWeatherCacheStore(File(offDirectory, "cache"))
        val offHolder = AtomicReference<WeatherHomeOwner?>(null)
        val offScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val offResults = CopyOnWriteArrayList<WeatherLoadResult>()
        val offWork = WeatherWorkFactory.create(
            transport = transport(offInterceptor),
            cacheStore = offCache,
            throttleStore = FileWeatherThrottleStore(File(offDirectory, "throttle")),
            sessionProvider = WeatherRuntimeSessionProvider { offHolder.get() },
            clock = { fixedNow },
        )
        val offOwner = WeatherHomeOwner(
            consentStore = offConsent,
            work = offWork,
            scope = offScope,
            resultSink = WeatherResultSink { offResults += it },
            ioDispatcher = Dispatchers.Unconfined,
        )
        offHolder.set(offOwner)
        try {
            offOwner.setScreenInteractive(true)
            offOwner.setUserPresent(true)
            offOwner.setHomeVisible(true)
            HarnessAssert.check(started.await(5, TimeUnit.SECONDS), "the screen-off load never started")
            offOwner.onScreenOff()
            HarnessAssert.check(cancelled.await(5, TimeUnit.SECONDS), "screen-off did not cancel the OkHttp call")
            release.countDown()
            delay(250)
            HarnessAssert.check(
                offResults.none { it is WeatherLoadResult.Success },
                "a screen-off load must not surface a success",
            )
            HarnessAssert.eq(
                null,
                offCache.read(location.cacheKey),
                "a screen-off load must not commit the cache",
            )
        } finally {
            release.countDown()
            offOwner.shutdown()
            offScope.cancel()
        }
        return "synthetic owner seam (not a real Launcher activity/transition): " +
            "persisted enable loaded once; screen-off cancelled and dropped the late result"
    }

    private fun weatherWork(
        transport: WeatherHttpTransport,
        cache: WeatherCacheStore,
        throttle: WeatherThrottleStore,
        provider: WeatherSessionProvider,
        clock: FakeClock,
    ): WeatherLoadWork = WeatherWorkFactory.create(
        transport = transport,
        cacheStore = cache,
        throttleStore = throttle,
        sessionProvider = provider,
        clock = { clock.now },
    )

    private fun transport(interceptor: Interceptor): OkHttpWeatherTransport =
        OkHttpWeatherTransport(
            appVersion = "harness-1",
            client = OkHttpClient.Builder()
                .addInterceptor(interceptor)
                .retryOnConnectionFailure(false)
                .callTimeout(10, TimeUnit.SECONDS)
                .build(),
        )

    private fun caseDirectory(root: File, name: String): File =
        File(root, "$name-${System.nanoTime()}").apply { mkdirs() }

    private class FakeClock(@Volatile var now: Instant)

    private data class FakeHttpResponse(
        val code: Int,
        val body: String,
        val expires: String? = null,
        val lastModified: String? = null,
        val retryAfter: String? = null,
    )

    private data class RecordedRequest(
        val url: String,
        val path: String,
        val latitude: String?,
        val longitude: String?,
        val userAgent: String?,
        val accept: String?,
        val ifModifiedSince: String?,
    )

    /**
     * The test-only injected OkHttp client. It never proceeds down the chain:
     * the synthetic response is returned in-process, so the production URL is
     * only a shape under test and no socket or MET request exists.
     */
    private class RecordingInterceptor(
        responses: List<FakeHttpResponse>,
        private val startGate: CountDownLatch? = null,
        private val releaseGate: CountDownLatch? = null,
        private val cancelledGate: CountDownLatch? = null,
    ) : Interceptor {
        private val responses: List<FakeHttpResponse> = responses.toList()
        private var index: Int = 0
        val requests: MutableList<RecordedRequest> = CopyOnWriteArrayList()

        override fun intercept(chain: Interceptor.Chain): Response {
            val request = chain.request()
            requests += RecordedRequest(
                url = request.url.toString(),
                path = request.url.encodedPath,
                latitude = request.url.queryParameter("lat"),
                longitude = request.url.queryParameter("lon"),
                userAgent = request.header("User-Agent"),
                accept = request.header("Accept"),
                ifModifiedSince = request.header("If-Modified-Since"),
            )
            startGate?.countDown()
            if (releaseGate != null) {
                while (!releaseGate.await(10, TimeUnit.MILLISECONDS)) {
                    if (chain.call().isCanceled()) {
                        cancelledGate?.countDown()
                        throw IOException("harness cancelled the weather call")
                    }
                }
            }
            if (chain.call().isCanceled()) {
                cancelledGate?.countDown()
                throw IOException("harness cancelled the weather call")
            }
            val fake = synchronized(this) {
                if (responses.isEmpty()) throw IOException("no harness response configured")
                val chosen = responses[index.coerceAtMost(responses.lastIndex)]
                index += 1
                chosen
            }
            return Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(fake.code)
                .message(
                    if (fake.code == MetWeatherRepository.HTTP_NOT_MODIFIED) "Not Modified" else "OK",
                )
                .apply {
                    if (fake.code == MetWeatherRepository.HTTP_NOT_MODIFIED || fake.body.isEmpty()) {
                        body("".toResponseBody(null))
                    } else {
                        body(fake.body.toResponseBody(jsonMediaType))
                    }
                    fake.expires?.let { header("Expires", it) }
                    fake.lastModified?.let { header("Last-Modified", it) }
                    fake.retryAfter?.let { header("Retry-After", it) }
                }
                .build()
        }
    }

    private class GatedTransport(private val response: WeatherHttpResponse) : WeatherHttpTransport {
        private val started = CountDownLatch(1)
        private val gate = CompletableDeferred<Unit>()

        override suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse {
            started.countDown()
            withContext(NonCancellable) { gate.await() }
            return response
        }

        suspend fun awaitStarted(timeoutMs: Long): Boolean =
            withContext(Dispatchers.IO) { started.await(timeoutMs, TimeUnit.MILLISECONDS) }

        fun release() {
            gate.complete(Unit)
        }
    }

    private class StaticSessionProvider(private val value: WeatherSession) : WeatherSessionProvider {
        override fun current(): WeatherSession = value
    }

    private class MutableSessionProvider(initial: WeatherSession) : WeatherSessionProvider {
        @Volatile
        var session: WeatherSession = initial

        override fun current(): WeatherSession = session
    }

    private object HarnessAssert {
        fun check(condition: Boolean, message: String) {
            if (!condition) throw AssertionError(message)
        }

        fun eq(expected: Any?, actual: Any?, what: String) {
            if (expected != actual) {
                throw AssertionError("$what: expected <$expected> but was <$actual>")
            }
        }

        fun eq(expected: Double, actual: Double, what: String) {
            if (kotlin.math.abs(expected - actual) > TEMPERATURE_TOLERANCE) {
                throw AssertionError("$what: expected <$expected> but was <$actual>")
            }
        }
    }

    private fun String.oneLine(): String = replace('\n', ' ').replace('\r', ' ').take(240)
}

data class WeatherHarnessCase(
    val name: String,
    val passed: Boolean,
    val detail: String,
)

data class WeatherHarnessReport(
    val cases: List<WeatherHarnessCase>,
) {
    val passed: Boolean
        get() = cases.isNotEmpty() && cases.all { it.passed }

    val passedCount: Int
        get() = cases.count { it.passed }

    val failedCount: Int
        get() = cases.count { !it.passed }
}
