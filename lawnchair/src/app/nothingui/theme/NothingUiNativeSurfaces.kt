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

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import app.lawnchair.theme.color.tokens.ColorToken
import app.lawnchair.theme.color.tokens.DayNightColorToken
import app.lawnchair.theme.color.tokens.StaticColorToken
import app.lawnchair.theme.color.tokens.withContext

/**
 * Neutral native HOME popup and app-drawer colors for the Play channel.
 *
 * These tokens are consumed by the inherited [app.lawnchair.theme.color.tokens.ColorTokens]
 * definitions through [playNativeSurface]. They deliberately use only the original
 * [NothingUiPalette] monochrome swatches, never the wallpaper-derived accent scheme, so a large
 * drawer background or popup cannot be tinted by an accent swatch. The light/dark choice is made
 * by [DayNightColorToken], which follows the inherited LIGHT/DARK/SYSTEM theme resolution.
 *
 * Non-Play channels keep the inherited color tokens unchanged.
 */
object NothingUiNativeSurfaces {
    fun popupSurface(dark: Boolean): Color =
        if (dark) NothingUiPalette.Gray900 else NothingUiPalette.White

    fun popupShadeFirst(dark: Boolean): Color = popupSurface(dark)

    fun popupShadeSecond(dark: Boolean): Color =
        if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Paper

    fun popupShadeThird(dark: Boolean): Color =
        if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Gray100

    fun popupSecondary(dark: Boolean): Color = popupSurface(dark)

    fun popupTertiary(dark: Boolean): Color =
        if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Gray100

    fun textPrimary(dark: Boolean): Color =
        if (dark) NothingUiPalette.Paper else NothingUiPalette.Ink

    fun textPrimaryInverse(dark: Boolean): Color =
        if (dark) NothingUiPalette.Ink else NothingUiPalette.Paper

    fun allAppsBackground(dark: Boolean): Color =
        if (dark) NothingUiPalette.Gray900 else NothingUiPalette.White

    fun allAppsHeader(dark: Boolean): Color = allAppsBackground(dark)

    fun allAppsTabBackground(dark: Boolean): Color = allAppsBackground(dark)

    fun allAppsTabSelected(dark: Boolean): Color =
        if (dark) NothingUiPalette.Paper else NothingUiPalette.Ink

    fun allAppsScrim(dark: Boolean): Color =
        allAppsBackground(dark).copy(alpha = SCRIM_ALPHA)

    fun allAppsExpressive(dark: Boolean): Color =
        allAppsBackground(dark).copy(alpha = EXPRESSIVE_ALPHA)

    fun allAppsBlurBackground(dark: Boolean): Color =
        allAppsBackground(dark).copy(alpha = BLUR_LAYER_ALPHA)

    fun allAppsBlurForeground(dark: Boolean): Color = if (dark) {
        NothingUiPalette.Gray700.copy(alpha = BLUR_LAYER_ALPHA)
    } else {
        NothingUiPalette.White.copy(alpha = BLUR_LAYER_ALPHA)
    }

    val PopupSurface = neutral(popupSurface(dark = false), popupSurface(dark = true))
    val PopupShadeFirst = neutral(popupShadeFirst(dark = false), popupShadeFirst(dark = true))
    val PopupShadeSecond = neutral(popupShadeSecond(dark = false), popupShadeSecond(dark = true))
    val PopupShadeThird = neutral(popupShadeThird(dark = false), popupShadeThird(dark = true))
    val PopupSecondary = neutral(popupSecondary(dark = false), popupSecondary(dark = true))
    val PopupTertiary = neutral(popupTertiary(dark = false), popupTertiary(dark = true))
    val TextPrimary = neutral(textPrimary(dark = false), textPrimary(dark = true))
    val TextPrimaryInverse = neutral(
        textPrimaryInverse(dark = false),
        textPrimaryInverse(dark = true),
    )
    val AllAppsBackground = neutral(allAppsBackground(dark = false), allAppsBackground(dark = true))
    val AllAppsHeader = neutral(allAppsHeader(dark = false), allAppsHeader(dark = true))
    val AllAppsTabBackground = neutral(
        allAppsTabBackground(dark = false),
        allAppsTabBackground(dark = true),
    )
    val AllAppsTabSelected = neutral(
        allAppsTabSelected(dark = false),
        allAppsTabSelected(dark = true),
    )
    val AllAppsScrim = neutral(allAppsScrim(dark = false), allAppsScrim(dark = true))
    val AllAppsExpressive = neutral(
        allAppsExpressive(dark = false),
        allAppsExpressive(dark = true),
    )
    val AllAppsBlurBackground = neutral(
        allAppsBlurBackground(dark = false),
        allAppsBlurBackground(dark = true),
    )
    val AllAppsBlurForeground = neutral(
        allAppsBlurForeground(dark = false),
        allAppsBlurForeground(dark = true),
    )

    private fun neutral(light: Color, dark: Color): DayNightColorToken =
        DayNightColorToken(static(light), static(dark))

    private fun static(color: Color): StaticColorToken =
        StaticColorToken(color.toArgb().toLong())

    private const val SCRIM_ALPHA = 0.40f
    private const val EXPRESSIVE_ALPHA = 0.50f
    private const val BLUR_LAYER_ALPHA = 0.32f
}

/**
 * Uses [play] only when the Play theme gate is enabled; otherwise resolves the inherited token
 * exactly as before.
 */
fun ColorToken.playNativeSurface(play: ColorToken): ColorToken = withContext {
    if (NothingUiFeature.themeEnabled) play else this
}
