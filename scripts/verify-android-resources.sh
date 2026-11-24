#!/bin/sh
# Focused Android resource validation that does not run a Gradle/Android build.
#
# aapt2 (not the XML parser) is what flattens string resources, and it rejects
# an apostrophe that is not backslash-escaped. Compiling the shipped values
# resource here fails CI early, before the expensive assemble step, with the
# real AAPT diagnostic.
#
# Usage: scripts/verify-android-resources.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

if [ ! -d "$ROOT" ]; then
    printf 'verify-android-resources: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
fi

fail() {
    printf 'verify-android-resources: %s\n' "$*" >&2
    exit 1
}

find_aapt2() {
    if command -v aapt2 >/dev/null 2>&1; then
        command -v aapt2
        return 0
    fi
    for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
        /usr/local/lib/android/sdk "$HOME/Android/Sdk"; do
        [ -n "$sdk" ] || continue
        [ -d "$sdk/build-tools" ] || continue
        candidate=$(
            find "$sdk/build-tools" -type f -name aapt2 2>/dev/null |
                sort | tail -n 1
        )
        if [ -n "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

AAPT2=$(find_aapt2) ||
    fail 'aapt2 was not found; install Android build-tools or set ANDROID_HOME'

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

validate() {
    relative=$1
    src="$ROOT/$relative"
    [ -f "$src" ] || fail "missing resource file: $relative"
    printf 'verify-android-resources: compiling %s\n' "$relative"
    if ! "$AAPT2" compile "$src" -o "$OUT"; then
        fail "aapt2 could not compile $relative (see the resource error above)"
    fi
}

# The Weather copy lives here; keeping the list explicit keeps the check fast
# and focused on the values that change with the launcher copy.
validate 'lawnchair/res/values/strings.xml'

printf 'verify-android-resources: OK: %s\n' 'lawnchair/res/values/strings.xml'
