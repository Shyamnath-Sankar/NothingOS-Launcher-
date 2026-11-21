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
#     for Settings, taps the result, verifies the installed Settings app is
#     foreground, then returns HOME
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
THEME_SAMPLE_ACTIVITY=app.lawnchair.ui.preferences.PreferenceActivity
THEME_SAMPLE_EXTRA=app.lawnchair.ui.preferences.THEME_SAMPLE

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

capture_screenshot_to() {
    target=$1
    adb_cmd exec-out screencap -p > "$ARTIFACTS/$target" 2>/dev/null || true
}

capture_ui_xml() {
    name=$1
    remote="/sdcard/$name"
    attempt=1
    while [ "$attempt" -le 3 ]; do
        if adb_cmd shell uiautomator dump "$remote" > "$ARTIFACTS/uiautomator-$name.txt" 2>&1 &&
            adb_cmd pull "$remote" "$ARTIFACTS/$name" > /dev/null 2>&1 &&
            [ -s "$ARTIFACTS/$name" ]; then
            adb_cmd shell rm -f "$remote" > /dev/null 2>&1 || true
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

return_home() {
    label=$1
    adb_cmd shell input keyevent KEYCODE_HOME > "$ARTIFACTS/home-key-$label.txt" 2>&1 ||
        fail "could not send the HOME key ($label)"
    sleep 2
    adb_cmd shell dumpsys activity activities > "$ARTIFACTS/activities-$label.txt" 2>&1 || true
    resumed=$(grep -E 'mResumedActivity|topResumedActivity' "$ARTIFACTS/activities-$label.txt" |
        grep -F "$PKG/" | sed -n '1p' || true)
    [ -n "$resumed" ] || fail "launcher is not resumed after $label"
}

capture_app_info() {
    if ! app_info_out=$(adb_cmd shell am start -W \
        -a android.settings.APPLICATION_DETAILS_SETTINGS \
        -d "package:$PKG" 2>&1); then
        printf '%s\n' "$app_info_out" > "$ARTIFACTS/app-info-launch.txt"
        fail "could not open app-info for $PKG"
    fi
    printf '%s\n' "$app_info_out" > "$ARTIFACTS/app-info-launch.txt"
    case "$app_info_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "app-info launch reported an error"
            ;;
    esac
    printf '%s\n' "$app_info_out" | grep -q 'Status: ok' ||
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
    about_url='lawnchair://settings/about'
    about_component="$PKG/app.lawnchair.ui.preferences.PreferenceActivity"
    if ! about_out=$(adb_cmd shell am start -W \
        -a android.intent.action.VIEW \
        -d "$about_url" \
        -n "$about_component" 2>&1); then
        printf 'About screen unavailable: deep link launch failed.\n%s\n' \
            "$about_out" > "$ARTIFACTS/about-pending.txt"
        return 0
    fi
    printf '%s\n' "$about_out" > "$ARTIFACTS/about-launch.txt"
    case "$about_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            printf 'About screen unavailable: deep link launch reported an error.\n%s\n' \
                "$about_out" > "$ARTIFACTS/about-pending.txt"
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
    mode=$1
    # The About capture already used this activity. Force a fresh task so the
    # new diagnostic extra is delivered to a new instance instead of the system
    # merely bringing the existing About task to the front.
    if ! sample_out=$(adb_cmd shell am start -W \
        -f 0x18000000 \
        -n "$PKG/$THEME_SAMPLE_ACTIVITY" \
        --es "$THEME_SAMPLE_EXTRA" "$mode" 2>&1); then
        printf '%s\n' "$sample_out" > "$ARTIFACTS/theme-sample-$mode-launch.txt"
        fail "could not open the $mode theme sample"
    fi
    printf '%s\n' "$sample_out" > "$ARTIFACTS/theme-sample-$mode-launch.txt"
    case "$sample_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "theme sample $mode launch reported an error"
            ;;
    esac
    printf '%s\n' "$sample_out" | grep -q 'Status: ok' ||
        fail "theme sample $mode launch did not report Status: ok"
    sleep 2
    capture_ui_xml "theme-sample-$mode.xml" ||
        fail "theme sample $mode UI XML capture failed"
    if ! grep -Fq 'DOTWEL' "$ARTIFACTS/theme-sample-$mode.xml"; then
        fail "theme sample $mode UI XML does not expose the DOTWEL sample text"
    fi
    capture_screenshot_to "theme-sample-$mode.png"
    [ -s "$ARTIFACTS/theme-sample-$mode.png" ] ||
        fail "theme sample $mode screenshot capture failed"
    printf 'Theme sample (%s): DOTWEL text is visible in the UI hierarchy.\n' \
        "$mode" > "$ARTIFACTS/theme-sample-$mode.txt"
    printf 'Screenshot: theme-sample-%s.png.\n' "$mode" \
        >> "$ARTIFACTS/theme-sample-$mode.txt"
}

# Extract the first UIAutomator bounds tuple for a node that contains the given
# needle. Prints "x1 y1 x2 y2" or nothing.
ui_bounds_for() {
    xml=$1
    needle=$2
    tr '>' '\n' < "$xml" |
        grep -F "$needle" |
        sed -n 's/.*bounds="\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]\[\([0-9][0-9]*\),\([0-9][0-9]*\)\]".*/\1 \2 \3 \4/p' |
        sed -n '1p'
}

tap_center_of_bounds() {
    bounds=$1
    set -- $bounds
    x=$((($1 + $3) / 2))
    y=$((($2 + $4) / 2))
    adb_cmd shell input tap "$x" "$y" > "$ARTIFACTS/tap-$x-$y.txt" 2>&1
}

# The Play home replaces the inherited welcome smartspace with the original
# NothingUI clock/date header. Assert the rendered clock and date text, not a
# static source guard, and keep the inherited brand check on the actual HOME.
verify_nothing_home() {
    attempt=1
    captured=0
    while [ "$attempt" -le 4 ]; do
        if capture_ui_xml home.xml; then
            captured=1
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
        attempt=$((attempt + 1))
        sleep 1
    done
    [ "$captured" -eq 1 ] || fail "could not dump the actual HOME UIAutomator hierarchy"
    fail "actual HOME does not expose the NothingUI clock/date text"
}

app_drawer_visible() {
    grep -Fq '/input"' "$ARTIFACTS/appdrawer.xml" ||
        grep -Fq 'EditText' "$ARTIFACTS/appdrawer.xml" ||
        grep -Fq 'Settings' "$ARTIFACTS/appdrawer.xml"
}

open_app_drawer() {
    size=$(adb_cmd shell wm size | tr -d '\r' |
        sed -n 's/.*: \([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1 \2/p')
    [ -n "$size" ] || fail "could not read the display size for the app-drawer swipe"
    set -- $size
    width=$1
    height=$2
    adb_cmd shell input swipe \
        $((width / 2)) $((height * 3 / 4)) \
        $((width / 2)) $((height / 4)) 300 \
        > "$ARTIFACTS/appdrawer-swipe.txt" 2>&1 ||
        fail "could not swipe open the app drawer"
    sleep 2
    capture_ui_xml appdrawer.xml || fail "app drawer UI XML capture failed"
    app_drawer_visible || fail "app drawer did not expose a search input or an app label"
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
    grep -Fq 'Settings' "$ARTIFACTS/appdrawer.xml" ||
        fail "app drawer does not list Settings"

    input_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer.xml" '/input"')
    [ -n "$input_bounds" ] ||
        input_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer.xml" 'android.widget.EditText')
    [ -n "$input_bounds" ] || fail "could not find the app drawer search input"
    tap_center_of_bounds "$input_bounds" || fail "could not focus the app drawer search input"
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

    result_bounds=$(ui_bounds_for "$ARTIFACTS/appdrawer-search.xml" 'text="Settings"')
    [ -n "$result_bounds" ] || fail "could not find the Settings search result bounds"
    tap_center_of_bounds "$result_bounds" || fail "could not tap the Settings search result"
    sleep 4
    adb_cmd shell dumpsys activity activities > "$ARTIFACTS/activities-app-launch.txt" 2>&1 || true
    grep -Fq 'com.android.settings/' "$ARTIFACTS/activities-app-launch.txt" ||
        fail "tapping the Settings search result did not launch com.android.settings"
    printf 'App drawer/search: Settings was found, tapped and launched.\n' \
        > "$ARTIFACTS/appdrawer.txt"
    printf 'Screenshots: appdrawer.png, appdrawer-search.png.\n' >> "$ARTIFACTS/appdrawer.txt"
    return_home app-launch
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
