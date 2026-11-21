#!/bin/sh
# Tests for scripts/play-identity-guard.sh.
# Run with: sh scripts/play-identity-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/play-identity-guard.sh"
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
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
    play_id=${2:-com.launchernos.dotwellabs}
    github_id=${3:-app.lawnchair}
    nightly_id=${4:-app.lawnchair.nightly}
    {
        printf '%s\n' 'android {'
        printf '%s\n' '    namespace "com.android.launcher3"'
        printf '%s\n' '    defaultConfig {'
        printf '%s\n' '        minSdk = 26'
        printf '%s\n' '        targetSdk = 37'
        printf '%s\n' '    }'
        printf '%s\n' '    productFlavors {'
        printf '%s\n' '        github {'
        printf '%s\n' "            applicationId '$github_id'"
        printf '%s\n' '        }'
        printf '%s\n' '        nightly {'
        printf '%s\n' "            applicationId '$nightly_id'"
        printf '%s\n' '        }'
        printf '%s\n' '        play {'
        printf '%s\n' "            applicationId \"$play_id\""
        printf '%s\n' '        }'
        printf '%s\n' '    }'
        printf '%s\n' '}'
    } > "$build_file"
}

write_manifest() {
    manifest_file=$1
    authority=$2
    {
        printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
        printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        printf '%s\n' '    <application>'
        printf '%s\n' "        <provider android:name=\"example.Provider\" android:authorities=\"$authority\" />"
        printf '%s\n' '    </application>'
        printf '%s\n' '</manifest>'
    } > "$manifest_file"
}

expect_pass() {
    name=$1
    root=$2
    if sh "$GUARD" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
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
    if sh "$GUARD" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
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

clean_root="$TMP_DIR/clean"
mkdir -p "$clean_root"
write_build_file "$clean_root/build.gradle"
write_manifest "$clean_root/AndroidManifest-common.xml" '${applicationId}.settings'
expect_pass 'clean fixture passes' "$clean_root"

wrong_play_root="$TMP_DIR/wrong-play"
mkdir -p "$wrong_play_root"
write_build_file "$wrong_play_root/build.gradle" 'app.lawnchair.play'
write_manifest "$wrong_play_root/AndroidManifest-common.xml" '${applicationId}.settings'
expect_fail_contains \
    'old Play applicationId fails' \
    "$wrong_play_root" \
    'com.launchernos.dotwellabs'

changed_github_root="$TMP_DIR/changed-github"
mkdir -p "$changed_github_root"
write_build_file "$changed_github_root/build.gradle" \
    'com.launchernos.dotwellabs' 'app.lawnchair.rebranded'
write_manifest "$changed_github_root/AndroidManifest-common.xml" '${applicationId}.settings'
expect_fail_contains \
    'changed github applicationId fails' \
    "$changed_github_root" \
    'github'

changed_nightly_root="$TMP_DIR/changed-nightly"
mkdir -p "$changed_nightly_root"
write_build_file "$changed_nightly_root/build.gradle" \
    'com.launchernos.dotwellabs' 'app.lawnchair' 'app.lawnchair.beta'
write_manifest "$changed_nightly_root/AndroidManifest-common.xml" '${applicationId}.settings'
expect_fail_contains \
    'changed nightly applicationId fails' \
    "$changed_nightly_root" \
    'nightly'

literal_authority_root="$TMP_DIR/literal-authority"
mkdir -p "$literal_authority_root"
write_build_file "$literal_authority_root/build.gradle"
write_manifest "$literal_authority_root/AndroidManifest-common.xml" 'app.lawnchair.settings'
expect_fail_contains \
    'literal provider authority fails' \
    "$literal_authority_root" \
    'app.lawnchair.settings'

package_name_authority_root="$TMP_DIR/package-name-authority"
mkdir -p "$package_name_authority_root"
write_build_file "$package_name_authority_root/build.gradle"
write_manifest "$package_name_authority_root/AndroidManifest-common.xml" '${packageName}.commands'
expect_pass \
    'packageName placeholder authority passes' \
    "$package_name_authority_root"

missing_sdk_root="$TMP_DIR/missing-sdk"
mkdir -p "$missing_sdk_root"
{
    printf '%s\n' 'android {'
    printf '%s\n' '    namespace "com.android.launcher3"'
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
} > "$missing_sdk_root/build.gradle"
write_manifest "$missing_sdk_root/AndroidManifest-common.xml" '${applicationId}.settings'
expect_fail_contains \
    'missing SDK values fail' \
    "$missing_sdk_root" \
    'targetSdk'

# The real repository must satisfy the guard.
expect_pass 'repository identity and authorities pass' "$REPO_ROOT"

if [ "$failures" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nall play-identity-guard tests passed\n'
