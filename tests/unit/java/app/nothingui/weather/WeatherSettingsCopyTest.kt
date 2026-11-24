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

import com.android.launcher3.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherSettingsCopyTest {

    @Test
    fun debugBuildSelectsSetupOnlyCopy() {
        val networkEnabled = WeatherSettingsCopy.networkEnabled(debugBuild = true)

        assertFalse(networkEnabled)
        assertEquals(
            R.string.dotwel_weather_privacy_notice_debug,
            WeatherSettingsCopy.privacyNotice(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_forecast_notice_debug,
            WeatherSettingsCopy.forecastNotice(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_settings_description_debug,
            WeatherSettingsCopy.settingsDescription(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_enabled_status_debug,
            WeatherSettingsCopy.enabledStatus(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_message_enabled_debug,
            WeatherSettingsCopy.enabledMessage(networkEnabled),
        )
    }

    @Test
    fun releaseBuildSelectsTransmissionCopy() {
        val networkEnabled = WeatherSettingsCopy.networkEnabled(debugBuild = false)

        assertTrue(networkEnabled)
        assertEquals(
            R.string.dotwel_weather_privacy_notice_release,
            WeatherSettingsCopy.privacyNotice(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_forecast_notice_release,
            WeatherSettingsCopy.forecastNotice(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_settings_description_release,
            WeatherSettingsCopy.settingsDescription(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_enabled_status_release,
            WeatherSettingsCopy.enabledStatus(networkEnabled),
        )
        assertEquals(
            R.string.dotwel_weather_message_enabled_release,
            WeatherSettingsCopy.enabledMessage(networkEnabled),
        )
    }

    @Test
    fun onlyTheEnabledConfirmationFollowsTheBuildMode() {
        assertEquals(
            R.string.dotwel_weather_message_enabled_debug,
            WeatherSettingsCopy.messageResource(WeatherSettingsMessage.ENABLED, networkEnabled = false),
        )
        assertEquals(
            R.string.dotwel_weather_message_enabled_release,
            WeatherSettingsCopy.messageResource(WeatherSettingsMessage.ENABLED, networkEnabled = true),
        )
        assertEquals(
            R.string.dotwel_weather_message_disabled,
            WeatherSettingsCopy.messageResource(WeatherSettingsMessage.DISABLED, networkEnabled = false),
        )
        assertEquals(
            R.string.dotwel_weather_message_disabled,
            WeatherSettingsCopy.messageResource(WeatherSettingsMessage.DISABLED, networkEnabled = true),
        )
        assertEquals(
            R.string.dotwel_weather_message_revoked,
            WeatherSettingsCopy.messageResource(WeatherSettingsMessage.REVOKED_BY_EDIT, networkEnabled = true),
        )
    }
}
