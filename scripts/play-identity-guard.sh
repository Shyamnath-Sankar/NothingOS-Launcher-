#!/bin/sh
# Fail when the Play channel identity or provider authorities are unsafe.
#
# Checks that build.gradle keeps the approved Play applicationId, the inherited
# github/nightly ids, the namespace and the SDK levels, and that every manifest
# provider authority is derived from the applicationId (so a Play build cannot
# collide with a github/nightly install on the same device).
#
# Usage: scripts/play-identity-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

if [ ! -d "$ROOT" ]; then
    printf 'play-identity-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
fi

BUILD_FILE="$ROOT/build.gradle"
if [ ! -f "$BUILD_FILE" ]; then
    printf 'play-identity-guard: cannot read build file: %s\n' "$BUILD_FILE" >&2
    exit 2
fi

violations=0

violate() {
    printf 'play-identity-guard: %s\n' "$*" >&2
    violations=$((violations + 1))
}

application_id_lines() {
    flavor=$1
    awk -v flavor="$flavor" '
        $0 ~ "^[[:space:]]*" flavor "[[:space:]]*\\{" { inblock = 1; next }
        inblock && /^[[:space:]]*\}/ { inblock = 0 }
        inblock && /applicationId/ { print }
    ' "$BUILD_FILE"
}

normalize_id() {
    sed -n "s/.*applicationId[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p"
}

check_id() {
    flavor=$1
    expected=$2
    actual=$(application_id_lines "$flavor" | normalize_id)
    if [ -z "$actual" ]; then
        violate "missing $flavor applicationId (expected $expected)"
    elif [ "$actual" != "$expected" ]; then
        violate "$flavor applicationId is '$actual', expected '$expected'"
    fi
}

check_id play 'com.launchernos.dotwellabs'
check_id github 'app.lawnchair'
check_id nightly 'app.lawnchair.nightly'

if grep -Eq "applicationId[[:space:]]+['\"](app\.lawnchair\.play|dev\.shyamnath\.launcher)['\"]" "$BUILD_FILE"; then
    violate 'build file still contains a superseded Play applicationId'
fi

if ! grep -Eq "namespace[[:space:]]+['\"]com\.android\.launcher3['\"]" "$BUILD_FILE"; then
    violate 'namespace is not com.android.launcher3'
fi

if ! grep -Eq "minSdk[[:space:]]*=[[:space:]]*26([^0-9]|$)" "$BUILD_FILE"; then
    violate 'minSdk is not 26'
fi

if ! grep -Eq "targetSdk[[:space:]]*=[[:space:]]*37([^0-9]|$)" "$BUILD_FILE"; then
    violate 'targetSdk is not 37'
fi

literal_authorities=$(
    grep -rE 'android:authorities="[^"]*"' "$ROOT" \
        --include='AndroidManifest*.xml' --exclude-dir=build 2>/dev/null |
        grep -vE 'android:authorities="[^"]*(\$\{applicationId\}|\$\{packageName\})[^"]*"' || true
)
if [ -n "$literal_authorities" ]; then
    printf '%s\n' "$literal_authorities" >&2
    violate 'provider authority is not derived from applicationId/packageName'
fi

if [ "$violations" -ne 0 ]; then
    printf 'play-identity-guard: FAIL: %d identity/authority violation(s).\n' \
        "$violations" >&2
    exit 1
fi

printf 'play-identity-guard: OK: Play identity and provider authorities are safe\n'
