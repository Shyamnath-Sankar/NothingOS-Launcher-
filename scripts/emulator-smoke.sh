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
#     NothingUI date strip and live clock widget text, with no inherited
#     "Lawnchair" text; proves all three original widget providers are bound and
#     captures home.png as the actual-home visual evidence
#   - captures the clean HOME in system dark/light (UI XML + screenshot) before
#     any third-party widget is added, then restores the previous night mode
#   - opens the real Play customization dashboard (no diagnostic extra), measures
#     the unique Customize launcher / Icon size and home screen entries, opens
#     the real Browse widgets picker on explicit taps only, and steps the actual
#     top icon-size SeekBar by one focused keyboard step and back, capturing
#     HOME before/after PNGs and an unchanged widget-binding baseline
#   - opens the real Home screen grid preferences through the existing
#     lawnchair://settings/home-screen-grid deep link, captures grid-settings.xml
#     + .png, and requires the preview, Columns/Rows/Dock icons controls and a
#     still-disabled Apply; it never applies a grid change
#   - long-presses the measured empty central HOME workspace, captures the real
#     options popup, taps Widgets by its bounds, and requires the native widget
#     picker search/list (not HOME) before returning HOME
#   - opens the inherited app drawer, captures its UI XML + screenshot, searches
#     for Settings, taps the real clickable result, polls until the Settings
#     activity is the exact resumed foreground, captures settings-launched.xml
#     + .png, then returns HOME and captures home-after-app-launch.xml + .png
#   - captures the app-info screen and the About screen (UI XML + screenshot);
#     the About screenshot is the launcher-icon evidence, reviewed visually
#   - captures the real Play settings dashboard in system dark/light while the
#     launcher theme choice is SYSTEM, without the diagnostic sample extra, and
#     restores the previous system night mode before returning HOME
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
PREFERENCES_ACTIVITY=app.lawnchair.ui.preferences.PreferenceActivity
THEME_SAMPLE_ACTIVITY=$PREFERENCES_ACTIVITY
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

# Bounded debug-only gesture trace. Captured after every swipe attempt even when
# the drawer never becomes ready, so a no-op swipe still leaves evidence.
capture_drawer_trace() (
    attempt=$1
    ADB_TIMEOUT=30 adb_cmd logcat -d -s DotwelDrawerTrace \
        > "$ARTIFACTS/appdrawer-trace-$attempt.txt" 2>/dev/null || true
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

# Poll the real resumed component, bounded, until exactly <package>/<launcher>.
# A picker or Settings activity in the same package does not satisfy this.
wait_for_launcher_activity() (
    _wfla_label=$1
    _wfla_attempts=${2:-10}
    _wfla_attempt=1
    while [ "$_wfla_attempt" -le "$_wfla_attempts" ]; do
        adb_cmd shell dumpsys activity activities \
            > "$ARTIFACTS/activities-$_wfla_label-$_wfla_attempt.txt" 2>&1 || true
        if foreground_is_component \
            "$ARTIFACTS/activities-$_wfla_label-$_wfla_attempt.txt" \
            "$PKG" "$LAUNCHER_ACTIVITY"; then
            cp "$ARTIFACTS/activities-$_wfla_label-$_wfla_attempt.txt" \
                "$ARTIFACTS/activities-$_wfla_label.txt"
            return 0
        fi
        _wfla_attempt=$((_wfla_attempt + 1))
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

# Succeed only when the captured hierarchy is the existing primary/default HOME:
# the date pill, the live clock text and the three original widget child ids are
# all visible. This is the same primary-page identity verify_nothing_home asserts,
# so it can gate a bounded restore without weakening the later assertion.
primary_home_is_ready() (
    xml=$1
    [ -s "$xml" ] || return 1
    grep -Eq 'text="[0-9]{1,2}:[0-9]{2}"' "$xml" || return 1
    grep -Eq 'text="[A-Z]{3} [0-9]{1,2} [A-Z]{3}"' "$xml" || return 1
    grep -Eq 'resource-id="[^"]*/nothingui_clock_time"' "$xml" || return 1
    grep -Eq 'resource-id="[^"]*/nothingui_battery_art"' "$xml" || return 1
    grep -Eq 'resource-id="[^"]*/nothingui_device_storage_value"' "$xml" || return 1
    grep -Eq 'resource-id="[^"]*/nothingui_device_storage_progress"' "$xml" || return 1
)

# After every third-party proof (exact placed host and new launcher-owned id,
# Settings/HOME survival and the bounded page recheck) restore the existing
# primary/default HOME with an ordinary HOME key. Launcher.onNewIntent moves the
# workspace to its default page for that normal MAIN intent; do not reset, move
# or delete any workspace item. Poll the real hierarchy, bounded, and fail closed
# if the primary page does not become ready.
restore_primary_home() {
    _rph_label=$1
    adb_cmd shell input keyevent KEYCODE_HOME > "$ARTIFACTS/home-key-$_rph_label.txt" 2>&1 ||
        fail "could not send the HOME key ($_rph_label)"
    _rph_attempt=1
    while [ "$_rph_attempt" -le 10 ]; do
        if wait_for_foreground "$PKG" "$ARTIFACTS/activities-$_rph_label-$_rph_attempt.txt" 2 &&
            capture_ui_xml "home-primary-$_rph_label-$_rph_attempt.xml" &&
            primary_home_is_ready "$ARTIFACTS/home-primary-$_rph_label-$_rph_attempt.xml"; then
            cp "$ARTIFACTS/home-primary-$_rph_label-$_rph_attempt.xml" \
                "$ARTIFACTS/home-primary.xml"
            capture_screenshot_to home-primary.png
            [ -s "$ARTIFACTS/home-primary.png" ] ||
                fail "primary HOME screenshot capture failed"
            printf 'Restored the existing primary/default HOME through the normal HOME key after all third-party widget proof; the date pill, live clock and three original widget children are visible.\n' \
                > "$ARTIFACTS/primary-home-restored.txt"
            printf 'Evidence: home-primary-$_rph_label-*.xml, home-primary.xml, home-primary.png.\n' \
                >> "$ARTIFACTS/primary-home-restored.txt"
            return 0
        fi
        _rph_attempt=$((_rph_attempt + 1))
        sleep 1
    done
    fail "the primary/default HOME did not become ready after the normal HOME key ($_rph_label)"
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

# The real Play settings surface must follow the launcher's SYSTEM theme choice
# under system night yes/no. This reads the existing preference (a clean install
# defaults to SYSTEM) and never writes it; the diagnostic sample extra is not
# passed. The previous system night mode is restored even when a capture fails.
assert_settings_theme_choice_system() {
    _ast_prefs=$(adb_cmd shell run-as "$PKG" cat \
        shared_prefs/com.android.launcher3.prefs.xml 2>/dev/null || true)
    printf '%s\n' "$_ast_prefs" > "$ARTIFACTS/settings-theme-pref.xml"
    _ast_value=$(printf '%s\n' "$_ast_prefs" |
        sed -n 's/.*name="pref_launcherTheme"[^>]*>\([^<]*\)<.*/\1/p' |
        sed -n '1p')
    if [ -z "$_ast_value" ]; then
        _ast_value=system
    fi
    printf 'pref_launcherTheme=%s\n' "$_ast_value" \
        > "$ARTIFACTS/settings-theme-pref.txt"
    [ "$_ast_value" = system ] ||
        fail "settings theme choice is '$_ast_value', expected system"
}

capture_settings_theme() {
    _cst_night_before=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r')
    printf '%s\n' "$_cst_night_before" \
        > "$ARTIFACTS/settings-theme-night-before.txt"
    _cst_night_value=$(printf '%s\n' "$_cst_night_before" |
        sed -n 's/^[Nn]ight mode:[[:space:]]*//p' | sed -n '1p')
    case "$_cst_night_value" in
        yes | no | auto) ;;
        *) _cst_night_value=auto ;;
    esac

    assert_settings_theme_choice_system

    _cst_failure=
    for _cst_mode in yes no; do
        case "$_cst_mode" in
            yes) _cst_name=dark ;;
            no) _cst_name=light ;;
        esac
        if ! _cst_out=$(adb_cmd shell cmd uimode night "$_cst_mode" 2>&1); then
            printf '%s\n' "$_cst_out" \
                > "$ARTIFACTS/settings-theme-$_cst_name-night.txt"
            _cst_failure="could not switch the emulator to night $_cst_mode for the $_cst_name settings capture"
            break
        fi
        printf '%s\n' "$_cst_out" \
            > "$ARTIFACTS/settings-theme-$_cst_name-night.txt"
        sleep 2
        if ! _cst_out=$(adb_cmd shell am start -W -f 0x18000000 \
            -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
            printf '%s\n' "$_cst_out" \
                > "$ARTIFACTS/settings-theme-$_cst_name-launch.txt"
            _cst_failure="could not open the real $_cst_name settings surface"
            break
        fi
        printf '%s\n' "$_cst_out" \
            > "$ARTIFACTS/settings-theme-$_cst_name-launch.txt"
        case "$_cst_out" in
            *"Error:"* | *"Error type"* | *Exception*)
                _cst_failure="real $_cst_name settings launch reported an error"
                break
                ;;
        esac
        if ! printf '%s\n' "$_cst_out" | grep -q 'Status: ok'; then
            _cst_failure="real $_cst_name settings launch did not report Status: ok"
            break
        fi
        sleep 2
        if ! capture_ui_xml "settings-theme-$_cst_name.xml"; then
            _cst_failure="settings theme $_cst_name UI XML capture failed"
            break
        fi
        if ! grep -Fq 'Settings' "$ARTIFACTS/settings-theme-$_cst_name.xml" ||
            ! grep -Fq 'General' "$ARTIFACTS/settings-theme-$_cst_name.xml"; then
            _cst_failure="settings theme $_cst_name did not expose the real Preferences dashboard"
            break
        fi
        if grep -Fq 'DOTWEL' "$ARTIFACTS/settings-theme-$_cst_name.xml"; then
            _cst_failure="settings theme $_cst_name rendered the diagnostic sample"
            break
        fi
        capture_screenshot_to "settings-theme-$_cst_name.png"
        if [ ! -s "$ARTIFACTS/settings-theme-$_cst_name.png" ]; then
            _cst_failure="settings theme $_cst_name screenshot capture failed"
            break
        fi
        printf 'Settings theme (%s): real Preferences dashboard captured under system night %s.\n' \
            "$_cst_name" "$_cst_mode" \
            > "$ARTIFACTS/settings-theme-$_cst_name.txt"
        printf 'Screenshot: settings-theme-%s.png.\n' "$_cst_name" \
            >> "$ARTIFACTS/settings-theme-$_cst_name.txt"
    done

    if ! _cst_restore_out=$(adb_cmd shell cmd uimode night "$_cst_night_value" 2>&1); then
        printf '%s\n' "$_cst_restore_out" \
            > "$ARTIFACTS/settings-theme-night-restore.txt"
        fail "could not restore the emulator night mode to $_cst_night_value"
    fi
    printf '%s\n' "$_cst_restore_out" \
        > "$ARTIFACTS/settings-theme-night-restore.txt"
    sleep 1

    [ -z "$_cst_failure" ] || fail "$_cst_failure"
    return_home settings-theme
}

# Capture the real HOME long-press options popup under the current system night
# mode. The popup is opened with a genuine long-press on empty workspace, never
# by starting an activity, and it is dismissed with BACK before returning.
capture_native_home_popup() {
    _cnhp_name=$1
    _cnhp_max_attempts=3
    : > "$ARTIFACTS/native-popup-$_cnhp_name-longpress-log.txt"
    _cnhp_attempt=1
    while [ "$_cnhp_attempt" -le "$_cnhp_max_attempts" ]; do
        wait_for_launcher_idle \
            "$ARTIFACTS/native-popup-$_cnhp_name-idle-$_cnhp_attempt.txt" 10 ||
            fail "launcher was not idle before the $_cnhp_name native popup attempt $_cnhp_attempt"
        capture_ui_xml "native-popup-$_cnhp_name-before-$_cnhp_attempt.xml" ||
            fail "could not capture HOME before the $_cnhp_name native popup attempt $_cnhp_attempt"
        _cnhp_target=$(home_longpress_target \
            "$ARTIFACTS/native-popup-$_cnhp_name-before-$_cnhp_attempt.xml") ||
            fail "could not compute an empty HOME long-press target for the $_cnhp_name native popup"
        set -- $_cnhp_target
        printf 'attempt=%s longpress=%s,%s duration=1000\n' \
            "$_cnhp_attempt" "$1" "$2" \
            >> "$ARTIFACTS/native-popup-$_cnhp_name-longpress-log.txt"
        adb_cmd shell input swipe "$1" "$2" "$1" "$2" 1000 \
            > "$ARTIFACTS/native-popup-$_cnhp_name-longpress-$_cnhp_attempt.txt" 2>&1 ||
            fail "could not long-press HOME for the $_cnhp_name native popup"

        _cnhp_popup=
        _cnhp_poll=1
        while [ "$_cnhp_poll" -le 6 ]; do
            sleep 1
            if capture_ui_xml \
                "native-popup-$_cnhp_name-$_cnhp_attempt-$_cnhp_poll.xml" &&
                home_popup_is_ready \
                    "$ARTIFACTS/native-popup-$_cnhp_name-$_cnhp_attempt-$_cnhp_poll.xml"; then
                _cnhp_popup="$ARTIFACTS/native-popup-$_cnhp_name-$_cnhp_attempt-$_cnhp_poll.xml"
                break
            fi
            _cnhp_poll=$((_cnhp_poll + 1))
        done

        if [ -n "$_cnhp_popup" ]; then
            cp "$_cnhp_popup" "$ARTIFACTS/native-popup-$_cnhp_name.xml"
            capture_screenshot_to "native-popup-$_cnhp_name.png"
            [ -s "$ARTIFACTS/native-popup-$_cnhp_name.png" ] ||
                fail "native popup $_cnhp_name screenshot capture failed"
            grep -Fq 'Widgets' "$ARTIFACTS/native-popup-$_cnhp_name.xml" ||
                fail "native popup $_cnhp_name did not expose the Widgets option"
            adb_cmd shell input keyevent KEYCODE_BACK \
                > "$ARTIFACTS/native-popup-$_cnhp_name-close.txt" 2>&1 || true
            sleep 1
            return 0
        fi
        printf 'attempt=%s popup-not-ready\n' "$_cnhp_attempt" \
            >> "$ARTIFACTS/native-popup-$_cnhp_name-longpress-log.txt"
        adb_cmd shell input keyevent KEYCODE_BACK \
            >> "$ARTIFACTS/native-popup-$_cnhp_name-longpress-log.txt" 2>&1 || true
        sleep 1
        _cnhp_attempt=$((_cnhp_attempt + 1))
    done
    fail "the real HOME long-press did not open the $_cnhp_name native popup after $_cnhp_max_attempts bounded attempts"
}

# Poll the debug-only theme-refresh trace until the launcher reports the expected
# night configuration and a resolved native activity theme whose uiColorMode
# matches it. The baseline excludes earlier captures, so a stale line cannot
# satisfy a later mode. This is evidence only; no preference is read or written.
wait_for_native_theme_state() {
    _wnst_label=$1
    _wnst_night=$2
    _wnst_dark=$3
    _wnst_baseline=$4
    _wnst_attempt=1
    _wnst_last=
    while [ "$_wnst_attempt" -le 20 ]; do
        ADB_TIMEOUT=30 adb_cmd logcat -d -s DotWelTheme:D -v brief \
            > "$ARTIFACTS/native-theme-$_wnst_label.log" 2>/dev/null || true
        tail -n +"$((_wnst_baseline + 1))" \
            "$ARTIFACTS/native-theme-$_wnst_label.log" 2>/dev/null \
            > "$ARTIFACTS/native-theme-$_wnst_label-current.log" || true
        if _wnst_last=$(theme_refresh_line \
            "$ARTIFACTS/native-theme-$_wnst_label-current.log" \
            "$_wnst_night" "$_wnst_dark" "$LAUNCHER_ACTIVITY"); then
            printf '%s\n' "$_wnst_last" \
                > "$ARTIFACTS/native-theme-$_wnst_label-state.txt"
            return 0
        fi
        _wnst_attempt=$((_wnst_attempt + 1))
        sleep 1
    done
    _wnst_seen=$(
        grep -F 'theme-refresh' "$ARTIFACTS/native-theme-$_wnst_label.log" 2>/dev/null |
            grep -F "activity=$LAUNCHER_ACTIVITY " |
            tail -n 1
    ) || true
    _wnst_now_night=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r') || true
    printf '%s\n' "$_wnst_now_night" \
        > "$ARTIFACTS/native-theme-$_wnst_label-system-night-now.txt"
    adb_cmd shell dumpsys activity activities \
        > "$ARTIFACTS/native-theme-$_wnst_label-activities.txt" 2>/dev/null || true
    capture_screenshot_to "native-theme-$_wnst_label-failure.png" || true
    {
        printf 'expected night=%s resolvedDark=%s activity=%s\n' \
            "$_wnst_night" "$_wnst_dark" "$LAUNCHER_ACTIVITY"
        printf 'current uimode night: %s\n' "${_wnst_now_night:-<unknown>}"
        printf 'last launcher theme-refresh: %s\n' "${_wnst_seen:-<none>}"
    } > "$ARTIFACTS/native-theme-$_wnst_label-state.txt"
    return 1
}

# Capture the real HOME long-press popup and the real app drawer in both system
# night modes while the launcher preference stays SYSTEM. The previous night mode
# is restored even when a capture fails. The diagnostic theme sample is not used.
capture_native_surfaces_theme() {
    _cnst_night_before=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r')
    printf '%s\n' "$_cnst_night_before" \
        > "$ARTIFACTS/native-surfaces-night-before.txt"
    _cnst_night_value=$(printf '%s\n' "$_cnst_night_before" |
        sed -n 's/^[Nn]ight mode:[[:space:]]*//p' | sed -n '1p')
    case "$_cnst_night_value" in
        yes | no | auto) ;;
        *) _cnst_night_value=auto ;;
    esac

    assert_settings_theme_choice_system

    _cnst_theme_baseline=$(ADB_TIMEOUT=30 adb_cmd logcat -d -s DotWelTheme:D -v brief 2>/dev/null |
        wc -l | tr -d ' ')
    _cnst_theme_baseline=${_cnst_theme_baseline:-0}

    _cnst_failure=
    for _cnst_mode in yes no; do
        case "$_cnst_mode" in
            yes)
                _cnst_name=dark
                _cnst_night=true
                _cnst_dark=true
                ;;
            no)
                _cnst_name=light
                _cnst_night=false
                _cnst_dark=false
                ;;
        esac
        if ! _cnst_out=$(adb_cmd shell cmd uimode night "$_cnst_mode" 2>&1); then
            printf '%s\n' "$_cnst_out" \
                > "$ARTIFACTS/native-surfaces-$_cnst_name-night.txt"
            _cnst_failure="could not switch the emulator to night $_cnst_mode for the $_cnst_name native surfaces"
            break
        fi
        printf '%s\n' "$_cnst_out" \
            > "$ARTIFACTS/native-surfaces-$_cnst_name-night.txt"
        sleep 2
        _cnst_actual_night=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r' |
            sed -n 's/^[Nn]ight mode:[[:space:]]*//p' | sed -n '1p')
        printf '%s\n' "$_cnst_actual_night" \
            > "$ARTIFACTS/native-theme-$_cnst_name-system-night.txt"
        if [ "$_cnst_actual_night" != "$_cnst_mode" ]; then
            _cnst_failure="the emulator reported night $_cnst_actual_night instead of $_cnst_mode for the $_cnst_name native surfaces"
            break
        fi
        if ! ( wait_for_native_theme_state \
            "$_cnst_name" "$_cnst_night" "$_cnst_dark" "$_cnst_theme_baseline" ); then
            _cnst_failure="the $_cnst_name native theme was not ready: expected night $_cnst_mode and resolved native dark=$_cnst_dark"
            break
        fi

        # A subshell lets a failed helper exit without skipping the night-mode
        # restore below; its artifact writes still land in $ARTIFACTS.
        if ! ( capture_native_home_popup "$_cnst_name" ); then
            _cnst_failure="native popup $_cnst_name capture failed"
            break
        fi
        if ! ( return_home "native-popup-$_cnst_name" ); then
            _cnst_failure="could not return HOME after the $_cnst_name native popup"
            break
        fi

        if ! ( open_app_drawer ); then
            _cnst_failure="native drawer $_cnst_name open failed"
            break
        fi
        cp "$ARTIFACTS/appdrawer.xml" "$ARTIFACTS/native-drawer-$_cnst_name.xml"
        cp "$ARTIFACTS/appdrawer.png" "$ARTIFACTS/native-drawer-$_cnst_name.png"
        if [ ! -s "$ARTIFACTS/native-drawer-$_cnst_name.png" ]; then
            _cnst_failure="native drawer $_cnst_name screenshot capture failed"
            break
        fi
        adb_cmd shell input keyevent KEYCODE_BACK \
            > "$ARTIFACTS/native-drawer-$_cnst_name-close.txt" 2>&1 || true
        sleep 1
        if ! ( return_home "native-drawer-$_cnst_name" ); then
            _cnst_failure="could not return HOME after the $_cnst_name native drawer"
            break
        fi

        printf 'Native surfaces (%s): the real HOME popup and app drawer were captured under system night %s.\n' \
            "$_cnst_name" "$_cnst_mode" \
            > "$ARTIFACTS/native-surfaces-$_cnst_name.txt"
        printf 'Screenshots: native-popup-%s.png, native-drawer-%s.png.\n' \
            "$_cnst_name" "$_cnst_name" \
            >> "$ARTIFACTS/native-surfaces-$_cnst_name.txt"
    done

    if ! _cnst_restore_out=$(adb_cmd shell cmd uimode night "$_cnst_night_value" 2>&1); then
        printf '%s\n' "$_cnst_restore_out" \
            > "$ARTIFACTS/native-surfaces-night-restore.txt"
        fail "could not restore the emulator night mode to $_cnst_night_value"
    fi
    printf '%s\n' "$_cnst_restore_out" \
        > "$ARTIFACTS/native-surfaces-night-restore.txt"
    sleep 1

    [ -z "$_cnst_failure" ] || fail "$_cnst_failure"
    return_home native-surfaces
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

# Find the platform consent screen's cancel control. RoleManager's HOME dialog
# uses "Cancel" on AOSP/Pixel; the extra labels keep the smoke from guessing a
# coordinate if a future system image renames the button.
ui_cancel_bounds() (
    xml=$1
    for label in Cancel CANCEL "No thanks" "No, thanks" "Not now" "Don't switch"; do
        bounds=$(ui_bounds_for "$xml" "$label")
        if [ -n "$bounds" ]; then
            printf '%s\n' "$bounds"
            return 0
        fi
    done
    return 0
)

# The Play settings dashboard must not render the inherited Lawnchair live
# information announcement cards (the "Lawnchair 16 sneak peek" card and the
# placeholder "important announcement" cards). Check the real captured
# hierarchy before the smoke taps the default-launcher warning.
ui_assert_no_inherited_announcements() (
    xml=$1
    for marker in 'Lawnchair' 'sneak peek' 'important announcement' 'announcement'; do
        if grep -Fqi "$marker" "$xml"; then
            printf '%s\n' "$marker"
            return 1
        fi
    done
    return 0
)

# Capture the real platform HOME-role consent screen after an explicit tap on
# the existing settings warning, cancel it, and prove the role holder list did
# not change. This runs only on the disposable API 37 emulator, before the smoke
# grants the role for the remaining HOME checks.
verify_default_home_consent() {
    _vdhc_before="$ARTIFACTS/role-consent-before.txt"
    adb_cmd shell cmd role get-role-holders --user 0 "$HOME_ROLE" > "$_vdhc_before" 2>&1 || true
    if grep -Fq "$PKG" "$_vdhc_before"; then
        printf 'Role consent skipped: %s already holds HOME.\n' "$PKG" \
            > "$ARTIFACTS/role-consent-pending.txt"
        return 0
    fi
    if ! _vdhc_launch=$(adb_cmd shell am start -W \
        -n "$PKG/$THEME_SAMPLE_ACTIVITY" 2>&1); then
        printf '%s\n' "$_vdhc_launch" > "$ARTIFACTS/role-consent-settings-launch.txt"
        fail "could not open settings for the HOME role consent check"
    fi
    printf '%s\n' "$_vdhc_launch" > "$ARTIFACTS/role-consent-settings-launch.txt"
    case "$_vdhc_launch" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "settings launch for the HOME role consent check reported an error"
            ;;
    esac
    printf '%s\n' "$_vdhc_launch" | grep -q 'Status: ok' ||
        fail "settings launch for the HOME role consent check did not report Status: ok"
    sleep 2
    capture_ui_xml role-consent-settings.xml ||
        fail "could not capture the settings default-launcher warning"
    capture_screenshot_to role-consent-settings.png
    if ! _vdhc_announcement=$(ui_assert_no_inherited_announcements \
        "$ARTIFACTS/role-consent-settings.xml"); then
        fail "Play settings still renders an inherited announcement card: $_vdhc_announcement"
    fi
    if ! grep -Fq 'default launcher' "$ARTIFACTS/role-consent-settings.xml"; then
        fail "settings did not expose the default-launcher warning"
    fi
    _vdhc_warning=$(ui_bounds_for "$ARTIFACTS/role-consent-settings.xml" 'default launcher')
    [ -n "$_vdhc_warning" ] || fail "could not find the default-launcher warning bounds"
    tap_center_of_bounds "$_vdhc_warning" ||
        fail "could not tap the default-launcher warning"
    _vdhc_attempt=1
    _vdhc_consent=
    while [ "$_vdhc_attempt" -le 5 ]; do
        sleep 1
        if capture_ui_xml "role-consent-attempt-$_vdhc_attempt.xml"; then
            _vdhc_xml="$ARTIFACTS/role-consent-attempt-$_vdhc_attempt.xml"
            if grep -Eiq 'default (home|launcher)' "$_vdhc_xml" &&
                [ -n "$(ui_cancel_bounds "$_vdhc_xml")" ]; then
                _vdhc_consent=$_vdhc_xml
                break
            fi
        fi
        _vdhc_attempt=$((_vdhc_attempt + 1))
    done
    [ -n "$_vdhc_consent" ] ||
        fail "tapping the warning did not open the platform HOME role consent screen"
    cp "$_vdhc_consent" "$ARTIFACTS/role-consent.xml"
    capture_screenshot_to role-consent.png
    [ -s "$ARTIFACTS/role-consent.png" ] ||
        fail "HOME role consent screenshot capture failed"
    _vdhc_cancel=$(ui_cancel_bounds "$_vdhc_consent")
    [ -n "$_vdhc_cancel" ] || fail "could not find the HOME role consent cancel control"
    tap_center_of_bounds "$_vdhc_cancel" ||
        fail "could not cancel the platform HOME role consent"
    wait_for_foreground "$PKG" "$ARTIFACTS/activities-role-consent-cancel.txt" 10 ||
        fail "cancelling the HOME role consent did not return to settings"
    adb_cmd shell cmd role get-role-holders --user 0 "$HOME_ROLE" \
        > "$ARTIFACTS/role-consent-after.txt" 2>&1 ||
        fail "could not read the HOME role holders after cancelling consent"
    if grep -Fq "$PKG" "$ARTIFACTS/role-consent-after.txt"; then
        fail "cancelling the HOME role consent still granted the role"
    fi
    sort "$_vdhc_before" > "$ARTIFACTS/role-consent-before.sorted"
    sort "$ARTIFACTS/role-consent-after.txt" > "$ARTIFACTS/role-consent-after.sorted"
    cmp -s "$ARTIFACTS/role-consent-before.sorted" \
        "$ARTIFACTS/role-consent-after.sorted" ||
        fail "cancelling the HOME role consent changed the role holder list"
    printf 'Default-home consent: the platform role dialog was shown after a settings tap and cancelled; the role holder list is unchanged.\n' \
        > "$ARTIFACTS/role-consent.txt"
    printf 'Screenshots: role-consent-settings.png, role-consent.png.\n' \
        >> "$ARTIFACTS/role-consent.txt"
}

# The Play home replaces the inherited welcome smartspace with a quiet date pill
# plus the three original widgets. Assert the rendered date strip and the live
# clock widget text, not a static source guard, and keep the inherited brand
# check on the actual HOME.
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
                printf 'Actual HOME: date strip and live clock widget text are visible; no Lawnchair text.\n' \
                    > "$ARTIFACTS/home-nothing.txt"
                printf 'Screenshot: home.png.\n' >> "$ARTIFACTS/home-nothing.txt"
                verify_home_widgets
                return 0
            fi
        fi
        _vnh_attempt=$((_vnh_attempt + 1))
        sleep 1
    done
    [ "$_vnh_captured" -eq 1 ] || fail "could not dump the actual HOME UIAutomator hierarchy"
    fail "actual HOME does not expose the NothingUI date strip and live clock widget"
}

# Fresh Play installs seed two 2x2 widgets plus the wide device card through the
# default workspace. Prove the host actually bound all three with distinct
# launcher-owned AppWidgetIds and that the measured HOME exposes the real
# clock/battery/device child values, instead of trusting a provider catalog or
# the layout file.
verify_home_widgets() {
    _vhw_xml=${1:-$ARTIFACTS/home.xml}
    adb_cmd shell dumpsys appwidget > "$ARTIFACTS/home-widgets.txt" 2>&1 ||
        fail "could not dump the appwidget host state"
    appwidget_launcher_instances "$ARTIFACTS/home-widgets.txt" "$PKG" \
        > "$ARTIFACTS/home-widgets-instances.txt"
    _vhw_clock_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelClockWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/home-widgets-instances.txt")
    _vhw_battery_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelBatteryWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/home-widgets-instances.txt")
    _vhw_device_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelDeviceWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/home-widgets-instances.txt")
    [ -n "$_vhw_clock_id" ] ||
        fail "the clock widget has no launcher-owned AppWidgetId on the fresh Play HOME"
    [ -n "$_vhw_battery_id" ] ||
        fail "the battery widget has no launcher-owned AppWidgetId on the fresh Play HOME"
    [ -n "$_vhw_device_id" ] ||
        fail "the device widget has no launcher-owned AppWidgetId on the fresh Play HOME"
    [ "$_vhw_clock_id" != "$_vhw_battery_id" ] ||
        fail "the clock and battery widgets share AppWidgetId $_vhw_clock_id"
    [ "$_vhw_device_id" != "$_vhw_clock_id" ] &&
        [ "$_vhw_device_id" != "$_vhw_battery_id" ] ||
        fail "the device widget shares an AppWidgetId with another own widget"
    [ -s "$_vhw_xml" ] ||
        fail "the HOME UI XML for the widget child proof is missing"
    grep -Eq 'resource-id="[^"]*/nothingui_clock_time"' "$_vhw_xml" ||
        fail "the HOME UI XML does not expose the clock child id nothingui_clock_time"
    grep -Eq 'resource-id="[^"]*/nothingui_battery_art"' "$_vhw_xml" ||
        fail "the HOME UI XML does not expose the battery child id nothingui_battery_art"
    grep -Eq 'resource-id="[^"]*/nothingui_device_storage_value"' "$_vhw_xml" ||
        fail "the HOME UI XML does not expose the device child id nothingui_device_storage_value"
    grep -Eq 'resource-id="[^"]*/nothingui_device_storage_progress"' "$_vhw_xml" ||
        fail "the HOME UI XML does not expose the device child id nothingui_device_storage_progress"
    _vhw_clock_text=$(home_widget_clock_text "$_vhw_xml")
    home_widget_clock_text_is_live "$_vhw_clock_text" ||
        fail "the HOME clock child has no live time text (got '$_vhw_clock_text')"
    _vhw_battery_description=$(home_widget_battery_description "$_vhw_xml")
    home_widget_battery_description_is_real "$_vhw_battery_description" ||
        fail "the HOME battery child has no real percentage or -- description (got '$_vhw_battery_description')"
    _vhw_device_value=$(home_widget_device_storage_value "$_vhw_xml")
    _vhw_device_detail=$(home_widget_device_storage_detail "$_vhw_xml")
    home_widget_device_storage_is_real "$_vhw_device_value" "$_vhw_device_detail" ||
        fail "the HOME device child has no real storage value (got '$_vhw_device_value' / '$_vhw_device_detail')"
    printf 'Home widgets: clock AppWidgetId %s, battery AppWidgetId %s and device AppWidgetId %s are launcher-owned; the HOME XML exposes nothingui_clock_time=%s, nothingui_battery_art=%s and nothingui_device_storage_value=%s (%s).\n' \
        "$_vhw_clock_id" "$_vhw_battery_id" "$_vhw_device_id" \
        "$_vhw_clock_text" "$_vhw_battery_description" \
        "$_vhw_device_value" "$_vhw_device_detail" \
        > "$ARTIFACTS/home-widgets-verified.txt"
}

# Fresh Play installs seed all three original widgets through the default layout. When
# Android denies the automatic bind, DefaultLayoutParser keeps each own slot as a
# pending widget. Complete at most those three visible pending widgets through
# ordinary HOME taps and the standard per-widget bind consent, never granting
# permanent binding. The real hosted-widget proof stays in verify_nothing_home.
complete_own_widget_setup() {
    _cows_max_rounds=3
    _cows_max_polls=12
    _cows_round=0
    _cows_completed=0
    : > "$ARTIFACTS/own-widget-setup-log.txt"
    while [ "$_cows_round" -lt "$_cows_max_rounds" ]; do
        _cows_round=$((_cows_round + 1))
        if ! capture_ui_xml "own-widget-before-$_cows_round.xml"; then
            fail "could not capture HOME before own-widget setup round $_cows_round"
        fi
        capture_screenshot_to "own-widget-before-$_cows_round.png"
        [ -s "$ARTIFACTS/own-widget-before-$_cows_round.png" ] ||
            fail "own-widget before screenshot capture failed"
        _cows_pending=$(home_pending_widget_bounds \
            "$ARTIFACTS/own-widget-before-$_cows_round.xml")
        if [ -z "$_cows_pending" ]; then
            printf 'round=%s pending=none\n' "$_cows_round" \
                >> "$ARTIFACTS/own-widget-setup-log.txt"
            break
        fi
        _cows_pending_before_count=$(printf '%s\n' "$_cows_pending" |
            awk 'NF { n++ } END { print n + 0 }')
        _cows_target=$(printf '%s\n' "$_cows_pending" | sed -n '1p')
        printf 'round=%s pending=%s target=%s\n' \
            "$_cows_round" "$(printf '%s\n' "$_cows_pending" | tr '\n' ';')" \
            "$_cows_target" >> "$ARTIFACTS/own-widget-setup-log.txt"
        adb_cmd shell dumpsys appwidget \
            > "$ARTIFACTS/own-widget-appwidget-before-$_cows_round.txt" 2>&1 || true
        tap_center_of_bounds "$_cows_target" ||
            fail "could not tap the pending own widget in round $_cows_round"

        _cows_bind_tapped=0
        _cows_dialog_polls=0
        _cows_bound=
        _cows_bound_id=
        _cows_bound_class=
        _cows_round_finished=0
        _cows_remaining_count=0
        _cows_home_ok=0
        _cows_xml=
        _cows_poll=1
        while [ "$_cows_poll" -le "$_cows_max_polls" ]; do
            sleep 1
            _cows_xml="$ARTIFACTS/own-widget-poll-$_cows_round-$_cows_poll.xml"
            capture_ui_xml "own-widget-poll-$_cows_round-$_cows_poll.xml" || true
            adb_cmd shell dumpsys activity activities \
                > "$ARTIFACTS/own-widget-activity-$_cows_round-$_cows_poll.txt" 2>&1 || true
            if [ "$_cows_bind_tapped" -eq 0 ] &&
                widget_bind_consent_is_ready \
                    "$_cows_xml" "$EXPECTED_LABEL" "$EXPECTED_LABEL"; then
                foreground_is_component \
                    "$ARTIFACTS/own-widget-activity-$_cows_round-$_cows_poll.txt" \
                    com.android.settings .AllowBindAppWidgetActivity ||
                    fail "the own-widget bind consent is not the exact AllowBindAppWidgetActivity"
                cp "$_cows_xml" "$ARTIFACTS/own-widget-consent-$_cows_round.xml"
                capture_screenshot_to "own-widget-consent-$_cows_round.png"
                [ -s "$ARTIFACTS/own-widget-consent-$_cows_round.png" ] ||
                    fail "own-widget consent screenshot capture failed"
                if widget_bind_always_allow_is_checked \
                    "$ARTIFACTS/own-widget-consent-$_cows_round.xml"; then
                    fail "the own-widget bind consent has Always allow checked; refusing permanent binding"
                fi
                _cows_create=$(widget_bind_create_button_bounds \
                    "$ARTIFACTS/own-widget-consent-$_cows_round.xml" \
                    "$EXPECTED_LABEL" "$EXPECTED_LABEL")
                [ -n "$_cows_create" ] ||
                    fail "could not find the measured Create control in the own-widget consent"
                tap_center_of_bounds "$_cows_create" ||
                    fail "could not tap Create in the own-widget consent"
                printf 'round=%s route=bind-consent create=%s always_allow=unchecked\n' \
                    "$_cows_round" "$_cows_create" \
                    >> "$ARTIFACTS/own-widget-setup-log.txt"
                _cows_bind_tapped=1
            elif [ "$_cows_bind_tapped" -eq 0 ] &&
                [ -s "$_cows_xml" ] &&
                grep -Fq 'android:id/alertTitle' "$_cows_xml" &&
                grep -Fq 'com.android.settings' "$_cows_xml"; then
                _cows_dialog_polls=$((_cows_dialog_polls + 1))
                if [ "$_cows_dialog_polls" -ge 3 ]; then
                    cp "$_cows_xml" "$ARTIFACTS/own-widget-unexpected-dialog.xml"
                    capture_screenshot_to own-widget-unexpected-dialog.png
                    fail "unexpected own-widget bind dialog (expected Application/Widget $EXPECTED_LABEL)"
                fi
            fi
            if [ "$_cows_bind_tapped" -eq 1 ]; then
                adb_cmd shell dumpsys appwidget \
                    > "$ARTIFACTS/own-widget-appwidget-after-$_cows_round-$_cows_poll.txt" \
                    2>&1 || true
                _cows_new_raw=$(appwidget_new_providers \
                    "$ARTIFACTS/own-widget-appwidget-before-$_cows_round.txt" \
                    "$ARTIFACTS/own-widget-appwidget-after-$_cows_round-$_cows_poll.txt" \
                    "$PKG" id)
                _cows_binding=$(own_widget_new_binding \
                    "$ARTIFACTS/own-widget-appwidget-before-$_cows_round.txt" \
                    "$ARTIFACTS/own-widget-appwidget-after-$_cows_round-$_cows_poll.txt" \
                    "$PKG")
                if [ -n "$_cows_new_raw" ] && [ -z "$_cows_binding" ]; then
                    cp "$_cows_xml" "$ARTIFACTS/own-widget-wrong-provider.xml"
                    capture_screenshot_to own-widget-wrong-provider.png
                    fail "the own-widget setup did not bind exactly one expected DotWel provider: $_cows_new_raw"
                fi
                if [ -n "$_cows_binding" ]; then
                    _cows_bound=$_cows_binding
                    _cows_bound_id=$(printf '%s\n' "$_cows_binding" |
                        awk -F '\t' '{ print $1 }')
                    _cows_bound_class=$(printf '%s\n' "$_cows_binding" |
                        awk -F '\t' '{ print $2 }')
                fi
                _cows_remaining=$(home_pending_widget_bounds "$_cows_xml")
                _cows_remaining_count=$(printf '%s\n' "$_cows_remaining" |
                    awk 'NF { n++ } END { print n + 0 }')
                _cows_dialog_still_open=0
                widget_bind_consent_is_ready \
                    "$_cows_xml" "$EXPECTED_LABEL" "$EXPECTED_LABEL" &&
                    _cows_dialog_still_open=1
                _cows_home_ok=0
                foreground_is_component \
                    "$ARTIFACTS/own-widget-activity-$_cows_round-$_cows_poll.txt" \
                    "$PKG" "$LAUNCHER_ACTIVITY" &&
                    _cows_home_ok=1
                if [ -n "$_cows_bound" ] && [ "$_cows_dialog_still_open" -eq 0 ] &&
                    [ "$_cows_remaining_count" -eq "$((_cows_pending_before_count - 1))" ] &&
                    [ "$_cows_home_ok" -eq 1 ]; then
                    _cows_round_finished=1
                    break
                fi
            fi
            _cows_poll=$((_cows_poll + 1))
        done
        if [ -z "$_cows_bound" ]; then
            [ -z "$_cows_xml" ] || cp "$_cows_xml" "$ARTIFACTS/own-widget-setup-last.xml"
            capture_screenshot_to own-widget-setup-last.png
            fail "the own widget was not bound after the per-widget consent in round $_cows_round"
        fi
        [ "$_cows_round_finished" -eq 1 ] ||
            fail "the pending own widget count did not decrease by exactly one after Create in round $_cows_round (before=$_cows_pending_before_count remaining=$_cows_remaining_count home=$_cows_home_ok dialog=$_cows_dialog_still_open)"
        printf 'round=%s bound_id=%s bound_class=%s remaining=%s\n' \
            "$_cows_round" "$_cows_bound_id" "$_cows_bound_class" \
            "$_cows_remaining_count" >> "$ARTIFACTS/own-widget-setup-log.txt"
        _cows_completed=$((_cows_completed + 1))
    done

    if ! capture_ui_xml own-widget-after.xml; then
        fail "could not capture HOME after own-widget setup"
    fi
    capture_screenshot_to own-widget-after.png
    [ -s "$ARTIFACTS/own-widget-after.png" ] ||
        fail "own-widget after screenshot capture failed"
    _cows_remaining=$(home_pending_widget_bounds "$ARTIFACTS/own-widget-after.xml")
    [ -z "$_cows_remaining" ] ||
        fail "own widgets are still pending after $_cows_completed setup action(s)"
    printf 'Own widgets: completed %s pending setup action(s) through the standard per-widget bind consent with Always allow unchecked; no pending placeholders remain.\n' \
        "$_cows_completed" > "$ARTIFACTS/own-widget-setup.txt"
    printf 'Evidence: own-widget-before-*.xml/.png, own-widget-consent-*.xml/.png, own-widget-after.xml/.png.\n' \
        >> "$ARTIFACTS/own-widget-setup.txt"
}

# Capture the clean HOME under system dark/light before any third-party widget is
# added, so the composition can be reviewed without test pollution. The previous
# night mode is restored even when a capture fails.
capture_clean_home_theme() {
    assert_settings_theme_choice_system
    _ccht_night_before=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r')
    printf '%s\n' "$_ccht_night_before" \
        > "$ARTIFACTS/clean-home-night-before.txt"
    _ccht_night_value=$(printf '%s\n' "$_ccht_night_before" |
        sed -n 's/^[Nn]ight mode:[[:space:]]*//p' | sed -n '1p')
    case "$_ccht_night_value" in
        yes | no | auto) ;;
        *) _ccht_night_value=auto ;;
    esac

    _ccht_failure=
    for _ccht_mode in yes no; do
        case "$_ccht_mode" in
            yes) _ccht_name=dark ;;
            no) _ccht_name=light ;;
        esac
        if ! _ccht_out=$(adb_cmd shell cmd uimode night "$_ccht_mode" 2>&1); then
            printf '%s\n' "$_ccht_out" \
                > "$ARTIFACTS/clean-home-$_ccht_name-night.txt"
            _ccht_failure="could not switch the emulator to night $_ccht_mode for the clean $_ccht_name HOME"
            break
        fi
        printf '%s\n' "$_ccht_out" \
            > "$ARTIFACTS/clean-home-$_ccht_name-night.txt"
        sleep 2
        return_home "clean-home-$_ccht_name"
        sleep 1
        if ! capture_ui_xml "clean-home-$_ccht_name.xml"; then
            _ccht_failure="clean home $_ccht_name UI XML capture failed"
            break
        fi
        if ! grep -Eq 'text="[A-Z]{3} [0-9]{1,2} [A-Z]{3}"' \
            "$ARTIFACTS/clean-home-$_ccht_name.xml"; then
            _ccht_failure="clean home $_ccht_name does not expose the NothingUI date strip"
            break
        fi
        if grep -Fq 'Lawnchair' "$ARTIFACTS/clean-home-$_ccht_name.xml"; then
            _ccht_failure="clean home $_ccht_name still exposes inherited Lawnchair text"
            break
        fi
        if ! ( verify_home_widgets "$ARTIFACTS/clean-home-$_ccht_name.xml" ); then
            _ccht_failure="clean home $_ccht_name widget hosting proof failed"
            break
        fi
        cp "$ARTIFACTS/home-widgets.txt" \
            "$ARTIFACTS/clean-home-$_ccht_name-widgets.txt"
        cp "$ARTIFACTS/home-widgets-verified.txt" \
            "$ARTIFACTS/clean-home-$_ccht_name-widgets-verified.txt"
        capture_screenshot_to "clean-home-$_ccht_name.png"
        if [ ! -s "$ARTIFACTS/clean-home-$_ccht_name.png" ]; then
            _ccht_failure="clean home $_ccht_name screenshot capture failed"
            break
        fi
        printf 'Clean HOME (%s): date pill and all three original widgets captured under system night %s before the third-party widget test.\n' \
            "$_ccht_name" "$_ccht_mode" \
            > "$ARTIFACTS/clean-home-$_ccht_name.txt"
        printf 'Screenshots: clean-home-%s.png.\n' "$_ccht_name" \
            >> "$ARTIFACTS/clean-home-$_ccht_name.txt"
    done

    if ! _ccht_restore_out=$(adb_cmd shell cmd uimode night "$_ccht_night_value" 2>&1); then
        printf '%s\n' "$_ccht_restore_out" \
            > "$ARTIFACTS/clean-home-night-restore.txt"
        fail "could not restore the emulator night mode to $_ccht_night_value"
    fi
    printf '%s\n' "$_ccht_restore_out" \
        > "$ARTIFACTS/clean-home-night-restore.txt"
    sleep 1

    [ -z "$_ccht_failure" ] || fail "$_ccht_failure"
    return_home clean-home
    verify_nothing_home
}

# Succeed only when the measured controls are top-to-bottom: the Customize
# launcher label, then the top icon-size slider, then Browse widgets. Each
# bounds string is split through ui_bounds_top_y, so a quoted 4-number string is
# never treated as one positional and cannot abort under `set -u`. Malformed or
# unresolved bounds fail closed.
customization_controls_in_order() {
    _ccio_customize_y=$(ui_bounds_top_y "$1")
    _ccio_slider_y=$(ui_bounds_top_y "$2")
    _ccio_browse_y=$(ui_bounds_top_y "$3")
    [ -n "$_ccio_customize_y" ] && [ -n "$_ccio_slider_y" ] && [ -n "$_ccio_browse_y" ] ||
        return 1
    [ "$_ccio_customize_y" -lt "$_ccio_slider_y" ] &&
        [ "$_ccio_slider_y" -lt "$_ccio_browse_y" ]
}

# Runtime gate for the Play-only "Customize launcher" path. It uses the real
# PreferenceActivity dashboard (no diagnostic extras), measured exact controls,
# the real Browse-widgets launcher request and the real native picker, then
# changes the actual top icon-size slider by one keyboard step and restores it.
# Every unresolved label, slider, percentage, focus or binding fails closed with
# the captured XML/PNG. No preference is written and no widget is bound.
capture_customization_settings() {
    _ccs_label=customization

    # Immutable HOME baseline before any Settings interaction.
    return_home customization-baseline
    wait_for_launcher_idle "$ARTIFACTS/customization-home-idle.txt" 10 ||
        fail "launcher was not idle before the customization baseline"
    capture_ui_xml customization-home-baseline.xml ||
        fail "customization HOME baseline XML capture failed"
    capture_screenshot_to customization-home-baseline.png
    [ -s "$ARTIFACTS/customization-home-baseline.png" ] ||
        fail "customization HOME baseline screenshot capture failed"
    primary_home_is_ready "$ARTIFACTS/customization-home-baseline.xml" ||
        fail "customization baseline is not the existing primary HOME"
    ui_widget_host_bounds "$ARTIFACTS/customization-home-baseline.xml" \
        > "$ARTIFACTS/customization-widget-host-bounds-baseline.txt"
    [ -s "$ARTIFACTS/customization-widget-host-bounds-baseline.txt" ] ||
        fail "customization baseline exposed no measured widget-host bounds"
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/customization-appwidget-baseline.txt" 2>&1 || true
    appwidget_launcher_instances "$ARTIFACTS/customization-appwidget-baseline.txt" "$PKG" \
        > "$ARTIFACTS/customization-appwidget-instances-baseline.txt"
    [ -s "$ARTIFACTS/customization-appwidget-instances-baseline.txt" ] ||
        fail "customization baseline exposed no launcher-owned widget bindings"
    adb_cmd shell dumpsys wallpaper \
        > "$ARTIFACTS/customization-wallpaper-baseline.txt" 2>&1 || true
    _ccs_wall_ids_baseline=$(wallpaper_ids_from_dump \
        "$ARTIFACTS/customization-wallpaper-baseline.txt" 0) ||
        fail "could not parse the baseline Home/Lock wallpaper IDs"
    _ccs_wall_component_baseline=$(wallpaper_component_from_dump \
        "$ARTIFACTS/customization-wallpaper-baseline.txt")
    printf 'ids=%s component=%s\n' \
        "$_ccs_wall_ids_baseline" "${_ccs_wall_component_baseline:-none}" \
        > "$ARTIFACTS/customization-wallpaper-baseline-summary.txt"
    {
        printf 'home_lock_source=datastore-if-available\n'
        adb_cmd shell run-as "$PKG" ls -l databases files/datastore \
            2>&1 || true
    } > "$ARTIFACTS/customization-private-files-baseline.txt"
    if adb_cmd shell run-as "$PKG" cat databases/launcher.db \
        > "$ARTIFACTS/customization-workspace-baseline.db" 2> "$ARTIFACTS/customization-workspace-baseline.err"; then
        [ -s "$ARTIFACTS/customization-workspace-baseline.db" ] &&
            printf 'workspace_db=present\n' \
                > "$ARTIFACTS/customization-workspace-baseline.txt" ||
            printf 'workspace_db=empty\n' \
                > "$ARTIFACTS/customization-workspace-baseline.txt"
    else
        printf 'workspace_db=unavailable\n' \
            > "$ARTIFACTS/customization-workspace-baseline.txt"
    fi
    adb_cmd shell run-as "$PKG" cat shared_prefs/com.android.launcher3.prefs.xml \
        > "$ARTIFACTS/customization-prefs-baseline.xml" 2>/dev/null || true
    adb_cmd shell run-as "$PKG" cat files/datastore/preferences.preferences_pb \
        > "$ARTIFACTS/customization-datastore-baseline.pb" 2>/dev/null || true
    if grep -aq 'lock_home_screen' "$ARTIFACTS/customization-datastore-baseline.pb"; then
        printf 'lock_home_screen_marker=present (presence only; value not proven)\n' \
            > "$ARTIFACTS/customization-homelock-baseline.txt"
    else
        printf 'lock_home_screen_marker=unavailable\n' \
            > "$ARTIFACTS/customization-homelock-baseline.txt"
    fi

    # 1. Real dashboard, no diagnostic sample extra.
    if ! _ccs_out=$(adb_cmd shell am start -W -f 0x18000000 \
        -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
        printf '%s\n' "$_ccs_out" \
            > "$ARTIFACTS/customization-dashboard-launch.txt"
        fail "could not open the real customization dashboard"
    fi
    printf '%s\n' "$_ccs_out" \
        > "$ARTIFACTS/customization-dashboard-launch.txt"
    case "$_ccs_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "customization dashboard launch reported an error"
            ;;
    esac
    printf '%s\n' "$_ccs_out" | grep -q 'Status: ok' ||
        fail "customization dashboard launch did not report Status: ok"
    sleep 2
    capture_ui_xml customization-dashboard.xml ||
        fail "customization dashboard UI XML capture failed"
    if grep -Fq 'DOTWEL' "$ARTIFACTS/customization-dashboard.xml"; then
        fail "customization dashboard rendered the diagnostic sample"
    fi
    _ccs_customize=$(ui_unique_label_bounds \
        "$ARTIFACTS/customization-dashboard.xml" 'Customize launcher')
    _ccs_category=$(ui_unique_clickable_label_bounds \
        "$ARTIFACTS/customization-dashboard.xml" 'Icon size and home screen')
    [ -n "$_ccs_customize" ] ||
        fail "the dashboard has no unique Customize launcher entry"
    [ -n "$_ccs_category" ] ||
        fail "the dashboard has no unique clickable Icon size and home screen entry"
    capture_screenshot_to customization-dashboard.png
    [ -s "$ARTIFACTS/customization-dashboard.png" ] ||
        fail "customization dashboard screenshot capture failed"
    tap_center_of_bounds "$_ccs_category" ||
        fail "could not tap the measured Icon size and home screen entry"

    _ccs_home_xml=
    _ccs_poll=1
    while [ "$_ccs_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-home-screen-attempt-$_ccs_poll.xml"
        if capture_ui_xml "customization-home-screen-attempt-$_ccs_poll.xml"; then
            _ccs_customize=$(ui_unique_label_bounds "$_ccs_candidate" 'Customize launcher')
            _ccs_slider=$(ui_top_slider_bounds "$_ccs_candidate")
            _ccs_percent=$(ui_slider_percent "$_ccs_candidate" "$_ccs_slider")
            _ccs_browse=$(ui_unique_clickable_label_bounds "$_ccs_candidate" 'Browse widgets')
            if [ -n "$_ccs_customize" ] && [ -n "$_ccs_slider" ] &&
                [ -n "$_ccs_percent" ] && [ -n "$_ccs_browse" ]; then
                _ccs_home_xml=$_ccs_candidate
                break
            fi
        fi
        _ccs_poll=$((_ccs_poll + 1))
    done
    [ -n "$_ccs_home_xml" ] ||
        fail "the measured Icon size and home screen entry did not expose the top Customize launcher group, icon-size percentage and Browse widgets"
    cp "$_ccs_home_xml" "$ARTIFACTS/customization-home-screen.xml"
    capture_screenshot_to customization-home-screen.png
    [ -s "$ARTIFACTS/customization-home-screen.png" ] ||
        fail "customization Home screen screenshot capture failed"
    customization_controls_in_order \
        "$_ccs_customize" "$_ccs_slider" "$_ccs_browse" ||
        fail "the customization controls are not in the top Customize launcher group order"
    printf 'customize=%s slider=%s percent=%s browse=%s\n' \
        "$_ccs_customize" "$_ccs_slider" "$_ccs_percent" "$_ccs_browse" \
        > "$ARTIFACTS/customization-home-screen-controls.txt"

    # 2. First explicit Browse widgets tap opens the real native picker.
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/customization-appwidget-before-browse.txt" 2>&1 || true
    tap_center_of_bounds "$_ccs_browse" ||
        fail "could not tap the measured Browse widgets entry"
    _ccs_picker=
    _ccs_picker_poll=1
    while [ "$_ccs_picker_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-picker-attempt-$_ccs_picker_poll.xml"
        if capture_ui_xml "customization-picker-attempt-$_ccs_picker_poll.xml" &&
            widget_picker_is_ready "$_ccs_candidate" "$ARTIFACTS/customization-home-screen.xml"; then
            _ccs_picker=$_ccs_candidate
            break
        fi
        _ccs_picker_poll=$((_ccs_picker_poll + 1))
    done
    [ -n "$_ccs_picker" ] ||
        fail "Browse widgets did not open the real native widget picker"
    cp "$_ccs_picker" "$ARTIFACTS/customization-picker.xml"
    capture_screenshot_to customization-picker.png
    [ -s "$ARTIFACTS/customization-picker.png" ] ||
        fail "customization picker screenshot capture failed"
    adb_cmd shell dumpsys activity activities \
        > "$ARTIFACTS/customization-picker-activities.txt" 2>&1 || true
    foreground_is "$ARTIFACTS/customization-picker-activities.txt" "$PKG" ||
        fail "the customization picker is not owned by the launcher package"
    printf 'resumed=%s\n' \
        "$(resumed_component "$ARTIFACTS/customization-picker-activities.txt")" \
        > "$ARTIFACTS/customization-picker-resumed.txt"
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/customization-appwidget-during-browse.txt" 2>&1 || true

    # 3. Back closes the picker and returns HOME without binding anything.
    adb_cmd shell input keyevent KEYCODE_BACK \
        > "$ARTIFACTS/customization-picker-back.txt" 2>&1 ||
        fail "could not press Back from the customization picker"
    wait_for_launcher_activity customization-after-browse 10 ||
        fail "Back from the customization picker did not resume the exact launcher activity"
    sleep 1
    capture_ui_xml customization-home-after-browse-back.xml ||
        fail "HOME XML after the customization picker Back capture failed"
    capture_screenshot_to customization-home-after-browse-back.png
    [ -s "$ARTIFACTS/customization-home-after-browse-back.png" ] ||
        fail "HOME screenshot after the customization picker Back capture failed"
    primary_home_is_ready "$ARTIFACTS/customization-home-after-browse-back.xml" ||
        fail "Back from the customization picker did not restore the primary HOME"
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/customization-appwidget-after-browse.txt" 2>&1 || true
    appwidget_launcher_instances "$ARTIFACTS/customization-appwidget-after-browse.txt" "$PKG" \
        > "$ARTIFACTS/customization-appwidget-instances-after-browse.txt"
    sort "$ARTIFACTS/customization-appwidget-instances-baseline.txt" \
        > "$ARTIFACTS/customization-appwidget-instances-baseline.sorted"
    sort "$ARTIFACTS/customization-appwidget-instances-after-browse.txt" \
        > "$ARTIFACTS/customization-appwidget-instances-after-browse.sorted"
    cmp -s "$ARTIFACTS/customization-appwidget-instances-baseline.sorted" \
        "$ARTIFACTS/customization-appwidget-instances-after-browse.sorted" ||
        fail "opening and closing Browse widgets changed the launcher widget bindings"
    if widget_picker_is_ready "$ARTIFACTS/customization-home-after-browse-back.xml" \
        "$ARTIFACTS/customization-home-screen.xml"; then
        fail "the native picker is still visible after Back"
    fi

    # 4. Reopen Settings: no automatic picker, and a second explicit tap works.
    if ! _ccs_out=$(adb_cmd shell am start -W -f 0x18000000 \
        -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
        printf '%s\n' "$_ccs_out" \
            > "$ARTIFACTS/customization-reopen-launch.txt"
        fail "could not reopen the real customization dashboard"
    fi
    printf '%s\n' "$_ccs_out" \
        > "$ARTIFACTS/customization-reopen-launch.txt"
    printf '%s\n' "$_ccs_out" | grep -q 'Status: ok' ||
        fail "reopened customization dashboard did not report Status: ok"
    sleep 2
    adb_cmd shell dumpsys activity activities \
        > "$ARTIFACTS/customization-reopen-activities.txt" 2>&1 || true
    foreground_is_component "$ARTIFACTS/customization-reopen-activities.txt" \
        "$PKG" "$PREFERENCES_ACTIVITY" ||
        fail "reopened customization Settings is not the exact foreground activity"
    capture_ui_xml customization-dashboard-reopen.xml ||
        fail "reopened customization dashboard XML capture failed"
    sleep 2
    adb_cmd shell dumpsys activity activities \
        > "$ARTIFACTS/customization-reopen-stable-activities.txt" 2>&1 || true
    foreground_is_component "$ARTIFACTS/customization-reopen-stable-activities.txt" \
        "$PKG" "$PREFERENCES_ACTIVITY" ||
        fail "reopened customization Settings lost the exact foreground to an automatic picker"
    capture_ui_xml customization-dashboard-reopen-stable.xml ||
        fail "reopened customization dashboard stable XML capture failed"
    if widget_picker_is_ready "$ARTIFACTS/customization-dashboard-reopen-stable.xml" \
        "$ARTIFACTS/customization-home-screen.xml"; then
        fail "reopening Settings opened the native picker without a tap"
    fi
    _ccs_customize=$(ui_unique_label_bounds \
        "$ARTIFACTS/customization-dashboard-reopen-stable.xml" 'Customize launcher')
    _ccs_category=$(ui_unique_clickable_label_bounds \
        "$ARTIFACTS/customization-dashboard-reopen-stable.xml" 'Icon size and home screen')
    [ -n "$_ccs_customize" ] && [ -n "$_ccs_category" ] ||
        fail "reopened customization dashboard lost a unique Customize launcher or category entry"
    tap_center_of_bounds "$_ccs_category" ||
        fail "could not tap the measured customization category after reopening"
    _ccs_home_xml=
    _ccs_poll=1
    while [ "$_ccs_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-home-screen-reopen-attempt-$_ccs_poll.xml"
        if capture_ui_xml "customization-home-screen-reopen-attempt-$_ccs_poll.xml"; then
            _ccs_slider=$(ui_top_slider_bounds "$_ccs_candidate")
            _ccs_browse=$(ui_unique_clickable_label_bounds "$_ccs_candidate" 'Browse widgets')
            if [ -n "$_ccs_slider" ] && [ -n "$_ccs_browse" ]; then
                _ccs_home_xml=$_ccs_candidate
                break
            fi
        fi
        _ccs_poll=$((_ccs_poll + 1))
    done
    [ -n "$_ccs_home_xml" ] ||
        fail "the reopened customization category did not expose the icon-size slider and Browse widgets"
    cp "$_ccs_home_xml" "$ARTIFACTS/customization-home-screen-reopen.xml"
    capture_screenshot_to customization-home-screen-reopen.png
    _ccs_browse=$(ui_unique_clickable_label_bounds \
        "$ARTIFACTS/customization-home-screen-reopen.xml" 'Browse widgets')
    [ -n "$_ccs_browse" ] ||
        fail "the reopened customization Home screen lost the unique Browse widgets entry"
    tap_center_of_bounds "$_ccs_browse" ||
        fail "the second explicit Browse widgets tap was not measured"
    _ccs_picker=
    _ccs_picker_poll=1
    while [ "$_ccs_picker_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-picker-second-attempt-$_ccs_picker_poll.xml"
        if capture_ui_xml "customization-picker-second-attempt-$_ccs_picker_poll.xml" &&
            widget_picker_is_ready "$_ccs_candidate" "$ARTIFACTS/customization-home-screen-reopen.xml"; then
            _ccs_picker=$_ccs_candidate
            break
        fi
        _ccs_picker_poll=$((_ccs_picker_poll + 1))
    done
    [ -n "$_ccs_picker" ] ||
        fail "the second explicit Browse widgets tap did not reopen the native picker (a handled flag blocked it)"
    cp "$_ccs_picker" "$ARTIFACTS/customization-picker-second.xml"
    capture_screenshot_to customization-picker-second.png
    adb_cmd shell input keyevent KEYCODE_BACK \
        > "$ARTIFACTS/customization-picker-second-back.txt" 2>&1 ||
        fail "could not press Back from the second customization picker"
    wait_for_launcher_activity customization-after-browse-second 10 ||
        fail "Back from the second customization picker did not resume the exact launcher activity"
    sleep 1
    capture_ui_xml customization-home-after-browse-second-back.xml ||
        fail "HOME XML after the second picker Back capture failed"
    if widget_picker_is_ready "$ARTIFACTS/customization-home-after-browse-second-back.xml" \
        "$ARTIFACTS/customization-home-screen-reopen.xml"; then
        fail "the native picker is still visible after the second Back"
    fi
    adb_cmd shell input keyevent KEYCODE_HOME \
        > "$ARTIFACTS/customization-home-repeat-key.txt" 2>&1 ||
        fail "could not send the ordinary HOME key after the second picker"
    sleep 2
    adb_cmd shell dumpsys activity activities \
        > "$ARTIFACTS/customization-home-repeat-activities.txt" 2>&1 || true
    foreground_is_component "$ARTIFACTS/customization-home-repeat-activities.txt" \
        "$PKG" "$LAUNCHER_ACTIVITY" ||
        fail "ordinary HOME after the second picker did not resume the exact launcher"
    capture_ui_xml customization-home-after-home-repeat.xml ||
        fail "HOME XML after the ordinary HOME repeat capture failed"
    if widget_picker_is_ready "$ARTIFACTS/customization-home-after-home-repeat.xml" \
        "$ARTIFACTS/customization-home-screen-reopen.xml"; then
        fail "an ordinary HOME repeat reopened the native picker without a tap"
    fi
    adb_cmd shell input keyevent KEYCODE_HOME \
        > "$ARTIFACTS/customization-home-repeat-second-key.txt" 2>&1 ||
        fail "could not send the second ordinary HOME key"
    sleep 2
    capture_ui_xml customization-home-after-home-repeat-second.xml ||
        fail "HOME XML after the second ordinary HOME repeat capture failed"
    if widget_picker_is_ready "$ARTIFACTS/customization-home-after-home-repeat-second.xml" \
        "$ARTIFACTS/customization-home-screen-reopen.xml"; then
        fail "a second ordinary HOME repeat reopened the native picker without a tap"
    fi

    # 5. Actual top icon-size slider: keyboard focus, one legal 10% step, HOME
    # persistence and an exact one-step restore.
    if ! _ccs_out=$(adb_cmd shell am start -W -f 0x18000000 \
        -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
        printf '%s\n' "$_ccs_out" \
            > "$ARTIFACTS/customization-size-launch.txt"
        fail "could not open Settings for the icon-size slider check"
    fi
    printf '%s\n' "$_ccs_out" > "$ARTIFACTS/customization-size-launch.txt"
    printf '%s\n' "$_ccs_out" | grep -q 'Status: ok' ||
        fail "Settings launch for the icon-size slider did not report Status: ok"
    sleep 2
    capture_ui_xml customization-size-dashboard.xml ||
        fail "icon-size dashboard XML capture failed"
    _ccs_category=$(ui_unique_clickable_label_bounds \
        "$ARTIFACTS/customization-size-dashboard.xml" 'Icon size and home screen')
    [ -n "$_ccs_category" ] ||
        fail "the icon-size dashboard lost the unique measured category"
    tap_center_of_bounds "$_ccs_category" ||
        fail "could not tap the measured icon-size category"
    _ccs_home_xml=
    _ccs_poll=1
    while [ "$_ccs_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-size-screen-attempt-$_ccs_poll.xml"
        if capture_ui_xml "customization-size-screen-attempt-$_ccs_poll.xml"; then
            _ccs_slider=$(ui_top_slider_bounds "$_ccs_candidate")
            _ccs_percent=$(ui_slider_percent "$_ccs_candidate" "$_ccs_slider")
            if [ -n "$_ccs_slider" ] && [ -n "$_ccs_percent" ]; then
                _ccs_home_xml=$_ccs_candidate
                break
            fi
        fi
        _ccs_poll=$((_ccs_poll + 1))
    done
    [ -n "$_ccs_home_xml" ] ||
        fail "the icon-size screen exposed no actual top SeekBar with a unique measured percentage"
    cp "$_ccs_home_xml" "$ARTIFACTS/customization-size-before.xml"
    capture_screenshot_to customization-size-before.png
    _ccs_initial_percent=$_ccs_percent
    _ccs_initial_slider=$_ccs_slider
    case "$_ccs_initial_percent" in
        50 | 60 | 70 | 80 | 90 | 100 | 110 | 120 | 130 | 140 | 150) ;;
        *) fail "the actual top icon-size percentage '$_ccs_initial_percent' is not a 50-150 step of 10" ;;
    esac

    _ccs_focused=
    _ccs_tab=0
    while [ "$_ccs_tab" -lt 12 ]; do
        _ccs_tab=$((_ccs_tab + 1))
        adb_cmd shell input keyevent KEYCODE_TAB \
            > "$ARTIFACTS/customization-size-tab-$_ccs_tab.txt" 2>&1 ||
            fail "could not send TAB $_ccs_tab for the icon-size slider"
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-size-tab-$_ccs_tab.xml"
        if capture_ui_xml "customization-size-tab-$_ccs_tab.xml"; then
            _ccs_focused=$(ui_focused_slider_bounds "$_ccs_candidate")
            if [ -n "$_ccs_focused" ]; then
                break
            fi
        fi
    done
    [ -n "$_ccs_focused" ] ||
        fail "no actual focused SeekBar appeared within 12 bounded TAB steps; refusing to guess a thumb coordinate"
    [ "$_ccs_focused" = "$_ccs_initial_slider" ] ||
        fail "TAB focused the slider at $_ccs_focused instead of the actual top icon-size slider $_ccs_initial_slider"
    printf 'tab_steps=%s focused=%s initial_percent=%s\n' \
        "$_ccs_tab" "$_ccs_focused" "$_ccs_initial_percent" \
        > "$ARTIFACTS/customization-size-focus.txt"

    if [ "$_ccs_initial_percent" -lt 150 ]; then
        _ccs_step_key=KEYCODE_DPAD_RIGHT
        _ccs_expected_percent=$((_ccs_initial_percent + 10))
        _ccs_restore_key=KEYCODE_DPAD_LEFT
    else
        _ccs_step_key=KEYCODE_DPAD_LEFT
        _ccs_expected_percent=$((_ccs_initial_percent - 10))
        _ccs_restore_key=KEYCODE_DPAD_RIGHT
    fi
    adb_cmd shell input keyevent "$_ccs_step_key" \
        > "$ARTIFACTS/customization-size-step-key.txt" 2>&1 ||
        fail "could not send $_ccs_step_key to the focused icon-size slider"
    sleep 1
    capture_ui_xml customization-size-changed.xml ||
        fail "icon-size changed XML capture failed"
    _ccs_slider=$(ui_top_slider_bounds "$ARTIFACTS/customization-size-changed.xml")
    _ccs_percent=$(ui_slider_percent "$ARTIFACTS/customization-size-changed.xml" "$_ccs_slider")
    [ -n "$_ccs_percent" ] ||
        fail "the icon-size slider percentage was unresolved after one keyboard step"
    [ "$_ccs_percent" = "$_ccs_expected_percent" ] ||
        fail "one keyboard step changed the icon-size percentage to '$_ccs_percent', expected '$_ccs_expected_percent'"
    _ccs_delta=$((_ccs_initial_percent - _ccs_percent))
    [ "$_ccs_delta" -eq 10 ] || [ "$_ccs_delta" -eq -10 ] ||
        fail "the icon-size keyboard step changed the percentage by $_ccs_delta, not exactly 10"
    capture_screenshot_to customization-size-changed.png

    return_home customization-size-changed
    sleep 1
    capture_ui_xml customization-home-after-size.xml ||
        fail "HOME XML after the icon-size change capture failed"
    capture_screenshot_to customization-home-after-size.png
    [ -s "$ARTIFACTS/customization-home-after-size.png" ] ||
        fail "HOME screenshot after the icon-size change capture failed"
    primary_home_is_ready "$ARTIFACTS/customization-home-after-size.xml" ||
        fail "the icon-size change did not leave the primary HOME intact"

    if ! _ccs_out=$(adb_cmd shell am start -W -f 0x18000000 \
        -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
        printf '%s\n' "$_ccs_out" \
            > "$ARTIFACTS/customization-size-reopen-launch.txt"
        fail "could not reopen Settings to prove the icon-size persistence"
    fi
    printf '%s\n' "$_ccs_out" > "$ARTIFACTS/customization-size-reopen-launch.txt"
    printf '%s\n' "$_ccs_out" | grep -q 'Status: ok' ||
        fail "reopened Settings for the icon-size persistence did not report Status: ok"
    sleep 2
    capture_ui_xml customization-size-reopen-dashboard.xml ||
        fail "icon-size reopen dashboard XML capture failed"
    _ccs_category=$(ui_unique_clickable_label_bounds \
        "$ARTIFACTS/customization-size-reopen-dashboard.xml" 'Icon size and home screen')
    [ -n "$_ccs_category" ] ||
        fail "the reopened icon-size dashboard lost the unique measured category"
    tap_center_of_bounds "$_ccs_category" ||
        fail "could not tap the measured icon-size category after reopening"
    _ccs_home_xml=
    _ccs_poll=1
    while [ "$_ccs_poll" -le 8 ]; do
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-size-reopen-attempt-$_ccs_poll.xml"
        if capture_ui_xml "customization-size-reopen-attempt-$_ccs_poll.xml"; then
            _ccs_slider=$(ui_top_slider_bounds "$_ccs_candidate")
            _ccs_percent=$(ui_slider_percent "$_ccs_candidate" "$_ccs_slider")
            if [ -n "$_ccs_slider" ] && [ -n "$_ccs_percent" ]; then
                _ccs_home_xml=$_ccs_candidate
                break
            fi
        fi
        _ccs_poll=$((_ccs_poll + 1))
    done
    [ -n "$_ccs_home_xml" ] ||
        fail "the reopened icon-size screen exposed no actual top SeekBar with a percentage"
    cp "$_ccs_home_xml" "$ARTIFACTS/customization-size-reopen.xml"
    capture_screenshot_to customization-size-reopen.png
    [ "$_ccs_percent" = "$_ccs_expected_percent" ] ||
        fail "the persisted icon-size percentage reopened as '$_ccs_percent', expected '$_ccs_expected_percent'"

    _ccs_focused=
    _ccs_tab=0
    while [ "$_ccs_tab" -lt 12 ]; do
        _ccs_tab=$((_ccs_tab + 1))
        adb_cmd shell input keyevent KEYCODE_TAB \
            > "$ARTIFACTS/customization-size-restore-tab-$_ccs_tab.txt" 2>&1 ||
            fail "could not send restore TAB $_ccs_tab for the icon-size slider"
        sleep 1
        _ccs_candidate="$ARTIFACTS/customization-size-restore-tab-$_ccs_tab.xml"
        if capture_ui_xml "customization-size-restore-tab-$_ccs_tab.xml"; then
            _ccs_focused=$(ui_focused_slider_bounds "$_ccs_candidate")
            if [ -n "$_ccs_focused" ]; then
                break
            fi
        fi
    done
    [ -n "$_ccs_focused" ] ||
        fail "no actual focused SeekBar appeared for the bounded restore TAB search"
    [ "$_ccs_focused" = "$_ccs_slider" ] ||
        fail "restore TAB focused $_ccs_focused instead of the actual top icon-size slider $_ccs_slider"
    adb_cmd shell input keyevent "$_ccs_restore_key" \
        > "$ARTIFACTS/customization-size-restore-key.txt" 2>&1 ||
        fail "could not send $_ccs_restore_key to restore the icon-size slider"
    sleep 1
    capture_ui_xml customization-size-restored.xml ||
        fail "icon-size restored XML capture failed"
    _ccs_restored_slider=$(ui_top_slider_bounds "$ARTIFACTS/customization-size-restored.xml")
    _ccs_restored_percent=$(ui_slider_percent "$ARTIFACTS/customization-size-restored.xml" "$_ccs_restored_slider")
    [ "$_ccs_restored_percent" = "$_ccs_initial_percent" ] ||
        fail "the reverse keyboard step restored '$_ccs_restored_percent', expected '$_ccs_initial_percent'"
    capture_screenshot_to customization-size-restored.png

    return_home customization-size-restored
    sleep 1
    capture_ui_xml customization-home-size-restored.xml ||
        fail "HOME XML after the icon-size restore capture failed"
    capture_screenshot_to customization-home-size-restored.png
    [ -s "$ARTIFACTS/customization-home-size-restored.png" ] ||
        fail "HOME screenshot after the icon-size restore capture failed"
    primary_home_is_ready "$ARTIFACTS/customization-home-size-restored.xml" ||
        fail "the icon-size restore did not leave the primary HOME intact"
    ui_widget_host_bounds "$ARTIFACTS/customization-home-size-restored.xml" \
        > "$ARTIFACTS/customization-widget-host-bounds-restored.txt"
    [ -s "$ARTIFACTS/customization-widget-host-bounds-restored.txt" ] ||
        fail "the restored HOME exposed no measured widget-host bounds"
    tr -d '\r' < "$ARTIFACTS/customization-widget-host-bounds-baseline.txt" |
        sort > "$ARTIFACTS/customization-widget-host-bounds-baseline.sorted"
    tr -d '\r' < "$ARTIFACTS/customization-widget-host-bounds-restored.txt" |
        sort > "$ARTIFACTS/customization-widget-host-bounds-restored.sorted"
    cmp -s "$ARTIFACTS/customization-widget-host-bounds-baseline.sorted" \
        "$ARTIFACTS/customization-widget-host-bounds-restored.sorted" ||
        fail "the icon-size round-trip changed the measured HOME widget-host bounds"
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/customization-appwidget-restored.txt" 2>&1 || true
    appwidget_launcher_instances "$ARTIFACTS/customization-appwidget-restored.txt" "$PKG" \
        > "$ARTIFACTS/customization-appwidget-instances-restored.txt"
    sort "$ARTIFACTS/customization-appwidget-instances-restored.txt" \
        > "$ARTIFACTS/customization-appwidget-instances-restored.sorted"
    cmp -s "$ARTIFACTS/customization-appwidget-instances-baseline.sorted" \
        "$ARTIFACTS/customization-appwidget-instances-restored.sorted" ||
        fail "the icon-size round-trip changed the launcher widget bindings"
    adb_cmd shell dumpsys wallpaper \
        > "$ARTIFACTS/customization-wallpaper-restored.txt" 2>&1 || true
    _ccs_wall_ids_restored=$(wallpaper_ids_from_dump \
        "$ARTIFACTS/customization-wallpaper-restored.txt" 0) ||
        fail "could not parse the restored Home/Lock wallpaper IDs"
    [ "$_ccs_wall_ids_restored" = "$_ccs_wall_ids_baseline" ] ||
        fail "the icon-size round-trip changed the Home/Lock wallpaper IDs"
    _ccs_wall_component_restored=$(wallpaper_component_from_dump \
        "$ARTIFACTS/customization-wallpaper-restored.txt")
    [ "$_ccs_wall_component_restored" = "$_ccs_wall_component_baseline" ] ||
        fail "the icon-size round-trip changed the active wallpaper component"
    printf 'ids=%s component=%s\n' \
        "$_ccs_wall_ids_restored" "${_ccs_wall_component_restored:-none}" \
        > "$ARTIFACTS/customization-wallpaper-restored-summary.txt"
    adb_cmd shell run-as "$PKG" cat shared_prefs/com.android.launcher3.prefs.xml \
        > "$ARTIFACTS/customization-prefs-restored.xml" 2>/dev/null || true
    adb_cmd shell run-as "$PKG" cat files/datastore/preferences.preferences_pb \
        > "$ARTIFACTS/customization-datastore-restored.pb" 2>/dev/null || true
    if grep -aq 'lock_home_screen' "$ARTIFACTS/customization-datastore-restored.pb"; then
        printf 'lock_home_screen_marker=present (presence only; value not proven)\n' \
            > "$ARTIFACTS/customization-homelock-restored.txt"
    else
        printf 'lock_home_screen_marker=unavailable\n' \
            > "$ARTIFACTS/customization-homelock-restored.txt"
    fi
    {
        printf 'home_lock_source=datastore-if-available\n'
        adb_cmd shell run-as "$PKG" ls -l databases files/datastore \
            2>&1 || true
    } > "$ARTIFACTS/customization-private-files-restored.txt"
    printf 'Customization: real dashboard category and Browse widgets were measured; the native picker opened only on explicit taps, Back/HOME repeated without it, and no binding changed. Actual top SeekBar %s%% -> %s%% -> %s%% via one keyboard step and one reverse step; HOME before/after PNGs are retained for pixel review. The restored HOME widget-host bounds and the Home/Lock wallpaper IDs plus normalized System wallpaper component were compared to the baseline. The lock_home_screen datastore entry is a presence marker only and is NOT a value-preservation proof.\n' \
        "$_ccs_initial_percent" "$_ccs_expected_percent" "$_ccs_restored_percent" \
        > "$ARTIFACTS/customization.txt"
    printf 'Screenshots: customization-home-baseline.png, customization-home-screen.png, customization-picker.png, customization-picker-second.png, customization-home-after-size.png, customization-home-size-restored.png.\n' \
        >> "$ARTIFACTS/customization.txt"
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
# real display area (insets included), the lowest labelled row gives the dock
# band and the QSB container bounds the gutter below it. Fall back to measured
# wm size only when the hierarchy is unavailable.
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
        dock_bottom=$(ui_dock_bottom "$xml" "$root")
        qsb_top=$(ui_qsb_top "$xml" "$dock_bottom")
    else
        origin_x=0
        origin_y=0
        width=$fallback_width
        height=$fallback_height
        dock_top=
        dock_bottom=
        qsb_top=
    fi
    target=$(drawer_swipe_target \
        "$width" "$height" "$dock_top" "$dock_bottom" "$qsb_top") || return 1
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
    # adb delivers move samples over the swipe duration. The 500 ms gesture was
    # observed with only a partial displacement, so use a bounded 1500 ms
    # gesture and record it with every attempt.
    swipe_duration=1500
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
        printf 'attempt=%s start=%s,%s end=%s,%s duration=%s\n' \
            "$attempt" "$1" "$2" "$3" "$4" "$swipe_duration" \
            >> "$ARTIFACTS/appdrawer-swipe-log.txt"
        adb_cmd shell input swipe "$1" "$2" "$3" "$4" "$swipe_duration" \
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
        capture_drawer_trace "$attempt"
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

# Capture the real drawer at mid-scroll and at the true end of the list, then
# prove the final app row can be brought entirely above the measured navigation
# bar. The navigation bar is a separate SystemUI window, so its bounds come from
# `dumpsys window`, never a guessed phone height. Scrolling is bounded and stops
# only when the visible app-row signature stops changing.
capture_drawer_bottom_boundary() {
    open_app_drawer
    capture_ui_xml appdrawer-bottom-start.xml ||
        fail "could not capture the opened app drawer for the bottom-boundary check"
    capture_screenshot_to appdrawer-bottom-start.png
    [ -s "$ARTIFACTS/appdrawer-bottom-start.png" ] ||
        fail "app drawer bottom-boundary start screenshot capture failed"

    adb_cmd shell dumpsys window windows \
        > "$ARTIFACTS/appdrawer-navigation-window.txt" 2>&1 || true
    adb_cmd shell dumpsys window displays \
        >> "$ARTIFACTS/appdrawer-navigation-window.txt" 2>&1 || true
    _cdbb_nav=$(ui_navigation_bar_bounds "$ARTIFACTS/appdrawer-navigation-window.txt")
    [ -n "$_cdbb_nav" ] ||
        fail "could not measure the navigation bar bounds from dumpsys window"
    set -- $_cdbb_nav
    _cdbb_nav_top=$2
    printf 'navigation=%s navigation_top=%s\n' "$_cdbb_nav" "$_cdbb_nav_top" \
        > "$ARTIFACTS/appdrawer-navigation-bounds.txt"

    _cdbb_list=$(drawer_list_bounds "$ARTIFACTS/appdrawer-bottom-start.xml")
    [ -n "$_cdbb_list" ] || fail "could not measure the app drawer list bounds"
    printf 'list=%s\n' "$_cdbb_list" >> "$ARTIFACTS/appdrawer-navigation-bounds.txt"

    _cdbb_target=$(drawer_scroll_swipe_target "$_cdbb_list" "$_cdbb_nav_top") ||
        fail "could not compute a safe drawer scroll above the navigation bar"
    set -- $_cdbb_target
    adb_cmd shell input swipe "$1" "$2" "$3" "$4" 600 \
        > "$ARTIFACTS/appdrawer-scroll-mid.txt" 2>&1 ||
        fail "could not scroll the app drawer to the mid-scroll capture"
    sleep 1
    capture_ui_xml appdrawer-mid-scroll.xml ||
        fail "app drawer mid-scroll UI XML capture failed"
    capture_screenshot_to appdrawer-mid-scroll.png
    [ -s "$ARTIFACTS/appdrawer-mid-scroll.png" ] ||
        fail "app drawer mid-scroll screenshot capture failed"

    _cdbb_previous=$(drawer_scroll_signature \
        "$ARTIFACTS/appdrawer-mid-scroll.xml" "$_cdbb_list")
    _cdbb_attempt=1
    _cdbb_max=6
    while [ "$_cdbb_attempt" -le "$_cdbb_max" ]; do
        adb_cmd shell input swipe "$1" "$2" "$3" "$4" 600 \
            > "$ARTIFACTS/appdrawer-scroll-end-$_cdbb_attempt.txt" 2>&1 ||
            fail "could not scroll the app drawer toward the end of the list"
        sleep 1
        capture_ui_xml "appdrawer-end-attempt-$_cdbb_attempt.xml" ||
            fail "app drawer end-of-list UI XML capture failed"
        _cdbb_current=$(drawer_scroll_signature \
            "$ARTIFACTS/appdrawer-end-attempt-$_cdbb_attempt.xml" "$_cdbb_list")
        cp "$ARTIFACTS/appdrawer-end-attempt-$_cdbb_attempt.xml" \
            "$ARTIFACTS/appdrawer-end.xml"
        capture_screenshot_to appdrawer-end.png
        [ -s "$ARTIFACTS/appdrawer-end.png" ] ||
            fail "app drawer end-of-list screenshot capture failed"
        if [ "$_cdbb_current" = "$_cdbb_previous" ]; then
            printf 'end reached after %s bounded swipe(s)\n' "$_cdbb_attempt" \
                >> "$ARTIFACTS/appdrawer-navigation-bounds.txt"
            break
        fi
        _cdbb_previous=$_cdbb_current
        _cdbb_attempt=$((_cdbb_attempt + 1))
    done
    [ "$_cdbb_attempt" -le "$_cdbb_max" ] ||
        fail "the app drawer did not reach a stable end after $_cdbb_max bounded swipes"

    _cdbb_last=$(drawer_last_row_bounds "$ARTIFACTS/appdrawer-end.xml" "$_cdbb_list")
    [ -n "$_cdbb_last" ] ||
        fail "could not measure the final app drawer row above the navigation bar"
    set -- $_cdbb_last
    _cdbb_last_bottom=$4
    [ "$_cdbb_last_bottom" -le "$_cdbb_nav_top" ] ||
        fail "the final app drawer row bottom $_cdbb_last_bottom is below the navigation bar top $_cdbb_nav_top"
    printf 'last_row=%s navigation_top=%s\n' "$_cdbb_last" "$_cdbb_nav_top" \
        >> "$ARTIFACTS/appdrawer-navigation-bounds.txt"
    printf 'Drawer bottom boundary: mid-scroll and end-of-list captured; final row %s is above navigation top %s.\n' \
        "$_cdbb_last" "$_cdbb_nav_top" > "$ARTIFACTS/appdrawer-bottom.txt"
    return_home drawer-bottom
}

# Open the real Home screen grid preferences through the existing
# lawnchair://settings/home-screen-grid deep link and the existing
# PreferenceActivity. This is read-only: no slider is moved, Apply must still be
# disabled, and the smoke never taps Apply.
capture_grid_settings() {
    _cgs_url='lawnchair://settings/home-screen-grid'
    _cgs_component="$PKG/$PREFERENCES_ACTIVITY"
    if ! _cgs_out=$(adb_cmd shell am start -W \
        -a android.intent.action.VIEW \
        -d "$_cgs_url" \
        -n "$_cgs_component" 2>&1); then
        printf '%s\n' "$_cgs_out" > "$ARTIFACTS/grid-settings-launch.txt"
        fail "could not open the Home screen grid settings deep link"
    fi
    printf '%s\n' "$_cgs_out" > "$ARTIFACTS/grid-settings-launch.txt"
    case "$_cgs_out" in
        *"Error:"* | *"Error type"* | *Exception*)
            fail "Home screen grid deep link launch reported an error"
            ;;
    esac
    printf '%s\n' "$_cgs_out" | grep -q 'Status: ok' ||
        fail "Home screen grid deep link launch did not report Status: ok"
    _cgs_attempt=1
    _cgs_ready=0
    while [ "$_cgs_attempt" -le 6 ]; do
        sleep 1
        if capture_ui_xml "grid-settings-attempt-$_cgs_attempt.xml" &&
            grid_settings_is_ready "$ARTIFACTS/grid-settings-attempt-$_cgs_attempt.xml"; then
            cp "$ARTIFACTS/grid-settings-attempt-$_cgs_attempt.xml" \
                "$ARTIFACTS/grid-settings.xml"
            _cgs_ready=1
            break
        fi
        _cgs_attempt=$((_cgs_attempt + 1))
    done
    if [ "$_cgs_ready" -ne 1 ]; then
        _cgs_last=$((_cgs_attempt - 1))
        capture_screenshot_to "grid-settings-attempt-$_cgs_last.png"
        fail "Home screen grid settings did not expose the preview, Columns/Rows/Dock icons and Apply"
    fi
    capture_screenshot_to grid-settings.png
    [ -s "$ARTIFACTS/grid-settings.png" ] ||
        fail "Home screen grid settings screenshot capture failed"
    grid_apply_is_unchanged "$ARTIFACTS/grid-settings.xml" ||
        fail "Home screen grid Apply is enabled, so the read-only grid check cannot prove no change was applied"
    printf 'Grid settings: preview, Columns, Rows, Dock icons and Apply are visible; Apply is disabled, so no grid change was applied.\n' \
        > "$ARTIFACTS/grid-settings.txt"
    printf 'Screenshots: grid-settings.png.\n' >> "$ARTIFACTS/grid-settings.txt"
    return_home grid-settings
    verify_nothing_home
}

# Resolve a Settings action through the installed platform, falling back to the
# top-level Settings action exactly as the device widget does. Prints
# "<action><TAB><component>"; never guesses an activity alias.
resolve_settings_action_component() (
    action=$1
    for candidate in "$action" android.settings.SETTINGS; do
        out=$(adb_cmd shell cmd package resolve-activity --brief -a "$candidate" \
            2>&1 | tr -d '\r' || true)
        component=$(parse_resolved_component "$out")
        if [ -n "$component" ]; then
            printf '%s\t%s\n' "$candidate" "$component"
            return 0
        fi
    done
    return 1
)

# Tap each real device-card Settings pill at its measured child bounds, prove the
# resulting platform-resolved Settings destination is foreground, capture the
# activity UI, return HOME and require all three own widget ids to be unchanged.
# No setting is changed and no widget is rebound.
exercise_device_settings_shortcuts() {
    capture_ui_xml device-settings-before.xml ||
        fail "could not capture HOME before the device Settings shortcuts"
    capture_screenshot_to device-settings-before.png
    [ -s "$ARTIFACTS/device-settings-before.png" ] ||
        fail "device Settings before screenshot capture failed"
    adb_cmd shell dumpsys appwidget \
        > "$ARTIFACTS/device-settings-appwidget-before.txt" 2>&1 || true
    appwidget_launcher_instances \
        "$ARTIFACTS/device-settings-appwidget-before.txt" "$PKG" \
        > "$ARTIFACTS/device-settings-instances-before.txt"
    _eds_clock_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelClockWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/device-settings-instances-before.txt")
    _eds_battery_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelBatteryWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/device-settings-instances-before.txt")
    _eds_device_id=$(awk -F '\t' \
        '$2 ~ /app\.dotwel\.widgets\.DotWelDeviceWidgetProvider}/ { print $1; exit }' \
        "$ARTIFACTS/device-settings-instances-before.txt")
    [ -n "$_eds_clock_id" ] && [ -n "$_eds_battery_id" ] && [ -n "$_eds_device_id" ] ||
        fail "the device Settings check could not find all three launcher-owned widget ids"
    [ "$_eds_clock_id" != "$_eds_battery_id" ] &&
        [ "$_eds_device_id" != "$_eds_clock_id" ] &&
        [ "$_eds_device_id" != "$_eds_battery_id" ] ||
        fail "the three own widget ids are not distinct before the device Settings check"
    : > "$ARTIFACTS/device-settings-log.txt"

    for _eds_action in wifi sound display; do
        case "$_eds_action" in
            wifi) _eds_intent=android.settings.WIFI_SETTINGS ;;
            sound) _eds_intent=android.settings.SOUND_SETTINGS ;;
            display) _eds_intent=android.settings.DISPLAY_SETTINGS ;;
        esac
        _eds_bounds=$(home_widget_device_action_bounds \
            "$ARTIFACTS/device-settings-before.xml" "$_eds_action")
        [ -n "$_eds_bounds" ] ||
            fail "the device card does not expose measured $_eds_action child bounds"
        _eds_resolved=$(resolve_settings_action_component "$_eds_intent") ||
            fail "the installed platform resolved neither $_eds_intent nor the top-level Settings fallback"
        _eds_expected_action=${_eds_resolved%%	*}
        _eds_expected_component=${_eds_resolved#*	}
        _eds_expected_pkg=${_eds_expected_component%%/*}
        _eds_expected_cls=${_eds_expected_component#*/}
        printf 'action=%s bounds=%s expected_action=%s expected_component=%s\n' \
            "$_eds_action" "$_eds_bounds" "$_eds_expected_action" \
            "$_eds_expected_component" >> "$ARTIFACTS/device-settings-log.txt"
        tap_center_of_bounds "$_eds_bounds" ||
            fail "could not tap the measured device $_eds_action pill"
        _eds_activities="$ARTIFACTS/activities-device-settings-$_eds_action.txt"
        wait_for_foreground com.android.settings "$_eds_activities" 15 ||
            fail "the device $_eds_action shortcut did not foreground Settings"
        capture_ui_xml "device-settings-$_eds_action.xml" ||
            fail "could not capture the device $_eds_action Settings UI"
        capture_screenshot_to "device-settings-$_eds_action.png"
        [ -s "$ARTIFACTS/device-settings-$_eds_action.png" ] ||
            fail "device $_eds_action Settings screenshot capture failed"
        foreground_is_component \
            "$_eds_activities" "$_eds_expected_pkg" "$_eds_expected_cls" ||
            fail "the device $_eds_action shortcut opened '$(resumed_component "$_eds_activities")', expected the platform-resolved '$_eds_expected_component'"
        grep -Fq 'package="com.android.settings"' \
            "$ARTIFACTS/device-settings-$_eds_action.xml" ||
            fail "the device $_eds_action destination UI is not the Settings package"
        printf 'actual_component=%s ui=device-settings-%s.xml\n' \
            "$(resumed_component "$_eds_activities")" "$_eds_action" \
            >> "$ARTIFACTS/device-settings-log.txt"

        return_home "device-settings-$_eds_action"
        _eds_home_xml="$ARTIFACTS/device-settings-home-$_eds_action.xml"
        capture_ui_xml "device-settings-home-$_eds_action.xml" ||
            fail "could not capture HOME after the device $_eds_action shortcut"
        capture_screenshot_to "device-settings-home-$_eds_action.png"
        [ -n "$(home_widget_device_action_bounds "$_eds_home_xml" "$_eds_action")" ] ||
            fail "the device card $_eds_action pill is not visible after returning HOME"
        adb_cmd shell dumpsys appwidget \
            > "$ARTIFACTS/device-settings-appwidget-after-$_eds_action.txt" 2>&1 || true
        appwidget_launcher_instances \
            "$ARTIFACTS/device-settings-appwidget-after-$_eds_action.txt" "$PKG" \
            > "$ARTIFACTS/device-settings-instances-after-$_eds_action.txt"
        _eds_clock_after=$(awk -F '\t' \
            '$2 ~ /app\.dotwel\.widgets\.DotWelClockWidgetProvider}/ { print $1; exit }' \
            "$ARTIFACTS/device-settings-instances-after-$_eds_action.txt")
        _eds_battery_after=$(awk -F '\t' \
            '$2 ~ /app\.dotwel\.widgets\.DotWelBatteryWidgetProvider}/ { print $1; exit }' \
            "$ARTIFACTS/device-settings-instances-after-$_eds_action.txt")
        _eds_device_after=$(awk -F '\t' \
            '$2 ~ /app\.dotwel\.widgets\.DotWelDeviceWidgetProvider}/ { print $1; exit }' \
            "$ARTIFACTS/device-settings-instances-after-$_eds_action.txt")
        [ "$_eds_clock_after" = "$_eds_clock_id" ] &&
            [ "$_eds_battery_after" = "$_eds_battery_id" ] &&
            [ "$_eds_device_after" = "$_eds_device_id" ] ||
            fail "a launcher-owned widget id changed after the device $_eds_action shortcut (clock=$_eds_clock_after battery=$_eds_battery_after device=$_eds_device_after)"
        printf 'returned_home=1 ids=%s,%s,%s\n' \
            "$_eds_clock_after" "$_eds_battery_after" "$_eds_device_after" \
            >> "$ARTIFACTS/device-settings-log.txt"
    done
    printf 'Device settings: the three measured device-card pills opened the platform-resolved Settings destinations, each Settings UI was captured, HOME was restored without changing a setting, and all three own widget ids stayed distinct and unchanged.\n' \
        > "$ARTIFACTS/device-settings.txt"
    printf 'Screenshots: device-settings-before.png, device-settings-wifi.png, device-settings-sound.png, device-settings-display.png, device-settings-home-*.png.\n' \
        >> "$ARTIFACTS/device-settings.txt"
}

# Search up to three measured HOME page advances for the newly placed provider,
# identified by the picker-selected label and a real workspace host, and never
# by geometry alone. The caller must have already verified the launcher is
# resumed and the new launcher-owned AppWidgetId is bound. An open bind consent
# or a configuration activity stops the search before any swipe. Results are
# returned in _cwp_search_page, _cwp_search_bounds and _cwp_search_xml; every
# page advance saves XML/PNG plus a line in the page log.
search_home_pages_for_widget() {
    _shw_label=$1
    _shw_ref=$2
    _shw_xml=$3
    _shw_prefix=$4
    _shw_log=$5
    _shw_page=0
    _shw_bounds=$(home_widget_bounds "$_shw_xml" "$_shw_ref" "$_shw_label")
    printf 'page=%s xml=%s bounds=%s\n'         "$_shw_page" "$_shw_xml" "${_shw_bounds:-none}" >> "$_shw_log"
    while [ -z "$_shw_bounds" ] && [ "$_shw_page" -lt 3 ]; do
        _shw_next=$((_shw_page + 1))
        adb_cmd shell dumpsys activity activities \
            > "$ARTIFACTS/$_shw_prefix-activities-$_shw_next.txt" 2>&1 || true
        if ! foreground_is_component \
            "$ARTIFACTS/$_shw_prefix-activities-$_shw_next.txt" \
            "$PKG" "$LAUNCHER_ACTIVITY"; then
            printf 'page=%s stopped=launcher-not-resumed\n' "$_shw_page" \
                >> "$_shw_log"
            return 1
        fi
        # A bind consent or configuration activity is not the launcher, so the
        # exact resumed-component check above is the consent guard. Never swipe
        # while any other activity owns the foreground.
        _shw_swipe=$(workspace_page_swipe "$_shw_xml" next)
        if [ -z "$_shw_swipe" ]; then
            printf 'page=%s stopped=no-safe-page-swipe\n' "$_shw_page" \
                >> "$_shw_log"
            return 1
        fi
        set -- $_shw_swipe
        printf 'page=%s swipe=%s,%s,%s,%s\n' \
            "$_shw_next" "$1" "$2" "$3" "$4" >> "$_shw_log"
        if ! adb_cmd shell input swipe "$1" "$2" "$3" "$4" 500 \
            > "$ARTIFACTS/$_shw_prefix-swipe-$_shw_next.txt" 2>&1; then
            printf 'page=%s stopped=swipe-failed\n' "$_shw_page" \
                >> "$_shw_log"
            return 1
        fi
        sleep 1
        _shw_page=$_shw_next
        _shw_xml="$ARTIFACTS/$_shw_prefix-page-$_shw_page.xml"
        if ! capture_ui_xml "$_shw_prefix-page-$_shw_page.xml"; then
            printf 'page=%s stopped=capture-failed\n' "$_shw_page" \
                >> "$_shw_log"
            return 1
        fi
        capture_screenshot_to "$_shw_prefix-page-$_shw_page.png"
        _shw_bounds=$(home_widget_bounds "$_shw_xml" "$_shw_ref" "$_shw_label")
        printf 'page=%s xml=%s bounds=%s\n' \
            "$_shw_page" "$_shw_xml" "${_shw_bounds:-none}" >> "$_shw_log"
    done
    if [ -z "$_shw_bounds" ]; then
        printf 'stopped=not-found-after-max-pages\n' >> "$_shw_log"
        return 1
    fi
    _cwp_search_page=$_shw_page
    _cwp_search_bounds=$_shw_bounds
    _cwp_search_xml=$_shw_xml
    return 0
}

# Long-press the empty central HOME workspace with a real gesture, open the real
# options popup, tap Widgets by its measured bounds, and require the native widget
# picker search/list. No activity is started directly and no preference is
# written. Every wait is a bounded UIAutomator readiness poll.
capture_widgets_picker() {
    : > "$ARTIFACTS/widgets-longpress-log.txt"
    _cwp_max_attempts=3
    _cwp_attempt=1
    while [ "$_cwp_attempt" -le "$_cwp_max_attempts" ]; do
        wait_for_launcher_idle "$ARTIFACTS/widgets-launcher-idle-$_cwp_attempt.txt" 10 ||
            fail "launcher was not idle before widgets long-press attempt $_cwp_attempt"
        capture_ui_xml "home-before-widgets-attempt-$_cwp_attempt.xml" ||
            fail "could not capture HOME before widgets attempt $_cwp_attempt"
        capture_screenshot_to "home-before-widgets-attempt-$_cwp_attempt.png"
        _cwp_target=$(home_longpress_target \
            "$ARTIFACTS/home-before-widgets-attempt-$_cwp_attempt.xml") ||
            fail "could not compute an empty HOME long-press target on attempt $_cwp_attempt"
        set -- $_cwp_target
        printf 'attempt=%s longpress=%s,%s duration=1000\n' \
            "$_cwp_attempt" "$1" "$2" >> "$ARTIFACTS/widgets-longpress-log.txt"
        adb_cmd shell input swipe "$1" "$2" "$1" "$2" 1000 \
            > "$ARTIFACTS/widgets-longpress-$_cwp_attempt.txt" 2>&1 ||
            fail "could not long-press the HOME workspace on attempt $_cwp_attempt"

        _cwp_popup=
        _cwp_poll=1
        while [ "$_cwp_poll" -le 6 ]; do
            sleep 1
            if capture_ui_xml "home-popup-attempt-$_cwp_attempt-$_cwp_poll.xml" &&
                home_popup_is_ready \
                    "$ARTIFACTS/home-popup-attempt-$_cwp_attempt-$_cwp_poll.xml"; then
                _cwp_popup="$ARTIFACTS/home-popup-attempt-$_cwp_attempt-$_cwp_poll.xml"
                break
            fi
            _cwp_poll=$((_cwp_poll + 1))
        done

        if [ -n "$_cwp_popup" ]; then
            cp "$_cwp_popup" "$ARTIFACTS/home-popup.xml"
            capture_screenshot_to home-popup.png
            [ -s "$ARTIFACTS/home-popup.png" ] ||
                fail "HOME long-press popup screenshot capture failed"
            _cwp_widgets_bounds=$(ui_clickable_label_bounds \
                "$ARTIFACTS/home-popup.xml" 'Widgets')
            [ -n "$_cwp_widgets_bounds" ] ||
                fail "could not find the Widgets option bounds in the real HOME popup"
            tap_center_of_bounds "$_cwp_widgets_bounds" ||
                fail "could not tap the Widgets option in the real HOME popup"

            _cwp_picker=
            _cwp_picker_poll=1
            while [ "$_cwp_picker_poll" -le 8 ]; do
                sleep 1
                if capture_ui_xml "widgets-picker-attempt-$_cwp_attempt-$_cwp_picker_poll.xml" &&
                    widget_picker_is_ready \
                        "$ARTIFACTS/widgets-picker-attempt-$_cwp_attempt-$_cwp_picker_poll.xml" \
                        "$ARTIFACTS/home-before-widgets-attempt-$_cwp_attempt.xml"; then
                    _cwp_picker="$ARTIFACTS/widgets-picker-attempt-$_cwp_attempt-$_cwp_picker_poll.xml"
                    break
                fi
                _cwp_picker_poll=$((_cwp_picker_poll + 1))
            done

            if [ -n "$_cwp_picker" ]; then
                cp "$_cwp_picker" "$ARTIFACTS/widgets-picker.xml"
                capture_screenshot_to widgets-picker.png
                [ -s "$ARTIFACTS/widgets-picker.png" ] ||
                    fail "widget picker screenshot capture failed"
                _cwp_ref="$ARTIFACTS/home-before-widgets-attempt-$_cwp_attempt.xml"
                : > "$ARTIFACTS/widgets-add-log.txt"

                # P10b: add a real third-party widget through the native picker,
                # then prove it survives HOME. Select a provider header that
                # reports a real widget, never a shortcut-only row.
                #
                # A picker row can sit at the bottom with its preview clipped
                # under the navigation bar (CI114: 51 px visible). Bring the
                # provider into the measured viewport before selecting it: the
                # real search input first, then a bounded genuine scroll inside
                # the measured widget list. A clipped preview is never tapped,
                # even when its resource id is valid.
                _cwp_picker_xml="$ARTIFACTS/widgets-picker.xml"
                _cwp_search_input=$(widget_picker_search_bar_bounds "$_cwp_picker_xml")
                if [ -n "$_cwp_search_input" ]; then
                    tap_center_of_bounds "$_cwp_search_input" ||
                        fail "could not focus the native widget picker search input"
                    adb_cmd shell input text Clock \
                        >> "$ARTIFACTS/widgets-add-log.txt" 2>&1 ||
                        fail "could not type Clock into the native widget picker search"
                    _cwp_search=
                    _cwp_search_poll=1
                    while [ "$_cwp_search_poll" -le 6 ]; do
                        sleep 1
                        if capture_ui_xml \
                            "widgets-search-$_cwp_search_poll.xml" &&
                            [ -n "$(widget_picker_provider_bounds \
                                "$ARTIFACTS/widgets-search-$_cwp_search_poll.xml" Clock)" ]; then
                            _cwp_search="$ARTIFACTS/widgets-search-$_cwp_search_poll.xml"
                            break
                        fi
                        _cwp_search_poll=$((_cwp_search_poll + 1))
                    done
                    if [ -n "$_cwp_search" ]; then
                        cp "$_cwp_search" "$ARTIFACTS/widgets-search.xml"
                        _cwp_picker_xml="$ARTIFACTS/widgets-search.xml"
                        printf 'search=Clock results=%s\n' "$_cwp_search" \
                            >> "$ARTIFACTS/widgets-add-log.txt"
                    else
                        # Clear the failed query so the measured list is usable
                        # again; the cursor is at the end after input text.
                        printf 'search=Clock no-matching-header; clearing and using the measured list\n' \
                            >> "$ARTIFACTS/widgets-add-log.txt"
                        _cwp_clear=0
                        while [ "$_cwp_clear" -lt 8 ]; do
                            adb_cmd shell input keyevent KEYCODE_DEL \
                                >> "$ARTIFACTS/widgets-add-log.txt" 2>&1 || true
                            _cwp_clear=$((_cwp_clear + 1))
                        done
                        sleep 1
                        if capture_ui_xml widgets-picker-cleared.xml; then
                            _cwp_picker_xml="$ARTIFACTS/widgets-picker-cleared.xml"
                        fi
                    fi
                fi

                _cwp_provider_title=
                _cwp_header=
                _cwp_preview=
                _cwp_provider_xml=
                _cwp_expand=0
                _cwp_scroll=0
                _cwp_max_scrolls=3
                _cwp_selected=0
                while [ "$_cwp_selected" -eq 0 ]; do
                    _cwp_candidate_expand=
                    for _cwp_title in Clock Calendar; do
                        _cwp_candidate_header=$(widget_picker_provider_bounds \
                            "$_cwp_picker_xml" "$_cwp_title")
                        [ -n "$_cwp_candidate_header" ] || continue
                        _cwp_candidate_preview=$(widget_picker_preview_bounds \
                            "$_cwp_picker_xml" "$_cwp_candidate_header")
                        _cwp_candidate_viewport=$(widget_picker_viewport_bounds \
                            "$_cwp_picker_xml")
                        if widget_picker_preview_is_visible \
                            "$_cwp_candidate_preview" "$_cwp_candidate_viewport"; then
                            _cwp_provider_title=$_cwp_title
                            _cwp_header=$_cwp_candidate_header
                            _cwp_preview=$_cwp_candidate_preview
                            _cwp_provider_xml=$_cwp_picker_xml
                            _cwp_selected=1
                            break
                        fi
                        if [ -z "$_cwp_candidate_preview" ] &&
                            [ -z "$_cwp_candidate_expand" ]; then
                            _cwp_candidate_expand="$_cwp_title $_cwp_candidate_header"
                        fi
                    done
                    if [ "$_cwp_selected" -eq 1 ]; then
                        break
                    fi

                    # No fully visible preview. If a provider is still collapsed,
                    # expand it and re-resolve. A clipped preview is never
                    # re-tapped because that would collapse it.
                    if [ -n "$_cwp_candidate_expand" ] && [ "$_cwp_expand" -lt 2 ]; then
                        set -- $_cwp_candidate_expand
                        _cwp_expand_title=$1
                        shift
                        _cwp_expand_header="$*"
                        tap_center_of_bounds "$_cwp_expand_header" ||
                            fail "could not tap the measured $_cwp_expand_title provider header"
                        _cwp_expand=$((_cwp_expand + 1))
                        _cwp_expand_poll=1
                        while [ "$_cwp_expand_poll" -le 5 ]; do
                            sleep 1
                            if capture_ui_xml \
                                "widgets-provider-$_cwp_expand-$_cwp_expand_poll.xml"; then
                                _cwp_candidate_xml="$ARTIFACTS/widgets-provider-$_cwp_expand-$_cwp_expand_poll.xml"
                                _cwp_candidate_header=$(widget_picker_provider_bounds \
                                    "$_cwp_candidate_xml" "$_cwp_expand_title")
                                if [ -n "$_cwp_candidate_header" ]; then
                                    _cwp_picker_xml=$_cwp_candidate_xml
                                    break
                                fi
                            fi
                            _cwp_expand_poll=$((_cwp_expand_poll + 1))
                        done
                        continue
                    fi

                    # Still clipped or off-screen: one bounded genuine scroll
                    # inside the measured widget list, then re-resolve.
                    if [ "$_cwp_scroll" -ge "$_cwp_max_scrolls" ]; then
                        break
                    fi
                    _cwp_scroll_target=$(widget_picker_scroll_target "$_cwp_picker_xml") ||
                        break
                    set -- $_cwp_scroll_target
                    printf 'scroll=%s from=%s,%s to=%s,%s\n' \
                        "$((_cwp_scroll + 1))" "$1" "$2" "$1" "$3" \
                        >> "$ARTIFACTS/widgets-add-log.txt"
                    adb_cmd shell input swipe "$1" "$2" "$1" "$3" 600 \
                        >> "$ARTIFACTS/widgets-add-log.txt" 2>&1 ||
                        fail "could not scroll the measured native widget list"
                    _cwp_scroll=$((_cwp_scroll + 1))
                    sleep 1
                    if ! capture_ui_xml "widgets-scroll-$_cwp_scroll.xml"; then
                        break
                    fi
                    _cwp_picker_xml="$ARTIFACTS/widgets-scroll-$_cwp_scroll.xml"
                done

                if [ "$_cwp_selected" -eq 0 ]; then
                    capture_ui_xml widgets-add-last.xml || true
                    capture_screenshot_to widgets-add-last.png
                    fail "the native widget picker exposed no Clock/Calendar provider with a fully visible preview above the navigation bar (clipped previews are rejected)"
                fi
                # Two identities: the provider/app title ("Clock") stays the
                # HOME host and page-search identity, while the consent names
                # the selected preview's own widget caption ("Analog clock").
                # Read the caption only from the actual WidgetCell that owns the
                # measured preview; never the provider header or a global
                # widget_name. A missing or ambiguous caption fails closed.
                _cwp_widget_caption=$(widget_picker_selected_caption \
                    "$_cwp_provider_xml" "$_cwp_preview")
                [ -n "$_cwp_widget_caption" ] ||
                    fail "the selected preview WidgetCell exposes no unambiguous widget_name caption; refusing to guess the bind consent identity"
                printf 'provider=%s header=%s preview=%s widget_caption=%s\n' \
                    "$_cwp_provider_title" "$_cwp_header" "$_cwp_preview" \
                    "$_cwp_widget_caption" \
                    >> "$ARTIFACTS/widgets-add-log.txt"
                cp "$_cwp_provider_xml" "$ARTIFACTS/widgets-provider.xml"
                capture_screenshot_to widgets-provider.png
                [ -s "$ARTIFACTS/widgets-provider.png" ] ||
                    fail "widget provider screenshot capture failed"
                adb_cmd shell dumpsys appwidget \
                    > "$ARTIFACTS/widgets-appwidget-before.txt" 2>&1 || true

                # Tap the fully visible preview to expose the real Add button.
                tap_center_of_bounds "$_cwp_preview" ||
                    fail "could not tap the measured widget preview"
                _cwp_add=
                _cwp_add_xml=
                _cwp_add_poll=1
                while [ "$_cwp_add_poll" -le 5 ]; do
                    sleep 1
                    if capture_ui_xml "widgets-add-attempt-$_cwp_add_poll.xml"; then
                        _cwp_candidate_xml="$ARTIFACTS/widgets-add-attempt-$_cwp_add_poll.xml"
                        _cwp_candidate_add=$(widget_picker_add_button_bounds \
                            "$_cwp_candidate_xml")
                        if [ -n "$_cwp_candidate_add" ]; then
                            _cwp_add=$_cwp_candidate_add
                            _cwp_add_xml=$_cwp_candidate_xml
                            break
                        fi
                    fi
                    _cwp_add_poll=$((_cwp_add_poll + 1))
                done
                if [ -z "$_cwp_add" ]; then
                    # No ordinary swipe fallback: a workspace drag is a different
                    # gesture from the picker's long-press drag. Fail with the
                    # captured hierarchy and PNG instead of faking it.
                    capture_ui_xml widgets-add-last.xml || true
                    capture_screenshot_to widgets-add-last.png
                    fail "the widget Add button was not exposed after tapping the fully visible preview (no fake drag fallback)"
                fi
                # The exposed Add can sit partly under the navigation bar (CI120:
                # [434,1755][645,1881], navbar from about 1800, so the original
                # centre 1818 opened Android HOME). Remeasure the viewport from
                # the same hierarchy, intersect it with the enabled clickable Add
                # and pull the tap above the navigation bar. Never tap the
                # original centre. If no safe intersection remains, scroll the
                # measured real list and re-resolve, bounded, then fail with the
                # last hierarchy and PNG instead of guessing a coordinate.
                _cwp_add_scroll=0
                _cwp_max_add_scrolls=3
                _cwp_safe_add=
                _cwp_add_viewport=
                while :; do
                    _cwp_add_viewport=$(widget_picker_viewport_bounds "$_cwp_add_xml")
                    _cwp_safe_add=$(widget_add_safe_bounds \
                        "$_cwp_add" "$_cwp_add_viewport")
                    if [ -n "$_cwp_safe_add" ]; then
                        break
                    fi
                    if [ "$_cwp_add_scroll" -ge "$_cwp_max_add_scrolls" ]; then
                        break
                    fi
                    _cwp_add_scroll_target=$(widget_picker_scroll_target \
                        "$_cwp_add_xml") || break
                    set -- $_cwp_add_scroll_target
                    printf 'add-scroll=%s from=%s,%s to=%s,%s add=%s viewport=%s\n' \
                        "$((_cwp_add_scroll + 1))" "$1" "$2" "$1" "$3" \
                        "$_cwp_add" "$_cwp_add_viewport" \
                        >> "$ARTIFACTS/widgets-add-log.txt"
                    adb_cmd shell input swipe "$1" "$2" "$1" "$3" 600 \
                        >> "$ARTIFACTS/widgets-add-log.txt" 2>&1 ||
                        fail "could not scroll the measured widget list to expose a safe Add button"
                    _cwp_add_scroll=$((_cwp_add_scroll + 1))
                    sleep 1
                    if ! capture_ui_xml \
                        "widgets-add-scroll-$_cwp_add_scroll.xml"; then
                        break
                    fi
                    _cwp_add_xml="$ARTIFACTS/widgets-add-scroll-$_cwp_add_scroll.xml"
                    _cwp_add=$(widget_picker_add_button_bounds "$_cwp_add_xml")
                    [ -n "$_cwp_add" ] || break
                done
                if [ -z "$_cwp_safe_add" ]; then
                    cp "$_cwp_add_xml" "$ARTIFACTS/widgets-add.xml" || true
                    capture_ui_xml widgets-add-last.xml || true
                    capture_screenshot_to widgets-add-last.png
                    fail "the widget Add button had no safe intersection above the navigation bar after $_cwp_add_scroll measured scroll(s) (add=$_cwp_add viewport=$_cwp_add_viewport)"
                fi
                cp "$_cwp_add_xml" "$ARTIFACTS/widgets-add.xml"
                capture_screenshot_to widgets-add.png
                [ -s "$ARTIFACTS/widgets-add.png" ] ||
                    fail "widget Add screenshot capture failed"
                printf 'route=add-button add=%s safe=%s viewport=%s scrolls=%s\n' \
                    "$_cwp_add" "$_cwp_safe_add" "$_cwp_add_viewport" \
                    "$_cwp_add_scroll" \
                    >> "$ARTIFACTS/widgets-add-log.txt"
                tap_center_of_bounds "$_cwp_safe_add" ||
                    fail "could not tap the safe widget Add intersection"

                # Wait, bounded, for the sheet to close and a real
                # AppWidgetHostView to appear in the workspace. The platform may
                # first show AllowBindAppWidgetActivity; accept only its exact
                # launcher/widget consent, tap its measured Create control and
                # keep polling. A configuration activity, a dismissed dialog or
                # an unbound provider fails with saved evidence.
                _cwp_placed=
                _cwp_placed_bounds=
                _cwp_last_xml="$ARTIFACTS/widgets-add.xml"
                _cwp_bind_tapped=0
                _cwp_place_poll=1
                while [ "$_cwp_place_poll" -le 15 ]; do
                    sleep 1
                    adb_cmd shell dumpsys activity activities \
                        > "$ARTIFACTS/activities-widget-placed-$_cwp_place_poll.txt" 2>&1 || true
                    if capture_ui_xml \
                        "widgets-home-placed-attempt-$_cwp_place_poll.xml"; then
                        _cwp_candidate_xml="$ARTIFACTS/widgets-home-placed-attempt-$_cwp_place_poll.xml"
                        _cwp_last_xml=$_cwp_candidate_xml
                        if widget_bind_consent_is_ready \
                            "$_cwp_candidate_xml" "$EXPECTED_LABEL" "$_cwp_widget_caption"; then
                            if [ "$_cwp_bind_tapped" -eq 0 ]; then
                                cp "$_cwp_candidate_xml" "$ARTIFACTS/widgets-bind-consent.xml"
                                capture_screenshot_to widgets-bind-consent.png
                                [ -s "$ARTIFACTS/widgets-bind-consent.png" ] ||
                                    fail "widget bind consent screenshot capture failed"
                                if widget_bind_always_allow_is_checked \
                                    "$ARTIFACTS/widgets-bind-consent.xml"; then
                                    fail "the widget bind consent has Always allow checked; refusing to grant permanent binding"
                                fi
                                _cwp_bind_create=$(widget_bind_create_button_bounds \
                                    "$ARTIFACTS/widgets-bind-consent.xml" \
                                    "$EXPECTED_LABEL" "$_cwp_widget_caption")
                                [ -n "$_cwp_bind_create" ] ||
                                    fail "could not find the measured android:id/button1 Create control in the widget bind consent"
                                tap_center_of_bounds "$_cwp_bind_create" ||
                                    fail "could not tap the measured Create control in the widget bind consent"
                                printf 'route=bind-consent create=%s always_allow=unchecked\n' \
                                    "$_cwp_bind_create" >> "$ARTIFACTS/widgets-add-log.txt"
                                _cwp_bind_tapped=1
                            else
                                printf 'consent=still-visible-after-create poll=%s\n' \
                                    "$_cwp_place_poll" >> "$ARTIFACTS/widgets-add-log.txt"
                            fi
                        fi
                        _cwp_candidate_bounds=$(home_widget_bounds \
                            "$_cwp_candidate_xml" "$_cwp_ref" "$_cwp_provider_title")
                        if [ -n "$_cwp_candidate_bounds" ]; then
                            _cwp_placed=$_cwp_candidate_xml
                            _cwp_placed_bounds=$_cwp_candidate_bounds
                            break
                        fi
                    fi
                    _cwp_place_poll=$((_cwp_place_poll + 1))
                done
                if [ -z "$_cwp_placed" ] && [ "$_cwp_bind_tapped" -eq 1 ]; then
                    # The denser factory HOME can push the added widget onto a
                    # later page. Only after Create has been handled, the
                    # launcher is resumed and a new launcher-owned AppWidgetId is
                    # bound may the measured normal HOME pages be searched. The
                    # helper refuses to swipe while a consent or configuration
                    # activity is open.
                    _cwp_pre_new=
                    _cwp_pre_aw=1
                    while [ "$_cwp_pre_aw" -le 5 ]; do
                        adb_cmd shell dumpsys appwidget \
                            > "$ARTIFACTS/widgets-appwidget-page-before.txt" \
                            2>&1 || true
                        _cwp_pre_new=$(appwidget_new_providers \
                            "$ARTIFACTS/widgets-appwidget-before.txt" \
                            "$ARTIFACTS/widgets-appwidget-page-before.txt" "$PKG")
                        [ -n "$_cwp_pre_new" ] && break
                        _cwp_pre_aw=$((_cwp_pre_aw + 1))
                        sleep 1
                    done
                    [ -n "$_cwp_pre_new" ] ||
                        fail "no new launcher-owned AppWidgetId was bound before HOME page discovery"
                    : > "$ARTIFACTS/widgets-page-log.txt"
                    if search_home_pages_for_widget \
                        "$_cwp_provider_title" "$_cwp_ref" "$_cwp_last_xml" \
                        widgets-placement "$ARTIFACTS/widgets-page-log.txt"; then
                        _cwp_placed=$_cwp_search_xml
                        _cwp_placed_bounds=$_cwp_search_bounds
                        printf 'placement-page=%s bounds=%s\n' \
                            "$_cwp_search_page" "$_cwp_placed_bounds" \
                            >> "$ARTIFACTS/widgets-add-log.txt"
                    else
                        capture_screenshot_to widgets-page-last.png
                        fail "the new $_cwp_provider_title widget was not found on the first three measured HOME pages after Add and consent"
                    fi
                fi
                if [ -z "$_cwp_placed" ]; then
                    cp "$_cwp_last_xml" "$ARTIFACTS/widgets-add-last.xml" \
                        2>/dev/null || true
                    capture_screenshot_to widgets-add-last.png
                    _cwp_last_activities="$ARTIFACTS/activities-widget-placed-$((_cwp_place_poll - 1)).txt"
                    _cwp_foreground=$(resumed_component "$_cwp_last_activities" \
                        2>/dev/null || true)
                    printf 'last_foreground=%s\n' "$_cwp_foreground" \
                        >> "$ARTIFACTS/widgets-add-log.txt"
                    fail "the added widget did not appear as a new workspace AppWidgetHostView (the bind consent was not completed, a widget configuration activity is open, or the provider is unbound)"
                fi
                cp "$_cwp_placed" "$ARTIFACTS/widgets-home-placed.xml"
                capture_screenshot_to widgets-home-placed.png
                [ -s "$ARTIFACTS/widgets-home-placed.png" ] ||
                    fail "placed-widget screenshot capture failed"

                # Validate the widget against the workspace/header/dock that is
                # actually visible on the page where it was found. A later page
                # may legitimately have no first-page search_container_workspace
                # header, so never inherit the reference page's header band.
                placed_widget_page_is_safe \
                    "$_cwp_placed" "$_cwp_ref" "$_cwp_provider_title" \
                    "$_cwp_placed_bounds" ||
                    fail "the placed $_cwp_provider_title widget is not a genuine workspace host inside the actual page's workspace, header and dock bounds ($_cwp_placed_bounds)"

                # The new widget id must be bound and owned by this launcher,
                # not merely an installed provider or another host's widget.
                _cwp_new_providers=
                _cwp_aw_poll=1
                while [ "$_cwp_aw_poll" -le 5 ]; do
                    adb_cmd shell dumpsys appwidget \
                        > "$ARTIFACTS/widgets-appwidget-after.txt" 2>&1 || true
                    _cwp_new_providers=$(appwidget_new_providers \
                        "$ARTIFACTS/widgets-appwidget-before.txt" \
                        "$ARTIFACTS/widgets-appwidget-after.txt" "$PKG")
                    [ -n "$_cwp_new_providers" ] && break
                    _cwp_aw_poll=$((_cwp_aw_poll + 1))
                    sleep 1
                done
                [ -n "$_cwp_new_providers" ] ||
                    fail "no new appwidget id owned by $PKG appeared in dumpsys appwidget after placement"
                printf '%s\n' "$_cwp_new_providers" \
                    > "$ARTIFACTS/widgets-appwidget-providers.txt"

                # Launch Settings and return HOME to prove the same widget
                # survives a real app switch, not just another HOME key press.
                adb_cmd shell am start -W -a android.settings.SETTINGS \
                    > "$ARTIFACTS/widgets-settings-launch.txt" 2>&1 ||
                    fail "could not launch Settings for the widget survival check"
                wait_for_foreground com.android.settings \
                    "$ARTIFACTS/activities-widget-settings.txt" 15 ||
                    fail "Settings was not foreground for the widget survival check"
                capture_ui_xml widgets-settings-launched.xml || true
                capture_screenshot_to widgets-settings-launched.png
                return_home widgets-picker
                capture_ui_xml widgets-home-after-home.xml ||
                    fail "could not capture HOME after launching Settings"
                capture_screenshot_to widgets-home-after-home.png
                [ -s "$ARTIFACTS/widgets-home-after-home.png" ] ||
                    fail "HOME-after-widget screenshot capture failed"
                # The widget may have landed on a page other than the one visible
                # after HOME. Search a bounded number of pages for the selected
                # provider label and exact placed bounds, return to the original
                # page, then navigate back to the widget page and re-prove the
                # same identity and bounds.
                if ! search_home_pages_for_widget \
                    "$_cwp_provider_title" "$_cwp_ref" \
                    "$ARTIFACTS/widgets-home-after-home.xml" widgets-survival \
                    "$ARTIFACTS/widgets-page-log.txt"; then
                    fail "the placed $_cwp_provider_title widget was not found on the first three measured HOME pages after launching Settings and returning HOME"
                fi
                _cwp_page=$_cwp_search_page
                _cwp_search_xml=$_cwp_search_xml
                [ "$_cwp_search_bounds" = "$_cwp_placed_bounds" ] ||
                    fail "the widget found after Settings has bounds '$_cwp_search_bounds', expected '$_cwp_placed_bounds'"
                printf 'survival-page=%s bounds=%s\n' \
                    "$_cwp_page" "$_cwp_search_bounds" \
                    >> "$ARTIFACTS/widgets-add-log.txt"
                _cwp_return=0
                while [ "$_cwp_return" -lt "$_cwp_page" ]; do
                    _cwp_return=$((_cwp_return + 1))
                    _cwp_swipe=$(workspace_page_swipe "$_cwp_search_xml" prev)
                    [ -n "$_cwp_swipe" ] ||
                        fail "could not compute the bounded HOME page return swipe"
                    set -- $_cwp_swipe
                    adb_cmd shell input swipe "$1" "$2" "$3" "$4" 500 \
                        > "$ARTIFACTS/widgets-page-return-$_cwp_return.txt" 2>&1 ||
                        fail "could not return to the original HOME page for the widget survival check"
                    sleep 1
                    _cwp_search_xml="$ARTIFACTS/widgets-home-return-$_cwp_return.xml"
                    capture_ui_xml "widgets-home-return-$_cwp_return.xml" ||
                        fail "could not capture the returned HOME page for the widget survival check"
                done
                if [ "$_cwp_page" -gt 0 ]; then
                    _cwp_forward=0
                    while [ "$_cwp_forward" -lt "$_cwp_page" ]; do
                        _cwp_forward=$((_cwp_forward + 1))
                        _cwp_swipe=$(workspace_page_swipe "$_cwp_search_xml" next)
                        [ -n "$_cwp_swipe" ] ||
                            fail "could not compute the bounded HOME page re-check swipe"
                        set -- $_cwp_swipe
                        adb_cmd shell input swipe "$1" "$2" "$3" "$4" 500 \
                            > "$ARTIFACTS/widgets-page-recheck-$_cwp_forward.txt" 2>&1 ||
                            fail "could not navigate back to the widget page for the survival re-check"
                        sleep 1
                        _cwp_search_xml="$ARTIFACTS/widgets-home-recheck-$_cwp_forward.xml"
                        capture_ui_xml "widgets-home-recheck-$_cwp_forward.xml" ||
                            fail "could not capture the widget page for the survival re-check"
                    done
                fi
                _cwp_recheck_bounds=$(home_widget_bounds \
                    "$_cwp_search_xml" "$_cwp_ref" "$_cwp_provider_title")
                [ "$_cwp_recheck_bounds" = "$_cwp_placed_bounds" ] ||
                    fail "the placed $_cwp_provider_title widget did not survive bounded page navigation (expected $_cwp_placed_bounds, got '${_cwp_recheck_bounds:-none}')"

                printf 'Widgets: the real HOME long-press popup opened the native picker; a real %s widget provider was expanded, its preview tapped, Add used, the exact bind consent Create control tapped with Always allow unchecked, and a new AppWidgetHostView plus a new launcher-owned AppWidgetId survived launching Settings, returning HOME and a bounded page search/return that found the widget on its actual page.\n' \
                    "$_cwp_provider_title" > "$ARTIFACTS/widgets-picker.txt"
                printf 'Provider: %s\n' "$_cwp_new_providers" \
                    >> "$ARTIFACTS/widgets-picker.txt"
                printf 'Widget bounds: %s\n' "$_cwp_placed_bounds" \
                    >> "$ARTIFACTS/widgets-picker.txt"
                printf 'Screenshots: home-popup.png, widgets-picker.png, widgets-provider.png, widgets-add.png, widgets-bind-consent.png, widgets-home-placed.png, widgets-settings-launched.png, widgets-home-after-home.png.\n' \
                    >> "$ARTIFACTS/widgets-picker.txt"
                # All third-party proof is complete. The bounded search may have
                # left the added widget's later page visible, so restore the
                # existing primary/default HOME with the normal HOME key before
                # the primary-page date-pill/own-widget assertion. No workspace
                # item is reset, moved or deleted.
                restore_primary_home widgets-primary
                verify_nothing_home
                return 0
            fi
            printf 'attempt=%s widgets-picker-not-ready; returning HOME\n' \
                "$_cwp_attempt" >> "$ARTIFACTS/widgets-longpress-log.txt"
            adb_cmd shell input keyevent KEYCODE_BACK \
                >> "$ARTIFACTS/widgets-longpress-log.txt" 2>&1 || true
            sleep 1
        else
            printf 'attempt=%s home-popup-not-ready; returning HOME\n' \
                "$_cwp_attempt" >> "$ARTIFACTS/widgets-longpress-log.txt"
            capture_screenshot_to "home-popup-attempt-$_cwp_attempt-last.png"
            adb_cmd shell input keyevent KEYCODE_BACK \
                >> "$ARTIFACTS/widgets-longpress-log.txt" 2>&1 || true
            sleep 1
        fi
        _cwp_attempt=$((_cwp_attempt + 1))
    done
    fail "the real HOME long-press did not open the Widgets picker after $_cwp_max_attempts bounded attempts"
}

_cwg_launch_gallery() {
    _clg_tag=$1
    if ! _clg_out=$(adb_cmd shell am start -W -f 0x18000000         -a android.intent.action.VIEW         -d 'lawnchair://settings/amoled-wallpapers'         -n "$PKG/$PREFERENCES_ACTIVITY" 2>&1); then
        printf '%s\n' "$_clg_out" > "$ARTIFACTS/wallpaper-gallery-$_clg_tag-launch.txt"
        return 1
    fi
    printf '%s\n' "$_clg_out" > "$ARTIFACTS/wallpaper-gallery-$_clg_tag-launch.txt"
    case "$_clg_out" in
        *"Error:"* | *"Error type"* | *Exception*) return 1 ;;
    esac
    printf '%s\n' "$_clg_out" | grep -q 'Status: ok'
}

_cwg_read_ids() {
    _cri_file=$1
    adb_cmd shell dumpsys wallpaper > "$_cri_file" 2>&1 || return 1
    _cri_user=$(adb_cmd shell am get-current-user 2>/dev/null | tr -d '\r' | sed -n '1p')
    case "$_cri_user" in
        '' | *[!0-9]*) wallpaper_ids_from_dump "$_cri_file" ;;
        *) wallpaper_ids_from_dump "$_cri_file" "$_cri_user" ;;
    esac
}

_cwg_widget_ids() {
    _cwi_file=$1
    adb_cmd shell dumpsys appwidget > "$_cwi_file" 2>&1 || return 1
    appwidget_launcher_instances "$_cwi_file" "$PKG" id | sort | tr '\n' ' '
}

# Measure a real tappable control inside the settings scroll container. Each
# attempt re-captures the hierarchy, measures the actual scrollable container
# clipped to the navigation-bar safe viewport, and accepts the control only
# when it is fully visible. When the content is already at its end, UiAutomator
# reports the same surface as a non-scrollable `android.widget.ScrollView`, so
# the strict scrollable measurement falls back to that exact known class in
# this app's package before deciding. Otherwise it performs one bounded swipe
# inside the measured container. No hardcoded phone height or coordinate is
# used. Prints the measured bounds on success and nothing after the small
# attempt bound.
_cwg_measure_control() {
    _cmc_label=$1
    _cmc_tag=$2
    _cmc_max=${3:-4}
    _cmc_attempt=0
    _cmc_log="$ARTIFACTS/wallpaper-scroll-$_cmc_tag.txt"
    : > "$_cmc_log"
    while [ "$_cmc_attempt" -lt "$_cmc_max" ]; do
        _cmc_attempt=$((_cmc_attempt + 1))
        capture_ui_xml "wallpaper-scroll-$_cmc_tag-$_cmc_attempt.xml" || return 1
        _cmc_xml="$ARTIFACTS/wallpaper-scroll-$_cmc_tag-$_cmc_attempt.xml"
        _cmc_viewport=$(ui_scroll_container_bounds "$_cmc_xml" "$_cwg_nav_top")
        if [ -z "$_cmc_viewport" ]; then
            _cmc_viewport=$(ui_known_scroll_container_bounds \
                "$_cmc_xml" "$_cwg_nav_top" "$PKG")
        fi
        _cmc_bounds=
        if [ -n "$_cmc_viewport" ]; then
            _cmc_bounds=$(ui_clickable_label_within "$_cmc_xml" "$_cmc_label" "$_cmc_viewport")
        fi
        printf 'attempt=%s label=%s viewport=%s bounds=%s\n' \
            "$_cmc_attempt" "$_cmc_label" "${_cmc_viewport:-none}" "${_cmc_bounds:-none}" \
            >> "$_cmc_log"
        if [ -n "$_cmc_bounds" ]; then
            cp "$_cmc_xml" \
                "$ARTIFACTS/wallpaper-scroll-$_cmc_tag-visible.xml" || return 1
            capture_screenshot_to "wallpaper-scroll-$_cmc_tag-visible.png"
            printf '%s\n' "$_cmc_bounds"
            return 0
        fi
        _cmc_target=$(settings_scroll_target "$_cmc_xml" "$_cwg_nav_top") || return 1
        set -- $_cmc_target
        printf 'scroll=%s from=%s,%s to=%s,%s\n' \
            "$_cmc_attempt" "$1" "$2" "$1" "$3" >> "$_cmc_log"
        adb_cmd shell input swipe "$1" "$2" "$1" "$3" 400 >> "$_cmc_log" 2>&1 || return 1
        sleep 1
    done
    return 1
}

# Offline AMOLED gallery proof. Preview, theme changes, Cancel and Back must
# leave the Home/Lock wallpaper IDs and widget IDs untouched. Only then are
# Pitch Black and Wireframe Torus explicitly applied, each followed by a real
# HOME capture, a Home-ID change and an unchanged widget/layout proof.
capture_wallpaper_gallery() {
    _cwg_failure=
    _cwg_widgets_before=$(_cwg_widget_ids "$ARTIFACTS/wallpaper-widgets-before.txt") ||
        fail "could not dump widgets before the wallpaper gallery"
    [ -n "$_cwg_widgets_before" ] ||
        fail "no launcher-owned widget IDs before the wallpaper gallery"

    adb_cmd shell dumpsys window windows \
        > "$ARTIFACTS/wallpaper-navigation-window.txt" 2>&1 || true
    adb_cmd shell dumpsys window displays \
        >> "$ARTIFACTS/wallpaper-navigation-window.txt" 2>&1 || true
    _cwg_nav=$(ui_navigation_bar_bounds "$ARTIFACTS/wallpaper-navigation-window.txt")
    [ -n "$_cwg_nav" ] ||
        fail "could not measure the navigation bar for the wallpaper gallery"
    set -- $_cwg_nav
    _cwg_nav_top=$2
    printf 'navigation=%s navigation_top=%s\n' "$_cwg_nav" "$_cwg_nav_top" \
        > "$ARTIFACTS/wallpaper-navigation-bounds.txt"

    _cwg_ids_before=$(_cwg_read_ids "$ARTIFACTS/wallpaper-ids-before.txt") ||
        fail "could not measure the Home and lock wallpaper IDs"
    set -- $_cwg_ids_before
    _cwg_home_before=$1
    _cwg_lock_before=$2
    printf 'home=%s lock=%s widgets=%s\n' \
        "$_cwg_home_before" "$_cwg_lock_before" "$_cwg_widgets_before" \
        > "$ARTIFACTS/wallpaper-baseline.txt"

    _cwg_night_before=$(adb_cmd shell cmd uimode night 2>&1 | tr -d '\r')
    _cwg_night_value=$(printf '%s\n' "$_cwg_night_before" |
        sed -n 's/^[Nn]ight mode:[[:space:]]*//p' | sed -n '1p')
    case "$_cwg_night_value" in
        yes | no | auto) ;;
        *) _cwg_night_value=auto ;;
    esac

    for _cwg_mode in yes no; do
        case "$_cwg_mode" in
            yes) _cwg_name=dark ;;
            no) _cwg_name=light ;;
        esac
        if ! adb_cmd shell cmd uimode night "$_cwg_mode" >/dev/null 2>&1; then
            _cwg_failure="could not switch to night $_cwg_mode for the wallpaper $_cwg_name capture"
            break
        fi
        sleep 1
        if ! _cwg_launch_gallery "$_cwg_name"; then
            _cwg_failure="could not open the wallpaper gallery in $_cwg_name mode"
            break
        fi
        sleep 1
        if ! capture_ui_xml "wallpaper-gallery-$_cwg_name.xml"; then
            _cwg_failure="wallpaper gallery $_cwg_name XML capture failed"
            break
        fi
        for _cwg_label in 'AMOLED Wallpapers' 'Pitch Black' 'Wireframe Torus'; do
            grep -Fq "$_cwg_label" "$ARTIFACTS/wallpaper-gallery-$_cwg_name.xml" ||
                { _cwg_failure="wallpaper gallery $_cwg_name is missing '$_cwg_label'"; break; }
        done
        [ -z "$_cwg_failure" ] || break
        capture_screenshot_to "wallpaper-gallery-$_cwg_name.png"
        _cwg_tile=$(ui_clickable_label_bounds \
            "$ARTIFACTS/wallpaper-gallery-$_cwg_name.xml" 'Pitch Black')
        [ -n "$_cwg_tile" ] ||
            { _cwg_failure="could not measure the Pitch Black tile in $_cwg_name mode"; break; }
        tap_center_of_bounds "$_cwg_tile"
        sleep 1
        if ! capture_ui_xml "wallpaper-preview-$_cwg_name.xml"; then
            _cwg_failure="wallpaper preview $_cwg_name XML capture failed"
            break
        fi
        capture_screenshot_to "wallpaper-preview-$_cwg_name.png"
        # The selected preview's credit, licence and Apply/Cancel controls sit
        # below the initial viewport, so they are absent from the unscrolled
        # XML. Reveal and measure each one through the bounded, navigation-aware
        # settings scroll before asserting it.
        _cwg_credit=$(_cwg_measure_control \
            'Copyright (c) 2024 Tecdrop. CC BY 4.0.' \
            "attribution-$_cwg_name" 8) ||
            { _cwg_failure="could not reveal the CC BY 4.0 attribution in $_cwg_name mode"; break; }
        _cwg_credit_xml="$ARTIFACTS/wallpaper-scroll-attribution-$_cwg_name-visible.xml"
        grep -Fq 'CC BY 4.0' "$_cwg_credit_xml" ||
            { _cwg_failure="the revealed $_cwg_name preview is missing 'CC BY 4.0'"; break; }
        _cwg_license=$(_cwg_measure_control \
            'License: https://creativecommons.org/licenses/by/4.0/' \
            "license-$_cwg_name" 8) ||
            { _cwg_failure="could not measure the CC BY 4.0 licence control in $_cwg_name mode"; break; }
        _cwg_license_xml="$ARTIFACTS/wallpaper-scroll-license-$_cwg_name-visible.xml"
        grep -Fq 'https://creativecommons.org/licenses/by/4.0/' "$_cwg_license_xml" ||
            { _cwg_failure="the revealed $_cwg_name preview is missing the CC BY 4.0 licence URL"; break; }
        _cwg_apply=$(_cwg_measure_control 'Apply to Home screen' \
            "apply-preview-$_cwg_name" 8) ||
            { _cwg_failure="could not measure a real Apply button in $_cwg_name mode"; break; }
        [ -n "$_cwg_apply" ] ||
            { _cwg_failure="the $_cwg_name preview Apply button has no measured bounds"; break; }
        _cwg_cancel=$(_cwg_measure_control 'Cancel preview' "cancel-$_cwg_name" 8) ||
            { _cwg_failure="could not measure the Cancel preview control in $_cwg_name mode"; break; }
        tap_center_of_bounds "$_cwg_cancel"
        sleep 1
        if ! capture_ui_xml "wallpaper-cancelled-$_cwg_name.xml"; then
            _cwg_failure="wallpaper cancelled $_cwg_name XML capture failed"
            break
        fi
        if grep -Fq 'Cancel preview' "$ARTIFACTS/wallpaper-cancelled-$_cwg_name.xml"; then
            _cwg_failure="Cancel preview did not clear the selection in $_cwg_name mode"
            break
        fi
        _cwg_ids_cancelled=$(_cwg_read_ids "$ARTIFACTS/wallpaper-ids-cancelled-$_cwg_name.txt") ||
            { _cwg_failure="could not re-read wallpaper IDs after Cancel preview in $_cwg_name mode"; break; }
        [ "$_cwg_ids_cancelled" = "$_cwg_ids_before" ] ||
            { _cwg_failure="Cancel preview changed wallpaper IDs in $_cwg_name mode"; break; }
        adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 ||
            { _cwg_failure="could not leave the wallpaper gallery in $_cwg_name mode"; break; }
        sleep 1
        _cwg_ids_after=$(_cwg_read_ids "$ARTIFACTS/wallpaper-ids-preview-$_cwg_name.txt") ||
            { _cwg_failure="could not re-read wallpaper IDs after the $_cwg_name preview"; break; }
        [ "$_cwg_ids_after" = "$_cwg_ids_before" ] ||
            { _cwg_failure="preview/Cancel/Back changed wallpaper IDs in $_cwg_name mode"; break; }
    done

    if ! adb_cmd shell cmd uimode night "$_cwg_night_value" >/dev/null 2>&1; then
        _cwg_failure="could not restore the emulator night mode after the wallpaper gallery"
    fi
    sleep 1

    _cwg_widgets_after_preview=$(_cwg_widget_ids "$ARTIFACTS/wallpaper-widgets-after-preview.txt") ||
        _cwg_failure="could not re-dump widgets after the wallpaper preview"
    [ "$_cwg_widgets_after_preview" = "$_cwg_widgets_before" ] ||
        _cwg_failure="preview/Back changed widget IDs"
    [ -z "$_cwg_failure" ] || fail "$_cwg_failure"

    _cwg_preview_live_wallpaper

    _cwg_apply_wallpaper 'Pitch Black' 'pitch-black'
    _cwg_apply_wallpaper 'Wireframe Torus' 'wireframe-torus'

    # The live apply runs after both static applies so the Lock wallpaper is an
    # explicit, already-changed target that must be preserved by the Home-only
    # live selection. It reopens the gallery, confirms through the measured
    # system UI, and then proves the real pause/resume draw gate.
    _cwg_apply_live_wallpaper

    _cwg_ids_final=$(_cwg_read_ids "$ARTIFACTS/wallpaper-ids-final.txt") ||
        fail "could not measure the final wallpaper IDs"
    printf 'final ids=%s\n' "$_cwg_ids_final" >> "$ARTIFACTS/wallpaper-baseline.txt"
    return_home wallpaper-gallery
}

# Bounded, measured proof that the explicit live-wallpaper action opens the
# real platform preview without changing the current Home/Lock wallpaper.
# Applying the live wallpaper and proving its pause/resume draw gate after
# system confirmation stay a separate runtime gate: this run never fakes a
# confirmation and never calls the platform setter itself.
_cwg_preview_live_wallpaper() {
    _cpl_ids_before=$(_cwg_read_ids "$ARTIFACTS/live-wallpaper-ids-before.txt") ||
        fail "could not measure wallpaper IDs before the live preview"
    _cwg_launch_gallery live-wallpaper ||
        fail "could not open the gallery for the live wallpaper preview"
    sleep 1
    capture_ui_xml "live-wallpaper-gallery.xml" ||
        fail "could not capture the live wallpaper gallery"
    _cpl_control=$(_cwg_measure_control 'Preview live wallpaper' 'live-wallpaper' 8) ||
        fail "could not reveal the live wallpaper preview action"
    [ -n "$_cpl_control" ] ||
        fail "the live wallpaper preview action has no measured bounds"
    # Read-only baseline: never clear the shared logcat buffer, so every earlier
    # crash/ANR line stays available to the final logcat checks. Only the appends
    # after this baseline may prove the fresh preview engine.
    adb_cmd logcat -d > "$ARTIFACTS/live-wallpaper-logcat-before.txt" 2>&1 || true
    tap_center_of_bounds "$_cpl_control"

    _cpl_ready=
    _cpl_attempt=0
    while [ "$_cpl_attempt" -lt 8 ]; do
        _cpl_attempt=$((_cpl_attempt + 1))
        sleep 1
        capture_ui_xml "live-wallpaper-preview-$_cpl_attempt.xml" || continue
        if live_wallpaper_preview_is_ready \
            "$ARTIFACTS/live-wallpaper-preview-$_cpl_attempt.xml"; then
            _cpl_ready=1
            break
        fi
    done
    [ -n "$_cpl_ready" ] ||
        fail "the system live-wallpaper preview did not open from the measured action"
    capture_screenshot_to "live-wallpaper-preview.png"
    [ -s "$ARTIFACTS/live-wallpaper-preview.png" ] ||
        fail "could not capture the live-wallpaper preview pixels"

    adb_cmd shell dumpsys wallpaper > "$ARTIFACTS/live-wallpaper-dumpsys.txt" 2>&1 || true
    adb_cmd logcat -d > "$ARTIFACTS/live-wallpaper-logcat.txt" 2>&1 || true
    live_wallpaper_preview_log_after \
        "$ARTIFACTS/live-wallpaper-logcat-before.txt" \
        "$ARTIFACTS/live-wallpaper-logcat.txt" \
        "$ARTIFACTS/live-wallpaper-logcat-preview.txt" ||
        fail "could not isolate the fresh post-preview live-wallpaper log"
    live_wallpaper_became_visible "$ARTIFACTS/live-wallpaper-logcat-preview.txt" ||
        fail "the live wallpaper engine never logged a fresh visible transition"

    adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 ||
        fail "could not leave the system live-wallpaper preview"
    sleep 1
    _cpl_ids_after=$(_cwg_read_ids "$ARTIFACTS/live-wallpaper-ids-after.txt") ||
        fail "could not re-read wallpaper IDs after cancelling the live preview"
    [ "$_cpl_ids_after" = "$_cpl_ids_before" ] ||
        fail "leaving the live preview changed the Home or lock wallpaper ID"
    adb_cmd logcat -d > "$ARTIFACTS/live-wallpaper-logcat-after-back.txt" 2>&1 || true
    capture_ui_xml "live-wallpaper-after-back.xml" || true
    adb_cmd shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
    sleep 1
}

# Runtime gate for the original live wallpaper. Reopens the gallery, measures
# the explicit Preview live wallpaper action, requires the exact Dot Field
# (Live) platform preview from com.android.wallpaper.livepicker, taps only a
# positive fully visible measured Set wallpaper control above the navigation
# bar, and resolves any normal destination dialog only through its exact
# measured Home screen option. It never taps a Home-and-lock/lock destination,
# never uses a shell wallpaper setter/service binding and never confirms
# blindly. dumpsys must then prove DotFieldWallpaperService is the System
# wallpaper, the Home ID changed and the Lock wallpaper was preserved.
_cwg_apply_live_wallpaper() {
    _cal_ids_before=$(_cwg_read_ids "$ARTIFACTS/live-apply-ids-before.txt") ||
        fail "could not measure wallpaper IDs before applying the live wallpaper"
    set -- $_cal_ids_before
    _cal_home_before=$1
    _cal_lock_before=$2

    _cwg_launch_gallery live-apply ||
        fail "could not open the gallery for the live wallpaper apply"
    sleep 1
    capture_ui_xml "live-apply-gallery.xml" ||
        fail "could not capture the live wallpaper gallery for the apply"
    _cal_control=$(_cwg_measure_control 'Preview live wallpaper' 'live-apply' 8) ||
        fail "could not reveal the live wallpaper preview action for the apply"
    [ -n "$_cal_control" ] ||
        fail "the live wallpaper preview action has no measured bounds for the apply"
    adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-preview-before.txt" 2>&1 || true
    tap_center_of_bounds "$_cal_control"

    _cal_ready=
    _cal_attempt=0
    while [ "$_cal_attempt" -lt 8 ]; do
        _cal_attempt=$((_cal_attempt + 1))
        sleep 1
        capture_ui_xml "live-apply-preview-$_cal_attempt.xml" || continue
        if live_wallpaper_preview_is_dotfield \
            "$ARTIFACTS/live-apply-preview-$_cal_attempt.xml"; then
            _cal_ready=1
            break
        fi
    done
    [ -n "$_cal_ready" ] ||
        fail "the exact Dot Field (Live) system preview did not open from the measured action"
    _cal_preview_xml="$ARTIFACTS/live-apply-preview-$_cal_attempt.xml"
    capture_screenshot_to "live-apply-preview.png"
    [ -s "$ARTIFACTS/live-apply-preview.png" ] ||
        fail "could not capture the Dot Field (Live) system preview pixels"

    set -- $_cwg_nav
    _cal_viewport="0 0 $3 $2"
    _cal_set=$(ui_clickable_label_within "$_cal_preview_xml" 'Set wallpaper' "$_cal_viewport") || true
    [ -n "$_cal_set" ] ||
        fail "could not measure a positive, fully visible Set wallpaper button above the navigation bar"
    printf 'set_wallpaper=%s viewport=%s\n' "$_cal_set" "$_cal_viewport" \
        > "$ARTIFACTS/live-apply-set-wallpaper.txt"
    tap_center_of_bounds "$_cal_set"

    _cal_dialog=
    _cal_applied=
    _cal_dest_attempt=0
    while [ "$_cal_dest_attempt" -lt 10 ]; do
        _cal_dest_attempt=$((_cal_dest_attempt + 1))
        sleep 1
        _cal_dest_xml="$ARTIFACTS/live-apply-destination-$_cal_dest_attempt.xml"
        capture_ui_xml "live-apply-destination-$_cal_dest_attempt.xml" || true
        if [ -s "$_cal_dest_xml" ]; then
            _cal_dest=$(live_wallpaper_destination_bounds "$_cal_dest_xml" "$_cwg_nav_top")
            if [ -n "$_cal_dest" ]; then
                printf 'destination=Home screen bounds=%s\n' "$_cal_dest" \
                    > "$ARTIFACTS/live-apply-destination.txt"
                tap_center_of_bounds "$_cal_dest"
                _cal_dialog=1
                break
            fi
            if live_wallpaper_destination_ambiguous "$_cal_dest_xml"; then
                fail "the live-wallpaper destination dialog has no unique measured 'Home screen' option; refusing to tap a lock destination (evidence: $_cal_dest_xml)"
            fi
        fi
        _cal_poll_id_file="$ARTIFACTS/live-apply-ids-destination-$_cal_dest_attempt.txt"
        _cal_poll_ids=$(_cwg_read_ids "$_cal_poll_id_file" 2>/dev/null || true)
        if [ -n "$_cal_poll_ids" ]; then
            set -- $_cal_poll_ids
            if [ "$1" != "$_cal_home_before" ] &&
                live_wallpaper_service_active "$_cal_poll_id_file"; then
                _cal_applied=1
                break
            fi
        fi
    done
    if [ -z "$_cal_dialog" ] && [ -z "$_cal_applied" ]; then
        capture_screenshot_to "live-apply-destination-last.png"
        capture_ui_xml "live-apply-destination-last.xml" || true
        fail "the system neither offered a measured 'Home screen' destination nor applied the live wallpaper; refusing to guess"
    fi

    _cal_poll=0
    _cal_home_after=
    _cal_lock_after=
    while [ "$_cal_poll" -lt 10 ]; do
        _cal_poll=$((_cal_poll + 1))
        sleep 1
        _cal_ids_file="$ARTIFACTS/live-apply-ids-$_cal_poll.txt"
        _cal_after=$(_cwg_read_ids "$_cal_ids_file") ||
            fail "could not read wallpaper IDs after confirming the live wallpaper"
        set -- $_cal_after
        _cal_home_after=$1
        _cal_lock_after=$2
        if [ "$_cal_home_after" != "$_cal_home_before" ] &&
            live_wallpaper_service_active "$_cal_ids_file"; then
            break
        fi
    done
    [ -n "$_cal_home_after" ] ||
        fail "no wallpaper ID result after confirming the live wallpaper"
    [ "$_cal_home_after" != "$_cal_home_before" ] ||
        fail "confirming the live wallpaper did not change the Home wallpaper ID"
    live_wallpaper_service_active "$_cal_ids_file" ||
        fail "dumpsys wallpaper does not report DotFieldWallpaperService as the System wallpaper"
    wallpaper_lock_preserved "$_cal_home_before" "$_cal_lock_before" "$_cal_lock_after" ||
        fail "confirming the live wallpaper changed the lock wallpaper"
    printf 'applied=live-wallpaper before=%s after=%s lock=%s dialog=%s\n' \
        "$_cal_ids_before" "$_cal_home_after" "$_cal_lock_after" "$_cal_dialog" \
        > "$ARTIFACTS/live-apply.txt"

    # Keep two timed HOME frames. The slow dot-field motion normally changes the
    # pixels between them, but a stable frame is recorded rather than treated as
    # a failure: this is not a clock-difference correctness oracle.
    return_home live-apply
    sleep 2
    capture_ui_xml "live-apply-home.xml" ||
        fail "could not capture HOME after applying the live wallpaper"
    capture_screenshot_to "live-apply-home-frame1.png"
    sleep 2
    capture_screenshot_to "live-apply-home-frame2.png"
    [ -s "$ARTIFACTS/live-apply-home-frame1.png" ] &&
        [ -s "$ARTIFACTS/live-apply-home-frame2.png" ] ||
        fail "could not capture the two timed HOME frames after applying the live wallpaper"

    _cal_widgets_after=$(_cwg_widget_ids "$ARTIFACTS/live-apply-widgets-after.txt") ||
        fail "could not re-dump widgets after applying the live wallpaper"
    [ "$_cal_widgets_after" = "$_cwg_widgets_before" ] ||
        fail "applying the live wallpaper changed the widget IDs"
    # A third-party Clock/Calendar widget may have been placed on another page.
    # Its binding is still explicit through the launcher-owned appwidget dump.
    if [ -s "$ARTIFACTS/widgets-appwidget-providers.txt" ]; then
        while IFS= read -r _cal_binding; do
            _cal_binding_id=$(printf '%s\n' "$_cal_binding" | awk -F '\t' '{ print $2 }')
            [ -n "$_cal_binding_id" ] || continue
            case " $_cal_widgets_after " in
                *" $_cal_binding_id "*) ;;
                *) fail "the third-party widget binding AppWidgetId=$_cal_binding_id disappeared after applying the live wallpaper" ;;
            esac
        done < "$ARTIFACTS/widgets-appwidget-providers.txt"
    fi
    verify_home_widgets "$ARTIFACTS/live-apply-home.xml"

    _cwg_live_pause_resume
}

# Prove the real pause/resume draw gate through opaque fullscreen activity
# transitions. Launching the device Settings must hide the applied engine with
# pending=false drawing=false; the normal HOME key must resume the exact same
# engine token at the exact hidden drawn count (no hidden drawing); staying HOME
# and opening Settings again must hide that same engine with a strictly larger
# drawn count. Every phase is sliced after a read-only logcat baseline and the
# shared crash history is never cleared.
_cwg_live_pause_resume() {
    capture_ui_xml "live-apply-hidden-before.xml" ||
        fail "could not capture HOME before the live wallpaper pause"
    capture_screenshot_to "live-apply-hidden-before.png"
    adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-home-before.txt" 2>&1 || true

    adb_cmd shell am start -W -a android.settings.SETTINGS \
        > "$ARTIFACTS/live-apply-settings-launch1.txt" 2>&1 ||
        fail "could not launch Settings for the live wallpaper hidden transition"
    wait_for_foreground com.android.settings \
        "$ARTIFACTS/live-apply-activities-settings1.txt" 15 ||
        fail "Settings was not the measured resumed activity for the hidden transition"
    capture_ui_xml "live-apply-settings-hidden1.xml" || true
    capture_screenshot_to "live-apply-settings-hidden1.png"
    adb_cmd shell dumpsys wallpaper > "$ARTIFACTS/live-apply-dumpsys-hidden1.txt" 2>&1 || true
    _cal_engine=
    _cal_hidden_drawn=
    _cal_try=0
    while [ "$_cal_try" -lt 6 ]; do
        _cal_try=$((_cal_try + 1))
        sleep 1
        adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-hidden1-full.txt" 2>&1 || true
        live_wallpaper_preview_log_after \
            "$ARTIFACTS/live-apply-logcat-home-before.txt" \
            "$ARTIFACTS/live-apply-logcat-hidden1-full.txt" \
            "$ARTIFACTS/live-apply-logcat-hidden1.txt" || continue
        live_wallpaper_single_engine "$ARTIFACTS/live-apply-logcat-hidden1.txt" ||
            continue
        _cal_engine=$(live_wallpaper_hidden_engine \
            "$ARTIFACTS/live-apply-logcat-hidden1.txt") || continue
        _cal_hidden_drawn=$(live_wallpaper_hidden_drawn \
            "$ARTIFACTS/live-apply-logcat-hidden1.txt" "$_cal_engine") || continue
        break
    done
    [ -n "$_cal_engine" ] && [ -n "$_cal_hidden_drawn" ] ||
        fail "no clean single-engine applied live-wallpaper hidden transition was captured"
    printf 'hidden1 engine=%s drawn=%s\n' "$_cal_engine" "$_cal_hidden_drawn" \
        > "$ARTIFACTS/live-apply-transitions.txt"

    sleep 2

    return_home live-hidden
    capture_ui_xml "live-apply-home-resumed.xml" ||
        fail "could not capture HOME after the hidden interval"
    capture_screenshot_to "live-apply-home-resumed.png"
    _cal_resumed=
    _cal_try=0
    while [ "$_cal_try" -lt 6 ]; do
        _cal_try=$((_cal_try + 1))
        sleep 1
        adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-resumed-full.txt" 2>&1 || true
        live_wallpaper_preview_log_after \
            "$ARTIFACTS/live-apply-logcat-hidden1-full.txt" \
            "$ARTIFACTS/live-apply-logcat-resumed-full.txt" \
            "$ARTIFACTS/live-apply-logcat-resumed.txt" || continue
        live_wallpaper_single_engine "$ARTIFACTS/live-apply-logcat-resumed.txt" ||
            continue
        live_wallpaper_resume_unchanged \
            "$ARTIFACTS/live-apply-logcat-resumed.txt" "$_cal_engine" \
            "$_cal_hidden_drawn" || continue
        _cal_resumed=1
        break
    done
    [ -n "$_cal_resumed" ] ||
        fail "the same live wallpaper engine did not resume at the exact hidden drawn count (hidden drawing suspected)"
    printf 'resumed engine=%s drawn=%s\n' "$_cal_engine" \
        "$(live_wallpaper_visible_drawn "$ARTIFACTS/live-apply-logcat-resumed.txt" "$_cal_engine")" \
        >> "$ARTIFACTS/live-apply-transitions.txt"

    sleep 1
    adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-home2-full.txt" 2>&1 || true

    adb_cmd shell am start -W -a android.settings.SETTINGS \
        > "$ARTIFACTS/live-apply-settings-launch2.txt" 2>&1 ||
        fail "could not relaunch Settings for the resumed-frame transition"
    wait_for_foreground com.android.settings \
        "$ARTIFACTS/live-apply-activities-settings2.txt" 15 ||
        fail "Settings was not the measured resumed activity for the resumed-frame transition"
    capture_ui_xml "live-apply-settings-hidden2.xml" || true
    capture_screenshot_to "live-apply-settings-hidden2.png"
    adb_cmd shell dumpsys wallpaper > "$ARTIFACTS/live-apply-dumpsys-hidden2.txt" 2>&1 || true
    _cal_hidden2=
    _cal_try=0
    while [ "$_cal_try" -lt 6 ]; do
        _cal_try=$((_cal_try + 1))
        sleep 1
        adb_cmd logcat -d > "$ARTIFACTS/live-apply-logcat-hidden2-full.txt" 2>&1 || true
        live_wallpaper_preview_log_after \
            "$ARTIFACTS/live-apply-logcat-home2-full.txt" \
            "$ARTIFACTS/live-apply-logcat-hidden2-full.txt" \
            "$ARTIFACTS/live-apply-logcat-hidden2.txt" || continue
        live_wallpaper_single_engine "$ARTIFACTS/live-apply-logcat-hidden2.txt" ||
            continue
        live_wallpaper_hidden_frame_increase \
            "$ARTIFACTS/live-apply-logcat-hidden2.txt" "$_cal_engine" \
            "$_cal_hidden_drawn" || continue
        _cal_hidden2=1
        break
    done
    [ -n "$_cal_hidden2" ] ||
        fail "the resumed live wallpaper engine did not draw new frames before hiding again"
    printf 'hidden2 engine=%s drawn=%s\n' "$_cal_engine" \
        "$(live_wallpaper_hidden_drawn "$ARTIFACTS/live-apply-logcat-hidden2.txt" "$_cal_engine")" \
        >> "$ARTIFACTS/live-apply-transitions.txt"

    return_home live-hidden-again
}

# Explicitly apply one measured tile. The caller has already entered the
# gallery; this opens it again, taps the tile and the separate Apply button,
# then polls only for a changed Home ID.
_cwg_apply_wallpaper() {
    _caw_label=$1
    _caw_slug=$2
    _caw_ids_before=$(_cwg_read_ids "$ARTIFACTS/wallpaper-apply-$_caw_slug-ids-before.txt") ||
        fail "could not measure wallpaper IDs before applying $_caw_label"
    set -- $_caw_ids_before
    _caw_home_before=$1
    _caw_lock_before=$2

    _cwg_launch_gallery "apply-$_caw_slug" ||
        fail "could not open the gallery to apply $_caw_label"
    sleep 1
    capture_ui_xml "wallpaper-apply-$_caw_slug-tile.xml" ||
        fail "could not capture the $_caw_label gallery tile"
    _caw_tile=$(ui_clickable_label_bounds \
        "$ARTIFACTS/wallpaper-apply-$_caw_slug-tile.xml" "$_caw_label")
    [ -n "$_caw_tile" ] || fail "could not measure the $_caw_label tile"
    tap_center_of_bounds "$_caw_tile"
    sleep 1
    capture_ui_xml "wallpaper-apply-$_caw_slug-preview.xml" ||
        fail "could not capture the $_caw_label preview"
    _caw_apply=$(_cwg_measure_control 'Apply to Home screen' "apply-$_caw_slug" 4) ||
        fail "could not measure a visible $_caw_label Apply button inside the settings scroll container"
    tap_center_of_bounds "$_caw_apply"

    _caw_after=
    _caw_after_home=
    _caw_after_lock=
    _caw_poll=0
    while [ "$_caw_poll" -lt 10 ]; do
        _caw_poll=$((_caw_poll + 1))
        sleep 1
        _caw_after=$(_cwg_read_ids "$ARTIFACTS/wallpaper-apply-$_caw_slug-ids-$_caw_poll.txt") ||
            fail "could not read wallpaper IDs after applying $_caw_label"
        set -- $_caw_after
        _caw_after_home=$1
        _caw_after_lock=$2
        [ "$_caw_after_home" != "$_caw_home_before" ] && break
    done
    [ -n "$_caw_after_home" ] || fail "no wallpaper ID result after applying $_caw_label"
    [ "$_caw_after_home" != "$_caw_home_before" ] ||
        fail "applying $_caw_label did not change the Home wallpaper ID"
    wallpaper_lock_preserved "$_caw_home_before" "$_caw_lock_before" "$_caw_after_lock" ||
        fail "applying $_caw_label changed the lock wallpaper"
    printf 'applied=%s before=%s after=%s\n' "$_caw_slug" "$_caw_ids_before" "$_caw_after" \
        > "$ARTIFACTS/wallpaper-apply-$_caw_slug.txt"

    capture_screenshot_to "wallpaper-apply-$_caw_slug.png"
    return_home "wallpaper-$_caw_slug"
    sleep 1
    capture_screenshot_to "wallpaper-home-after-$_caw_slug.png"
    [ -s "$ARTIFACTS/wallpaper-home-after-$_caw_slug.png" ] ||
        fail "could not capture the HOME pixels after applying $_caw_label"
    _caw_widgets=$(_cwg_widget_ids "$ARTIFACTS/wallpaper-apply-$_caw_slug-widgets.txt") ||
        fail "could not re-dump widgets after applying $_caw_label"
    [ "$_caw_widgets" = "$_cwg_widgets_before" ] ||
        fail "applying $_caw_label changed the widget IDs"
    verify_home_widgets
    capture_ui_xml "wallpaper-home-after-$_caw_slug.xml" ||
        fail "could not capture HOME after applying $_caw_label"
    _cwg_home_before=$_caw_after_home
    _cwg_lock_before=$_caw_after_lock
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
    devices=$(run_with_timeout 30 adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    device_count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$device_count" -ne 1 ]; then
        fail "expected exactly one adb device, found $device_count; pass --serial"
    fi
    SERIAL=$(printf '%s\n' "$devices" | sed -n '1p')
fi

adb_cmd get-state >/dev/null 2>&1 || fail "adb device $SERIAL is not available"

{
    printf 'serial=%s\n' "$SERIAL"
    run_with_timeout 30 adb devices -l
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

verify_default_home_consent

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

complete_own_widget_setup
verify_nothing_home
capture_clean_home_theme
capture_customization_settings
exercise_device_settings_shortcuts
capture_grid_settings
capture_widgets_picker
exercise_app_drawer
capture_drawer_bottom_boundary

capture_app_info
return_home app-info
capture_about
return_home about
capture_settings_theme
capture_native_surfaces_theme
capture_theme_sample dark
capture_theme_sample light
return_home theme-sample

capture_wallpaper_gallery

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
