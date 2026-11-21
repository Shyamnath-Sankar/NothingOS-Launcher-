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

package app.nothingui.home

import android.content.Context
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.ColorUtils
import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.R
import com.android.launcher3.util.Themes

/**
 * Monochrome chrome colors for the Play home surface.
 *
 * Surface and ink are selected as an explicit, high-contrast pair from the original NothingUI
 * palette, driven by the inherited user light/dark theme (`isMainColorDark`). This deliberately
 * avoids pairing the inherited wallpaper-derived text color (often white) with the pale floating
 * surface color, which could render white-on-white. The user's light/dark choice still selects
 * the pair, matching the inherited day/night QSB icon and page-dot tints.
 *
 * Only consulted behind [app.nothingui.theme.NothingUiFeature.homeEnabled].
 */
object NothingUiHomeChrome {

    fun isLightSurface(context: Context): Boolean {
        val darkTheme = runCatching {
            Themes.getAttrBoolean(context, R.attr.isMainColorDark)
        }.getOrDefault(false)
        return !darkTheme
    }

    fun surfaceColor(context: Context): Int {
        val color = if (isLightSurface(context)) {
            NothingUiPalette.Paper
        } else {
            NothingUiPalette.Gray900
        }
        return color.toArgb()
    }

    fun textColor(context: Context): Int {
        val color = if (isLightSurface(context)) {
            NothingUiPalette.Ink
        } else {
            NothingUiPalette.Paper
        }
        return color.toArgb()
    }

    fun outlineColor(context: Context): Int = ColorUtils.setAlphaComponent(textColor(context), OUTLINE_ALPHA)

    fun pageIndicatorColor(context: Context): Int = textColor(context)

    private const val OUTLINE_ALPHA = 0x40
}
