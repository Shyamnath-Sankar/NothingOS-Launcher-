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

package app.nothingui.icons

import android.content.Context
import android.graphics.Color
import androidx.compose.ui.graphics.toArgb
import app.lawnchair.icons.shouldTransparentBGIcons
import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.Utilities

/**
 * Neutral black/white palette for the Play-only themed icon renderer.
 *
 * The inherited [com.android.launcher3.icons.mono.ThemedIconDrawable] resolves its
 * background/foreground pair through a process-wide loader that Lawnchair points at
 * wallpaper-derived accent swatches. The Play home is deliberately monochrome, so the Play icon
 * controller supplies this constant pair instead. The order is `[background, foreground]`, which
 * matches [com.android.launcher3.icons.mono.ThemedIconDrawable.getColors].
 *
 * Non-Play channels never consult this object and keep the inherited wallpaper colors.
 */
object NothingUiIconColors {
    fun forLightSurface(lightSurface: Boolean): IntArray = if (lightSurface) {
        intArrayOf(NothingUiPalette.White.toArgb(), NothingUiPalette.Ink.toArgb())
    } else {
        intArrayOf(NothingUiPalette.Ink.toArgb(), NothingUiPalette.White.toArgb())
    }

    fun forContext(context: Context): IntArray {
        val colors = forLightSurface(!Utilities.isDarkTheme(context))
        return if (context.shouldTransparentBGIcons()) {
            intArrayOf(Color.TRANSPARENT, colors[1])
        } else {
            colors
        }
    }
}
