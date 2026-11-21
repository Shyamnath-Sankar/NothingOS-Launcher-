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

package app.nothingui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

@Composable
fun NothingUiThemeSampleScreen(modifier: Modifier = Modifier) {
    val colors = LocalNothingUiColors.current
    Surface(
        modifier = modifier.fillMaxSize(),
        color = colors.background,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(NothingUiSpacing.Xl),
            verticalArrangement = Arrangement.spacedBy(NothingUiSpacing.Lg),
        ) {
            Text(
                text = "DOTWEL",
                style = NothingUiTypography.displaySmall,
                color = colors.onBackground,
            )
            Text(
                text = "23:59",
                style = NothingUiType.NumericDisplay,
                color = colors.onBackground,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(NothingUiSpacing.Sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(NothingUiSpacing.Sm)
                        .background(colors.accent, CircleShape),
                )
                Text(
                    text = "MONOCHROME / ACCENT",
                    style = NothingUiTypography.labelSmall,
                    color = colors.onSurfaceMuted,
                )
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(colors.outline),
            )
            Text(
                text = "Body text stays in the platform sans-serif. Doto is reserved for display " +
                    "and numeric accents.",
                style = NothingUiTypography.bodyLarge,
                color = colors.onSurface,
            )
            Text(
                text = "Spacing and motion are fixed tokens so later home, drawer and widget " +
                    "surfaces share the same rhythm.",
                style = NothingUiTypography.bodyMedium,
                color = colors.onSurfaceMuted,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(NothingUiSpacing.Md)) {
                NothingUiSpacing.scale.drop(1).forEach { spacing ->
                    Box(
                        modifier = Modifier
                            .size(spacing)
                            .background(colors.onSurfaceMuted),
                    )
                }
            }
        }
    }
}

@Preview(name = "NothingUI dark", showBackground = true, backgroundColor = 0xFF0B0B0B)
@Composable
private fun NothingUiThemeSampleDarkPreview() {
    NothingUiTheme(darkTheme = true) {
        NothingUiThemeSampleScreen()
    }
}

@Preview(name = "NothingUI light", showBackground = true, backgroundColor = 0xFFFFFFFF)
@Composable
private fun NothingUiThemeSampleLightPreview() {
    NothingUiTheme(darkTheme = false) {
        NothingUiThemeSampleScreen()
    }
}
