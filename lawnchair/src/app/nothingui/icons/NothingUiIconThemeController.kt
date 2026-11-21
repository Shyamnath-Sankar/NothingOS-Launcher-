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

import android.annotation.TargetApi
import android.content.Context
import android.graphics.Rect
import android.graphics.drawable.AdaptiveIconDrawable
import android.os.Build
import app.lawnchair.data.iconoverride.IconOverrideRepository
import app.lawnchair.preferences.PreferenceManager
import com.android.launcher3.icons.BaseIconFactory
import com.android.launcher3.icons.BaseIconFactory.MODE_ALPHA
import com.android.launcher3.icons.BitmapInfo
import com.android.launcher3.icons.IconNormalizer.ICON_VISIBLE_AREA_FACTOR
import com.android.launcher3.icons.IconThemeController
import com.android.launcher3.icons.MonochromeIconFactory
import com.android.launcher3.icons.SourceHint
import com.android.launcher3.icons.ThemedBitmap
import com.android.launcher3.icons.mono.MonoIconThemeController
import com.android.launcher3.icons.mono.MonoThemedBitmap
import com.android.launcher3.util.ComponentKey

/**
 * Play-only icon controller that applies [NothingUiIconPolicy] to the inherited monochrome
 * renderer.
 *
 * The inherited controller is global: enabling its forced mode would also gray out an explicit
 * icon-pack or per-app choice. This wrapper keeps the decision per icon by inspecting the
 * [SourceHint] component key, so custom selections are left untouched while everything else gets
 * the neutral monochrome treatment.
 */
@TargetApi(Build.VERSION_CODES.TIRAMISU)
class NothingUiIconThemeController(
    private val prefs: PreferenceManager,
    private val overrideRepo: IconOverrideRepository,
) : IconThemeController {
    private val normal = MonoIconThemeController(colorProvider = NothingUiIconColors::forContext)

    override val themeID = "nothingui-theme"

    private fun isCustomIcon(key: ComponentKey?): Boolean {
        if (prefs.iconPackPackage.get().isNotEmpty()) return true
        return key != null && overrideRepo.overridesMap.containsKey(key)
    }

    private fun policyFor(key: ComponentKey?): NothingUiIconPolicy = NothingUiIconPolicy.resolve(
        playEnabled = true,
        themedIconsEnabled = prefs.themedIcons.get(),
        forceFallbackEnabled = prefs.forceIconMonochrome.get(),
        customIconSelected = isCustomIcon(key),
    )

    /**
     * Builds the grayscale/threshold fallback with the inherited [MonochromeIconFactory].
     *
     * The inherited forced controller reads the raw preference with a false default, so it cannot
     * see the Play default until the value is persisted. Generating the fallback from the already
     * resolved policy keeps fresh Play installs monochrome without a startup write.
     */
    private fun createForcedThemedBitmap(
        icon: AdaptiveIconDrawable,
        info: BitmapInfo,
        factory: BaseIconFactory,
        sourceHint: SourceHint?,
    ): ThemedBitmap? {
        if (icon.monochrome != null || sourceHint?.isFileDrawable == true) {
            return normal.createThemedBitmap(icon, info, factory, sourceHint)
        }
        val shapePath = factory.getShapePath(icon, Rect(0, 0, info.icon.width, info.icon.height))
        val monoDrawable = MonochromeIconFactory(info.icon.width).wrap(icon, shapePath)
        return MonoThemedBitmap(
            factory.createIconBitmap(monoDrawable, ICON_VISIBLE_AREA_FACTOR, MODE_ALPHA),
            factory.whiteShadowLayer,
            NothingUiIconColors::forContext,
        )
    }

    override fun createThemedBitmap(
        icon: AdaptiveIconDrawable,
        info: BitmapInfo,
        factory: BaseIconFactory,
        sourceHint: SourceHint?,
    ): ThemedBitmap? {
        val key = sourceHint?.key
        val policy = policyFor(key)
        if (!policy.useThemedIcons || isCustomIcon(key)) return null
        return if (policy.forceMonochromeFallback) {
            createForcedThemedBitmap(icon, info, factory, sourceHint)
        } else {
            normal.createThemedBitmap(icon, info, factory, sourceHint)
        }
    }

    override fun decode(
        data: ByteArray,
        info: BitmapInfo,
        factory: BaseIconFactory,
        sourceHint: SourceHint,
    ): ThemedBitmap {
        val policy = policyFor(sourceHint.key)
        if (!policy.useThemedIcons || isCustomIcon(sourceHint.key)) {
            return ThemedBitmap.NOT_SUPPORTED
        }
        return normal.decode(data, info, factory, sourceHint)
    }

    override fun createThemedAdaptiveIcon(
        context: Context,
        originalIcon: AdaptiveIconDrawable,
        info: BitmapInfo?,
    ): AdaptiveIconDrawable? {
        val policy = policyFor(key = null)
        if (!policy.useThemedIcons || isCustomIcon(key = null)) return originalIcon
        return normal.createThemedAdaptiveIcon(context, originalIcon, info)
    }
}
