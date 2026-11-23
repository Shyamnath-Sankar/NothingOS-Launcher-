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

/**
 * Weather opt-in, cache and throttle state must never reach Lawnchair's
 * `shared_prefs`, DataStore files or launcher database. Those are included in
 * backup/restore. The launch site passes `Context.noBackupFilesDir`, which the
 * platform excludes from cloud backup and device transfer.
 *
 * Keep the names distinct from every backed-up preference file so a future
 * backup allow-list change cannot silently start copying weather history.
 */
object WeatherPrivateStorage {
    const val ROOT_DIRECTORY = "dotwel-weather-private"

    fun consentDirectory(noBackupRoot: File): File = directory(noBackupRoot, "consent")

    fun cacheDirectory(noBackupRoot: File): File = directory(noBackupRoot, "cache")

    fun throttleDirectory(noBackupRoot: File): File = directory(noBackupRoot, "throttle")

    private fun directory(noBackupRoot: File, child: String): File =
        File(File(noBackupRoot, ROOT_DIRECTORY), child)
}
