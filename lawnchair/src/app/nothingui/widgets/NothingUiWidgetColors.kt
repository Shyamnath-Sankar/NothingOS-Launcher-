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

import android.content.Context
import android.content.res.Configuration
import androidx.compose.ui.graphics.toArgb
import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.R
import com.android.launcher3.Utilities

/**
 * Explicit dark/light surface and content pair for the Play home widgets.
 *
 * Widget providers are updated from an application or broadcast context, which does not carry the
 * launcher activity's theme attributes. Reading `isMainColorDark` there can silently fall back to
 * the light surface and paint ink glyphs on a dark wallpaper. [Utilities.isDarkTheme] instead reads
 * the stored launcher theme preference (light, dark or system) and is safe from any context.
 *
 * Both widgets use the same pair so the rounded clock tile and the circular battery face read as a
 * deliberate set: charcoal/white in dark mode and paper/ink in light mode.
 */
object NothingUiWidgetColors {

    fun isLightSurface(context: Context): Boolean {
        val darkTheme = runCatching { Utilities.isDarkTheme(context) }
            .getOrElse {
                val nightMode = context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK
                nightMode == Configuration.UI_MODE_NIGHT_YES
            }
        return !darkTheme
    }

    fun surfaceColor(lightSurface: Boolean): Int = if (lightSurface) {
        NothingUiPalette.Paper.toArgb()
    } else {
        NothingUiPalette.Gray900.toArgb()
    }

    fun contentColor(lightSurface: Boolean): Int = if (lightSurface) {
        NothingUiPalette.Ink.toArgb()
    } else {
        NothingUiPalette.White.toArgb()
    }

    fun surfaceColor(context: Context): Int = surfaceColor(isLightSurface(context))

    fun contentColor(context: Context): Int = contentColor(isLightSurface(context))

    fun tileDrawable(lightSurface: Boolean): Int = if (lightSurface) {
        R.drawable.nothingui_widget_tile_light
    } else {
        R.drawable.nothingui_widget_tile_dark
    }
}
