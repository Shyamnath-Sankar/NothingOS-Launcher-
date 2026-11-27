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
 *
 * The pinned upstream commit (`7167bcdf001b604f1d61a2f07f70825a999eb767`)
 * declares 61 widget providers. Twelve are weather widgets and are excluded;
 * the remaining 49 are the complete non-weather port. This test pins that
 * inventory by name so a missing or accidentally-dropped provider fails the
 * build instead of silently disappearing.
 */
class DotwelWidgetPortGuardTest {

    private val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
        .first { File(it, "settings.gradle").exists() }

    private val sourceDir = File(root, "lawnchair/src/app/nothingui/widgets/dotwel")
    private val resXmlDir = File(root, "lawnchair/res/xml")
    private val manifest = File(root, "lawnchair/AndroidManifest.xml").readText()
    private val dotwelBlock = manifest
        .substringAfter("<!-- Dotwel widget set (MIT).")
        .substringBefore("</application>")

    private val providerRegex = Regex(
        "<receiver\\s+android:name=\"app\\.nothingui\\.widgets\\.dotwel\\.([A-Za-z0-9]+Provider)\"",
    )

    private fun declaredProviders(): List<String> =
        providerRegex.findAll(dotwelBlock).map { it.groupValues[1] }.toList()

    private fun declaredInfoXmls(): List<String> =
        Regex("android:resource=\"@xml/([A-Za-z0-9_]+)\"")
            .findAll(dotwelBlock)
            .map { it.groupValues[1] }
            .toList()

    private fun layoutExists(name: String): Boolean =
        File(root, "lawnchair/res").listFiles()
            ?.filter { it.isDirectory && it.name.startsWith("layout") }
            ?.any { File(it, "$name.xml").isFile } == true

    private fun allSourceText(): String =
        sourceDir.walk().filter { it.isFile && it.extension == "kt" }
            .joinToString("\n") { it.readText() }

    @Test
    fun declaresExactlyTheFortyNineNonWeatherProviders() {
        val receivers = declaredProviders()
        assertEquals("provider count", EXPECTED_NON_WEATHER_PROVIDERS.size, receivers.size)
        assertEquals("duplicate providers", receivers.size, receivers.distinct().size)
        assertEquals(
            "declared providers differ from the pinned non-weather inventory",
            EXPECTED_NON_WEATHER_PROVIDERS.map { it.first }.sorted(),
            receivers.sorted(),
        )
    }

    @Test
    fun everyProviderPointsAtItsPinnedInfoXml() {
        val declared = declaredProviders()
        val resources = declaredInfoXmls()
        assertEquals(declared.size, resources.size)
        EXPECTED_NON_WEATHER_PROVIDERS.forEach { (provider, infoXml) ->
            assertTrue("$provider is not declared", provider in declared)
            assertTrue("$infoXml is not declared", infoXml in resources)
        }
        assertEquals(
            "declared info XMLs differ from the pinned inventory",
            EXPECTED_NON_WEATHER_PROVIDERS.map { it.second }.sorted(),
            resources.sorted(),
        )
    }

    @Test
    fun excludesEveryWeatherProvider() {
        WEATHER_PROVIDERS.forEach { name ->
            assertFalse("manifest still declares $name", dotwelBlock.contains(name))
            assertFalse(
                "source still contains $name",
                sourceDir.walk().any { it.isFile && it.readText().contains(name) },
            )
        }
        WEATHER_INFO_XMLS.forEach { name ->
            assertFalse("weather info XML $name was ported", File(resXmlDir, "$name.xml").exists())
            assertFalse("manifest still references $name", dotwelBlock.contains("@xml/$name"))
        }
        assertFalse(File(sourceDir, "NtWxRenderer.kt").exists())
        assertFalse(File(sourceDir, "WeatherWidgetProvider.kt").exists())
        assertFalse(File(sourceDir, "weather").exists())
    }

    @Test
    fun sharedWeatherNamedLayoutIsOnlyUsedByNonWeatherProviders() {
        // NtAway and NtPhoto reuse the upstream widget_weather_temp layout. It is
        // not a weather widget: no weather provider is declared and no weather
        // renderer is ported. Keep the shared layout, but prove the reuse.
        assertTrue(File(root, "lawnchair/res/layout/widget_weather_temp.xml").isFile)
        val source = allSourceText()
        assertTrue(source.contains("NtAwayWidgetProvider"))
        assertTrue(source.contains("BaseNtPhotoProvider"))
        assertTrue(source.contains("R.layout.widget_weather_temp"))
    }

    @Test
    fun everyDeclaredProviderHasASourceClass() {
        val source = allSourceText()
        declaredProviders().forEach { name ->
            assertTrue(
                "missing source class $name",
                Regex("\\bclass\\s+${Regex.escape(name)}\\b").containsMatchIn(source),
            )
        }
    }

    @Test
    fun everyConcreteProviderClassIsDeclared() {
        // Bidirectional check: a ported concrete provider that is never
        // registered in the manifest is just as broken as a receiver without a
        // class. Abstract bases are intentionally not registered.
        val concrete = Regex(
            "(?m)^(?:open\\s+|internal\\s+|private\\s+)?class\\s+([A-Za-z0-9_]+)\\s*:\\s*[A-Za-z0-9_]*Provider\\s*\\(\\s*\\)",
        ).findAll(allSourceText()).map { it.groupValues[1] }.toList()
        assertEquals(
            "concrete provider classes differ from the manifest declarations",
            declaredProviders().sorted(),
            concrete.sorted(),
        )
    }

    @Test
    fun everyAppWidgetInfoFileAndItsLayoutsExist() {
        EXPECTED_NON_WEATHER_PROVIDERS.map { it.second }.forEach { name ->
            val info = File(resXmlDir, "$name.xml")
            assertTrue("missing res/xml/$name.xml", info.isFile)
            val text = info.readText()
            val layouts = Regex("android:(?:initial|preview)Layout=\"@layout/([A-Za-z0-9_]+)\"")
                .findAll(text)
                .map { it.groupValues[1] }
                .toList()
            assertTrue("$name.xml declares no initial/preview layout", layouts.isNotEmpty())
            layouts.forEach { layout ->
                assertTrue("$name.xml references missing layout $layout", layoutExists(layout))
            }
        }
    }

    @Test
    fun widgetSourcesStayHermetic() {
        val sources = allSourceText()
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
        val attribution = File(root, "docs/ATTRIBUTION.md").readText()
        assertTrue(
            "attribution does not pin the upstream commit",
            attribution.contains("7167bcdf001b604f1d61a2f07f70825a999eb767"),
        )
        assertTrue("attribution does not mention MIT", attribution.contains("MIT"))
        listOf(
            "licenses/third-party/awesomeawidgets-MIT.txt",
            "licenses/third-party/kwgt-widgets-MIT.txt",
            "lawnchair/res/raw/awesomeawidgets_mit.txt",
            "lawnchair/res/raw/kwgt_widgets_mit.txt",
        ).forEach { path ->
            val file = File(root, path)
            assertTrue("missing $path", file.isFile)
            val text = file.readText()
            assertTrue("$path is not an MIT text", text.contains("MIT License"))
            assertTrue("$path has no copyright holder", text.contains("Copyright"))
        }
    }

    @Test
    fun manifestBlockKeepsOnlyInternalHelperComponents() {
        listOf(
            "app.nothingui.widgets.dotwel.MinuteTickReceiver",
            "app.nothingui.widgets.dotwel.BatteryRefreshReceiver",
            "app.nothingui.widgets.dotwel.media.MediaActionReceiver",
            "app.nothingui.widgets.dotwel.NtPhotoConfigActivity",
        ).forEach { component ->
            assertTrue("missing helper $component", dotwelBlock.contains("android:name=\"$component\""))
        }
        assertFalse(dotwelBlock.contains("MediaNotificationService"))
        // The upstream app's own request-pin flow (WidgetCatalog/MainActivity/
        // PinResultReceiver) is not ported: the system widget picker owns
        // pinning in a launcher, so there is no in-app pin receiver.
        assertFalse(dotwelBlock.contains("PinResultReceiver"))
    }

    private companion object {
        /**
         * The complete non-weather provider inventory at upstream commit
         * `7167bcdf001b604f1d61a2f07f70825a999eb767`, as provider class name to
         * `android.appwidget.provider` metadata resource.
         */
        val EXPECTED_NON_WEATHER_PROVIDERS = listOf(
            "AnalogBoldWidgetProvider" to "analog_bold_widget_info",
            "AnalogScaleWidgetProvider" to "analog_scale_widget_info",
            "BatteryMiniWidgetProvider" to "battery_mini_widget_info",
            "BatteryStatusWidgetProvider" to "battery_status_widget_info",
            "BatteryWidgetProvider" to "battery_widget_info",
            "BluetoothHeadphonesSquareWidgetProvider" to "bt_headphones_square_widget_info",
            "BluetoothHeadphonesWideWidgetProvider" to "bt_headphones_wide_widget_info",
            "BluetoothStatusWidgetProvider" to "bt_status_widget_info",
            "CellularStatusWidgetProvider" to "cellular_status_widget_info",
            "ClockWidgetProvider" to "clock_widget_info",
            "DateWidgetProvider" to "date_widget_info",
            "IosBatteryWidgetProvider" to "ios_battery_widget_info",
            "KwgtAnalog2WidgetProvider" to "kwgt_analog2_widget_info",
            "KwgtAnalog3WidgetProvider" to "kwgt_analog3_widget_info",
            "KwgtAnalog5TransparentWidgetProvider" to "kwgt_analog5clear_widget_info",
            "KwgtAnalog5WidgetProvider" to "kwgt_analog5_widget_info",
            "KwgtAnalogSecondsWidgetProvider" to "kwgt_analog_seconds_widget_info",
            "KwgtBattery2WidgetProvider" to "kwgt_battery2_widget_info",
            "KwgtCleanInfoWidgetProvider" to "kwgt_clean_info_widget_info",
            "KwgtDateTime2WidgetProvider" to "kwgt_datetime2_widget_info",
            "KwgtDateTimeWidgetProvider" to "kwgt_datetime_widget_info",
            "KwgtDigital2WidgetProvider" to "kwgt_digital2_widget_info",
            "KwgtDigital3WidgetProvider" to "kwgt_digital3_widget_info",
            "KwgtDigital4WidgetProvider" to "kwgt_digital4_widget_info",
            "KwgtFutureWidgetProvider" to "kwgt_future_widget_info",
            "KwgtGradientClockWidgetProvider" to "kwgt_gradient_clock_widget_info",
            "KwgtInterstellarEnduranceAnalog2Provider" to "interstellar_endurance_analog2_widget_info",
            "KwgtInterstellarEnduranceAnalogProvider" to "interstellar_endurance_analog_widget_info",
            "KwgtInterstellarEnduranceProvider" to "interstellar_endurance_widget_info",
            "KwgtMiniCalendarWidgetProvider" to "kwgt_mini_calendar_widget_info",
            "KwgtOrbitClockWidgetProvider" to "kwgt_orbit_widget_info",
            "Material3ExpandedMediaProvider" to "media_m3_expanded_widget_info",
            "Material3MediaOutputProvider" to "media_m3_output_widget_info",
            "MaterialNotificationWidgetProvider" to "media_notification_widget_info",
            "MiniMediaPlayerProvider" to "media_mini_widget_info",
            "MinimalMediaPlayer2Provider" to "media_minimal2_widget_info",
            "MinimalMediaPlayer3Provider" to "media_minimal3_widget_info",
            "MinimalMediaPlayerProvider" to "media_minimal_widget_info",
            "NothingMasterWidgetProvider" to "media_master_widget_info",
            "NothingMediaPlayer2Provider" to "media_player2_widget_info",
            "NothingMediaPlayer3Provider" to "media_player3_widget_info",
            "NothingMediaPlayerProvider" to "media_player_widget_info",
            "NtAwayWidgetProvider" to "away_info",
            "NtPhotoCircleProvider" to "photo_circle_info",
            "NtPhotoRectProvider" to "photo_rect_info",
            "QuotesWidgetProvider" to "quotes_widget_info",
            "UniversalMediaPlayerProvider" to "media_universal_widget_info",
            "WifiStatusWidgetProvider" to "wifi_status_widget_info",
            "WorldWidgetProvider" to "world_widget_info",
        )

        val WEATHER_PROVIDERS = listOf(
            "KwgtDateTime3WidgetProvider",
            "NothingSunInfoWidgetProvider",
            "NothingTempWidgetProvider",
            "NtWxAirProvider",
            "NtWxCircleProvider",
            "NtWxComboProvider",
            "NtWxRectProvider",
            "NtWxSquareProvider",
            "NtWxSunsetProvider",
            "NtWxW1RainProvider",
            "NtWxW1StatusProvider",
            "NtWxW1TempProvider",
        )

        val WEATHER_INFO_XMLS = listOf(
            "kwgt_date_time3_widget_info",
            "weather_sun_widget_info",
            "weather_temp_widget_info",
            "ntwx_air_info",
            "ntwx_circle_info",
            "ntwx_combo_info",
            "ntwx_rect_info",
            "ntwx_square_info",
            "ntwx_sunset_info",
            "ntwx_w1rain_info",
            "ntwx_w1status_info",
            "ntwx_w1temp_info",
        )
    }
}
