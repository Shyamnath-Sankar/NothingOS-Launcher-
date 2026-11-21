/*
 * Copyright 2021, Lawnchair
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

package app.lawnchair.ui.preferences

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.core.content.edit
import app.lawnchair.smartspace.provider.OnboardingProvider
import app.lawnchair.ui.preferences.navigation.PreferenceRoute
import app.lawnchair.ui.theme.EdgeToEdge
import app.lawnchair.ui.theme.LawnchairTheme
import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiTheme
import app.nothingui.theme.NothingUiThemeSampleScreen
import com.android.launcher3.BuildConfig
import com.android.launcher3.LauncherPrefs
import com.google.accompanist.adaptive.calculateDisplayFeatures
import kotlinx.serialization.json.Json

class PreferenceActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val initialRoute: PreferenceRoute? = intent.getStringExtra(EXTRA_DESTINATION_ROUTE)?.let { routeString ->
            try {
                Json.decodeFromString<PreferenceRoute>(routeString)
            } catch (e: Exception) {
                null // Fallback to default if deserialization fails
            }
        }
        val themeSampleMode = resolveThemeSampleMode(intent)

        setContent {
            if (themeSampleMode == null) {
                LawnchairTheme {
                    EdgeToEdge()
                    Preferences(
                        windowSizeClass = calculateWindowSizeClass(this),
                        displayFeatures = calculateDisplayFeatures(this),
                        startDestination = initialRoute,
                        intent = intent,
                    )
                }
            } else {
                NothingUiTheme(darkTheme = themeSampleMode == THEME_SAMPLE_DARK) {
                    EdgeToEdge()
                    NothingUiThemeSampleScreen()
                }
            }
        }
        if (themeSampleMode == null) {
            LauncherPrefs.getPrefs(this).edit {
                putBoolean(
                    OnboardingProvider.PREF_HAS_OPENED_SETTINGS,
                    true,
                )
            }
        }
    }

    // Diagnostic-only surface for capturing real dark/light theme samples on a
    // device. It requires an explicit extra, a debug build and the Play-only theme
    // gate, so release and non-Play builds keep the normal settings surface.
    private fun resolveThemeSampleMode(intent: Intent): String? {
        if (!BuildConfig.DEBUG || !NothingUiFeature.themeEnabled) return null
        return when (intent.getStringExtra(EXTRA_THEME_SAMPLE)?.lowercase()) {
            THEME_SAMPLE_DARK -> THEME_SAMPLE_DARK
            THEME_SAMPLE_LIGHT -> THEME_SAMPLE_LIGHT
            else -> null
        }
    }

    companion object {

        private const val EXTRA_DESTINATION_ROUTE = "app.lawnchair.ui.preferences.DESTINATION_ROUTE"
        private const val EXTRA_THEME_SAMPLE = "app.lawnchair.ui.preferences.THEME_SAMPLE"
        private const val THEME_SAMPLE_DARK = "dark"
        private const val THEME_SAMPLE_LIGHT = "light"

        @JvmStatic
        fun createIntent(context: Context, destination: PreferenceRoute): Intent {
            val intent = Intent(context, PreferenceActivity::class.java)
            val routeString = Json.encodeToString(destination)
            intent.putExtra(EXTRA_DESTINATION_ROUTE, routeString)
            return intent
        }
    }
}
