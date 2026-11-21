#!/bin/sh
# Fail when the Play channel branding or launcher icon is not the approved
# original DotWel artwork.
#
# Checks the Play-only resource overlay, the Play manifest icon wiring, the
# Play variant app-name override, and that upstream attribution survives.
# Nothing here proves what a device renders; it only catches static regressions.
#
# Usage: scripts/play-brand-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

if [ ! -d "$ROOT" ]; then
    printf 'play-brand-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
fi

PLAY_RES="$ROOT/play/res"
BUILD_FILE="$ROOT/build.gradle"
PLAY_MANIFEST="$ROOT/play/AndroidManifest.xml"
NOTICE_FILE="$ROOT/NOTICE.md"

violations=0

violate() {
    printf 'play-brand-guard: %s\n' "$*" >&2
    violations=$((violations + 1))
}

require_file() {
    if [ ! -f "$1" ]; then
        violate "missing required file: ${1#"$ROOT"/}"
    fi
}

extract_string() {
    name=$1
    file=$2
    sed -n "s:.*<string name=\"$name\"[^>]*>\\(.*\\)</string>.*:\\1:p" "$file" | head -n 1
}

require_file "$BUILD_FILE"
require_file "$PLAY_MANIFEST"
require_file "$NOTICE_FILE"
require_file "$PLAY_RES/values/strings.xml"
require_file "$PLAY_RES/drawable/ic_launcher_home.xml"
require_file "$PLAY_RES/drawable/ic_launcher_home_comp.xml"
require_file "$PLAY_RES/drawable/ic_launcher_home_background.xml"
require_file "$PLAY_RES/drawable/ic_launcher_home_foreground.xml"
require_file "$PLAY_RES/drawable/ic_launcher_home_monochrome.xml"
require_file "$PLAY_RES/mipmap-anydpi-v26/ic_launcher_home.xml"
require_file "$PLAY_RES/mipmap-anydpi-v26/ic_launcher_home_round.xml"

if [ "$violations" -ne 0 ]; then
    printf 'play-brand-guard: FAIL: %d missing Play brand resource(s).\n' "$violations" >&2
    exit 1
fi

play_app_name=$(extract_string play_app_name "$PLAY_RES/values/strings.xml")
if [ "$play_app_name" != 'DotWel Launcher' ]; then
    violate "Play app name is '$play_app_name', expected 'DotWel Launcher'"
fi

play_welcome=$(extract_string onboarding_welcome "$PLAY_RES/values/strings.xml")
case "$play_welcome" in
    *'DotWel Launcher'*) ;;
    *) violate "Play default onboarding welcome does not name DotWel Launcher: '$play_welcome'" ;;
esac
case "$play_welcome" in
    *Lawnchair*) violate 'Play default onboarding welcome still says Lawnchair' ;;
esac

for source_strings in "$ROOT"/lawnchair/res/values*/strings.xml; do
    [ -f "$source_strings" ] || continue
    grep -q 'name="onboarding_welcome"' "$source_strings" || continue

    qualifier=$(basename "$(dirname "$source_strings")")
    play_strings="$PLAY_RES/$qualifier/strings.xml"
    if [ ! -f "$play_strings" ]; then
        violate "missing Play onboarding override for $qualifier"
        continue
    fi

    play_welcome=$(extract_string onboarding_welcome "$play_strings")
    case "$play_welcome" in
        *'DotWel Launcher'*) ;;
        *) violate "Play onboarding override for $qualifier does not name DotWel Launcher" ;;
    esac
    case "$play_welcome" in
        *Lawnchair*) violate "Play onboarding override for $qualifier still says Lawnchair" ;;
    esac
done

if grep -rqi 'nothing' "$PLAY_RES"; then
    violate 'Play brand resources contain a Nothing mark or asset reference'
fi

if ! grep -Fq 'variant.makeResValueKey("string", "derived_app_name")' "$BUILD_FILE"; then
    violate 'build.gradle has no Play variant derived_app_name override'
fi
if ! grep -Fq 'new com.android.build.api.variant.ResValue("DotWel Launcher"' "$BUILD_FILE"; then
    violate 'build.gradle Play derived_app_name is not DotWel Launcher'
fi
if ! grep -Fq 'channel == "play"' "$BUILD_FILE"; then
    violate 'build.gradle has no Play channel gate around the app-name override'
fi

if ! grep -Fq 'android:icon="@mipmap/ic_launcher_home"' "$PLAY_MANIFEST"; then
    violate 'Play manifest application icon is not @mipmap/ic_launcher_home'
fi
if ! grep -Fq 'android:roundIcon="@mipmap/ic_launcher_home_round"' "$PLAY_MANIFEST"; then
    violate 'Play manifest application round icon is not @mipmap/ic_launcher_home_round'
fi
if ! grep -Fq 'android:label="@string/play_app_name"' "$PLAY_MANIFEST"; then
    violate 'Play manifest label does not reference play_app_name'
fi
if ! grep -Eq 'tools:replace="[^"]*android:icon([",]|$)' "$PLAY_MANIFEST"; then
    violate 'Play manifest tools:replace does not include android:icon; the base @drawable icon conflicts during manifest merge'
fi

for adaptive in \
    "$PLAY_RES/mipmap-anydpi-v26/ic_launcher_home.xml" \
    "$PLAY_RES/mipmap-anydpi-v26/ic_launcher_home_round.xml"; do
    if ! grep -Fq '<adaptive-icon' "$adaptive"; then
        violate "${adaptive#"$ROOT"/} is not an adaptive-icon"
    fi
    if ! grep -Fq '<background android:drawable="@drawable/ic_launcher_home_background"' "$adaptive"; then
        violate "${adaptive#"$ROOT"/} has no Play background layer"
    fi
    if ! grep -Fq '<foreground android:drawable="@drawable/ic_launcher_home_foreground"' "$adaptive"; then
        violate "${adaptive#"$ROOT"/} has no Play foreground layer"
    fi
    if ! grep -Fq '<monochrome android:drawable="@drawable/ic_launcher_home_monochrome"' "$adaptive"; then
        violate "${adaptive#"$ROOT"/} has no Play monochrome layer"
    fi
done

if ! grep -Fq '#0B0B0B' "$PLAY_RES/drawable/ic_launcher_home_background.xml"; then
    violate 'icon background is not the approved near-black #0B0B0B'
fi
if ! grep -Fq '#FFFFFF' "$PLAY_RES/drawable/ic_launcher_home_foreground.xml"; then
    violate 'icon foreground has no white dot matrix'
fi
if ! grep -Fq '#D7261E' "$PLAY_RES/drawable/ic_launcher_home_foreground.xml"; then
    violate 'icon foreground has no restrained red accent (#D7261E)'
fi
if ! grep -Fq '#FFFFFF' "$PLAY_RES/drawable/ic_launcher_home_monochrome.xml"; then
    violate 'monochrome icon has no white dot matrix'
fi
if grep -Fq '#D7261E' "$PLAY_RES/drawable/ic_launcher_home_monochrome.xml"; then
    violate 'monochrome icon must not carry the red accent'
fi
if ! grep -Fq '#D7261E' "$PLAY_RES/drawable/ic_launcher_home.xml"; then
    violate 'in-app Play icon has no restrained red accent (#D7261E)'
fi

if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$PLAY_RES" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
problems = []
for path in sorted(root.rglob("*.xml")):
    try:
        ET.parse(path)
    except ET.ParseError as error:
        problems.append(f"{path}: {error}")
if problems:
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
PY
    then
        violate 'Play brand XML is not well-formed'
    fi
fi

if ! grep -Fq 'Lawnchair' "$NOTICE_FILE"; then
    violate 'NOTICE.md no longer attributes the Lawnchair upstream work'
fi
if ! grep -Fq 'Apache License' "$NOTICE_FILE"; then
    violate 'NOTICE.md no longer records the Apache License'
fi
if ! grep -Fq 'DotWel Launcher' "$NOTICE_FILE"; then
    violate 'NOTICE.md no longer records the DotWel Launcher display label'
fi

if [ "$violations" -ne 0 ]; then
    printf 'play-brand-guard: FAIL: %d Play brand violation(s).\n' "$violations" >&2
    exit 1
fi

printf 'play-brand-guard: OK: Play icon and brand overlay are the approved original artwork\n'
