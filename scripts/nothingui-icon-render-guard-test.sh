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

    write_file "$root/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt" <<'EOF'
package app.nothingui.icons

class NothingUiIconThemeController {
    private val normal = MonoIconThemeController()

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
        return MonoThemedBitmap(bitmap, factory.whiteShadowLayer)
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

if [ "$failures" -ne 0 ]; then
    printf '%s nothingui-icon-render-guard test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-icon-render-guard tests passed\n'
