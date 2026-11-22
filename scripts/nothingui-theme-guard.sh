#!/bin/sh
# Static guard for the P3a NothingUI theme foundation.
#
# Proves, without Gradle, that:
# - the bundled Doto files are real TrueType fonts and match their attribution hashes;
# - the OFL license and source attribution are present;
# - the theme is gated to the Play channel by a build flag that github/nightly do not enable;
# - Doto stays on display/numeric styles while body styles use the platform sans-serif;
# - a renderable sample screen and previews exist.
#
# Usage: scripts/nothingui-theme-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-theme-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-theme-guard: %s\n' "$*" >&2
    exit 1
}

FONT_DIR="$ROOT/lawnchair/res/font"
THEME_DIR="$ROOT/lawnchair/src/app/nothingui/theme"
LICENSE_FILE="$ROOT/licenses/fonts/OFL-Doto.txt"
ATTRIBUTION_FILE="$ROOT/licenses/fonts/doto.md"
BUILD_FILE="$ROOT/build.gradle"
PREFS_FILE="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/PreferenceActivity.kt"
THEME_FILE="$ROOT/lawnchair/src/app/lawnchair/ui/theme/Theme.kt"
THEME_MANAGER="$ROOT/src/com/android/launcher3/util/WallpaperThemeManager.kt"

[ -d "$FONT_DIR" ] || fail "missing $FONT_DIR"
[ -d "$THEME_DIR" ] || fail "missing $THEME_DIR"
[ -f "$LICENSE_FILE" ] || fail "missing $LICENSE_FILE"
[ -f "$ATTRIBUTION_FILE" ] || fail "missing $ATTRIBUTION_FILE"
[ -f "$BUILD_FILE" ] || fail "missing $BUILD_FILE"
[ -f "$PREFS_FILE" ] || fail "missing $PREFS_FILE"
[ -f "$THEME_FILE" ] || fail "missing $THEME_FILE"
[ -f "$THEME_MANAGER" ] || fail "missing $THEME_MANAGER"

for font in doto_regular.ttf doto_bold.ttf; do
    path="$FONT_DIR/$font"
    [ -s "$path" ] || fail "missing or empty font: $path"

    magic=$(od -An -tx1 -N4 "$path" | tr -d ' \n')
    case "$magic" in
        00010000 | 4f54544f | 74727565 | 74746366) ;;
        *) fail "$path is not a TrueType/OpenType font (magic $magic)" ;;
    esac

    if LC_ALL=C grep -aqiE '<(!doctype|html)' "$path"; then
        fail "$path contains HTML instead of font data"
    fi
done

grep -q 'SIL OPEN FONT LICENSE Version 1.1' "$LICENSE_FILE" ||
    fail "$LICENSE_FILE does not contain the OFL 1.1 text"
grep -q 'Copyright 2024 The Doto Project Authors' "$LICENSE_FILE" ||
    fail "$LICENSE_FILE does not contain the Doto copyright"

grep -q 'github.com/google/fonts/tree/7380f7cebbf2250460c23fd301b51bcbab162edf/ofl/doto' \
    "$ATTRIBUTION_FILE" ||
    fail "$ATTRIBUTION_FILE does not pin the official Google Fonts source"
grep -q 'Doto\[ROND,wght\].ttf' "$ATTRIBUTION_FILE" ||
    fail "$ATTRIBUTION_FILE does not name the official variable source file"

for font in doto_regular.ttf doto_bold.ttf; do
    actual_hash=$(sha256sum "$FONT_DIR/$font" | awk '{print $1}')
    grep -q "$actual_hash" "$ATTRIBUTION_FILE" ||
        fail "$ATTRIBUTION_FILE does not record the $font hash ($actual_hash)"
done

default_blocks=$(
    awk '/^[[:space:]]*defaultConfig[[:space:]]*\{/ { in_block = 1 }
         in_block { print }
         in_block && /^[[:space:]]*\}/ { in_block = 0; print "---" }' "$BUILD_FILE"
)
printf '%s\n' "$default_blocks" |
    grep -q 'NOTHINGUI_THEME_ENABLED", "false"' ||
    fail "defaultConfig must disable NOTHINGUI_THEME_ENABLED"

play_block=$(
    awk '/^[[:space:]]*play[[:space:]]*\{/ { in_block = 1 }
         in_block { print }
         in_block && /^[[:space:]]*\}/ { exit }' "$BUILD_FILE"
)
printf '%s\n' "$play_block" |
    grep -q 'NOTHINGUI_THEME_ENABLED", "true"' ||
    fail "the play flavor must enable NOTHINGUI_THEME_ENABLED"

for flavor in github nightly; do
    flavor_block=$(
        awk -v name="$flavor" '
            $0 ~ "^[[:space:]]*" name "[[:space:]]*\\{" { in_block = 1 }
            in_block { print }
            in_block && /^[[:space:]]*\}/ { exit }' "$BUILD_FILE"
    )
    if printf '%s\n' "$flavor_block" |
        grep -q 'NOTHINGUI_THEME_ENABLED", "true"'; then
        fail "the $flavor flavor must not enable the NothingUI theme"
    fi
done

enabled_lines=$(grep -c 'NOTHINGUI_THEME_ENABLED", "true"' "$BUILD_FILE" || true)
[ "$enabled_lines" -eq 1 ] ||
    fail "expected exactly one NOTHINGUI_THEME_ENABLED=true line, found $enabled_lines"

grep -q 'BuildConfig.NOTHINGUI_THEME_ENABLED' "$THEME_DIR/NothingUiFeature.kt" ||
    fail "NothingUiFeature does not read the Play-only build flag"
grep -q 'fun NothingUiThemeIfEnabled' "$THEME_DIR/NothingUiFeature.kt" ||
    fail "NothingUiFeature does not expose the safe theme gate"

grep -q 'private val BodyFontFamily = FontFamily.SansSerif' \
    "$THEME_DIR/NothingUiTypography.kt" ||
    fail "body typography must use the platform sans-serif"
grep -q 'bodyLarge = base.bodyLarge.copy(fontFamily = BodyFontFamily)' \
    "$THEME_DIR/NothingUiTypography.kt" ||
    fail "bodyLarge is not wired to the platform sans-serif"
grep -q 'displayLarge = base.displayLarge.copy' \
    "$THEME_DIR/NothingUiTypography.kt" ||
    fail "displayLarge is missing from the Doto typography"
grep -q 'fontFamily = DotoFontFamily' "$THEME_DIR/NothingUiTypography.kt" ||
    fail "display typography is not wired to Doto"

# Headline styles and titleLarge are the dot-matrix headings; body and labels
# stay on the readable platform sans-serif.
for heading in headlineLarge headlineMedium headlineSmall titleLarge; do
    grep -A1 -F "$heading = base.$heading.copy(" "$THEME_DIR/NothingUiTypography.kt" |
        grep -q 'fontFamily = DotoFontFamily' ||
        fail "$heading is not wired to the Doto heading typography"
done
for heading in \
    headlineLargeEmphasized headlineMediumEmphasized headlineSmallEmphasized titleLargeEmphasized; do
    grep -A1 -F "$heading = base.$heading.copy(" "$THEME_DIR/NothingUiTypography.kt" |
        grep -q 'fontFamily = DotoFontFamily' ||
        fail "$heading is not wired to the Doto heading typography"
done
grep -q 'bodyMedium = base.bodyMedium.copy(fontFamily = BodyFontFamily)' \
    "$THEME_DIR/NothingUiTypography.kt" ||
    fail "bodyMedium is not wired to the platform sans-serif"
grep -q 'labelSmall = base.labelSmall.copy(fontFamily = BodyFontFamily)' \
    "$THEME_DIR/NothingUiTypography.kt" ||
    fail "labelSmall is not wired to the platform sans-serif"

# The real settings entry point must use the NothingUI palette only on Play,
# with the already-resolved darkTheme argument (LIGHT/DARK/SYSTEM).
grep -Fq 'import app.nothingui.theme.NothingUiFeature' "$THEME_FILE" ||
    fail "LawnchairTheme does not import the Play-only theme gate"
grep -Fq 'import app.nothingui.theme.NothingUiTheme' "$THEME_FILE" ||
    fail "LawnchairTheme does not import the NothingUI theme"
grep -Fq 'if (NothingUiFeature.themeEnabled) {' "$THEME_FILE" ||
    fail "LawnchairTheme does not gate the NothingUI palette to Play"
grep -Fq 'NothingUiTheme(darkTheme = darkTheme, content = content)' "$THEME_FILE" ||
    fail "LawnchairTheme does not pass the resolved darkTheme to NothingUiTheme"
grep -Fq 'val colorScheme = getColorScheme(darkTheme = darkTheme)' "$THEME_FILE" ||
    fail "LawnchairTheme lost the inherited non-Play color scheme"
grep -Fq 'MaterialExpressiveTheme(' "$THEME_FILE" ||
    fail "LawnchairTheme lost the inherited non-Play Material theme"

if grep -Fq 'NothingUiTheme(darkTheme = true' "$THEME_FILE"; then
    fail "LawnchairTheme hardcodes the dark theme instead of using darkTheme"
fi

gate_line=$(grep -n 'if (NothingUiFeature.themeEnabled) {' "$THEME_FILE" |
    sed -n '1s/:.*//p')
inherited_line=$(grep -n 'val colorScheme = getColorScheme(darkTheme = darkTheme)' "$THEME_FILE" |
    sed -n '1s/:.*//p')
if [ -z "$gate_line" ] || [ -z "$inherited_line" ] || [ "$gate_line" -ge "$inherited_line" ]; then
    fail "the Play theme gate must run before the inherited color scheme"
fi

grep -q 'fun NothingUiThemeSampleScreen' "$THEME_DIR/NothingUiThemeSample.kt" ||
    fail "missing renderable theme sample screen"
grep -q '@Preview' "$THEME_DIR/NothingUiThemeSample.kt" ||
    fail "missing theme sample previews"

# The device-only sample route must stay behind both the debug build and the
# Play theme gate, so release and non-Play builds keep the normal settings UI.
grep -Fq 'EXTRA_THEME_SAMPLE' "$PREFS_FILE" ||
    fail "PreferenceActivity does not expose the diagnostic theme sample extra"
grep -Fq '!BuildConfig.DEBUG' "$PREFS_FILE" ||
    fail "the theme sample route must be debug-gated"
grep -Fq '!NothingUiFeature.themeEnabled' "$PREFS_FILE" ||
    fail "the theme sample route must be Play-gated"
grep -Fq 'NothingUiThemeSampleScreen' "$PREFS_FILE" ||
    fail "the theme sample route is not wired to the sample screen"

# The diagnostic sample must drive system-bar contrast from the requested sample
# mode, not from the launcher's inherited theme preference. The normal settings
# path must keep using the inherited default.
grep -Fq 'fun ComponentActivity.EdgeToEdge(darkTheme: Boolean = isSelectedThemeDark)' "$THEME_FILE" ||
    fail "EdgeToEdge does not accept an explicit dark-theme override"
grep -Fq 'LaunchedEffect(darkTheme)' "$THEME_FILE" ||
    fail "EdgeToEdge does not react to explicit dark-theme changes"
grep -Fq 'EdgeToEdge(darkTheme = themeSampleDark)' "$PREFS_FILE" ||
    fail "the theme sample does not pass its sample mode to EdgeToEdge"
grep -Fq 'EdgeToEdge()' "$PREFS_FILE" ||
    fail "the normal settings path no longer uses the inherited EdgeToEdge"

# The native activity theme is resolved from the launcher theme choice and the current
# configuration. A resume after Settings must re-check it, and the old activity's callbacks must
# be unregistered. Updating themeRes before recreation is the loop guard: a resume that cannot
# recreate immediately cannot request the same recreation forever.
grep -Fq 'override fun onActivityResumed(' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager has no resume theme check"
grep -Fq 'if (resumedActivity === activity)' "$THEME_MANAGER" ||
    fail "the resume theme check is not scoped to the launcher activity"
grep -Fq 'if (themeRes == expectedTheme) return' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager lost the no-change theme guard"
grep -Fq 'themeRes = expectedTheme' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager does not remember the applied theme before recreation"
grep -Fq 'activity.setTheme(expectedTheme)' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager does not apply the expected activity theme"
grep -Fq 'unregisterComponentCallbacks(this)' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager does not unregister its component callbacks"
grep -Fq 'unregisterActivityLifecycleCallbacks(this)' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager does not unregister its lifecycle callbacks"
grep -Fq 'private const val TAG = "DotWelTheme"' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager lost its debug theme-state tag"
grep -Fq 'if (!BuildConfig.DEBUG) return' "$THEME_MANAGER" ||
    fail "the native theme-state evidence is not debug-only"
grep -Fq 'theme-refresh night=$night resolvedDark=$resolvedDark' "$THEME_MANAGER" ||
    fail "WallpaperThemeManager does not record the real night/resolved dark state"

# Inspect basenames only. The repository parent directory may legitimately contain
# a brand token (for example .../NothingOS-Launcher-...), which must not be read as
# a bundled Nothing font.
forbidden_font=
while IFS= read -r font; do
    [ -n "$font" ] || continue
    base=${font##*/}
    lower=$(printf '%s\n' "$base" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *ndot* | *nothing* | *nfont*) forbidden_font=$base ;;
    esac
done <<EOF
$(find "$FONT_DIR" -maxdepth 1 -type f)
EOF
[ -z "$forbidden_font" ] ||
    fail "a Nothing font asset is present in $FONT_DIR: $forbidden_font"

printf 'nothingui-theme-guard: OK\n'
