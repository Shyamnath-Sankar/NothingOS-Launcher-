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

package app.nothingui.widgets

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Text-level guard for the Dotwel widget port. It keeps the provider inventory,
 * weather exclusion, hermeticity and attribution files from drifting without
 * needing an Android runtime.
 */
class DotwelWidgetPortGuardTest {

    private val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
        .first { File(it, "settings.gradle").exists() }

    private val sourceDir = File(root, "lawnchair/src/app/nothingui/widgets/dotwel")
    private val manifest = File(root, "lawnchair/AndroidManifest.xml").readText()
    private val dotwelBlock = manifest
        .substringAfter("<!-- Dotwel widget set (MIT).")
        .substringBefore("</application>")

    @Test
    fun declaresFortyNineNonWeatherProviders() {
        val receivers = Regex(
            "<receiver\\s+android:name=\"app\\.nothingui\\.widgets\\.dotwel\\.([A-Za-z0-9]+Provider)\"",
        ).findAll(dotwelBlock).map { it.groupValues[1] }.toList()
        assertEquals(49, receivers.size)
        assertEquals(receivers.size, receivers.distinct().size)
    }

    @Test
    fun excludesEveryWeatherProvider() {
        val forbidden = listOf(
            "NtWx",
            "NothingTempWidgetProvider",
            "NothingSunInfoWidgetProvider",
            "KwgtDateTime3WidgetProvider",
        )
        forbidden.forEach { name ->
            assertFalse("manifest still declares $name", dotwelBlock.contains(name))
            assertFalse("source still contains $name", sourceDir.walk().any { it.isFile && it.readText().contains(name) })
        }
        assertFalse(File(sourceDir, "NtWxRenderer.kt").exists())
        assertFalse(File(sourceDir, "WeatherWidgetProvider.kt").exists())
        assertFalse(File(sourceDir, "weather").exists())
    }

    @Test
    fun everyDeclaredProviderHasASourceClass() {
        val receivers = Regex(
            "<receiver\\s+android:name=\"app\\.nothingui\\.widgets\\.dotwel\\.([A-Za-z0-9]+Provider)\"",
        ).findAll(dotwelBlock).map { it.groupValues[1] }.toList()
        val sources = sourceDir.walk().filter { it.isFile && it.extension == "kt" }
            .joinToString("\n") { it.readText() }
        receivers.forEach { name ->
            assertTrue("missing source class $name", sources.contains("class $name"))
        }
    }

    @Test
    fun everyAppWidgetInfoFileExists() {
        Regex("android:resource=\"@xml/([A-Za-z0-9_]+)\"")
            .findAll(dotwelBlock)
            .map { it.groupValues[1] }
            .forEach { name ->
                assertTrue("missing res/xml/$name.xml", File(root, "lawnchair/res/xml/$name.xml").exists())
            }
    }

    @Test
    fun widgetSourcesStayHermetic() {
        val sources = sourceDir.walk().filter { it.isFile && it.extension == "kt" }
            .joinToString("\n") { it.readText() }
        listOf(
            "java.net.",
            "HttpURLConnection",
            "okhttp",
            "Socket(",
            "android.permission.INTERNET",
            "SCHEDULE_EXACT_ALARM",
            "BIND_NOTIFICATION_LISTENER_SERVICE",
        ).forEach { token ->
            assertFalse("widget source contains $token", sources.contains(token))
        }
        assertFalse(dotwelBlock.contains("uses-permission"))
        assertFalse(dotwelBlock.contains("BIND_NOTIFICATION_LISTENER_SERVICE"))
    }

    @Test
    fun attributionAndLicenseTextsAreBundled() {
        listOf(
            "docs/ATTRIBUTION.md",
            "licenses/third-party/awesomeawidgets-MIT.txt",
            "licenses/third-party/kwgt-widgets-MIT.txt",
            "lawnchair/res/raw/awesomeawidgets_mit.txt",
            "lawnchair/res/raw/kwgt_widgets_mit.txt",
        ).forEach { path ->
            assertTrue("missing $path", File(root, path).exists())
        }
    }

    @Test
    fun manifestBlockKeepsOnlyInternalHelperComponents() {
        assertTrue(
            dotwelBlock.contains(
                "android:name=\"app.nothingui.widgets.dotwel.MinuteTickReceiver\"",
            ),
        )
        assertTrue(
            dotwelBlock.contains(
                "android:name=\"app.nothingui.widgets.dotwel.BatteryRefreshReceiver\"",
            ),
        )
        assertTrue(
            dotwelBlock.contains(
                "android:name=\"app.nothingui.widgets.dotwel.media.MediaActionReceiver\"",
            ),
        )
        assertTrue(
            dotwelBlock.contains(
                "android:name=\"app.nothingui.widgets.dotwel.NtPhotoConfigActivity\"",
            ),
        )
        assertFalse(dotwelBlock.contains("MediaNotificationService"))
    }
}
