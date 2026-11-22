#!/bin/sh
# Tests for scripts/nothingui-native-surfaces-guard.sh.
# Run with: sh scripts/nothingui-native-surfaces-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-native-surfaces-guard.sh"
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
    fail 'nothingui-native-surfaces-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt" <<'EOF'
package app.nothingui.theme

import app.lawnchair.theme.color.tokens.ColorToken
import app.lawnchair.theme.color.tokens.withContext

object NothingUiNativeSurfaces {
    fun popupSurface(dark: Boolean) = if (dark) NothingUiPalette.Gray900 else NothingUiPalette.White
    fun popupShadeFirst(dark: Boolean) = popupSurface(dark)
    fun popupShadeSecond(dark: Boolean) = if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Paper
    fun popupShadeThird(dark: Boolean) = if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Gray100
    fun popupSecondary(dark: Boolean) = popupSurface(dark)
    fun popupTertiary(dark: Boolean) = if (dark) NothingUiPalette.Gray700 else NothingUiPalette.Gray100
    fun textPrimary(dark: Boolean) = if (dark) NothingUiPalette.Paper else NothingUiPalette.Ink
    fun textPrimaryInverse(dark: Boolean) = if (dark) NothingUiPalette.Ink else NothingUiPalette.Paper
    fun allAppsBackground(dark: Boolean) = if (dark) NothingUiPalette.Gray900 else NothingUiPalette.White
    fun allAppsHeader(dark: Boolean) = allAppsBackground(dark)
    fun allAppsTabBackground(dark: Boolean) = allAppsBackground(dark)
    fun allAppsTabSelected(dark: Boolean) = if (dark) NothingUiPalette.Paper else NothingUiPalette.Ink
    fun allAppsScrim(dark: Boolean) = allAppsBackground(dark)
    fun allAppsExpressive(dark: Boolean) = allAppsBackground(dark)
    fun allAppsBlurBackground(dark: Boolean) = allAppsBackground(dark)
    fun allAppsBlurForeground(dark: Boolean) = allAppsBackground(dark)

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
    val AllAppsExpressive = neutral(allAppsExpressive(dark = false), allAppsExpressive(dark = true))
    val AllAppsBlurBackground = neutral(
        allAppsBlurBackground(dark = false),
        allAppsBlurBackground(dark = true),
    )
    val AllAppsBlurForeground = neutral(
        allAppsBlurForeground(dark = false),
        allAppsBlurForeground(dark = true),
    )

    private fun neutral(light: Any, dark: Any): Any = Unit
}

fun ColorToken.playNativeSurface(play: ColorToken): ColorToken = withContext {
    if (NothingUiFeature.themeEnabled) play else this
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiFeature.kt" <<'EOF'
package app.nothingui.theme

import com.android.launcher3.BuildConfig

object NothingUiFeature {
    val themeEnabled: Boolean = BuildConfig.NOTHINGUI_THEME_ENABLED
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt" <<'EOF'
package app.lawnchair.theme.color.tokens

import app.nothingui.theme.NothingUiNativeSurfaces
import app.nothingui.theme.playNativeSurface

object ColorTokens {
    @JvmField val SurfaceDimColor = DayNightColorToken(Neutral2_600, Neutral2_600)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsBackground)

    @JvmField val TextColorPrimary = DayNightColorToken(Neutral1_900, Neutral1_50)
        .playNativeSurface(NothingUiNativeSurfaces.TextPrimary)

    @JvmField val TextColorPrimaryInverse = DayNightColorToken(Neutral1_50, Neutral1_900)
        .playNativeSurface(NothingUiNativeSurfaces.TextPrimaryInverse)

    @JvmField val AllAppsHeaderProtectionColor = DayNightColorToken(Neutral1_500, Neutral1_500)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsHeader)

    @JvmField val AllAppsScrimColor = StaticColorToken(0x404040).setAlpha(.40f)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsScrim)

    @JvmField val AllAppsTabBackground = DayNightColorToken(Neutral1_100, Neutral1_800)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsTabBackground)

    @JvmField val AllAppsTabBackgroundSelected = DayNightColorToken(Accent1_600, Accent1_200)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsTabSelected)

    @JvmField val PopupColorPrimary = DayNightColorToken(Accent2_50, Neutral2_800)
        .playNativeSurface(NothingUiNativeSurfaces.PopupSurface)

    @JvmField val PopupColorSecondary = DayNightColorToken(Neutral2_100, Neutral1_900)
        .playNativeSurface(NothingUiNativeSurfaces.PopupSecondary)

    @JvmField val PopupColorTertiary = DayNightColorToken(Neutral2_300, Neutral2_700)
        .playNativeSurface(NothingUiNativeSurfaces.PopupTertiary)

    @JvmField val PopupShadeFirst = DayNightColorToken(PopupColorPrimary, PopupColorPrimary)
        .playNativeSurface(NothingUiNativeSurfaces.PopupShadeFirst)

    @JvmField val PopupShadeSecond = DayNightColorToken(PopupColorPrimary, PopupColorPrimary)
        .playNativeSurface(NothingUiNativeSurfaces.PopupShadeSecond)

    @JvmField val PopupShadeThird = DayNightColorToken(PopupColorPrimary, PopupColorPrimary)
        .playNativeSurface(NothingUiNativeSurfaces.PopupShadeThird)

    @JvmField val ExpressiveAllApps = DayNightColorToken(Accent1_100, Accent1_800).setAlpha(0.5f)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsExpressive)

    @JvmField val BottomSheetBackgroundColorBlurFallback = DayNightColorToken(Accent2_200, Accent2_800)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsBackground)

    @JvmField val shade_panel_fg_color = DayNightColorToken(
        Accent1_100.setAlpha(0.32f),
        Accent1_800.setAlpha(0.32f),
    ).playNativeSurface(NothingUiNativeSurfaces.AllAppsBlurForeground)

    @JvmField val shade_panel_bg_color = Surface.setAlpha(0.32f)
        .playNativeSurface(NothingUiNativeSurfaces.AllAppsBlurBackground)

    @JvmField val WidgetsPickerScrim = Scrim.setAlpha(.32f)

}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt" <<'EOF'
package app.lawnchair.util

fun overrideAllAppsTextColor(textView: TextView) {
    val context = textView.context
    val opacity = PreferenceManager.getInstance(context).drawerOpacity.get()
    if (NothingUiFeature.themeEnabled) {
        if (opacity <= 0.3f) {
            textView.setTextColor(Themes.getAttrColor(context, R.attr.allAppsAlternateTextColor))
        } else {
            textView.setTextColor(
                NothingUiNativeSurfaces.textPrimary(Utilities.isDarkTheme(context)).toArgb(),
            )
        }
        return
    }
    val luminance = getAllAppsBaseColor(context, ColorTokens.AllAppsScrimColor.resolveColor(context)).luminance
    if (luminance > 0.5f || opacity <= 0.3f) {
        textView.setTextColor(Themes.getAttrColor(context, R.attr.allAppsAlternateTextColor))
    }
}
EOF
}

run_guard() {
    sh "$GUARD" "$1" > "$TMP_DIR/out" 2> "$TMP_DIR/err"
}

expect_pass() {
    name=$1
    root=$2
    if run_guard "$root"; then
        pass "$name"
    else
        fail "$name (expected success)"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

expect_fail_contains() {
    name=$1
    root=$2
    needle=$3
    if run_guard "$root"; then
        fail "$name (expected failure)"
        return
    fi
    if grep -Fq "$needle" "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (failure did not mention '$needle')"
        cat "$TMP_DIR/err" >&2
    fi
}

clean="$TMP_DIR/clean"
write_fixture "$clean"
expect_pass 'complete native-surface wiring passes' "$clean"

missing_bridge="$TMP_DIR/missing-bridge"
cp -R "$clean" "$missing_bridge"
sed -i '/fun ColorToken.playNativeSurface/d' \
    "$missing_bridge/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
expect_fail_contains 'missing bridge fails' "$missing_bridge" 'playNativeSurface bridge'

missing_gate="$TMP_DIR/missing-gate"
cp -R "$clean" "$missing_gate"
sed -i 's/if (NothingUiFeature.themeEnabled) play else this/play/' \
    "$missing_gate/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
expect_fail_contains 'bridge without the Play gate fails' "$missing_gate" 'NOTHINGUI_THEME_ENABLED'

missing_token="$TMP_DIR/missing-token"
cp -R "$clean" "$missing_token"
sed -i '/val PopupShadeThird = neutral(/d' \
    "$missing_token/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
expect_fail_contains 'missing neutral token fails' "$missing_token" 'missing neutral token PopupShadeThird'

accent="$TMP_DIR/accent"
cp -R "$clean" "$accent"
printf '\n// NothingUiPalette.AccentRed\n' \
    >> "$accent/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
expect_fail_contains 'accent color in the native surfaces fails' "$accent" 'accent or widget-picker'

missing_import="$TMP_DIR/missing-import"
cp -R "$clean" "$missing_import"
sed -i '/import app.nothingui.theme.NothingUiNativeSurfaces/d' \
    "$missing_import/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
expect_fail_contains 'ColorTokens without the native-surface import fails' \
    "$missing_import" 'does not import the native surface tokens'

unwrapped="$TMP_DIR/unwrapped"
cp -R "$clean" "$unwrapped"
sed -i '/val AllAppsHeaderProtectionColor =/,/^$/ { /playNativeSurface/d; }' \
    "$unwrapped/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
expect_fail_contains 'unwrapped drawer header token fails' "$unwrapped" \
    'AllAppsHeaderProtectionColor is not Play-gated'

inverse="$TMP_DIR/inverse"
cp -R "$clean" "$inverse"
awk '
    /val TextColorPrimaryInverse =/ {
        print "    @JvmField val TextColorPrimaryInverse = TextColorPrimary.inverse()"
        skip = 1
        next
    }
    skip && /^[[:space:]]*$/ { skip = 0; print; next }
    skip { next }
    { print }
' "$inverse/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt" > "$TMP_DIR/inverse.tmp"
mv "$TMP_DIR/inverse.tmp" "$inverse/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
expect_fail_contains 'inverting the wrapped primary text fails' "$inverse" \
    'must not invert the wrapped TextColorPrimary'

widget_picker="$TMP_DIR/widget-picker"
cp -R "$clean" "$widget_picker"
sed -i 's|val WidgetsPickerScrim = Scrim.setAlpha(.32f)|val WidgetsPickerScrim = Scrim.setAlpha(.32f).playNativeSurface(NothingUiNativeSurfaces.AllAppsBackground)|' \
    "$widget_picker/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
expect_fail_contains 'A3 widget-picker scrim cannot be wrapped' "$widget_picker" \
    'belongs to A3'

extra_wrap="$TMP_DIR/extra-wrap"
cp -R "$clean" "$extra_wrap"
printf '\n    @JvmField val ExtraWrap = Scrim.playNativeSurface(NothingUiNativeSurfaces.AllAppsBackground)\n' \
    >> "$extra_wrap/lawnchair/src/app/lawnchair/theme/color/tokens/ColorTokens.kt"
expect_fail_contains 'an unexpected extra wrap fails the count' "$extra_wrap" \
    'expected 17 Play-gated native tokens'

missing_branch="$TMP_DIR/missing-branch"
cp -R "$clean" "$missing_branch"
sed -i 's/if (NothingUiFeature.themeEnabled) {/if (false) {/' \
    "$missing_branch/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt"
expect_fail_contains 'missing drawer text Play branch fails' "$missing_branch" \
    'has no Play branch'

missing_text_color="$TMP_DIR/missing-text-color"
cp -R "$clean" "$missing_text_color"
sed -i 's/NothingUiNativeSurfaces.textPrimary(Utilities.isDarkTheme(context)).toArgb()/Color.BLACK/' \
    "$missing_text_color/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt"
expect_fail_contains 'drawer text without the neutral resolved-theme color fails' \
    "$missing_text_color" 'neutral resolved-theme text color'

late_branch="$TMP_DIR/late-branch"
cp -R "$clean" "$late_branch"
sed -i '/val context = textView.context/a\    val luminance = getAllAppsBaseColor(context, ColorTokens.AllAppsScrimColor.resolveColor(context)).luminance' \
    "$late_branch/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt"
expect_fail_contains 'Play branch after the inherited luminance path fails' "$late_branch" \
    'must run before the inherited luminance path'

missing_palette="$TMP_DIR/missing-palette"
cp -R "$clean" "$missing_palette"
sed -i 's/NothingUiPalette.Gray100/NothingUiPalette.Gray300/g' \
    "$missing_palette/lawnchair/src/app/nothingui/theme/NothingUiNativeSurfaces.kt"
expect_fail_contains 'native surfaces without the Gray100 swatch fail' "$missing_palette" \
    'NothingUiPalette.Gray100'

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-native-surfaces-guard tests passed\n'
