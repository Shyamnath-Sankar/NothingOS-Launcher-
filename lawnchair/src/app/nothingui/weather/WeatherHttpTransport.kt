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

import java.time.Instant

/**
 * The injectable HTTP seam. Tests replace it with an offline fake; no Android
 * or network dependency leaks into the repository policy.
 */
interface WeatherHttpTransport {
    suspend fun get(request: WeatherHttpRequest): WeatherHttpResponse
}

data class WeatherHttpRequest(
    val url: String,
    val ifModifiedSince: String? = null,
    val accept: String = "application/json",
)

data class WeatherHttpResponse(
    val code: Int,
    val body: String?,
    val expiresAt: Instant?,
    val lastModified: String?,
    /** Raw `Retry-After`; the repository parses seconds or an HTTP-date with its injected clock. */
    val retryAfter: String? = null,
)
