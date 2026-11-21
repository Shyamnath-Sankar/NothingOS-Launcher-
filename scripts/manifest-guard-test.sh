#!/bin/sh
# Tests for scripts/manifest-guard.sh.
# Run with: sh scripts/manifest-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/manifest-guard.sh"
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

write_manifest() {
    manifest_file=$1
    shift
    {
        printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
        printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        printf '%s\n' "$@"
        printf '%s\n' '</manifest>'
    } > "$manifest_file"
}

expect_pass() {
    name=$1
    manifest=$2
    if sh "$GUARD" "$manifest" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (expected success)"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

expect_fail_contains() {
    name=$1
    manifest=$2
    needle=$3
    if sh "$GUARD" "$manifest" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
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

clean_manifest="$TMP_DIR/clean.xml"
write_manifest "$clean_manifest" \
    '<uses-permission android:name="android.permission.INTERNET" />' \
    '<uses-permission android:name="android.permission.ACCESS_HIDDEN_PROFILES" />'
expect_pass 'clean manifest passes' "$clean_manifest"

missing_private_space_manifest="$TMP_DIR/missing-private-space.xml"
write_manifest "$missing_private_space_manifest" \
    '<uses-permission android:name="android.permission.INTERNET" />'
expect_fail_contains \
    'missing private-space permission fails' \
    "$missing_private_space_manifest" \
    'ACCESS_HIDDEN_PROFILES'

for permission in \
    android.permission.READ_CONTACTS \
    android.permission.READ_MEDIA_IMAGES \
    android.permission.READ_MEDIA_VIDEO \
    android.permission.READ_MEDIA_AUDIO \
    android.permission.READ_MEDIA_VISUAL_USER_SELECTED \
    android.permission.READ_HISTORY_BOOKMARKS \
    android.permission.PACKAGE_USAGE_STATS \
    android.permission.INTERACT_ACROSS_USERS \
    android.permission.INTERACT_ACROSS_USERS_FULL \
    android.permission.MANAGE_USERS \
    android.permission.FORCE_STOP_PACKAGES \
    android.permission.STATUS_BAR_SERVICE \
    android.permission.SUSPEND_APPS \
    com.google.android.apps.nexuslauncher.permission.QSB \
    com.kieronquinn.app.smartspacer.permission.ACCESS_SMARTSPACER
do
    manifest="$TMP_DIR/permission.xml"
    write_manifest "$manifest" "<uses-permission android:name=\"$permission\" />"
    expect_fail_contains "forbidden permission $permission" "$manifest" "$permission"
done

for component in \
    app.lawnchair.smartspace.SmartspaceAppWidgetProvider \
    app.lawnchair.smartspace.SmartspacePreferencesShortcut \
    app.lawnchair.LawnchairAccessibilityService \
    app.lawnchair.bugreport.FileProvider \
    app.lawnchair.bugreport.BugReportReceiver \
    app.lawnchair.bugreport.UploaderService \
    app.lawnchair.feed.FeedService
do
    manifest="$TMP_DIR/component.xml"
    write_manifest "$manifest" "<application><receiver android:name=\"$component\" /></application>"
    expect_fail_contains "forbidden component $component" "$manifest" "$component"
done

# The Play overlay must remove the inherited accessibility and bug-report
# components (AGENTS.md section 7). The merged-manifest guard can only run
# after Gradle merges the overlay, so assert the overlay itself declares the
# removals.
overlay="$SCRIPT_DIR/../play/AndroidManifest.xml"

expect_overlay_remove() {
    name=$1
    tag=$2
    component=$3
    if [ ! -f "$overlay" ]; then
        fail "$name (overlay missing: $overlay)"
        return
    fi
    if awk -v tag="<$tag" -v component="$component" '
        BEGIN { RS = tag }
        index($0, "android:name=\"" component "\"") && index($0, "tools:node=\"remove\"") { found = 1 }
        END { exit found ? 0 : 1 }
    ' "$overlay"; then
        pass "$name"
    else
        fail "$name (overlay does not remove $component)"
    fi
}

expect_overlay_remove \
    'play overlay removes accessibility service' \
    'service' \
    'app.lawnchair.LawnchairAccessibilityService'
expect_overlay_remove \
    'play overlay removes bug-report provider' \
    'provider' \
    'app.lawnchair.bugreport.FileProvider'
expect_overlay_remove \
    'play overlay removes bug-report receiver' \
    'receiver' \
    'app.lawnchair.bugreport.BugReportReceiver'
expect_overlay_remove \
    'play overlay removes bug-report foreground-sync service' \
    'service' \
    'app.lawnchair.bugreport.UploaderService'

# The overlay must also declare the private-space permission.
if grep -Fq 'android.permission.ACCESS_HIDDEN_PROFILES' "$overlay"; then
    pass 'play overlay declares private-space permission'
else
    fail 'play overlay declares private-space permission (missing ACCESS_HIDDEN_PROFILES)'
fi

if sh "$GUARD" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail 'missing argument exits non-zero'
else
    pass 'missing argument exits non-zero'
fi

if sh "$GUARD" "$TMP_DIR/does-not-exist.xml" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail 'missing manifest file exits non-zero'
else
    pass 'missing manifest file exits non-zero'
fi

if [ "$failures" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nall manifest-guard tests passed\n'
