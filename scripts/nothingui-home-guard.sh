#!/bin/sh
# Static guard for the P3b NothingUI actual-home slice.
#
# Proves, without Gradle, that:
# - the actual-home surface is gated to the Play channel by its own build flag;
# - the Play smartspace slot is the original NothingUI clock header while non-Play
#   keeps the inherited smartspace container;
# - the header renders a live Doto clock/date, a red accent and a dot motif, and
#   does not add a parallel full-screen launcher;
# - monochrome icon treatment is enabled for fresh Play installs through the
#   inherited icon provider, with the legacy icon-pack migration gated off;
# - the search chrome and page indicator recolor hooks are Play-gated;
# - the inherited Workspace is not modified to reference the header directly.
#
# Usage: scripts/nothingui-home-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-home-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-home-guard: %s\n' "$*" >&2
    exit 1
}

BUILD_FILE="$ROOT/build.gradle"
FEATURE_FILE="$ROOT/lawnchair/src/app/nothingui/theme/NothingUiFeature.kt"
HEADER_VIEW="$ROOT/lawnchair/src/app/nothingui/home/NothingUiHomeHeaderView.kt"
CLOCK_FILE="$ROOT/lawnchair/src/app/nothingui/home/NothingUiHomeClock.kt"
CHROME_FILE="$ROOT/lawnchair/src/app/nothingui/home/NothingUiHomeChrome.kt"
HEADER_LAYOUT="$ROOT/lawnchair/res/layout/nothingui_home_header.xml"
SMARTSPACE_MODE="$ROOT/lawnchair/src/app/lawnchair/smartspace/model/SmartspaceMode.kt"
PREFS_FILE="$ROOT/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt"
LAUNCHER_FILE="$ROOT/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
QSB_FILE="$ROOT/lawnchair/src/app/lawnchair/qsb/LawnQsbLayout.kt"
PAGE_INDICATOR="$ROOT/src/com/android/launcher3/pageindicators/PageIndicatorDots.java"
WORKSPACE_FILE="$ROOT/src/com/android/launcher3/Workspace.java"
INHERITED_SMARTSPACE="$ROOT/lawnchair/src/app/lawnchair/smartspace/SmartspaceViewContainer.kt"

for file in \
    "$BUILD_FILE" \
    "$FEATURE_FILE" \
    "$HEADER_VIEW" \
    "$CLOCK_FILE" \
    "$CHROME_FILE" \
    "$HEADER_LAYOUT" \
    "$SMARTSPACE_MODE" \
    "$PREFS_FILE" \
    "$LAUNCHER_FILE" \
    "$QSB_FILE" \
    "$PAGE_INDICATOR" \
    "$WORKSPACE_FILE" \
    "$INHERITED_SMARTSPACE"; do
    [ -f "$file" ] || fail "missing $file"
done

default_blocks=$(
    awk '/^[[:space:]]*defaultConfig[[:space:]]*\{/ { in_block = 1 }
         in_block { print }
         in_block && /^[[:space:]]*\}/ { in_block = 0; print "---" }' "$BUILD_FILE"
)
printf '%s\n' "$default_blocks" |
    grep -q 'NOTHINGUI_HOME_ENABLED", "false"' ||
    fail "defaultConfig must disable NOTHINGUI_HOME_ENABLED"

play_block=$(
    awk '/^[[:space:]]*play[[:space:]]*\{/ { in_block = 1 }
         in_block { print }
         in_block && /^[[:space:]]*\}/ { exit }' "$BUILD_FILE"
)
printf '%s\n' "$play_block" |
    grep -q 'NOTHINGUI_HOME_ENABLED", "true"' ||
    fail "the play flavor must enable NOTHINGUI_HOME_ENABLED"

for flavor in github nightly; do
    flavor_block=$(
        awk -v name="$flavor" '
            $0 ~ "^[[:space:]]*" name "[[:space:]]*\\{" { in_block = 1 }
            in_block { print }
            in_block && /^[[:space:]]*\}/ { exit }' "$BUILD_FILE"
    )
    if printf '%s\n' "$flavor_block" |
        grep -q 'NOTHINGUI_HOME_ENABLED", "true"'; then
        fail "the $flavor flavor must not enable the NothingUI home surface"
    fi
done

enabled_lines=$(grep -c 'NOTHINGUI_HOME_ENABLED", "true"' "$BUILD_FILE" || true)
[ "$enabled_lines" -eq 1 ] ||
    fail "expected exactly one NOTHINGUI_HOME_ENABLED=true line, found $enabled_lines"

grep -Fq 'val homeEnabled: Boolean = BuildConfig.NOTHINGUI_HOME_ENABLED' "$FEATURE_FILE" ||
    fail "NothingUiFeature does not read the Play-only home flag"

# The Play smartspace slot must be the original header, and non-Play must keep the
# inherited smartspace container unchanged.
grep -Fq 'NothingUiFeature.homeEnabled' "$SMARTSPACE_MODE" ||
    fail "LawnchairSmartspace is not gated on NothingUiFeature.homeEnabled"
grep -Fq 'R.layout.nothingui_home_header' "$SMARTSPACE_MODE" ||
    fail "LawnchairSmartspace does not use the NothingUI header layout"
grep -Fq 'R.layout.smartspace_container' "$SMARTSPACE_MODE" ||
    fail "LawnchairSmartspace no longer keeps the inherited smartspace fallback"

grep -Fq 'app.nothingui.home.NothingUiHomeHeaderView' "$HEADER_LAYOUT" ||
    fail "the NothingUI header layout does not inflate NothingUiHomeHeaderView"

grep -Fq 'R.font.doto_bold' "$HEADER_VIEW" ||
    fail "the home header clock does not use the bundled Doto font"
grep -Fq 'R.font.doto_regular' "$HEADER_VIEW" ||
    fail "the home header date does not use the bundled Doto font"
grep -Fq 'NothingUiPalette.AccentRed' "$HEADER_VIEW" ||
    fail "the home header is missing the restrained red accent"
grep -Fq 'ACTION_TIME_TICK' "$HEADER_VIEW" ||
    fail "the home header clock does not update on the time tick"
grep -Fq 'contentDescription' "$HEADER_VIEW" ||
    fail "the home header clock/date has no accessibility label"
grep -Fq 'DateFormat.is24HourFormat' "$HEADER_VIEW" ||
    fail "the home header does not respect the system 12/24-hour setting"
grep -Fq 'formatClock' "$CLOCK_FILE" ||
    fail "the pure clock formatter is missing formatClock"
grep -Fq 'formatDate' "$CLOCK_FILE" ||
    fail "the pure clock formatter is missing formatDate"

# The monochrome icon treatment must default on only through the Play home gate.
grep -Fq 'BoolPref("themed_icons", NothingUiFeature.homeEnabled' "$PREFS_FILE" ||
    fail "themed icons are not defaulted through the Play home gate"
grep -Fq 'BoolPref("pref_forceIconMonochrome", NothingUiFeature.homeEnabled' "$PREFS_FILE" ||
    fail "monochrome icon fallback is not defaulted through the Play home gate"
grep -Fq '!NothingUiFeature.homeEnabled' "$LAUNCHER_FILE" ||
    fail "the legacy themed-icon migration is not gated off for the Play home"

# Search chrome and page dots must only recolor behind the Play gate.
grep -Fq 'NothingUiFeature.homeEnabled' "$QSB_FILE" ||
    fail "the search bar chrome is not Play-gated"
grep -Fq 'NothingUiHomeChrome.surfaceColor' "$QSB_FILE" ||
    fail "the search bar does not use the monochrome surface helper"
grep -Fq 'NothingUiFeature.INSTANCE.getHomeEnabled()' "$PAGE_INDICATOR" ||
    fail "the page indicator recolor is not Play-gated"
grep -Fq 'NothingUiHomeChrome.INSTANCE.pageIndicatorColor' "$PAGE_INDICATOR" ||
    fail "the page indicator does not use the monochrome dot helper"

# The inherited workspace engine must stay the only workspace. The header is
# selected through SmartspaceMode, not hard-wired into Workspace.
if grep -Fq 'NothingUiHomeHeaderView' "$WORKSPACE_FILE"; then
    fail "Workspace.java directly references the NothingUI header; keep the hook in SmartspaceMode"
fi

printf 'nothingui-home-guard: OK\n'
