#!/bin/sh
# Tests for scripts/verify-play-build.sh.
# Run with: sh scripts/verify-play-build-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERIFY="$SCRIPT_DIR/verify-play-build.sh"
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

write_build_file() {
    build_file=$1
    {
        printf '%s\n' 'android {'
        printf '%s\n' '    namespace "com.android.launcher3"'
        printf '%s\n' '    defaultConfig {'
        printf '%s\n' '        minSdk = 26'
        printf '%s\n' '        targetSdk = 37'
        printf '%s\n' '    }'
        printf '%s\n' '    buildTypes {'
        printf '%s\n' '        debug {'
        printf '%s\n' '            applicationIdSuffix ".debug"'
        printf '%s\n' '        }'
        printf '%s\n' '    }'
        printf '%s\n' '    productFlavors {'
        printf '%s\n' '        github {'
        printf '%s\n' "            applicationId 'app.lawnchair'"
        printf '%s\n' '        }'
        printf '%s\n' '        nightly {'
        printf '%s\n' "            applicationId 'app.lawnchair.nightly'"
        printf '%s\n' '        }'
        printf '%s\n' '        play {'
        printf '%s\n' "            applicationId \"com.launchernos.dotwellabs\""
        printf '%s\n' '        }'
        printf '%s\n' '    }'
        printf '%s\n' '}'
    } > "$build_file"
}

write_merged() {
    file=$1
    package=$2
    authority=$3
    extra=${4:-}
    mkdir -p "$(dirname "$file")"
    {
        printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
        printf '%s\n' "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"$package\">"
        printf '%s\n' '    <uses-permission android:name="android.permission.ACCESS_HIDDEN_PROFILES" />'
        if [ -n "$extra" ]; then
            printf '%s\n' "$extra"
        fi
        printf '%s\n' '    <application>'
        printf '%s\n' "        <provider android:name=\"example.Provider\" android:authorities=\"$authority\" />"
        printf '%s\n' '    </application>'
        printf '%s\n' '</manifest>'
    } > "$file"
}

new_root() {
    root=$1
    mkdir -p "$root"
    write_build_file "$root/build.gradle"
}

run_expect_pass() {
    name=$1
    root=$2
    if sh "$VERIFY" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (expected success)"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

run_expect_fail_contains() {
    name=$1
    root=$2
    needle=$3
    if sh "$VERIFY" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        fail "$name (expected failure)"
        return
    fi
    if grep -Fq "$needle" "$TMP_DIR/out" "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (failure did not mention '$needle')"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

valid_root="$TMP_DIR/valid"
new_root "$valid_root"
write_merged \
    "$valid_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'com.launchernos.dotwellabs.debug.settings'
run_expect_pass 'valid merged manifest passes' "$valid_root"

exact_authority_root="$TMP_DIR/exact-authority"
new_root "$exact_authority_root"
write_merged \
    "$exact_authority_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'com.launchernos.dotwellabs.debug'
run_expect_pass 'authority equal to applicationId passes' "$exact_authority_root"

missing_root="$TMP_DIR/missing"
new_root "$missing_root"
mkdir -p "$missing_root/build/intermediates"
run_expect_fail_contains \
    'missing merged manifest fails closed' \
    "$missing_root" \
    'no merged manifest'

ambiguous_root="$TMP_DIR/ambiguous"
new_root "$ambiguous_root"
write_merged \
    "$ambiguous_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/a/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'com.launchernos.dotwellabs.debug.settings'
write_merged \
    "$ambiguous_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/b/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'com.launchernos.dotwellabs.debug.settings'
run_expect_fail_contains \
    'ambiguous merged manifests fail closed' \
    "$ambiguous_root" \
    'ambiguous'

wrong_package_root="$TMP_DIR/wrong-package"
new_root "$wrong_package_root"
write_merged \
    "$wrong_package_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/AndroidManifest.xml" \
    'app.lawnchair.debug' \
    'app.lawnchair.debug.settings'
run_expect_fail_contains \
    'wrong merged package fails' \
    "$wrong_package_root" \
    'package'

bad_authority_root="$TMP_DIR/bad-authority"
new_root "$bad_authority_root"
write_merged \
    "$bad_authority_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'app.lawnchair.settings'
run_expect_fail_contains \
    'non-derived provider authority fails' \
    "$bad_authority_root" \
    'authority'

forbidden_root="$TMP_DIR/forbidden"
new_root "$forbidden_root"
write_merged \
    "$forbidden_root/build/intermediates/merged_manifest/lawnWithQuickstepPlayDebug/AndroidManifest.xml" \
    'com.launchernos.dotwellabs.debug' \
    'com.launchernos.dotwellabs.debug.settings' \
    '<uses-permission android:name="android.permission.READ_CONTACTS" />'
run_expect_fail_contains \
    'forbidden permission in merged manifest fails' \
    "$forbidden_root" \
    'READ_CONTACTS'

if [ "$failures" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nall verify-play-build tests passed\n'
