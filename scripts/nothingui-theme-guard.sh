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

[ -d "$FONT_DIR" ] || fail "missing $FONT_DIR"
[ -d "$THEME_DIR" ] || fail "missing $THEME_DIR"
[ -f "$LICENSE_FILE" ] || fail "missing $LICENSE_FILE"
[ -f "$ATTRIBUTION_FILE" ] || fail "missing $ATTRIBUTION_FILE"
[ -f "$BUILD_FILE" ] || fail "missing $BUILD_FILE"

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

grep -q 'fun NothingUiThemeSampleScreen' "$THEME_DIR/NothingUiThemeSample.kt" ||
    fail "missing renderable theme sample screen"
grep -q '@Preview' "$THEME_DIR/NothingUiThemeSample.kt" ||
    fail "missing theme sample previews"

if find "$FONT_DIR" -maxdepth 1 -type f | grep -qiE '/(ndot|nothing|nfont)'; then
    fail "a Nothing font asset is present in $FONT_DIR"
fi

printf 'nothingui-theme-guard: OK\n'
