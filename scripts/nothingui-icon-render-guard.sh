#!/bin/sh
# Static guard for the Play-only NothingUI icon renderer wiring.
#
# Proves, without Gradle, that:
# - the saved NothingUiIconPolicy is applied by the real icon provider and theme manager;
# - the Play path can force the inherited monochrome fallback per icon;
# - explicit icon-pack and per-app choices bypass the forced fallback;
# - native/fallback/off cache state is part of the icon freshness key;
# - the Play renderer draws the original neutral black/white pair, never wallpaper accents;
# - the QSB glyph follows the same neutral ink only behind the Play gate;
# - non-Play keeps the inherited icon controller and force preference behaviour.
#
# Usage: scripts/nothingui-icon-render-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-icon-render-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-icon-render-guard: %s\n' "$*" >&2
    exit 1
}

POLICY="$ROOT/lawnchair/src/app/nothingui/icons/NothingUiIconPolicy.kt"
COLORS="$ROOT/lawnchair/src/app/nothingui/icons/NothingUiIconColors.kt"
CONTROLLER="$ROOT/lawnchair/src/app/nothingui/icons/NothingUiIconThemeController.kt"
PROVIDER="$ROOT/lawnchair/src/app/lawnchair/icons/LawnchairIconProvider.kt"
THEME_MANAGER="$ROOT/lawnchair/src/app/lawnchair/icons/LawnchairThemeManager.kt"
QSB_ICON="$ROOT/lawnchair/src/app/lawnchair/qsb/QsbIconUtil.kt"
PROCESS_INITIALIZER="$ROOT/lawnchair/src/app/lawnchair/LawnchairProcessInitializer.kt"

for file in "$POLICY" "$COLORS" "$CONTROLLER" "$PROVIDER" "$THEME_MANAGER" "$QSB_ICON" "$PROCESS_INITIALIZER"; do
    [ -f "$file" ] || fail "missing $file"
done

grep -Fq 'fun resolve(' "$POLICY" || fail "the icon policy has no resolve()"
grep -Fq 'CACHE_KEY_NATIVE' "$POLICY" || fail "the icon policy is missing the native cache key"
grep -Fq 'CACHE_KEY_FALLBACK' "$POLICY" || fail "the icon policy is missing the fallback cache key"
grep -Fq 'CACHE_KEY_OFF' "$POLICY" || fail "the icon policy is missing the off cache key"

grep -Fq 'class NothingUiIconThemeController' "$CONTROLLER" ||
    fail "the Play icon controller wrapper is missing"
grep -Fq 'NothingUiIconPolicy.resolve(' "$CONTROLLER" ||
    fail "the Play icon controller does not use the saved policy"
grep -Fq 'MonochromeIconFactory(info.icon.width).wrap(icon, shapePath)' "$CONTROLLER" ||
    fail "the Play icon controller does not use the inherited grayscale fallback"
grep -Fq 'MonoThemedBitmap(' "$CONTROLLER" ||
    fail "the Play icon controller does not create the inherited themed bitmap"
grep -Fq 'sourceHint?.isFileDrawable == true' "$CONTROLLER" ||
    fail "the Play icon controller does not preserve file drawables"
grep -Fq 'MonoIconThemeController(colorProvider = NothingUiIconColors::forContext)' "$CONTROLLER" ||
    fail "the Play native themed renderer does not use the neutral palette"
grep -Fq 'NothingUiIconColors::forContext' "$CONTROLLER" ||
    fail "the Play icon controller does not supply the neutral palette"
grep -Fq 'NothingUiPalette.Ink' "$COLORS" ||
    fail "the neutral icon palette does not use the original ink"
grep -Fq 'NothingUiPalette.White' "$COLORS" ||
    fail "the neutral icon palette does not use black/white"
grep -Fq 'fun forLightSurface(' "$COLORS" ||
    fail "the neutral icon palette has no testable light/dark resolver"
grep -Fq 'fun forContext(' "$COLORS" ||
    fail "the neutral icon palette has no context resolver"
grep -Fq 'isCustomIcon(key)' "$CONTROLLER" ||
    fail "the Play icon controller does not preserve custom selections"
grep -Fq 'ThemedBitmap.NOT_SUPPORTED' "$CONTROLLER" ||
    fail "cached custom icons are not excluded from the themed path"
grep -Fq 'themeID = "nothingui-theme"' "$CONTROLLER" ||
    fail "the Play icon controller does not isolate its cache identity"

grep -Fq 'import app.nothingui.icons.NothingUiIconPolicy' "$PROVIDER" ||
    fail "the icon provider does not import the saved policy"
grep -Fq 'import app.nothingui.theme.NothingUiFeature' "$PROVIDER" ||
    fail "the icon provider does not read the Play gate"
grep -Fq 'NothingUiIconPolicy.resolve(' "$PROVIDER" ||
    fail "the icon provider does not resolve the policy"
grep -Fq 'playEnabled = NothingUiFeature.homeEnabled' "$PROVIDER" ||
    fail "the icon provider does not pass the Play gate to the policy"
grep -Fq 'customIconSelected = customIconSelected' "$PROVIDER" ||
    fail "the icon provider does not pass the custom-selection decision"
grep -Fq 'forceNativeFallback' "$PROVIDER" ||
    fail "the icon provider cannot bypass an icon pack for the fallback"
grep -Fq 'if (NothingUiFeature.homeEnabled && customIconSelected)' "$PROVIDER" ||
    fail "an explicit Play icon-pack/per-app choice can be overridden by the fallback"
grep -Fq '",ni=${policy.cacheKey}"' "$PROVIDER" ||
    fail "the icon freshness key does not isolate native/fallback/off"
grep -Fq 'prefs.forceIconMonochrome.get()' "$PROVIDER" ||
    fail "the inherited non-Play force preference is not retained"

grep -Fq 'import app.nothingui.icons.NothingUiIconThemeController' "$THEME_MANAGER" ||
    fail "the theme manager does not import the Play controller"
grep -Fq 'if (NothingUiFeature.homeEnabled)' "$THEME_MANAGER" ||
    fail "the Play controller is not gated to the Play channel"
grep -Fq 'nothingUiThemeController' "$THEME_MANAGER" ||
    fail "the theme manager does not install the Play controller"
grep -Fq 'iconControllerFactory.createThemeController()' "$THEME_MANAGER" ||
    fail "the inherited non-Play controller path was removed"
grep -Fq 'NothingUiIconColors.forContext(context).joinToString(",")' "$THEME_MANAGER" ||
    fail "the Play icon cache key does not use the neutral palette"
grep -Fq 'ThemedIconDrawable.getColors(context).joinToString(",")' "$THEME_MANAGER" ||
    fail "the non-Play icon cache key lost the inherited wallpaper colors"

grep -Fq 'import app.nothingui.home.NothingUiHomeChrome' "$QSB_ICON" ||
    fail "the QSB glyph does not use the neutral chrome ink"
grep -Fq 'import app.nothingui.theme.NothingUiFeature' "$QSB_ICON" ||
    fail "the QSB glyph is not Play-gated"
grep -Fq 'val playNeutral = NothingUiFeature.homeEnabled' "$QSB_ICON" ||
    fail "the QSB glyph does not gate its neutral palette"
grep -Fq 'if (playNeutral) neutralColor else ColorTokens.QsbIconTintPrimary.resolveColor(context)' "$QSB_ICON" ||
    fail "the QSB primary glyph can lose the neutral palette"
grep -Fq 'ColorTokens.ColorAccent.resolveColor(context)' "$QSB_ICON" ||
    fail "the non-Play QSB tint fallback was removed"

grep -Fq 'ThemedIconDrawable.COLORS_LOADER = {' "$PROCESS_INITIALIZER" ||
    fail "the inherited themed-icon color loader was removed"
grep -Fq 'if (NothingUiFeature.homeEnabled)' "$PROCESS_INITIALIZER" ||
    fail "the inherited themed-icon color loader is not Play-gated"
grep -Fq 'NothingUiIconColors.forContext(it)' "$PROCESS_INITIALIZER" ||
    fail "the Play themed-icon loader does not use the neutral palette"
grep -Fq 'ColorTokens.Accent1_700.resolveColor(it)' "$PROCESS_INITIALIZER" ||
    fail "the non-Play themed-icon loader lost the inherited accent colors"

printf 'nothingui-icon-render-guard: OK\n'
