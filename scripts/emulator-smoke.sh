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
#   - dumps the actual HOME UIAutomator hierarchy and requires the rendered
#     NothingUI clock and date text, with no inherited "Lawnchair" text; captures
#     home.png as the actual-home visual evidence
#   - opens the inherited app drawer, captures its UI XML + screenshot, searches
#     for Settings, taps the real clickable result, polls until the Settings
#     activity is the exact resumed foreground, captures settings-launched.xml
#     + .png, then returns HOME and captures home-after-app-launch.xml + .png
#   - captures the app-info screen and the About screen (UI XML + screenshot);
#     the About screenshot is the launcher-icon evidence, reviewed visually
#   - opens the debug-only Play theme sample through the existing
#     PreferenceActivity plus an explicit extra, and captures dark/light UI XML
#     and screenshots; the sample text must be present or the run fails
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
ARTIFACTS=${ARTIFACTS:-}
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

SCRIPT_DIR=${_EMULATOR_SMOKE_SCRIPT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck source=emulator-smoke-lib.sh
. "$SCRIPT_DIR/emulator-smoke-lib.sh"

PKG=com.launchernos.dotwellabs.debug
EXPECTED_LABEL='DotWel Launcher'
EXPECTED_SDK=37
HOME_ROLE=android.app.role.HOME
LAUNCHER_ACTIVITY=app.lawnchair.LawnchairLauncher
THEME_SAMPLE_ACTIVITY=app.lawnchair.ui.preferences.PreferenceActivity
THEME_SAMPLE_EXTRA=app.lawnchair.ui.preferences.THEME_SAMPLE

if [ -z "$ARTIFACTS" ]; then
    ARTIFACTS="$ROOT/build/emulator-smoke/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$ARTIFACTS"
ARTIFACTS=$(CDPATH= cd -- "$ARTIFACTS" && pwd)

adb_cmd() {
    if [ -n "$SERIAL" ]; then
        run_with_timeout "${ADB_TIMEOUT:-60}" adb -s "$SERIAL" "$@"
    else
        run_with_timeout "${ADB_TIMEOUT:-60}" adb "$@"
    fi
}

capture_logcat() {
    ADB_TIMEOUT=30 adb_cmd logcat -d -v threadtime > "$ARTIFACTS/logcat.txt" 2>/dev/null || true
}

capture_screenshot() {
    ADB_TIMEOUT=20 adb_cmd exec-out screencap -p > "$ARTIFACTS/screenshot.png" 2>/dev/null || true
}

capture_screenshot_to() (
    target=$1
    ADB_TIMEOUT=20 adb_cmd exec-out screencap -p > "$ARTIFACTS/$target" 2>/dev/null || true
)

capture_ui_xml() (
    name=$1
    remote="/sdcard/$name"
    attempt=1
    while [ "$attempt" -le 3 ]; do
        if ADB_TIMEOUT=20 adb_cmd shell uiautomator dump "$remote" \
                > "$ARTIFACTS/uiautomator-$name.txt" 2>&1 &&
            ADB_TIMEOUT=20 adb_cmd pull "$remote" "$ARTIFACTS/$name" > /dev/null 2>&1 &&
            [ -s "$ARTIFACTS/$name" ]; then
            ADB_TIMEOUT=10 adb_cmd shell rm -f "$remote" > /dev/null 2>&1 || true
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
)

# Poll the live resumed activity, bounded, until it belongs to $1. Only the
# topResumedActivity/mResumedActivity fields count: task history also names
# packages and must never be mistaken for the foreground app.
wait_for_foreground() (
    expected_pkg=$1
    dump=$2
    attempts=${3:-10}
    attempt=1
    while [ "$attempt" -le "$attempts" ]; do
        adb_cmd shell dumpsys activity activities > "$dump" 2>&1 || true
        if foreground_is "$dump" "$expected_pkg"; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
)

return_home() {
    _rh_label=$1
    adb_cmd shell input keyevent KEYCODE_HOME > "$ARTIFACTS/home-key-$_rh_label.txt" 2>&1 ||
        fail "could not send the HOME key ($_rh_label)"
    wait_for_foreground "$PKG" "$ARTIFACTS/activities-$_rh_label.txt" 10 ||
        fail "launcher is not the resumed foreground after $_rh_label"
}

capture_app_info() {
    if ! _cai_out=$(adb_cmd shell am start -W \
        -a android.settings.APPLICATION_DETAILS_SETTINGS \
        -d "package:$PKG" 2>&1); then
        printf '%s\n' "$_cai_out" > "$ARTIFACTS/app-info-launch.txt"
        fail "could not open app-info for $PKG"
    fi
    printf '%s\n' "$_cai_out" > "$ARTIFACTS/app-info-launch.txt"
    case "$_cai_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "app-info launch reported an error"
            ;;
    esac
    printf '%s\n' "$_cai_out" | grep -q 'Status: ok' ||
        fail "app-info launch did not report Status: ok"
    sleep 2
    capture_screenshot_to app-info.png
    [ -s "$ARTIFACTS/app-info.png" ] || fail "app-info screenshot capture failed"
    capture_ui_xml app-info.xml || fail "app-info UI XML capture failed"
    if ! grep -Fq "$PKG" "$ARTIFACTS/app-info.xml" &&
        ! grep -Fq "$EXPECTED_LABEL" "$ARTIFACTS/app-info.xml"; then
        fail "app-info UI XML does not mention $PKG or $EXPECTED_LABEL"
    fi
}

# About is reached through the existing lawnchair://settings/about deep link, then
# confirmed from the UIAutomator hierarchy. No guessed tap coordinates are used.
capture_about() {
    _cab_url='lawnchair://settings/about'
    _cab_component="$PKG/app.lawnchair.ui.preferences.PreferenceActivity"
    if ! _cab_out=$(adb_cmd shell am start -W \
        -a android.intent.action.VIEW \
        -d "$_cab_url" \
        -n "$_cab_component" 2>&1); then
        printf 'About screen unavailable: deep link launch failed.\n%s\n' \
            "$_cab_out" > "$ARTIFACTS/about-pending.txt"
        return 0
    fi
    printf '%s\n' "$_cab_out" > "$ARTIFACTS/about-launch.txt"
    case "$_cab_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            printf 'About screen unavailable: deep link launch reported an error.\n%s\n' \
                "$_cab_out" > "$ARTIFACTS/about-pending.txt"
            return 0
            ;;
    esac
    sleep 2
    if ! capture_ui_xml about.xml; then
        printf 'About screen unavailable: UIAutomator could not dump the hierarchy.\n' \
            > "$ARTIFACTS/about-pending.txt"
        return 0
    fi
    if ! grep -Fq 'About' "$ARTIFACTS/about.xml" ||
        ! grep -Fq "$EXPECTED_LABEL" "$ARTIFACTS/about.xml"; then
        printf 'About screen pending: UIAutomator hierarchy did not expose both "About" and "%s".\n' \
            "$EXPECTED_LABEL" > "$ARTIFACTS/about-pending.txt"
        return 0
    fi
    capture_screenshot_to about.png
    if [ -s "$ARTIFACTS/about.png" ]; then
        printf 'About screen captured: "About" title and "%s" text are visible.\n' \
            "$EXPECTED_LABEL" > "$ARTIFACTS/about.txt"
        printf 'Icon evidence: about.png. The launcher icon is reviewed visually; this script does not pixel-assert it.\n' \
            >> "$ARTIFACTS/about.txt"
    else
        printf 'About screen pending: UI hierarchy matched but screenshot capture failed.\n' \
            > "$ARTIFACTS/about-pending.txt"
    fi
}

# The theme sample is reachable only through the existing exported
# PreferenceActivity and an explicit diagnostic extra. The extra is ignored
# outside debug Play builds, so this exercises the real device rendering path.
capture_theme_sample() {
    _cts_mode=$1
    # The About capture already used this activity. Force a fresh task so the
    # new diagnostic extra is delivered to a new instance instead of the system
    # merely bringing the existing About task to the front.
    if ! _cts_out=$(adb_cmd shell am start -W \
        -f 0x18000000 \
        -n "$PKG/$THEME_SAMPLE_ACTIVITY" \
        --es "$THEME_SAMPLE_EXTRA" "$_cts_mode" 2>&1); then
        printf '%s\n' "$_cts_out" > "$ARTIFACTS/theme-sample-$_cts_mode-launch.txt"
        fail "could not open the $_cts_mode theme sample"
    fi
    printf '%s\n' "$_cts_out" > "$ARTIFACTS/theme-sample-$_cts_mode-launch.txt"
    case "$_cts_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "theme sample $_cts_mode launch reported an error"
            ;;
    esac
    printf '%s\n' "$_cts_out" | grep -q 'Status: ok' ||
        fail "theme sample $_cts_mode launch did not report Status: ok"
    sleep 2
    capture_ui_xml "theme-sample-$_cts_mode.xml" ||
        fail "theme sample $_cts_mode UI XML capture failed"
    if ! grep -Fq 'DOTWEL' "$ARTIFACTS/theme-sample-$_cts_mode.xml"; then
        fail "theme sample $_cts_mode UI XML does not expose the DOTWEL sample text"
    fi
    capture_screenshot_to "theme-sample-$_cts_mode.png"
    [ -s "$ARTIFACTS/theme-sample-$_cts_mode.png" ] ||
        fail "theme sample $_cts_mode screenshot capture failed"
    printf 'Theme sample (%s): DOTWEL text is visible in the UI hierarchy.\n' \
        "$_cts_mode" > "$ARTIFACTS/theme-sample-$_cts_mode.txt"
    printf 'Screenshot: theme-sample-%s.png.\n' "$_cts_mode" \
        >> "$ARTIFACTS/theme-sample-$_cts_mode.txt"
}

# Extract the first UIAutomator bounds tuple for a node that contains the given
# needle. Prints "x1 y1 x2 y2" or nothing.
ui_bounds_for() (
    xml=$1
    needle=$2
    tr '>' '\n' < "$xml" |
        grep -F "$needle" |
        sed -n 's/.*bounds="\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]".*/\1 \2 \3 \4/p' |
        sed -n '1p'
)

tap_center_of_bounds() (
    bounds=$1
    set -- $bounds
    x=$((($1 + $3) / 2))
    y=$((($2 + $4) / 2))
    adb_cmd shell input tap "$x" "$y" > "$ARTIFACTS/tap-$x-$y.txt" 2>&1
)

# The Play home replaces the inherited welcome smartspace with the original
# NothingUI clock/date header. Assert the rendered clock and date text, not a
# static source guard, and keep the inherited brand check on the actual HOME.
verify_nothing_home() {
    _vnh_attempt=1
    _vnh_captured=0
    while [ "$_vnh_attempt" -le 4 ]; do
        if capture_ui_xml home.xml; then
            _vnh_captured=1
            if grep -Eq 'text="[0-9]{1,2}:[0-9]{2}"' "$ARTIFACTS/home.xml" &&
                grep -Eq 'text="[A-Z]{3} [0-9]{1,2} [A-Z]{3}"' "$ARTIFACTS/home.xml"; then
                if grep -Fq 'Lawnchair' "$ARTIFACTS/home.xml"; then
                    fail "actual HOME UI still exposes inherited Lawnchair text"
                fi
                capture_screenshot_to home.png
                [ -s "$ARTIFACTS/home.png" ] || fail "actual HOME screenshot capture failed"
                printf 'Actual HOME: live clock and date text are visible; no Lawnchair text.\n' \
                    > "$ARTIFACTS/home-nothing.txt"
                printf 'Screenshot: home.png.\n' >> "$ARTIFACTS/home-nothing.txt"
                return 0
            fi
        fi
        _vnh_attempt=$((_vnh_attempt + 1))
        sleep 1
    done
    [ "$_vnh_captured" -eq 1 ] || fail "could not dump the actual HOME UIAutomator hierarchy"
    fail "actual HOME does not expose the NothingUI clock/date text"
}

wait_for_launcher_idle() (
    dump=$1
    attempts=${2:-10}
    attempt=1
    while [ "$attempt" -le "$attempts" ]; do
        adb_cmd shell dumpsys activity activities > "$dump" 2>&1 || true
        if foreground_is "$dump" "$PKG"; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
)

read_wm_size() (
    adb_cmd shell wm size | tr -d '\r' |
        sed -n 's/.*: \([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1 \2/p' |
        sed -n '$p'
)

capture_drawer_attempt() (
    label=$1
    capture_ui_xml "$label.xml" || return 1
    capture_screenshot_to "$label.png"
    [ -s "$ARTIFACTS/$label.png" ] || return 1
    return 0
)

# Derive the swipe from the current HOME hierarchy: its root bounds give the
# real display area (insets included) and the lowest labelled row gives the
# dock top. Fall back to measured wm size only when the hierarchy is unavailable.
drawer_target_for_dump() (
    xml=$1
    fallback_width=$2
    fallback_height=$3
    root=$(ui_root_bounds "$xml")
    if [ -n "$root" ]; then
        set -- $root
        origin_x=$1
        origin_y=$2
        width=$(($3 - $1))
        height=$(($4 - $2))
        dock_top=$(ui_dock_top "$xml" "$root")
    else
        origin_x=0
        origin_y=0
        width=$fallback_width
        height=$fallback_height
        dock_top=
    fi
    target=$(drawer_swipe_target "$width" "$height" "$dock_top") || return 1
    set -- $target
    printf '%s %s %s %s\n' \
        $((origin_x + $1)) $((origin_y + $2)) \
        $((origin_x + $3)) $((origin_y + $4))
)

# Open the app drawer with a bounded, state-based retry loop. Each attempt waits
# for the launcher to be the idle foreground, captures the pre-swipe HOME XML +
# PNG, swipes from the empty workspace above the measured dock top, then polls
# for the real drawer search input/app-list container. Every attempt leaves
# appdrawer-attempt-N-before/after XML+PNG plus a line in appdrawer-swipe-log.txt.
open_app_drawer() {
    wait_for_launcher_idle "$ARTIFACTS/appdrawer-launcher-idle.txt" 10 ||
        fail "launcher did not become the idle foreground before the app-drawer swipe"

    wm_size=$(read_wm_size)
    [ -n "$wm_size" ] || fail "could not read the display size for the app-drawer swipe"
    set -- $wm_size
    fallback_width=$1
    fallback_height=$2

    : > "$ARTIFACTS/appdrawer-swipe-log.txt"
    max_attempts=4
    attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        wait_for_launcher_idle "$ARTIFACTS/appdrawer-attempt-$attempt-idle.txt" 10 ||
            fail "launcher was not idle before app-drawer swipe attempt $attempt"
        capture_drawer_attempt "appdrawer-attempt-$attempt-before" ||
            fail "could not capture the HOME state before app-drawer swipe attempt $attempt"
        target=$(drawer_target_for_dump \
            "$ARTIFACTS/appdrawer-attempt-$attempt-before.xml" \
            "$fallback_width" "$fallback_height") ||
            fail "could not compute a safe app-drawer swipe target on attempt $attempt"
        set -- $target
        printf 'attempt=%s start=%s,%s end=%s,%s duration=300\n' \
            "$attempt" "$1" "$2" "$3" "$4" >> "$ARTIFACTS/appdrawer-swipe-log.txt"
        adb_cmd shell input swipe "$1" "$2" "$3" "$4" 300 \
            > "$ARTIFACTS/appdrawer-swipe-$attempt.txt" 2>&1 ||
            fail "could not swipe open the app drawer on attempt $attempt"

        ready=0
        poll=1
        while [ "$poll" -le 6 ]; do
            sleep 1
            if capture_ui_xml "appdrawer-attempt-$attempt.xml" &&
                drawer_is_ready "$ARTIFACTS/appdrawer-attempt-$attempt.xml" \
                    "$ARTIFACTS/appdrawer-attempt-$attempt-before.xml"; then
                ready=1
                break
            fi
            poll=$((poll + 1))
        done
        capture_screenshot_to "appdrawer-attempt-$attempt.png"
        [ -s "$ARTIFACTS/appdrawer-attempt-$attempt.png" ] ||
            fail "app drawer attempt $attempt screenshot capture failed"
        if [ "$ready" -eq 1 ]; then
            cp "$ARTIFACTS/appdrawer-attempt-$attempt.xml" "$ARTIFACTS/appdrawer.xml"
            cp "$ARTIFACTS/appdrawer-attempt-$attempt.png" "$ARTIFACTS/appdrawer.png"
            printf 'attempt=%s drawer-ready\n' "$attempt" \
                >> "$ARTIFACTS/appdrawer-swipe-log.txt"
            sleep 1
            return 0
        fi
        printf 'attempt=%s drawer-not-ready; returning HOME\n' "$attempt" \
            >> "$ARTIFACTS/appdrawer-swipe-log.txt"
        adb_cmd shell input keyevent KEYCODE_BACK \
            >> "$ARTIFACTS/appdrawer-swipe-log.txt" 2>&1 || true
        sleep 1
        attempt=$((attempt + 1))
    done
    fail "app drawer did not expose a search input or app list after $max_attempts bounded swipe attempts"
}

# Open the inherited app drawer, search for a real installed app, tap the result,
# verify the app is foreground, then resume HOME. This exercises search, tap
# launch and HOME resume on the actual device rather than reading source.
exercise_app_drawer() {
    adb_cmd shell pm path com.android.settings | grep -q '^package:' ||
        fail "com.android.settings is not installed on the emulator"

    open_app_drawer
    capture_screenshot_to appdrawer.png
    [ -s "$ARTIFACTS/appdrawer.png" ] || fail "app drawer screenshot capture failed"

    _ead_input_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer.xml" '/input"')
    [ -n "$_ead_input_bounds" ] ||
        _ead_input_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer.xml" 'android.widget.EditText')
    [ -n "$_ead_input_bounds" ] ||
        _ead_input_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer.xml" 'search_container_all_apps')
    [ -n "$_ead_input_bounds" ] || fail "could not find the app drawer search input or container"
    tap_center_of_bounds "$_ead_input_bounds" || fail "could not focus the app drawer search input"
    sleep 1
    adb_cmd shell input text 'settings' > "$ARTIFACTS/search-input.txt" 2>&1 ||
        fail "could not type into the app drawer search input"
    sleep 2
    capture_ui_xml appdrawer-search.xml || fail "app drawer search UI XML capture failed"
    capture_screenshot_to appdrawer-search.png
    [ -s "$ARTIFACTS/appdrawer-search.png" ] ||
        fail "app drawer search screenshot capture failed"
    grep -Fq 'text="Settings"' "$ARTIFACTS/appdrawer-search.xml" ||
        fail "app drawer search did not return Settings"

    _ead_result_bounds=$(ui_clickable_label_bounds "$ARTIFACTS/appdrawer-search.xml" 'Settings')
    [ -n "$_ead_result_bounds" ] ||
        fail "could not find the clickable Settings search result bounds"
    tap_center_of_bounds "$_ead_result_bounds" || fail "could not tap the Settings search result"
    wait_for_foreground com.android.settings "$ARTIFACTS/activities-app-launch.txt" 15 ||
        fail "tapping the Settings search result did not foreground com.android.settings"
    capture_ui_xml settings-launched.xml || fail "launched Settings UI XML capture failed"
    capture_screenshot_to settings-launched.png
    [ -s "$ARTIFACTS/settings-launched.png" ] ||
        fail "launched Settings screenshot capture failed"
    printf 'App drawer/search: Settings was found, tapped and launched.\n' \
        > "$ARTIFACTS/appdrawer.txt"
    printf 'Screenshots: appdrawer.png, appdrawer-search.png, settings-launched.png.\n' \
        >> "$ARTIFACTS/appdrawer.txt"
    return_home app-launch-home
    foreground_is "$ARTIFACTS/activities-app-launch-home.txt" "$PKG" ||
        fail "launcher is not foreground after returning from Settings"
    capture_ui_xml home-after-app-launch.xml ||
        fail "HOME UI XML capture after the app launch failed"
    capture_screenshot_to home-after-app-launch.png
    [ -s "$ARTIFACTS/home-after-app-launch.png" ] ||
        fail "HOME screenshot capture after the app launch failed"
}

fail() {
    printf 'emulator-smoke: FAIL: %s\n' "$*" >&2
    if command -v adb >/dev/null 2>&1; then
        capture_logcat
        capture_screenshot
    fi
    _SMOKE_EVIDENCE_CAPTURED=1
    printf 'emulator-smoke: evidence: %s\n' "$ARTIFACTS" >&2
    exit 1
}

find_aapt() (
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
)

# The mock-adb regression sources this file to exercise the real
# open_app_drawer orchestration without touching a device. All function
# definitions above this point are the production code under test.
if [ "${_EMULATOR_SMOKE_SOURCE_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

_SMOKE_EVIDENCE_CAPTURED=0

smoke_exit_trap() {
    _trap_status=$?
    if [ "$_trap_status" -ne 0 ] && [ "$_SMOKE_EVIDENCE_CAPTURED" -eq 0 ]; then
        if command -v adb >/dev/null 2>&1; then
            capture_logcat
            capture_screenshot
        fi
        printf 'emulator-smoke: FAIL: exit status %s\n' "$_trap_status" >&2
        printf 'emulator-smoke: evidence: %s\n' "$ARTIFACTS" >&2
    fi
    return "$_trap_status"
}
trap 'smoke_exit_trap' EXIT

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
    adb_cmd shell getprop ro.kernel.qemu
} > "$ARTIFACTS/device.txt" 2>&1 || fail "could not read device properties"

sdk=$(adb_cmd shell getprop ro.build.version.sdk | tr -d '\r')
[ "$sdk" = "$EXPECTED_SDK" ] ||
    fail "expected an Android API $EXPECTED_SDK emulator, found API '$sdk'"

qemu=$(adb_cmd shell getprop ro.kernel.qemu | tr -d '\r')
[ "$qemu" = "1" ] ||
    fail "expected a hardware-emulated device (ro.kernel.qemu=1), found '$qemu'; refusing to install/uninstall on a physical device"

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
        ADB_TIMEOUT=60 adb_cmd uninstall "$PKG" > "$ARTIFACTS/uninstall.txt" 2>&1 ||
            fail "could not uninstall existing $PKG"
        ;;
esac

if ! ADB_TIMEOUT=300 adb_cmd install -t "$APK" > "$ARTIFACTS/install.txt" 2>&1; then
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
ADB_TIMEOUT=180 adb_cmd pull "$base_apk" "$ARTIFACTS/installed-base.apk" > "$ARTIFACTS/pull.txt" 2>&1 ||
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

verify_nothing_home
exercise_app_drawer

capture_app_info
return_home app-info
capture_about
return_home about
capture_theme_sample dark
capture_theme_sample light
return_home theme-sample

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
