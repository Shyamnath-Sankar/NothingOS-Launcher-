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

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

object NothingUiPalette {
    val Ink = Color(0xFF0B0B0B)
    val Paper = Color(0xFFF2F2F2)
    val White = Color(0xFFFFFFFF)
    val Gray900 = Color(0xFF1A1A1A)
    val Gray700 = Color(0xFF3A3A3A)
    val Gray500 = Color(0xFF6E6E6E)
    val Gray300 = Color(0xFFB3B3B3)
    val Gray100 = Color(0xFFE6E6E6)
    val AccentRed = Color(0xFFD7261E)
}

@Immutable
data class NothingUiColors(
    val background: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val onBackground: Color,
    val onSurface: Color,
    val onSurfaceMuted: Color,
    val outline: Color,
    val accent: Color,
    val onAccent: Color,
)

val DarkNothingUiColors = NothingUiColors(
    background = NothingUiPalette.Ink,
    surface = NothingUiPalette.Gray900,
    surfaceElevated = NothingUiPalette.Gray700,
    onBackground = NothingUiPalette.Paper,
    onSurface = NothingUiPalette.Paper,
    onSurfaceMuted = NothingUiPalette.Gray300,
    outline = NothingUiPalette.Gray500,
    accent = NothingUiPalette.AccentRed,
    onAccent = NothingUiPalette.White,
)

val LightNothingUiColors = NothingUiColors(
    background = NothingUiPalette.White,
    surface = NothingUiPalette.Paper,
    surfaceElevated = NothingUiPalette.Gray100,
    onBackground = NothingUiPalette.Ink,
    onSurface = NothingUiPalette.Ink,
    onSurfaceMuted = NothingUiPalette.Gray500,
    outline = NothingUiPalette.Gray500,
    accent = NothingUiPalette.AccentRed,
    onAccent = NothingUiPalette.White,
)

val LocalNothingUiColors = staticCompositionLocalOf { DarkNothingUiColors }

internal fun NothingUiColors.toDarkColorScheme(): ColorScheme = darkColorScheme(
    surfaceBright = surfaceElevated,
    surfaceDim = background,
    surfaceTint = background,
    primary = accent,
    onPrimary = onAccent,
    primaryContainer = surfaceElevated,
    onPrimaryContainer = onSurface,
    inversePrimary = accent,
    secondary = onSurfaceMuted,
    onSecondary = background,
    secondaryContainer = surfaceElevated,
    onSecondaryContainer = onSurface,
    tertiary = onSurfaceMuted,
    onTertiary = background,
    tertiaryContainer = surfaceElevated,
    onTertiaryContainer = onSurface,
    background = background,
    onBackground = onBackground,
    surface = surface,
    onSurface = onSurface,
    surfaceVariant = surfaceElevated,
    onSurfaceVariant = onSurfaceMuted,
    surfaceContainerLowest = background,
    surfaceContainerLow = surface,
    surfaceContainer = surface,
    surfaceContainerHigh = surfaceElevated,
    surfaceContainerHighest = surfaceElevated,
    outline = outline,
    outlineVariant = surfaceElevated,
    error = accent,
    onError = onAccent,
    inverseSurface = onBackground,
    inverseOnSurface = background,
    scrim = background,
)

internal fun NothingUiColors.toLightColorScheme(): ColorScheme = lightColorScheme(
    surfaceBright = background,
    surfaceDim = surfaceElevated,
    surfaceTint = background,
    primary = accent,
    onPrimary = onAccent,
    primaryContainer = surfaceElevated,
    onPrimaryContainer = onSurface,
    inversePrimary = accent,
    secondary = onSurfaceMuted,
    onSecondary = background,
    secondaryContainer = surfaceElevated,
    onSecondaryContainer = onSurface,
    tertiary = onSurfaceMuted,
    onTertiary = background,
    tertiaryContainer = surfaceElevated,
    onTertiaryContainer = onSurface,
    background = background,
    onBackground = onBackground,
    surface = surface,
    onSurface = onSurface,
    surfaceVariant = surfaceElevated,
    onSurfaceVariant = onSurfaceMuted,
    surfaceContainerLowest = background,
    surfaceContainerLow = surface,
    surfaceContainer = surface,
    surfaceContainerHigh = surfaceElevated,
    surfaceContainerHighest = surfaceElevated,
    outline = outline,
    outlineVariant = surfaceElevated,
    error = accent,
    onError = onAccent,
    inverseSurface = onBackground,
    inverseOnSurface = background,
    scrim = background,
)
