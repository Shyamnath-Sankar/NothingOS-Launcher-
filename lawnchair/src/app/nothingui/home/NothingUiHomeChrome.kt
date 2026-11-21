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
import androidx.core.graphics.ColorUtils
import com.android.launcher3.R
import com.android.launcher3.util.Themes

/**
 * Monochrome chrome colors for the Play home surface.
 *
 * These reuse the inherited workspace theme attributes so light/dark and wallpaper-derived
 * contrast keep working. They are only consulted behind [app.nothingui.theme.NothingUiFeature.homeEnabled].
 */
object NothingUiHomeChrome {

    fun surfaceColor(context: Context): Int = Themes.getColorBackgroundFloating(context)

    fun textColor(context: Context): Int = Themes.getAttrColor(context, R.attr.workspaceTextColor)

    fun outlineColor(context: Context): Int = ColorUtils.setAlphaComponent(textColor(context), OUTLINE_ALPHA)

    fun pageIndicatorColor(context: Context): Int = textColor(context)

    private const val OUTLINE_ALPHA = 0x40
}
