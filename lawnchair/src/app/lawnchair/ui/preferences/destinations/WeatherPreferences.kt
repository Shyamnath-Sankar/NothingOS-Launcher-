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

package app.lawnchair.ui.preferences.destinations

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.lawnchair.theme.LawnchairTheme
import app.lawnchair.ui.preferences.components.layout.PreferenceGroup
import app.lawnchair.ui.preferences.components.layout.PreferenceLayout
import app.lawnchair.ui.util.preview.PreviewLawnchair
import app.nothingui.theme.NothingUiSpacing
import app.nothingui.weather.ClearableWeatherCacheStore
import app.nothingui.weather.FileWeatherCacheStore
import app.nothingui.weather.FileWeatherConsentStore
import app.nothingui.weather.WeatherConsentPolicy
import app.nothingui.weather.WeatherConsentState
import app.nothingui.weather.WeatherLocationInput
import app.nothingui.weather.WeatherLocationInputError
import app.nothingui.weather.WeatherPrivateStorage
import app.nothingui.weather.WeatherSettingsController
import app.nothingui.weather.WeatherSettingsDraft
import app.nothingui.weather.WeatherSettingsMessage
import app.nothingui.weather.WeatherSettingsUiState
import com.android.launcher3.R
import kotlinx.coroutines.launch

@Composable
fun WeatherPreferences(
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    val controller = remember(context) { createController(context) }
    LaunchedEffect(controller) { controller.load() }
    val state by controller.state.collectAsState()

    PreferenceLayout(
        label = stringResource(R.string.dotwel_weather_settings_label),
        modifier = modifier,
    ) {
        WeatherSettingsContent(
            state = state,
            onDraftChange = { draft -> scope.launch { controller.onDraftChanged(draft) } },
            onEnable = { scope.launch { controller.enable() } },
            onDisable = { scope.launch { controller.disable() } },
            onOpenUrl = { url -> runCatching { uriHandler.openUri(url) } },
        )
    }
}

private fun createController(context: Context): WeatherSettingsController {
    val noBackupRoot = context.noBackupFilesDir
    val cacheStore: ClearableWeatherCacheStore = FileWeatherCacheStore(
        WeatherPrivateStorage.cacheDirectory(noBackupRoot),
    )
    return WeatherSettingsController(
        store = FileWeatherConsentStore(WeatherPrivateStorage.consentDirectory(noBackupRoot)),
        cacheStore = cacheStore,
    )
}

@Composable
fun WeatherSettingsContent(
    state: WeatherSettingsUiState,
    onDraftChange: (WeatherSettingsDraft) -> Unit,
    onEnable: () -> Unit,
    onDisable: () -> Unit,
    onOpenUrl: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        PreferenceGroup(heading = stringResource(R.string.dotwel_weather_privacy_heading)) {
            Text(
                text = stringResource(R.string.dotwel_weather_privacy_notice),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = NothingUiSpacing.Lg,
                    vertical = NothingUiSpacing.Sm,
                ),
            )
            Text(
                text = stringResource(R.string.dotwel_weather_forecast_notice),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = NothingUiSpacing.Lg,
                    vertical = NothingUiSpacing.Sm,
                ),
            )
            Text(
                text = stringResource(R.string.dotwel_weather_attribution),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = NothingUiSpacing.Lg,
                    vertical = NothingUiSpacing.Sm,
                ),
            )
            Row(
                modifier = Modifier.padding(horizontal = NothingUiSpacing.Sm),
                horizontalArrangement = Arrangement.spacedBy(NothingUiSpacing.Xs),
            ) {
                ProviderLink(
                    label = stringResource(R.string.dotwel_weather_terms),
                    urlRes = R.string.dotwel_weather_terms_url,
                    onOpenUrl = onOpenUrl,
                )
                ProviderLink(
                    label = stringResource(R.string.dotwel_weather_source),
                    urlRes = R.string.dotwel_weather_source_url,
                    onOpenUrl = onOpenUrl,
                )
                ProviderLink(
                    label = stringResource(R.string.dotwel_weather_license),
                    urlRes = R.string.dotwel_weather_license_url,
                    onOpenUrl = onOpenUrl,
                )
            }
        }

        PreferenceGroup(heading = stringResource(R.string.dotwel_weather_settings_label)) {
            if (state.loading) {
                Text(
                    text = stringResource(R.string.dotwel_weather_message_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(
                        horizontal = NothingUiSpacing.Lg,
                        vertical = NothingUiSpacing.Sm,
                    ),
                )
            } else {
                LocationFields(
                    state = state,
                    onDraftChange = onDraftChange,
                )
                ConsentToggle(
                    checked = state.draft.consentChecked || state.isEnabled,
                    enabled = !state.isEnabled && !state.busy,
                    onCheckedChange = { checked ->
                        onDraftChange(state.draft.copy(consentChecked = checked))
                    },
                )
                if (state.isEnabled) {
                    EnabledStatus(state = state)
                    Button(
                        onClick = onDisable,
                        enabled = state.canDisable,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Sm)
                            .heightIn(min = NothingUiSpacing.Xxxl),
                    ) {
                        Text(stringResource(R.string.dotwel_weather_disable))
                    }
                } else {
                    Button(
                        onClick = onEnable,
                        enabled = state.canEnable,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Sm)
                            .heightIn(min = NothingUiSpacing.Xxxl),
                    ) {
                        Text(stringResource(R.string.dotwel_weather_enable))
                    }
                }
                state.message?.let { message ->
                    Text(
                        text = stringResource(message.resource()),
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(
                            horizontal = NothingUiSpacing.Lg,
                            vertical = NothingUiSpacing.Sm,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun LocationFields(
    state: WeatherSettingsUiState,
    onDraftChange: (WeatherSettingsDraft) -> Unit,
) {
    val draft = state.draft
    val enabled = !state.busy && !state.isEnabled
    val showErrors = state.showValidationErrors
    OutlinedTextField(
        value = draft.label,
        onValueChange = { onDraftChange(draft.copy(label = it)) },
        enabled = enabled,
        singleLine = true,
        label = { Text(stringResource(R.string.dotwel_weather_location_label)) },
        placeholder = { Text(stringResource(R.string.dotwel_weather_location_hint)) },
        isError = showErrors && labelErrorRes(state.validation) != null,
        supportingText = if (showErrors) {
            labelErrorRes(state.validation)?.let { res ->
                { Text(stringResource(res, WeatherConsentPolicy.MAX_LABEL_LENGTH)) }
            }
        } else {
            null
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Xs),
    )
    OutlinedTextField(
        value = draft.latitudeText,
        onValueChange = { onDraftChange(draft.copy(latitudeText = it)) },
        enabled = enabled,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        label = { Text(stringResource(R.string.dotwel_weather_latitude_label)) },
        isError = showErrors && WeatherLocationInputError.LATITUDE_INVALID in errors(state.validation),
        supportingText = if (showErrors && WeatherLocationInputError.LATITUDE_INVALID in errors(state.validation)) {
            { Text(stringResource(R.string.dotwel_weather_error_latitude)) }
        } else {
            null
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Xs),
    )
    OutlinedTextField(
        value = draft.longitudeText,
        onValueChange = { onDraftChange(draft.copy(longitudeText = it)) },
        enabled = enabled,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        label = { Text(stringResource(R.string.dotwel_weather_longitude_label)) },
        isError = showErrors && WeatherLocationInputError.LONGITUDE_INVALID in errors(state.validation),
        supportingText = if (showErrors && WeatherLocationInputError.LONGITUDE_INVALID in errors(state.validation)) {
            { Text(stringResource(R.string.dotwel_weather_error_longitude)) }
        } else {
            null
        },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Xs),
    )
    Text(
        text = stringResource(R.string.dotwel_weather_coordinates_hint),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(
            horizontal = NothingUiSpacing.Lg,
            vertical = NothingUiSpacing.Xs,
        ),
    )
}

@Composable
private fun ConsentToggle(
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(
                value = checked,
                enabled = enabled,
                role = Role.Checkbox,
                onValueChange = onCheckedChange,
            )
            .padding(horizontal = NothingUiSpacing.Lg, vertical = NothingUiSpacing.Sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
        )
        Text(
            text = stringResource(R.string.dotwel_weather_consent_checkbox),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(start = NothingUiSpacing.Sm),
        )
    }
}

@Composable
private fun EnabledStatus(state: WeatherSettingsUiState) {
    val location = state.saved.location
    if (location != null) {
        Text(
            text = stringResource(
                R.string.dotwel_weather_enabled_status,
                location.label,
                location.coordinates.latitudeText,
                location.coordinates.longitudeText,
            ),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(
                horizontal = NothingUiSpacing.Lg,
                vertical = NothingUiSpacing.Sm,
            ),
        )
    }
}

@Composable
private fun ProviderLink(
    label: String,
    @StringRes urlRes: Int,
    onOpenUrl: (String) -> Unit,
) {
    val url = stringResource(urlRes)
    TextButton(onClick = { onOpenUrl(url) }) {
        Text(label)
    }
}

@StringRes
private fun labelErrorRes(input: WeatherLocationInput): Int? {
    if (input !is WeatherLocationInput.Invalid) return null
    return when {
        WeatherLocationInputError.EMPTY_LABEL in input.errors -> R.string.dotwel_weather_error_empty_label
        WeatherLocationInputError.LABEL_TOO_LONG in input.errors -> R.string.dotwel_weather_error_label_too_long
        WeatherLocationInputError.LABEL_INVALID_CHARACTER in input.errors -> R.string.dotwel_weather_error_label_invalid
        else -> null
    }
}

private fun errors(input: WeatherLocationInput): Set<WeatherLocationInputError> = (input as? WeatherLocationInput.Invalid)?.errors.orEmpty()

@StringRes
private fun WeatherSettingsMessage.resource(): Int = when (this) {
    WeatherSettingsMessage.ENABLED -> R.string.dotwel_weather_message_enabled
    WeatherSettingsMessage.DISABLED -> R.string.dotwel_weather_message_disabled
    WeatherSettingsMessage.REVOKED_BY_EDIT -> R.string.dotwel_weather_message_revoked
    WeatherSettingsMessage.INVALID_LOCATION -> R.string.dotwel_weather_message_invalid
    WeatherSettingsMessage.CONSENT_REQUIRED -> R.string.dotwel_weather_message_consent
    WeatherSettingsMessage.STORAGE_FAILURE -> R.string.dotwel_weather_message_storage
    WeatherSettingsMessage.CONFLICT -> R.string.dotwel_weather_message_conflict
}

@PreviewLawnchair
@Composable
private fun WeatherSettingsDisabledPreview() {
    val draft = WeatherSettingsDraft(
        label = "Home",
        latitudeText = "51.5074",
        longitudeText = "-0.1278",
        consentChecked = true,
    )
    LawnchairTheme {
        Surface {
            WeatherSettingsContent(
                state = WeatherSettingsUiState(
                    draft = draft,
                    validation = WeatherConsentPolicy.parseLocation(
                        draft.label,
                        draft.latitudeText,
                        draft.longitudeText,
                    ),
                    loading = false,
                ),
                onDraftChange = {},
                onEnable = {},
                onDisable = {},
                onOpenUrl = {},
            )
        }
    }
}

@PreviewLawnchair
@Composable
private fun WeatherSettingsEnabledPreview() {
    val draft = WeatherSettingsDraft(
        label = "Home",
        latitudeText = "51.5074",
        longitudeText = "-0.1278",
    )
    val validation = WeatherConsentPolicy.parseLocation(
        draft.label,
        draft.latitudeText,
        draft.longitudeText,
    ) as WeatherLocationInput.Valid
    LawnchairTheme {
        Surface {
            WeatherSettingsContent(
                state = WeatherSettingsUiState(
                    saved = WeatherConsentPolicy.enable(
                        WeatherConsentState.DISABLED,
                        validation.location,
                    ),
                    draft = draft,
                    validation = validation,
                    loading = false,
                ),
                onDraftChange = {},
                onEnable = {},
                onDisable = {},
                onOpenUrl = {},
            )
        }
    }
}
