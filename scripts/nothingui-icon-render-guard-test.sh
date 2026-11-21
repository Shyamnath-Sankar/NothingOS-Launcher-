#!/bin/sh
# Tests for scripts/nothingui-icon-render-guard.sh.
# Run with: sh scripts/nothingui-icon-render-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-icon-render-guard.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

pass() {
    printf 'ok - %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf 'not ok - %s\n' "$1" >&2
}

if [ ! -f "$GUARD" ]; then
    fail 'nothingui-icon-render-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/lawnchair/src/app/nothingui/icons/NothingUiIconPolicy.kt" <<'EOF'
package app.nothingui.icons

data class NothingUiIconPolicy(val useThemedIcons: Boolean, val forceMonochromeFallback: Boolean, val cacheKey: String) {
    companion object {
        const val CACHE_KEY_OFF = "nothingui-icons-off"
        const val CACHE_KEY_NATIVE = "nothingui-icons-native"
        const val CACHE_KEY_FALLBACK = "nothingui-icons-fallback"

        fun resolve(
            playEnabled: Boolean,
            themedIconsEnabled: Boolean,
            forceFallbackEnabled: Boolean,
            customIconSelected: Boolean,
        ) = NothingUiIconPolicy(themedIconsEnabled, forceFallbackEnabled, CACHE_KEY_NATIVE)
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/icons/NothingUiIconColors.kt" <<'EOF'
package app.nothingui.icons

object NothingUiIconColors {
    fun forLightSurface(lightSurface: Boolean): IntArray = intArrayOf(NothingUiPalette.Ink.toArgb(), NothingUiPalette.White.toArgb())

    fun forContext(context: Context): IntArray = forLightSurface(!Utilities.isDarkTheme(context))
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt" <<'EOF'
package app.nothingui.icons

class NothingUiIconThemeController {
    private val normal = MonoIconThemeController(colorProvider = NothingUiIconColors::forContext)

    override val themeID = "nothingui-theme"

    private fun isCustomIcon(key: ComponentKey?): Boolean = false

    private fun policyFor(key: ComponentKey?) = NothingUiIconPolicy.resolve(
        playEnabled = true,
        themedIconsEnabled = true,
        forceFallbackEnabled = true,
        customIconSelected = isCustomIcon(key),
    )

    private fun createForcedThemedBitmap(icon: AdaptiveIconDrawable) {
        if (icon.monochrome != null || sourceHint?.isFileDrawable == true) return
        val monoDrawable = MonochromeIconFactory(info.icon.width).wrap(icon, shapePath)
        return MonoThemedBitmap(bitmap, factory.whiteShadowLayer, NothingUiIconColors::forContext)
    }

    override fun decode() {
        val policy = policyFor(null)
        if (isCustomIcon(null)) return ThemedBitmap.NOT_SUPPORTED
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/icons/LawnchairIconProvider.kt" <<'EOF'
package app.lawnchair.icons

import app.nothingui.icons.NothingUiIconPolicy
import app.nothingui.theme.NothingUiFeature

class LawnchairIconProvider {
    private fun resolveIconEntry(forceNativeFallback: Boolean) {
        if (forceNativeFallback) return
    }

    fun getIcon() {
        val customIconSelected = true
        val policy = NothingUiIconPolicy.resolve(
            playEnabled = NothingUiFeature.homeEnabled,
            themedIconsEnabled = true,
            forceFallbackEnabled = prefs.forceIconMonochrome.get(),
            customIconSelected = customIconSelected,
        )
        if (NothingUiFeature.homeEnabled && customIconSelected) return
    }

    fun getStateForApp() = "ov=x" + if (NothingUiFeature.homeEnabled) {
        ",ni=${policy.cacheKey}"
    } else {
        ""
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt" <<'EOF'
package app.lawnchair.icons

import app.nothingui.icons.NothingUiIconThemeController
import app.nothingui.theme.NothingUiFeature

class LawnchairThemeManager {
    private val nothingUiThemeController = NothingUiIconThemeController()

    fun parse() {
        val themeController = if (NothingUiFeature.homeEnabled) {
            nothingUiThemeController
        } else {
            iconControllerFactory.createThemeController()
        }
        val themedColorsKey = if (themeController != null) {
            if (NothingUiFeature.homeEnabled) {
                NothingUiIconColors.forContext(context).joinToString(",")
            } else {
                ThemedIconDrawable.getColors(context).joinToString(",")
            }
        } else {
            ""
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/LawnchairProcessInitializer.kt" <<'EOF'
package app.lawnchair

import app.nothingui.icons.NothingUiIconColors
import app.nothingui.theme.NothingUiFeature
import com.android.launcher3.Utilities
import com.android.launcher3.icons.mono.ThemedIconDrawable

class LawnchairProcessInitializer {
    fun init() {
        ThemedIconDrawable.COLORS_LOADER = {
            if (NothingUiFeature.homeEnabled) {
                NothingUiIconColors.forContext(it)
            } else if (Utilities.isDarkTheme(it)) {
                intArrayOf(ColorTokens.Accent2_800.resolveColor(it), ColorTokens.Accent1_200.resolveColor(it))
            } else {
                intArrayOf(ColorTokens.Accent1_100.resolveColor(it), ColorTokens.Accent1_700.resolveColor(it))
            }
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/qsb/QsbIconUtil.kt" <<'EOF'
package app.lawnchair.qsb

import app.nothingui.home.NothingUiHomeChrome
import app.nothingui.theme.NothingUiFeature

fun setThemedIconResource(context: Context, themed: Boolean, method: ThemingMethod) {
    val playNeutral = NothingUiFeature.homeEnabled
    val neutralColor = if (playNeutral) NothingUiHomeChrome.textColor(context) else 0
    val primary = if (playNeutral) neutralColor else ColorTokens.QsbIconTintPrimary.resolveColor(context)
    val tint = if (NothingUiFeature.homeEnabled) {
        NothingUiHomeChrome.textColor(context)
    } else {
        ColorTokens.ColorAccent.resolveColor(context)
    }
}
EOF
}

run_ok() {
    if sh "$GUARD" "$TMP_DIR" >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1"
    fi
}

run_fail() {
    if sh "$GUARD" "$TMP_DIR" >/dev/null 2>&1; then
        fail "$1"
    else
        pass "$1"
    fi
}

write_fixture "$TMP_DIR"
run_ok 'the coherent fixture passes'

sed -i '/NothingUiIconPolicy.resolve(/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairIconProvider.kt"
run_fail 'the provider must resolve the saved policy'

write_fixture "$TMP_DIR"
sed -i '/NothingUiFeature.homeEnabled && customIconSelected/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairIconProvider.kt"
run_fail 'an explicit custom selection must bypass the forced fallback'

write_fixture "$TMP_DIR"
sed -i '/ni=\${policy.cacheKey}/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairIconProvider.kt"
run_fail 'the freshness key must isolate native/fallback/off'

write_fixture "$TMP_DIR"
sed -i '/MonochromeIconFactory(info.icon.width)/d' \
    "$TMP_DIR/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt"
run_fail 'the inherited grayscale fallback must be present'

write_fixture "$TMP_DIR"
sed -i '/isCustomIcon(key)/d' \
    "$TMP_DIR/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt"
run_fail 'the controller must preserve custom selections'

write_fixture "$TMP_DIR"
sed -i '/iconControllerFactory.createThemeController()/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt"
run_fail 'non-Play must keep the inherited controller path'

write_fixture "$TMP_DIR"
sed -i '/nothingUiThemeController/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt"
run_fail 'the theme manager must install the Play controller'

write_fixture "$TMP_DIR"
sed -i '/NothingUiPalette.Ink/d' \
    "$TMP_DIR/lawnchair/src/app/nothingui/icons/NothingUiIconColors.kt"
run_fail 'the neutral palette must keep the original ink'

write_fixture "$TMP_DIR"
sed -i '/NothingUiIconColors::forContext/d' \
    "$TMP_DIR/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt"
run_fail 'the controller must supply the neutral palette to the renderer'

write_fixture "$TMP_DIR"
sed -i '/NothingUiIconColors.forContext(context)/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt"
run_fail 'the Play icon cache key must use the neutral palette'

write_fixture "$TMP_DIR"
sed -i '/ThemedIconDrawable.getColors(context)/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt"
run_fail 'non-Play must keep the inherited wallpaper colors in the cache key'

write_fixture "$TMP_DIR"
sed -i '/val playNeutral = NothingUiFeature.homeEnabled/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/qsb/QsbIconUtil.kt"
run_fail 'the QSB glyph must gate its neutral palette'

write_fixture "$TMP_DIR"
sed -i '/NothingUiIconColors.forContext(it)/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/LawnchairProcessInitializer.kt"
run_fail 'the Play themed-icon loader must use the neutral palette'

write_fixture "$TMP_DIR"
sed -i '/ColorTokens.Accent1_700.resolveColor(it)/d' \
    "$TMP_DIR/lawnchair/src/app/lawnchair/LawnchairProcessInitializer.kt"
run_fail 'the non-Play themed-icon loader must keep the inherited accent colors'

if [ "$failures" -ne 0 ]; then
    printf '%s nothingui-icon-render-guard test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-icon-render-guard tests passed\n'
