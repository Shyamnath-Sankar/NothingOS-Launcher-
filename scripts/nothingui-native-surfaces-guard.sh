#!/bin/sh
# Static guard for the a2 native popup/drawer neutral surfaces.
#
# Proves, without Gradle, that:
# - the shared neutral surface tokens exist and use only the monochrome palette;
# - the Play gate is the existing NOTHINGUI_THEME_ENABLED feature flag;
# - the inherited native popup, app-drawer, tab and text tokens are wrapped;
# - the widget-picker scrim stays on the inherited A3 path;
# - the app-drawer text override follows the resolved LIGHT/DARK/SYSTEM theme on
#   Play and keeps the inherited path on other channels.
#
# Usage: scripts/nothingui-native-surfaces-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-native-surfaces-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-native-surfaces-guard: %s\n' "$*" >&2
    exit 1
}

SURFACES="$ROOT/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
COLORS="$ROOT/lawnchair/src/app/nothingui/theme/NothingUiColors.kt"
FEATURE="$ROOT/lawnchair/src/app/nothingui/theme/NothingUiFeature.kt"
TOKENS="$ROOT/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
UTILS="$ROOT/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt"
TOPBAR="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/components/layout/TopBar.kt"
THEME="$ROOT/lawnchair/src/app/lawnchair/ui/theme/Theme.kt"

[ -f "$SURFACES" ] || fail "missing $SURFACES"
[ -f "$COLORS" ] || fail "missing $COLORS"
[ -f "$FEATURE" ] || fail "missing $FEATURE"
[ -f "$TOKENS" ] || fail "missing $TOKENS"
[ -f "$UTILS" ] || fail "missing $UTILS"
[ -f "$TOPBAR" ] || fail "missing $TOPBAR"
[ -f "$THEME" ] || fail "missing $THEME"

token_block() {
    token=$1
    awk -v name="$token" '
        $0 ~ "val " name " =" { in_block = 1 }
        in_block { print }
        in_block && /^[[:space:]]*$/ { exit }
    ' "$TOKENS"
}

grep -Fq 'fun ColorToken.playNativeSurface(play: ColorToken): ColorToken' "$SURFACES" ||
    fail "missing the ColorToken.playNativeSurface bridge"
grep -Fq 'if (NothingUiFeature.themeEnabled) play else this' "$SURFACES" ||
    fail "the native-surface bridge is not gated by NOTHINGUI_THEME_ENABLED"
grep -Fq 'BuildConfig.NOTHINGUI_THEME_ENABLED' "$FEATURE" ||
    fail "NothingUiFeature no longer reads the Play-only build flag"

for token in \
    PopupSurface PopupShadeFirst PopupShadeSecond PopupShadeThird \
    PopupSecondary PopupTertiary TextPrimary TextPrimaryInverse \
    AllAppsBackground AllAppsHeader AllAppsTabBackground AllAppsTabSelected \
    AllAppsScrim AllAppsExpressive AllAppsBlurBackground AllAppsBlurForeground; do
    grep -Fq "val $token = neutral(" "$SURFACES" ||
        fail "missing neutral token $token"
done

for color in Ink Paper White Black Gray900 Gray700 Gray100; do
    grep -Fq "NothingUiPalette.$color" "$SURFACES" ||
        fail "the native surfaces do not use NothingUiPalette.$color"
done

grep -Fq 'fun allAppsBackground(dark: Boolean): Color = if (dark) NothingUiPalette.Black else NothingUiPalette.White' "$SURFACES" ||
    fail "the dark app drawer must use pure black"
grep -Fq 'fun popupSurface(dark: Boolean): Color = if (dark) NothingUiPalette.Gray900 else NothingUiPalette.White' "$SURFACES" ||
    fail "the dark popup must stay charcoal"
grep -Fq 'fun allAppsHeader(dark: Boolean): Color = allAppsBackground(dark)' "$SURFACES" ||
    fail "the drawer header must share the pure-black drawer background"
grep -Fq 'fun allAppsTabBackground(dark: Boolean): Color = allAppsBackground(dark)' "$SURFACES" ||
    fail "the drawer tabs must share the pure-black drawer background"

grep -Fq 'val Black = Color(0xFF000000)' "$COLORS" ||
    fail "missing the pure-black palette swatch"
grep -Fq 'background = NothingUiPalette.Black' "$COLORS" ||
    fail "the dark settings background must be pure black"
grep -Fq 'NothingUiFeature.themeEnabled &&' "$TOPBAR" ||
    fail "the AMOLED top bar must stay Play-gated"
grep -Fq 'MaterialTheme.colorScheme.background == Color.Black' "$TOPBAR" ||
    fail "the AMOLED top bar must detect the pure-black background"
grep -Fq 'NothingUiFeature.themeEnabled &&' "$THEME" ||
    fail "the AMOLED navigation-bar scrim must stay Play-gated"
grep -Fq 'MaterialTheme.colorScheme.background.toArgb() == Color.BLACK' "$THEME" ||
    fail "the AMOLED navigation-bar scrim must use the pure-black background"

if grep -Eq 'Accent1|Accent2|Accent3|AccentRed|ColorAccent|WidgetsPicker' "$SURFACES"; then
    fail "the native surfaces must not use accent or widget-picker colors"
fi

grep -Fq 'import app.nothingui.theme.NothingUiNativeSurfaces' "$TOKENS" ||
    fail "ColorTokens does not import the native surface tokens"
grep -Fq 'import app.nothingui.theme.playNativeSurface' "$TOKENS" ||
    fail "ColorTokens does not import the native surface bridge"

if token_block TextColorPrimaryInverse | grep -Fq 'TextColorPrimary.inverse()'; then
    fail "TextColorPrimaryInverse must not invert the wrapped TextColorPrimary"
fi

for token in \
    SurfaceDimColor TextColorPrimary TextColorPrimaryInverse \
    AllAppsHeaderProtectionColor AllAppsScrimColor AllAppsTabBackground \
    AllAppsTabBackgroundSelected PopupColorPrimary PopupColorSecondary \
    PopupColorTertiary PopupShadeFirst PopupShadeSecond PopupShadeThird \
    ExpressiveAllApps BottomSheetBackgroundColorBlurFallback \
    shade_panel_fg_color shade_panel_bg_color; do
    block=$(token_block "$token")
    [ -n "$block" ] || fail "missing ColorTokens.$token"
    printf '%s\n' "$block" | grep -Fq 'playNativeSurface(' ||
        fail "ColorTokens.$token is not Play-gated"
done

if token_block WidgetsPickerScrim | grep -Fq 'playNativeSurface('; then
    fail "WidgetsPickerScrim belongs to A3 and must stay on the inherited path"
fi

wrapped=$(grep -c 'playNativeSurface(' "$TOKENS" || true)
[ "$wrapped" -eq 17 ] ||
    fail "expected 17 Play-gated native tokens, found $wrapped"

grep -Fq 'if (NothingUiFeature.themeEnabled) {' "$UTILS" ||
    fail "overrideAllAppsTextColor has no Play branch"
grep -Fq 'NothingUiNativeSurfaces.textPrimary(Utilities.isDarkTheme(context)).toArgb()' "$UTILS" ||
    fail "overrideAllAppsTextColor does not use the neutral resolved-theme text color"
grep -Fq 'if (luminance > 0.5f || opacity <= 0.3f)' "$UTILS" ||
    fail "overrideAllAppsTextColor lost the inherited non-Play path"

play_line=$(grep -n 'if (NothingUiFeature.themeEnabled) {' "$UTILS" | sed -n '1s/:.*//p')
luminance_line=$(grep -n 'val luminance = getAllAppsBaseColor' "$UTILS" | sed -n '1s/:.*//p')
if [ -z "$play_line" ] || [ -z "$luminance_line" ] || [ "$play_line" -ge "$luminance_line" ]; then
    fail "the Play text-color branch must run before the inherited luminance path"
fi

printf 'nothingui-native-surfaces-guard: OK\n'
