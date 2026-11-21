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
    printf '%s\n' \
        '<?xml version="1.0" encoding="utf-8"?>' \
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' \
        "$1" \
        '</manifest>' > "$2"
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
write_manifest \
    '<uses-permission android:name="android.permission.INTERNET" />' \
    "$clean_manifest"
expect_pass 'clean manifest passes' "$clean_manifest"

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
    write_manifest "<uses-permission android:name=\"$permission\" />" "$manifest"
    expect_fail_contains "forbidden permission $permission" "$manifest" "$permission"
done

for component in \
    app.lawnchair.smartspace.SmartspaceAppWidgetProvider \
    app.lawnchair.smartspace.SmartspacePreferencesShortcut
do
    manifest="$TMP_DIR/component.xml"
    write_manifest "<application><receiver android:name=\"$component\" /></application>" "$manifest"
    expect_fail_contains "forbidden component $component" "$manifest" "$component"
done

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
