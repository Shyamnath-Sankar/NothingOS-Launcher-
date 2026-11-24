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

import androidx.annotation.StringRes
import com.android.launcher3.R

/**
 * Build-mode-aware Weather settings copy.
 *
 * The runtime keeps debug/test builds network-off while release builds perform
 * the real opt-in HOME request. The settings screen therefore cannot use one
 * shared promise: [networkEnabled] selects the debug setup-only wording or the
 * release transmission wording from the same boundary as the runtime. Both
 * variants disclose that the selected coordinates and the device IP address go
 * to MET Norway when real requests are enabled, that the label stays on device,
 * and that no GPS or background tracking is used.
 */
object WeatherSettingsCopy {
    fun networkEnabled(debugBuild: Boolean): Boolean = WeatherNetworkMode.isEnabled(debugBuild)

    @StringRes
    fun privacyNotice(networkEnabled: Boolean): Int = if (networkEnabled) {
        R.string.dotwel_weather_privacy_notice_release
    } else {
        R.string.dotwel_weather_privacy_notice_debug
    }

    @StringRes
    fun forecastNotice(networkEnabled: Boolean): Int = if (networkEnabled) {
        R.string.dotwel_weather_forecast_notice_release
    } else {
        R.string.dotwel_weather_forecast_notice_debug
    }

    @StringRes
    fun settingsDescription(networkEnabled: Boolean): Int = if (networkEnabled) {
        R.string.dotwel_weather_settings_description_release
    } else {
        R.string.dotwel_weather_settings_description_debug
    }

    @StringRes
    fun enabledStatus(networkEnabled: Boolean): Int = if (networkEnabled) {
        R.string.dotwel_weather_enabled_status_release
    } else {
        R.string.dotwel_weather_enabled_status_debug
    }

    @StringRes
    fun enabledMessage(networkEnabled: Boolean): Int = if (networkEnabled) {
        R.string.dotwel_weather_message_enabled_release
    } else {
        R.string.dotwel_weather_message_enabled_debug
    }

    @StringRes
    fun messageResource(message: WeatherSettingsMessage, networkEnabled: Boolean): Int = when (message) {
        WeatherSettingsMessage.ENABLED -> enabledMessage(networkEnabled)
        WeatherSettingsMessage.DISABLED -> R.string.dotwel_weather_message_disabled
        WeatherSettingsMessage.REVOKED_BY_EDIT -> R.string.dotwel_weather_message_revoked
        WeatherSettingsMessage.INVALID_LOCATION -> R.string.dotwel_weather_message_invalid
        WeatherSettingsMessage.CONSENT_REQUIRED -> R.string.dotwel_weather_message_consent
        WeatherSettingsMessage.STORAGE_FAILURE -> R.string.dotwel_weather_message_storage
        WeatherSettingsMessage.REVOKE_UNCONFIRMED -> R.string.dotwel_weather_message_revoke_unconfirmed
        WeatherSettingsMessage.CONFLICT -> R.string.dotwel_weather_message_conflict
    }
}
