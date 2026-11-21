#!/bin/sh
# Smoke-test the Play debug build on a clean Android API 37 emulator.
#
# This script is deliberately evidence-heavy and fails closed:
#   - locates exactly one lawnWithQuickstepPlayDebug APK (or takes --apk)
#   - verifies the attached device is an API 37 emulator
#   - clean-installs the APK, then verifies the installed package and the
#     installed app/launcher-activity label ("DotWel Launcher")
#   - resolves and launches the HOME activity
#   - grants the HOME role with `cmd role` (a disposable-emulator stand-in for
#     the user-initiated RoleManager flow), then presses HOME and verifies the
#     launcher is the resumed/default home
#   - captures a screenshot, logcat, dumpsys and aapt evidence under an
#     artifact directory, and fails on install/launch/crash problems
#
# It does NOT validate locked private-space behaviour. That needs a provisioned
# private space with a secure lock screen; see scripts/private-space-check.sh.
#
# Usage: scripts/emulator-smoke.sh [--apk PATH] [--artifacts DIR] [--serial SERIAL]
set -eu

usage() {
    printf 'usage: %s [--apk PATH] [--artifacts DIR] [--serial SERIAL]\n' "$0" >&2
    exit 2
}

APK=
ARTIFACTS=
SERIAL=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apk)
            [ "$#" -ge 2 ] || usage
            APK=$2
            shift 2
            ;;
        --artifacts)
            [ "$#" -ge 2 ] || usage
            ARTIFACTS=$2
            shift 2
            ;;
        --serial)
            [ "$#" -ge 2 ] || usage
            SERIAL=$2
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

PKG=com.launchernos.dotwellabs.debug
EXPECTED_LABEL='DotWel Launcher'
EXPECTED_SDK=37
HOME_ROLE=android.app.role.HOME
LAUNCHER_ACTIVITY=app.lawnchair.LawnchairLauncher

if [ -z "$ARTIFACTS" ]; then
    ARTIFACTS="$ROOT/build/emulator-smoke/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$ARTIFACTS"
ARTIFACTS=$(CDPATH= cd -- "$ARTIFACTS" && pwd)

adb_cmd() {
    if [ -n "$SERIAL" ]; then
        adb -s "$SERIAL" "$@"
    else
        adb "$@"
    fi
}

capture_logcat() {
    adb_cmd logcat -d -v threadtime > "$ARTIFACTS/logcat.txt" 2>/dev/null || true
}

capture_screenshot() {
    adb_cmd exec-out screencap -p > "$ARTIFACTS/screenshot.png" 2>/dev/null || true
}

fail() {
    printf 'emulator-smoke: FAIL: %s\n' "$*" >&2
    if command -v adb >/dev/null 2>&1; then
        capture_logcat
        capture_screenshot
    fi
    printf 'emulator-smoke: evidence: %s\n' "$ARTIFACTS" >&2
    exit 1
}

find_aapt() {
    for tool in aapt2 aapt; do
        if command -v "$tool" >/dev/null 2>&1; then
            command -v "$tool"
            return 0
        fi
    done
    for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "/usr/local/lib/android/sdk"; do
        [ -n "$sdk" ] || continue
        [ -d "$sdk/build-tools" ] || continue
        for tool in aapt2 aapt; do
            found=$(find "$sdk/build-tools" -type f -name "$tool" 2>/dev/null | sort | tail -n 1)
            if [ -n "$found" ]; then
                printf '%s\n' "$found"
                return 0
            fi
        done
    done
    return 1
}

command -v adb >/dev/null 2>&1 || fail "adb is not on PATH"

if [ -z "$SERIAL" ]; then
    devices=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    device_count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$device_count" -ne 1 ]; then
        fail "expected exactly one adb device, found $device_count; pass --serial"
    fi
    SERIAL=$(printf '%s\n' "$devices" | sed -n '1p')
fi

adb_cmd get-state >/dev/null 2>&1 || fail "adb device $SERIAL is not available"

{
    printf 'serial=%s\n' "$SERIAL"
    adb devices -l
    adb_cmd shell getprop ro.build.version.sdk
    adb_cmd shell getprop ro.build.version.release
    adb_cmd shell getprop ro.build.type
    adb_cmd shell getprop ro.product.cpu.abi
} > "$ARTIFACTS/device.txt" 2>&1 || fail "could not read device properties"

sdk=$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')
[ "$sdk" = "$EXPECTED_SDK" ] ||
    fail "expected an Android API $EXPECTED_SDK emulator, found API '$sdk'"

if [ -z "$APK" ]; then
    matches=$(
        find "$ROOT/build/outputs/apk" -type f -name '*.apk' 2>/dev/null |
            grep -F '/lawnWithQuickstepPlayDebug/' |
            sort -u || true
    )
    match_count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$match_count" -ne 1 ]; then
        fail "expected exactly one Play debug APK under build/outputs/apk, found $match_count; pass --apk"
    fi
    APK=$(printf '%s\n' "$matches" | sed -n '1p')
fi

[ -f "$APK" ] || fail "APK does not exist: $APK"
case "$APK" in
    *lawnWithQuickstepPlayDebug* | *debug.apk | *debug/*) ;;
    *) fail "refusing to install a non-debug APK path: $APK" ;;
esac
printf 'apk=%s\n' "$APK" > "$ARTIFACTS/apk.txt"

# Clean install: only this package is touched.
installed_paths=$(adb_cmd shell pm path "$PKG" 2>/dev/null | tr -d '\r' || true)
case "$installed_paths" in
    package:*)
        adb_cmd uninstall "$PKG" > "$ARTIFACTS/uninstall.txt" 2>&1 ||
            fail "could not uninstall existing $PKG"
        ;;
esac

if ! adb_cmd install -t "$APK" > "$ARTIFACTS/install.txt" 2>&1; then
    cat "$ARTIFACTS/install.txt" >&2
    fail "adb install failed"
fi
grep -q 'Success' "$ARTIFACTS/install.txt" || {
    cat "$ARTIFACTS/install.txt" >&2
    fail "adb install did not report Success"
}

pm_paths=$(adb_cmd shell pm path "$PKG" 2>/dev/null | tr -d '\r' || true)
printf '%s\n' "$pm_paths" > "$ARTIFACTS/pm-path.txt"
case "$pm_paths" in
    package:*) ;;
    *) fail "installed package is not visible to pm: $PKG" ;;
esac

base_apk=$(printf '%s\n' "$pm_paths" | sed -n 's/^package://p' | sed -n '1p')
[ -n "$base_apk" ] || fail "could not find the installed base APK path"
adb_cmd pull "$base_apk" "$ARTIFACTS/installed-base.apk" > "$ARTIFACTS/pull.txt" 2>&1 ||
    fail "could not pull the installed APK"

AAPT=$(find_aapt) || fail "aapt2/aapt not found; install Android SDK build-tools"
badging=$("$AAPT" dump badging "$ARTIFACTS/installed-base.apk" 2> "$ARTIFACTS/aapt-error.txt" || true)
printf '%s\n' "$badging" > "$ARTIFACTS/apk-badging.txt"
[ -n "$badging" ] || fail "aapt could not read the installed APK"

actual_pkg=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | sed -n '1p')
[ "$actual_pkg" = "$PKG" ] ||
    fail "installed APK package is '$actual_pkg', expected '$PKG'"

actual_label=$(printf '%s\n' "$badging" | sed -n "s/^application-label:'\(.*\)'$/\1/p" | sed -n '1p')
[ "$actual_label" = "$EXPECTED_LABEL" ] ||
    fail "installed app label is '$actual_label', expected '$EXPECTED_LABEL'"

launchable_line=$(printf '%s\n' "$badging" | sed -n '/^launchable-activity:/{p;q;}')
launchable_component=$(printf '%s\n' "$launchable_line" | sed -n "s/.*name='\([^']*\)'.*/\1/p")
launchable_label=$(printf '%s\n' "$launchable_line" | sed -n "s/.*label='\([^']*\)'.*/\1/p")
case "$launchable_component" in
    *"$LAUNCHER_ACTIVITY"*) ;;
    *) fail "installed APK launchable activity is '$launchable_component', expected $LAUNCHER_ACTIVITY" ;;
esac
if [ -n "$launchable_label" ] && [ "$launchable_label" != "$EXPECTED_LABEL" ]; then
    fail "launcher activity label is '$launchable_label', expected '$EXPECTED_LABEL'"
fi

resolve=$(adb_cmd shell cmd package resolve-activity --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME -p "$PKG" | tr -d '\r')
printf '%s\n' "$resolve" > "$ARTIFACTS/resolve-activity.txt"
resolved_component=$(printf '%s\n' "$resolve" | grep -F "$PKG/" | sed -n '1p' || true)
[ -n "$resolved_component" ] || fail "could not resolve a HOME activity for $PKG"
case "$resolved_component" in
    *"$LAUNCHER_ACTIVITY"*) ;;
    *) fail "resolved HOME activity is '$resolved_component', expected $LAUNCHER_ACTIVITY" ;;
esac

adb_cmd logcat -c >/dev/null 2>&1 || fail "could not clear logcat before launch"

if ! launch_out=$(adb_cmd shell am start -W \
    -a android.intent.action.MAIN -c android.intent.category.HOME \
    -n "$resolved_component" 2>&1); then
    printf '%s\n' "$launch_out" > "$ARTIFACTS/launch.txt"
    fail "am start failed for $resolved_component"
fi
printf '%s\n' "$launch_out" > "$ARTIFACTS/launch.txt"
case "$launch_out" in
    *"Error:"* | *"Error type"* | *Exception*)
        fail "am start reported an error"
        ;;
esac
printf '%s\n' "$launch_out" | grep -q 'Status: ok' ||
    fail "am start did not report Status: ok"

sleep 2
adb_cmd shell dumpsys activity activities > "$ARTIFACTS/activities.txt" 2>&1 || true
resumed=$(grep -E 'mResumedActivity|topResumedActivity' "$ARTIFACTS/activities.txt" |
    grep -F "$PKG/" | sed -n '1p' || true)
[ -n "$resumed" ] || fail "launcher is not the resumed activity after launch"

adb_cmd shell cmd role get-role-holders --user 0 "$HOME_ROLE" \
    > "$ARTIFACTS/role-before.txt" 2>&1 || true
if ! adb_cmd shell cmd role add-role-holder --user 0 "$HOME_ROLE" "$PKG" \
    > "$ARTIFACTS/role-add.txt" 2>&1; then
    cat "$ARTIFACTS/role-add.txt" >&2
    fail "could not grant $HOME_ROLE to $PKG"
fi
adb_cmd shell cmd role get-role-holders --user 0 "$HOME_ROLE" \
    > "$ARTIFACTS/role-after.txt" 2>&1 || fail "could not read $HOME_ROLE holders"
grep -Fq "$PKG" "$ARTIFACTS/role-after.txt" ||
    fail "$HOME_ROLE does not list $PKG after the grant"
adb_cmd shell dumpsys role > "$ARTIFACTS/dumpsys-role.txt" 2>&1 || true

default_home=$(adb_cmd shell cmd package resolve-activity --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r')
printf '%s\n' "$default_home" > "$ARTIFACTS/default-home.txt"
printf '%s\n' "$default_home" | grep -Fq "$PKG/" ||
    fail "default HOME does not resolve to $PKG"

adb_cmd shell input keyevent KEYCODE_HOME > "$ARTIFACTS/home-key.txt" 2>&1 ||
    fail "could not send the HOME key"
sleep 2
adb_cmd shell dumpsys activity activities > "$ARTIFACTS/activities-after-home.txt" 2>&1 || true
home_resumed=$(grep -E 'mResumedActivity|topResumedActivity' "$ARTIFACTS/activities-after-home.txt" |
    grep -F "$PKG/" | sed -n '1p' || true)
[ -n "$home_resumed" ] || fail "launcher is not resumed after pressing HOME"

capture_screenshot
[ -s "$ARTIFACTS/screenshot.png" ] || fail "screenshot capture failed"
capture_logcat
[ -s "$ARTIFACTS/logcat.txt" ] || fail "logcat capture failed"

if grep -Fq "Process: $PKG" "$ARTIFACTS/logcat.txt"; then
    fail "logcat contains a crash/ANR stack for $PKG"
fi
if grep -Eq "ANR in $PKG|Force finishing activity.*$PKG" "$ARTIFACTS/logcat.txt"; then
    fail "logcat reports an ANR or forced finish for $PKG"
fi

pid=$(adb_cmd shell pidof "$PKG" | tr -d '\r')
[ -n "$pid" ] || fail "process for $PKG is not running after the HOME launch"
printf 'pid=%s\n' "$pid" > "$ARTIFACTS/pid.txt"

printf 'emulator-smoke: OK\n'
printf '  package: %s\n' "$actual_pkg"
printf '  app label: %s\n' "$actual_label"
printf '  activity: %s\n' "$resolved_component"
printf '  HOME role: granted and verified\n'
printf '  artifacts: %s\n' "$ARTIFACTS"
printf 'emulator-smoke: private-space validation NOT run; use scripts/private-space-check.sh with a provisioned, locked private space.\n'
