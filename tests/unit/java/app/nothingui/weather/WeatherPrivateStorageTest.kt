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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherPrivateStorageTest {

    private val noBackupRoot = File("/data/user/0/example/no_backup")

    @Test
    fun everyWeatherPrivateDirectoryLivesUnderTheNoBackupRoot() {
        listOf(
            WeatherPrivateStorage.consentDirectory(noBackupRoot),
            WeatherPrivateStorage.cacheDirectory(noBackupRoot),
            WeatherPrivateStorage.throttleDirectory(noBackupRoot),
        ).forEach { directory ->
            assertTrue(
                "$directory must be below $noBackupRoot",
                directory.canonicalPath.startsWith(noBackupRoot.canonicalPath + File.separator),
            )
        }
    }

    @Test
    fun theDirectoriesAreDistinctAndNotSharedWithBackupOrLauncherStorage() {
        val directories = listOf(
            WeatherPrivateStorage.consentDirectory(noBackupRoot),
            WeatherPrivateStorage.cacheDirectory(noBackupRoot),
            WeatherPrivateStorage.throttleDirectory(noBackupRoot),
        )

        assertEquals(directories.size, directories.toSet().size)
        val forbidden = setOf("shared_prefs", "datastore", "databases", "preferences")
        directories.forEach { directory ->
            assertFalse(
                "${directory.name} must not reuse a backed-up path",
                directory.name in forbidden,
            )
        }
    }

    @Test
    fun thePrivateRootNameCannotBeMistakenForALawnchairBackupEntry() {
        val rootName = WeatherPrivateStorage.consentDirectory(noBackupRoot).parentFile.name

        assertFalse(rootName == "preferences")
        assertFalse(rootName == "datastore")
        assertFalse(rootName == "shared_prefs")
        assertTrue(rootName.contains("weather"))
    }
}
