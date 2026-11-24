#!/bin/sh
# Focused regression tests for scripts/emulator-smoke-lib.sh and the app-launch
# foreground check in scripts/emulator-smoke.sh.
# Run with: sh scripts/emulator-smoke-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LIB="$SCRIPT_DIR/emulator-smoke-lib.sh"
SMOKE="$SCRIPT_DIR/emulator-smoke.sh"
PROD_STRINGS="$ROOT_DIR/lawnchair/res/values/strings.xml"
PROD_WEATHER_PROVIDER="$ROOT_DIR/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
PROD_WEATHER_COPY="$ROOT_DIR/lawnchair/src/app/nothingui/weather/WeatherSettingsCopy.kt"
PROD_WEATHER_PREFS="$ROOT_DIR/lawnchair/src/app/lawnchair/ui/preferences/destinations/WeatherPreferences.kt"
PROD_HOME_PREFS="$ROOT_DIR/lawnchair/src/app/lawnchair/ui/preferences/destinations/HomeScreenPreferences.kt"
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

if [ ! -f "$LIB" ] || [ ! -f "$SMOKE" ]; then
    fail 'emulator-smoke-lib.sh and emulator-smoke.sh exist'
    exit 1
fi

# shellcheck source=emulator-smoke-lib.sh
. "$LIB"

assert_eq() {
    name=$1
    expected=$2
    actual=$3
    if [ "$actual" = "$expected" ]; then
        pass "$name"
    else
        fail "$name (expected '$expected', got '$actual')"
    fi
}

assert_true() {
    name=$1
    shift
    if "$@"; then
        pass "$name"
    else
        fail "$name"
    fi
}

assert_false() {
    name=$1
    shift
    if "$@"; then
        fail "$name"
    else
        pass "$name"
    fi
}

# Return the raw source body of one exact <string name="...">value</string>.
prod_string_raw() {
    _psr_name=$1
    _psr_file=${2:-$PROD_STRINGS}
    sed -n "s/.*<string name=\"$_psr_name\"[^>]*>\(.*\)<\/string>.*/\1/p" "$_psr_file" |
        head -n 1
}

# aapt2 decodes backslash escapes before the runtime ever sees the value.
# Decode them here so copy assertions compare against the runtime value, never
# the raw source spelling such as \' or \". The escaping guard below still
# inspects the raw source.
android_string_runtime_value() {
    printf '%s\n' "$1" | awk '{
        gsub(/\\\047/, "\047")
        gsub(/\\"/, "\"")
        gsub(/\\\\/, "\\")
        print
    }'
}

# Resolve one exact <string name="...">value</string> from the shipped values
# resource as the runtime value. The Weather fixtures and helper constants are
# checked against this, so a production copy change cannot silently drift from
# the runtime gate.
prod_string() {
    android_string_runtime_value "$(prod_string_raw "$1" "${2:-}")"
}

# True when a raw resource body has an apostrophe that aapt2 rejects. Escaped
# apostrophes are removed first, so only unescaped ones remain.
android_string_has_unescaped_apostrophe() {
    printf '%s\n' "$1" | sed "s/\\\\'//g" | grep -Fq "'"
}

prod_string_contains() {
    _psc_name=$1
    _psc_needle=$2
    _psc_label=$3
    _psc_value=$(prod_string "$_psc_name")
    if printf '%s\n' "$_psc_value" | grep -Fq -- "$_psc_needle"; then
        pass "$_psc_label"
    else
        fail "$_psc_label (missing '$_psc_needle' in $_psc_name)"
    fi
}

prod_string_lacks() {
    _psl_name=$1
    _psl_needle=$2
    _psl_label=$3
    _psl_value=$(prod_string "$_psl_name")
    if printf '%s\n' "$_psl_value" | grep -Fq -- "$_psl_needle"; then
        fail "$_psl_label (unexpected '$_psl_needle' in $_psl_name)"
    else
        pass "$_psl_label"
    fi
}

# --- Weather settings copy contract (debug and release) --------------------
# Both build modes must disclose the real transmission that the enabled release
# path performs, or explicitly state that this build does not perform it. The
# debug APK is setup-only: it must never promise a forecast request.

for mode in debug release; do
    prod_string_contains "dotwel_weather_privacy_notice_$mode" \
        'coordinates and the IP address of this device' \
        "the $mode privacy notice discloses coordinate and device-IP transmission"
    prod_string_contains "dotwel_weather_privacy_notice_$mode" \
        'MET Norway' \
        "the $mode privacy notice names MET Norway"
    prod_string_contains "dotwel_weather_privacy_notice_$mode" \
        'label stays on this device' \
        "the $mode privacy notice keeps the location label on device"
    prod_string_contains "dotwel_weather_privacy_notice_$mode" \
        'No GPS' \
        "the $mode privacy notice rules out GPS"
    prod_string_contains "dotwel_weather_privacy_notice_$mode" \
        'background tracking' \
        "the $mode privacy notice rules out background tracking"
    prod_string_contains "dotwel_weather_forecast_notice_$mode" \
        'last successful forecast' \
        "the $mode forecast notice describes the retained last success"
    prod_string_contains "dotwel_weather_forecast_notice_$mode" \
        'as-of age' \
        "the $mode forecast notice says the retained value is marked as-of"
    prod_string_contains "dotwel_weather_forecast_notice_$mode" \
        'never replaced by a made-up value' \
        "the $mode forecast notice forbids fabrication"
    prod_string_lacks "dotwel_weather_forecast_notice_$mode" \
        'instead of showing a stale' \
        "the $mode forecast notice no longer denies the marked stale display"
done

prod_string_contains dotwel_weather_privacy_notice_debug \
    'network requests disabled' \
    'the debug privacy notice states that network requests are disabled'
prod_string_contains dotwel_weather_privacy_notice_debug \
    'setup-only' \
    'the debug privacy notice states that enabling is setup-only'
prod_string_lacks dotwel_weather_privacy_notice_debug \
    'are shared with MET Norway' \
    'the debug privacy notice does not claim it will send data'
prod_string_lacks dotwel_weather_privacy_notice_release \
    'network requests disabled' \
    'the release privacy notice does not claim network requests are disabled'
prod_string_contains dotwel_weather_privacy_notice_release \
    'are shared with MET Norway' \
    'the release privacy notice states that enabled requests share data'
prod_string_contains dotwel_weather_forecast_notice_debug \
    'network requests disabled' \
    'the debug forecast notice states that network requests are disabled'
prod_string_contains dotwel_weather_forecast_notice_debug \
    'Off or Not connected' \
    'the debug forecast notice keeps the truthful compact states'
prod_string_lacks dotwel_weather_forecast_notice_release \
    'network requests disabled' \
    'the release forecast notice does not claim network requests are disabled'

prod_string_contains dotwel_weather_settings_description_debug \
    'network off' \
    'the debug settings subtitle says the network is off'
prod_string_contains dotwel_weather_settings_description_debug \
    'setup-only' \
    'the debug settings subtitle says the debug build is setup-only'
prod_string_lacks dotwel_weather_settings_description_debug \
    'forecasts only while Home is visible' \
    'the debug settings subtitle does not promise a forecast request'
prod_string_contains dotwel_weather_settings_description_release \
    'Home is visible' \
    'the release settings subtitle describes the visible-HOME request'
prod_string_lacks dotwel_weather_settings_description_release \
    'network off' \
    'the release settings subtitle does not claim network off'

prod_string_contains dotwel_weather_enabled_status_debug \
    'network requests disabled' \
    'the debug enabled status says the network is off'
prod_string_contains dotwel_weather_enabled_status_debug \
    'no coordinates or device IP address are sent' \
    'the debug enabled status says nothing is sent'
prod_string_contains dotwel_weather_enabled_status_release \
    'MET Norway' \
    'the release enabled status names MET Norway'
prod_string_contains dotwel_weather_enabled_status_release \
    'the IP address of this device' \
    'the release enabled status discloses device-IP transmission'
prod_string_contains dotwel_weather_message_enabled_debug \
    'network requests disabled' \
    'the debug enabled confirmation says the network is off'
prod_string_contains dotwel_weather_message_enabled_debug \
    'no forecast is requested' \
    'the debug enabled confirmation says no forecast is requested'
prod_string_contains dotwel_weather_message_enabled_release \
    'MET Norway' \
    'the release enabled confirmation names MET Norway'
prod_string_contains dotwel_weather_message_enabled_release \
    'the IP address of this device' \
    'the release enabled confirmation discloses device-IP transmission'

debug_privacy=$(prod_string dotwel_weather_privacy_notice_debug)
release_privacy=$(prod_string dotwel_weather_privacy_notice_release)
[ "$debug_privacy" != "$release_privacy" ] &&
    pass 'the debug and release privacy notices are distinct build-mode copy' ||
    fail 'the debug and release privacy notices are not distinct'
debug_message=$(prod_string dotwel_weather_message_enabled_debug)
release_message=$(prod_string dotwel_weather_message_enabled_release)
[ "$debug_message" != "$release_message" ] &&
    pass 'the debug and release enabled confirmations are distinct build-mode copy' ||
    fail 'the debug and release enabled confirmations are not distinct'

# --- Weather string resource escaping -------------------------------------
# AAPT2 rejects an unescaped apostrophe in a string value even though the XML
# is well formed. Guard the shipped Weather strings, and prove that copy
# assertions consume the decoded runtime value rather than the raw escape.

for _wse_name in \
    dotwel_weather_privacy_notice_debug \
    dotwel_weather_privacy_notice_release \
    dotwel_weather_enabled_status_debug \
    dotwel_weather_enabled_status_release \
    dotwel_weather_forecast_notice_debug \
    dotwel_weather_forecast_notice_release \
    dotwel_weather_message_enabled_debug \
    dotwel_weather_message_enabled_release; do
    _wse_raw=$(prod_string_raw "$_wse_name")
    if [ -z "$_wse_raw" ]; then
        fail "the $_wse_name string is missing"
    elif android_string_has_unescaped_apostrophe "$_wse_raw"; then
        fail "the $_wse_name string has an unescaped apostrophe that aapt2 rejects"
    else
        pass "the $_wse_name string has no unescaped apostrophe"
    fi
done

_escaped_strings="$TMP_DIR/escaped-strings.xml"
cat > "$_escaped_strings" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="escaped_apostrophe">save this device\'s setting</string>
    <string name="unescaped_apostrophe">save this device's setting</string>
</resources>
EOF
assert_false 'the escaping guard accepts a backslash-escaped apostrophe' \
    android_string_has_unescaped_apostrophe \
    "$(prod_string_raw escaped_apostrophe "$_escaped_strings")"
assert_true 'the escaping guard rejects an unescaped apostrophe' \
    android_string_has_unescaped_apostrophe \
    "$(prod_string_raw unescaped_apostrophe "$_escaped_strings")"
assert_eq 'copy assertions consume the decoded runtime value' \
    "save this device's setting" \
    "$(prod_string escaped_apostrophe "$_escaped_strings")"
printf '%s\n' "$(prod_string escaped_apostrophe "$_escaped_strings")" \
    > "$TMP_DIR/decoded-escaped-string"
assert_true 'the decoded runtime value keeps the real apostrophe' \
    grep -Fq "device's" "$TMP_DIR/decoded-escaped-string"
assert_false 'the decoded runtime value never exposes the raw escape sequence' \
    grep -Fq "device\\'s" "$TMP_DIR/decoded-escaped-string"

# The Compose screen and the Home-screen entry must select through the single
# build-aware copy object, not a hard-coded string. The copy object itself must
# derive from the same WeatherNetworkMode build boundary as the runtime.
[ -f "$PROD_WEATHER_COPY" ] &&
    pass 'the build-aware weather copy object exists' ||
    fail 'the build-aware weather copy object is missing'
assert_true 'the copy object derives from the runtime network mode' \
    grep -Fq 'fun networkEnabled(debugBuild: Boolean): Boolean = WeatherNetworkMode.isEnabled(debugBuild)' \
    "$PROD_WEATHER_COPY"
assert_true 'the settings screen computes the mode from BuildConfig.DEBUG' \
    grep -Fq 'WeatherSettingsCopy.networkEnabled(BuildConfig.DEBUG)' \
    "$PROD_WEATHER_PREFS"
assert_true 'the settings screen renders the mode-aware privacy notice' \
    grep -Fq 'WeatherSettingsCopy.privacyNotice(networkEnabled)' \
    "$PROD_WEATHER_PREFS"
assert_true 'the settings screen renders the mode-aware forecast notice' \
    grep -Fq 'WeatherSettingsCopy.forecastNotice(networkEnabled)' \
    "$PROD_WEATHER_PREFS"
assert_true 'the settings screen renders the mode-aware enabled status' \
    grep -Fq 'WeatherSettingsCopy.enabledStatus(networkEnabled)' \
    "$PROD_WEATHER_PREFS"
assert_true 'the settings screen maps the enabled message through the copy object' \
    grep -Fq 'WeatherSettingsCopy.messageResource(message, networkEnabled)' \
    "$PROD_WEATHER_PREFS"
assert_true 'the Home-screen entry computes the mode from BuildConfig.DEBUG' \
    grep -Fq 'WeatherSettingsCopy.networkEnabled(BuildConfig.DEBUG)' \
    "$PROD_HOME_PREFS"
assert_true 'the Home-screen entry renders the mode-aware subtitle' \
    grep -Fq 'WeatherSettingsCopy.settingsDescription(networkEnabled)' \
    "$PROD_HOME_PREFS"

# --- dumpsys foreground fixtures -------------------------------------------

launcher_dump="$TMP_DIR/launcher.dump"
cat > "$launcher_dump" <<'EOF'
ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
  * Task{abc #1 type=home}
    mResumedActivity: ActivityRecord{abc u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t1}
    topResumedActivity=ActivityRecord{abc u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t1}
    * Hist #1: ActivityRecord{def u0 com.android.settings/.Settings t2}
      packageName=com.android.settings
    * Hist #2: ActivityRecord{ghi u0 com.android.settings.intelligence/.X t3}
EOF

settings_dump="$TMP_DIR/settings.dump"
cat > "$settings_dump" <<'EOF'
  * Task{def #2 type=standard}
    mResumedActivity: ActivityRecord{def u0 com.android.settings/.Settings t2}
    topResumedActivity=ActivityRecord{def u0 com.android.settings/.Settings t2}
EOF

settings_fallback_dump="$TMP_DIR/settings-fallback.dump"
cat > "$settings_fallback_dump" <<'EOF'
  * Task{def #2 type=standard}
    mResumedActivity: ActivityRecord{def u0 com.android.settings/.Settings t2}
EOF

intelligence_dump="$TMP_DIR/intelligence.dump"
cat > "$intelligence_dump" <<'EOF'
  * Task{ghi #3 type=standard}
    topResumedActivity=ActivityRecord{ghi u0 com.android.settings.intelligence/.X t3}
EOF

assert_eq 'historical Settings is not the resumed component' \
    'com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher' \
    "$(resumed_component "$launcher_dump")"
assert_false 'historical Settings does not count as foreground Settings' \
    foreground_is "$launcher_dump" com.android.settings
assert_true 'the launcher is the foreground package after HOME' \
    foreground_is "$launcher_dump" com.launchernos.dotwellabs.debug
assert_true 'topResumedActivity Settings counts as foreground' \
    foreground_is "$settings_dump" com.android.settings
assert_true 'mResumedActivity is the fallback foreground field' \
    foreground_is "$settings_fallback_dump" com.android.settings
assert_false 'com.android.settings.intelligence is not com.android.settings' \
    foreground_is "$intelligence_dump" com.android.settings

# The own-widget bind consent is a specific platform activity. A package-only
# check would also accept another Settings activity, so the helper must match the
# exact component (short or fully qualified class). The shape mirrors the real
# CI134 activities-widget-placed-1.txt resumed component.
bind_activity_dump="$TMP_DIR/bind-activity.dump"
cat > "$bind_activity_dump" <<'EOF'
  * Task{def #2 type=standard}
    mResumedActivity: ActivityRecord{def u0 com.android.settings/.AllowBindAppWidgetActivity t2}
    topResumedActivity=ActivityRecord{def u0 com.android.settings/.AllowBindAppWidgetActivity t2}
EOF
assert_eq 'the CI134 bind consent resumed component is extracted exactly' \
    'com.android.settings/.AllowBindAppWidgetActivity' \
    "$(resumed_component "$bind_activity_dump")"
assert_true 'the short-form AllowBindAppWidgetActivity is the exact consent activity' \
    foreground_is_component "$bind_activity_dump" com.android.settings .AllowBindAppWidgetActivity
assert_true 'the fully qualified AllowBindAppWidgetActivity is the exact consent activity' \
    foreground_is_component "$bind_activity_dump" com.android.settings \
    com.android.settings.AllowBindAppWidgetActivity
assert_false 'another Settings activity is not the bind consent' \
    foreground_is_component "$settings_dump" com.android.settings .AllowBindAppWidgetActivity
assert_false 'the bind consent package is required exactly' \
    foreground_is_component "$bind_activity_dump" com.android.settings.intelligence \
    .AllowBindAppWidgetActivity

bind_lookalike_dump="$TMP_DIR/bind-lookalike.dump"
cat > "$bind_lookalike_dump" <<'EOF'
  * Task{def #2 type=standard}
    topResumedActivity=ActivityRecord{def u0 com.android.settings/.AllowBindAppWidgetActivityExtra t2}
EOF
assert_false 'a class suffix lookalike is not the bind consent' \
    foreground_is_component "$bind_lookalike_dump" com.android.settings .AllowBindAppWidgetActivity

bind_foreign_dump="$TMP_DIR/bind-foreign.dump"
cat > "$bind_foreign_dump" <<'EOF'
  * Task{def #2 type=standard}
    topResumedActivity=ActivityRecord{def u0 com.example.fake/.AllowBindAppWidgetActivity t2}
EOF
assert_false 'a foreign package with the same class is not the bind consent' \
    foreground_is_component "$bind_foreign_dump" com.android.settings .AllowBindAppWidgetActivity

assert_eq 'a brief resolve-activity component is parsed exactly' \
    'com.android.settings/.Settings' \
    "$(parse_resolved_component 'com.android.settings/.Settings')"
assert_eq 'a resolve-activity component after priority fields is parsed' \
    'com.android.settings/.wifi.WifiSettings' \
    "$(parse_resolved_component 'priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true
com.android.settings/.wifi.WifiSettings')"
assert_eq 'a Settings alias class is preserved without guessing' \
    'com.android.settings/.Settings$SoundSettingsActivity' \
    "$(parse_resolved_component 'com.android.settings/.Settings$SoundSettingsActivity')"
assert_eq 'a no-activity result yields no component' \
    '' \
    "$(parse_resolved_component 'No activity found')"

# --- UIAutomator result-node fixtures --------------------------------------

ancestor_xml="$TMP_DIR/ancestor.xml"
cat > "$ancestor_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="Settings" resource-id="header" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[0,0][100,50]" />
  <node index="1" text="" resource-id="item" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="true" enabled="true" bounds="[0,100][500,300]">
    <node index="0" text="Settings" resource-id="label" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[20,200][300,250]" />
  </node>
</hierarchy>
EOF
assert_eq 'the clickable Settings result wins over an earlier Settings header' \
    '0 100 500 300' \
    "$(ui_clickable_label_bounds "$ancestor_xml" Settings)"

direct_xml="$TMP_DIR/direct.xml"
cat > "$direct_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Settings" class="android.widget.TextView" content-desc="" clickable="true" bounds="[10,20][110,120]" />
</hierarchy>
EOF
assert_eq 'a directly clickable Settings node is used' \
    '10 20 110 120' \
    "$(ui_clickable_label_bounds "$direct_xml" Settings)"

desc_xml="$TMP_DIR/desc.xml"
cat > "$desc_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.TextView" content-desc="Settings" clickable="true" bounds="[5,6][7,8]" />
</hierarchy>
EOF
assert_eq 'a Settings content description is matched' \
    '5 6 7 8' \
    "$(ui_clickable_label_bounds "$desc_xml" Settings)"

none_xml="$TMP_DIR/none.xml"
cat > "$none_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Other" clickable="true" bounds="[1,2][3,4]" />
</hierarchy>
EOF
assert_eq 'no Settings node yields no bounds' \
    '' \
    "$(ui_clickable_label_bounds "$none_xml" Settings)"

# --- HOME geometry / drawer readiness fixtures ------------------------------

home_xml="$TMP_DIR/home.xml"
cat > "$home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="4:10" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,100][200,160]" />
    <node index="1" text="FRI 21 NOV" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,170][300,210]" />
    <node index="2" text="Phone" class="android.widget.TextView" content-desc="" clickable="true" bounds="[120,1400][240,1460]" />
    <node index="3" text="Messaging" class="android.widget.TextView" content-desc="" clickable="true" bounds="[300,1400][420,1460]" />
  </node>
</hierarchy>
EOF
assert_eq 'the UIAutomator root bounds are the measured display' \
    '0 0 1080 1920' \
    "$(ui_root_bounds "$home_xml")"
assert_eq 'the dock top comes from the lowest labelled row' \
    '1400' \
    "$(ui_dock_top "$home_xml" "$(ui_root_bounds "$home_xml")")"
assert_eq 'the dock bottom comes from the lowest labelled row' \
    '1460' \
    "$(ui_dock_bottom "$home_xml" "$(ui_root_bounds "$home_xml")")"
assert_eq 'the drawer swipe starts above the measured dock, not at 75 percent' \
    '540 1208 540 96' \
    "$(drawer_swipe_target 1080 1920 1400)"
assert_eq 'the drawer swipe falls back to 60 percent without a dock measurement' \
    '540 1152 540 96' \
    "$(drawer_swipe_target 1080 1920 '')"
assert_eq 'a high dock still keeps the swipe above it' \
    '540 1608 540 96' \
    "$(drawer_swipe_target 1080 1920 1800)"
assert_false 'an invalid display width cannot produce a swipe target' \
    drawer_swipe_target 0 1920 1400

# The actual CI87/CI97 HOME: root 1080x1920, a workspace HEADER search container
# at [22,91][1058,294], a hotseat whose icons end at y=1568, and the three
# bottom QSB "Search" nodes at y=1626..1794, y=1642..1778 and y=1679..1742.
# Those bottom nodes have no resource-id, so the old ui_dock_bottom treated the
# deepest one (1794) as the dock bottom and produced start 1898 instead of the
# intended 1616. The dock band must be measured from the same icon row as
# ui_dock_top, never from the bottom Search nodes.
actual_home_xml="$TMP_DIR/actual-home.xml"
cat > "$actual_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="4:10" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,100][200,160]" />
    <node index="1" text="FRI 21 NOV" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,170][300,210]" />
    <node index="2" text="Search" resource-id="com.launchernos.dotwellabs.debug:id/search_container_workspace" class="android.widget.EditText" content-desc="Search" clickable="true" bounds="[22,91][1058,294]" />
    <node index="3" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,1375][1080,1920]">
      <node index="0" text="Phone" class="android.widget.TextView" content-desc="" clickable="true" bounds="[22,1375][281,1568]" />
      <node index="1" text="Messaging" class="android.widget.TextView" content-desc="" clickable="true" bounds="[281,1375][540,1568]" />
      <node index="2" text="Contacts" class="android.widget.TextView" content-desc="" clickable="true" bounds="[540,1375][799,1568]" />
      <node index="3" text="WebView Browser Tester" class="android.widget.TextView" content-desc="" clickable="true" bounds="[799,1375][1058,1568]" />
    </node>
    <node index="4" text="" class="android.widget.TextView" content-desc="Search" clickable="true" bounds="[0,1626][1080,1794]" />
    <node index="5" text="" class="android.widget.TextView" content-desc="Search" clickable="true" bounds="[0,1642][1080,1778]" />
    <node index="6" text="" class="android.widget.TextView" content-desc="Search" clickable="true" bounds="[0,1679][1080,1742]" />
  </node>
</hierarchy>
EOF
assert_eq 'the actual HOME fixture includes all three id-less bottom Search nodes' \
    '3' \
    "$(grep 'content-desc="Search"' "$actual_home_xml" | grep -vc 'resource-id=')"
actual_root=$(ui_root_bounds "$actual_home_xml")
actual_dock_top=$(ui_dock_top "$actual_home_xml" "$actual_root")
actual_dock_bottom=$(ui_dock_bottom "$actual_home_xml" "$actual_root")
assert_eq 'the actual HOME dock top is measured from the hierarchy' \
    '1375' "$actual_dock_top"
assert_eq 'the actual HOME dock bottom comes from the hotseat icon band' \
    '1568' "$actual_dock_bottom"
actual_qsb_top=$(ui_qsb_top "$actual_home_xml" "$actual_dock_bottom")
assert_eq 'the workspace header is rejected as the bottom QSB' \
    '' "$actual_qsb_top"
assert_eq 'a QSB cannot be derived without a measured dock bottom' \
    '' \
    "$(ui_qsb_top "$actual_home_xml")"
actual_target=$(drawer_swipe_target \
    1080 1920 "$actual_dock_top" "$actual_dock_bottom" "$actual_qsb_top")
assert_eq 'the actual 1080x1920 HOME swipes from the measured gutter to the top' \
    '540 1616 540 96' "$actual_target"
actual_start=$(printf '%s\n' "$actual_target" | awk '{ print $2 }')
actual_end=$(printf '%s\n' "$actual_target" | awk '{ print $4 }')
actual_travel=$((actual_start - actual_end))
if [ "$actual_start" -gt 1568 ] && [ "$actual_start" -lt 1626 ]; then
    pass 'the actual swipe starts below the icons and above the bottom Search nodes'
else
    fail "the actual swipe start $actual_start is not in the 1568..1626 gutter"
fi
if [ "$actual_travel" -gt 1500 ]; then
    pass 'the actual swipe travels more than 1500 px'
else
    fail "the actual swipe only travels $actual_travel px"
fi
assert_false 'the actual HOME swipe does not use the old 1183 px fallback' \
    test "$actual_start" = 1183
assert_false 'the actual HOME swipe does not start at the Search-node-derived 1898' \
    test "$actual_start" = 1898
assert_true 'the actual 1080x1920 swipe covers more than half the display' \
    drawer_swipe_is_long_enough 1920 "$actual_start" "$actual_end"
assert_eq 'the actual 1080x1920 swipe covers 79.2 percent of the display' \
    '0.7917' \
    "$(drawer_swipe_travel_fraction 1920 "$actual_start" "$actual_end")"

# A real bottom QSB, when UIAutomator does expose one, still wins: the swipe
# starts in the dock/QSB gutter and the QSB is excluded from the dock band.
bottom_qsb_xml="$TMP_DIR/bottom-qsb.xml"
cat > "$bottom_qsb_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="Phone" class="android.widget.TextView" content-desc="" clickable="true" bounds="[22,1375][281,1568]" />
    <node index="1" text="Messaging" class="android.widget.TextView" content-desc="" clickable="true" bounds="[281,1375][540,1568]" />
    <node index="2" text="Search" resource-id="com.launchernos.dotwellabs.debug:id/search_container_workspace" class="android.widget.EditText" content-desc="Search" clickable="true" bounds="[0,1640][1080,1775]" />
  </node>
</hierarchy>
EOF
bottom_root=$(ui_root_bounds "$bottom_qsb_xml")
assert_eq 'a bottom QSB is excluded from the dock band' \
    '1568' \
    "$(ui_dock_bottom "$bottom_qsb_xml" "$bottom_root")"
assert_eq 'a bottom QSB below the dock is measured' \
    '1640' \
    "$(ui_qsb_top "$bottom_qsb_xml" 1568)"
assert_eq 'a bottom QSB still produces the dock/QSB gutter swipe' \
    '540 1604 540 96' \
    "$(drawer_swipe_target 1080 1920 1375 1568 1640)"
assert_true 'the bottom-QSB swipe covers more than half the display' \
    drawer_swipe_is_long_enough 1920 1604 96
assert_eq 'the bottom-QSB swipe covers 78.5 percent of the display' \
    '0.7854' \
    "$(drawer_swipe_travel_fraction 1920 1604 96)"
assert_false 'the old 799 px swipe is rejected as too short' \
    drawer_swipe_is_long_enough 1920 1183 384
assert_eq 'the old 799 px swipe only covers 41.6 percent of the display' \
    '0.4161' \
    "$(drawer_swipe_travel_fraction 1920 1183 384)"
assert_false 'the CI84 37.6 percent trace is rejected as too short' \
    drawer_swipe_is_long_enough 1920 722 0
assert_eq 'the CI84 trace displacement is 37.6 percent of the display' \
    '0.3760' \
    "$(drawer_swipe_travel_fraction 1920 722 0)"

assert_false 'a closed HOME is not a ready app drawer' \
    drawer_is_ready "$home_xml"

input_drawer_xml="$TMP_DIR/input-drawer.xml"
cat > "$input_drawer_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/input" class="app.lawnchair.allapps.FallbackSearchInputView" bounds="[40,100][1040,200]" />
</hierarchy>
EOF
assert_true 'a drawer search input makes the drawer ready' \
    drawer_is_ready "$input_drawer_xml"
assert_false 'an unchanged reference HOME is not a drawer transition' \
    drawer_is_ready "$input_drawer_xml" "$input_drawer_xml"
assert_true 'a drawer that differs from the reference HOME is ready' \
    drawer_is_ready "$input_drawer_xml" "$home_xml"

list_drawer_xml="$TMP_DIR/list-drawer.xml"
cat > "$list_drawer_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/apps_list_view" class="androidx.recyclerview.widget.RecyclerView" bounds="[0,300][1080,1920]" />
</hierarchy>
EOF
assert_true 'an app list container makes the drawer ready' \
    drawer_is_ready "$list_drawer_xml"

unrelated_xml="$TMP_DIR/unrelated.xml"
cat > "$unrelated_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Browser" class="android.widget.TextView" bounds="[0,1400][200,1460]" />
</hierarchy>
EOF
assert_false 'an unrelated label does not make the drawer ready' \
    drawer_is_ready "$unrelated_xml"

# --- grid settings fixtures -------------------------------------------------
# Shape copied from the actual grid-settings-attempt-6 dump: the preview is an
# AndroidViewHolder/ViewGroup holding the workspace id, the hotseat and the
# search container. Apply is a separate non-clickable TextView inside a
# non-clickable Button, with a visually greyed (but accessibility-enabled) state.

grid_xml="$TMP_DIR/grid-settings.xml"
cat > "$grid_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="Home screen grid" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,80][500,140]" />
    <node index="1" text="" class="androidx.recyclerview.widget.RecyclerView" content-desc="" clickable="false" bounds="[0,160][1080,950]">
      <node index="0" text="" class="android.view.ViewGroup" content-desc="" clickable="false" bounds="[375,294][706,883]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="android.view.ViewGroup" content-desc="" clickable="false" bounds="[375,313][706,844]">
          <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_container_workspace" class="android.view.ViewGroup" content-desc="" clickable="false" bounds="[375,313][706,360]" />
          <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.view.ViewGroup" content-desc="" clickable="false" bounds="[375,700][706,844]" />
        </node>
      </node>
    </node>
    <node index="2" text="Columns" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,980][300,1040]" />
    <node index="3" text="4" class="android.widget.TextView" content-desc="" clickable="false" bounds="[900,980][1040,1040]" />
    <node index="4" text="" class="android.widget.SeekBar" content-desc="" clickable="true" enabled="true" bounds="[40,1050][1040,1100]" />
    <node index="5" text="Rows" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,1120][300,1180]" />
    <node index="6" text="6" class="android.widget.TextView" content-desc="" clickable="false" bounds="[900,1120][1040,1180]" />
    <node index="7" text="" class="android.widget.SeekBar" content-desc="" clickable="true" enabled="true" bounds="[40,1190][1040,1240]" />
    <node index="8" text="Dock icons" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,1260][300,1320]" />
    <node index="9" text="4" class="android.widget.TextView" content-desc="" clickable="false" bounds="[900,1260][1040,1320]" />
    <node index="10" text="" class="android.widget.SeekBar" content-desc="" clickable="true" enabled="true" bounds="[40,1330][1040,1380]" />
    <node index="11" text="" class="android.view.View" content-desc="" clickable="false" enabled="true" bounds="[42,1621][1038,1758]">
      <node index="0" text="" class="android.widget.Button" content-desc="" clickable="false" enabled="true" bounds="[42,1637][1038,1742]" />
      <node index="1" text="Apply" class="android.widget.TextView" content-desc="" clickable="false" enabled="true" bounds="[488,1663][592,1716]" />
    </node>
  </node>
</hierarchy>
EOF
assert_true 'the real grid settings expose the workspace preview, labels, three sliders and Apply' \
    grid_settings_is_ready "$grid_xml"
assert_true 'the grid settings Apply is a non-clickable label inside a non-clickable Button' \
    grid_apply_is_unchanged "$grid_xml"

grid_no_preview="$TMP_DIR/grid-no-preview.xml"
sed '/resource-id="com.launchernos.dotwellabs.debug:id\/workspace"/d' \
    "$grid_xml" > "$grid_no_preview"
assert_false 'a grid settings page without the workspace preview is rejected' \
    grid_settings_is_ready "$grid_no_preview"

grid_preview_below_controls="$TMP_DIR/grid-preview-below-controls.xml"
sed '/resource-id="com.launchernos.dotwellabs.debug:id\/workspace"/s/\[375,313\]\[706,844\]/[375,313][706,1300]/' \
    "$grid_xml" > "$grid_preview_below_controls"
assert_false 'a preview workspace that is not above the controls is rejected' \
    grid_settings_is_ready "$grid_preview_below_controls"

grid_preview_no_hotseat="$TMP_DIR/grid-preview-no-hotseat.xml"
sed '/resource-id="com.launchernos.dotwellabs.debug:id\/hotseat"/d; /resource-id="com.launchernos.dotwellabs.debug:id\/search_container_workspace"/d' \
    "$grid_xml" > "$grid_preview_no_hotseat"
assert_false 'a preview workspace without its hotseat/search container is rejected' \
    grid_settings_is_ready "$grid_preview_no_hotseat"

grid_no_columns="$TMP_DIR/grid-no-columns.xml"
sed '/text="Columns"/d' "$grid_xml" > "$grid_no_columns"
assert_false 'a grid settings page without Columns is rejected' \
    grid_settings_is_ready "$grid_no_columns"

grid_two_sliders="$TMP_DIR/grid-two-sliders.xml"
sed '0,/class="android.widget.SeekBar"/s//class="android.view.View"/' \
    "$grid_xml" > "$grid_two_sliders"
assert_false 'a grid settings page with fewer than three sliders is rejected' \
    grid_settings_is_ready "$grid_two_sliders"

grid_apply_clickable="$TMP_DIR/grid-apply-clickable.xml"
sed '/text="Apply"/s/clickable="false"/clickable="true"/' \
    "$grid_xml" > "$grid_apply_clickable"
assert_false 'a clickable Apply is rejected because it means a grid change can be applied' \
    grid_apply_is_unchanged "$grid_apply_clickable"

grid_apply_no_button="$TMP_DIR/grid-apply-no-button.xml"
sed '/class="android.widget.Button"/d' "$grid_xml" > "$grid_apply_no_button"
assert_false 'an Apply label without its containing non-clickable Button is rejected' \
    grid_apply_is_unchanged "$grid_apply_no_button"

grid_apply_missing="$TMP_DIR/grid-apply-missing.xml"
sed '/text="Apply"/d' "$grid_xml" > "$grid_apply_missing"
assert_false 'a grid settings page without Apply is rejected' \
    grid_apply_is_unchanged "$grid_apply_missing"

# --- HOME long-press and widget picker fixtures ----------------------------

popup_xml="$TMP_DIR/home-popup.xml"
cat > "$popup_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/popup_container" class="android.widget.LinearLayout" content-desc="" clickable="false" bounds="[472,180][1039,743]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" content-desc="" clickable="true" bounds="[472,180][1039,317]">
      <node index="0" text="Wallpapers" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" content-desc="" clickable="false" bounds="[472,180][1039,317]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" content-desc="" clickable="true" bounds="[472,322][1039,459]">
      <node index="0" text="Widgets" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" content-desc="" clickable="false" bounds="[472,322][1039,459]" />
    </node>
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" content-desc="" clickable="true" bounds="[472,464][1039,601]">
      <node index="0" text="Apps list" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" content-desc="" clickable="false" bounds="[472,464][1039,601]" />
    </node>
    <node index="3" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" content-desc="" clickable="true" bounds="[472,606][1039,743]">
      <node index="0" text="Home settings" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" content-desc="" clickable="false" bounds="[472,606][1039,743]" />
    </node>
  </node>
</hierarchy>
EOF
assert_true 'the actual HOME options popup with popup_container and clickable shortcuts is ready' \
    home_popup_is_ready "$popup_xml"
assert_true 'the actual Widgets bubble_text label is not itself clickable' \
    grep -Fq 'text="Widgets"' "$popup_xml"
assert_false 'the Widgets label is not a clickable node' \
    grep -Eq 'text="Widgets"[^>]*clickable="true"' "$popup_xml"
assert_eq 'the Widgets bounds come from the clickable system_shortcut parent' \
    '472 322 1039 459' \
    "$(ui_clickable_label_bounds "$popup_xml" Widgets)"
assert_eq 'the Home settings bounds come from its clickable system_shortcut parent' \
    '472 606 1039 743' \
    "$(ui_clickable_label_bounds "$popup_xml" 'Home settings')"

assert_false 'the actual HOME without a popup is rejected' \
    home_popup_is_ready "$home_xml"

popup_text_only="$TMP_DIR/home-popup-text-only.xml"
cat > "$popup_text_only" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Wallpapers" class="android.widget.TextView" clickable="true" bounds="[472,180][1039,317]" />
  <node index="1" text="Widgets" class="android.widget.TextView" clickable="true" bounds="[472,322][1039,459]" />
  <node index="2" text="Home settings" class="android.widget.TextView" clickable="true" bounds="[472,606][1039,743]" />
</hierarchy>
EOF
assert_false 'English-only popup text without popup_container and system_shortcut rows is rejected' \
    home_popup_is_ready "$popup_text_only"

popup_no_widgets="$TMP_DIR/home-popup-no-widgets.xml"
sed '/text="Widgets"/d' "$popup_xml" > "$popup_no_widgets"
assert_false 'a HOME popup without Widgets is rejected' \
    home_popup_is_ready "$popup_no_widgets"

popup_app_specific="$TMP_DIR/home-popup-app-specific.xml"
cat > "$popup_app_specific" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/popup_container" class="android.widget.LinearLayout" bounds="[472,180][1039,459]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" clickable="true" bounds="[472,180][1039,317]">
      <node index="0" text="App info" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" clickable="false" bounds="[472,180][1039,317]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" clickable="true" bounds="[472,322][1039,459]">
      <node index="0" text="Widgets" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" clickable="false" bounds="[472,322][1039,459]" />
    </node>
  </node>
</hierarchy>
EOF
assert_false 'an item menu with Widgets but no home-level option is rejected' \
    home_popup_is_ready "$popup_app_specific"

popup_one_shortcut="$TMP_DIR/home-popup-one-shortcut.xml"
cat > "$popup_one_shortcut" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/popup_container" class="android.widget.LinearLayout" bounds="[472,180][1039,459]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/system_shortcut" class="android.widget.FrameLayout" clickable="true" bounds="[472,180][1039,459]">
      <node index="0" text="Widgets" resource-id="com.launchernos.dotwellabs.debug:id/bubble_text" class="android.widget.TextView" clickable="false" bounds="[472,180][1039,459]" />
    </node>
    <node index="1" text="Home settings" class="android.widget.TextView" clickable="false" bounds="[472,464][1039,601]" />
  </node>
</hierarchy>
EOF
assert_false 'a single clickable system_shortcut with an unparented home option is rejected' \
    home_popup_is_ready "$popup_one_shortcut"

picker_new_xml="$TMP_DIR/widgets-picker-new.xml"
cat > "$picker_new_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.android.launcher3.widgetpicker:id/widgets_catalog" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,200][1080,1920]">
    <node index="0" text="Search" class="android.widget.TextView" content-desc="" clickable="true" bounds="[80,260][1000,360]" />
    <node index="1" text="Featured" class="android.widget.TextView" content-desc="" clickable="true" bounds="[80,380][500,460]" />
    <node index="2" text="Browse" class="android.widget.TextView" content-desc="" clickable="true" bounds="[520,380][1000,460]" />
  </node>
</hierarchy>
EOF
assert_true 'the refactored native picker with its catalog tag and search/list is ready' \
    widget_picker_is_ready "$picker_new_xml" "$home_xml"
assert_false 'an identical reference HOME is not a widget picker' \
    widget_picker_is_ready "$picker_new_xml" "$picker_new_xml"

picker_old_xml="$TMP_DIR/widgets-picker-old.xml"
cat > "$picker_old_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.LinearLayout" bounds="[0,200][1080,360]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar" class="com.android.launcher3.widget.picker.search.LauncherWidgetsSearchBar" bounds="[40,220][1040,340]" />
  </node>
  <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,380][1080,1920]" />
</hierarchy>
EOF
assert_true 'the inherited native picker with its search bar and widget list is ready' \
    widget_picker_is_ready "$picker_old_xml" "$home_xml"

picker_loose_xml="$TMP_DIR/widgets-picker-loose.xml"
cat > "$picker_loose_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Search" class="android.widget.TextView" clickable="true" bounds="[0,0][1080,100]" />
  <node index="1" text="Widgets" class="android.widget.TextView" clickable="true" bounds="[0,100][1080,200]" />
</hierarchy>
EOF
assert_false 'English Search and Widgets text without a native picker marker is rejected' \
    widget_picker_is_ready "$picker_loose_xml" "$home_xml"

picker_no_search="$TMP_DIR/widgets-picker-no-search.xml"
sed '/text="Search"/d; /text="Featured"/d; /text="Browse"/d' \
    "$picker_new_xml" > "$picker_no_search"
assert_false 'a catalog tag without a search or list control is rejected' \
    widget_picker_is_ready "$picker_no_search" "$home_xml"

picker_old_no_list="$TMP_DIR/widgets-picker-old-no-list.xml"
sed '/primary_widgets_list_view/d' "$picker_old_xml" > "$picker_old_no_list"
assert_false 'an inherited search bar without the widget list is rejected' \
    widget_picker_is_ready "$picker_old_no_list" "$home_xml"

# --- widget placement fixtures ---------------------------------------------
# Shape copied from the CI110 picker dump: a clickable widgets_list_header with
# app_title/app_subtitle, a widget_preview_container inside a WidgetCell, and a
# DotWel header that exposes only a shortcut. The helper must select a provider
# with a positive widget count and must never select the shortcut-only row.

widget_headers_xml="$TMP_DIR/widget-headers.xml"
cat > "$widget_headers_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,400][1080,520]">
      <node index="0" text="Calendar" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" clickable="false" bounds="[100,420][300,460]" />
      <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" clickable="false" bounds="[100,465][300,500]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,540][1080,660]">
      <node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" clickable="false" bounds="[100,560][300,600]" />
      <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" clickable="false" bounds="[100,605][300,640]" />
    </node>
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[80,700][500,1000]" />
    <node index="3" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,1100][1080,1220]">
      <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" clickable="false" bounds="[100,1120][300,1160]" />
      <node index="1" text="1 shortcut" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" clickable="false" bounds="[100,1165][300,1200]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a real Clock provider header is selected by its measured bounds' \
    '0 540 1080 660' \
    "$(widget_picker_provider_bounds "$widget_headers_xml" Clock)"
assert_eq 'a real Calendar provider header is selected by its measured bounds' \
    '0 400 1080 520' \
    "$(widget_picker_provider_bounds "$widget_headers_xml" Calendar)"
assert_eq 'a shortcut-only provider header is not selected as a widget' \
    '' \
    "$(widget_picker_provider_bounds "$widget_headers_xml" 'DotWel Launcher')"
assert_eq 'a missing provider header yields no bounds' \
    '' \
    "$(widget_picker_provider_bounds "$widget_headers_xml" Weather)"
assert_eq 'the widget preview below the expanded Clock header is measured' \
    '80 700 500 1000' \
    "$(widget_picker_preview_bounds "$widget_headers_xml" '0 540 1080 660')"
assert_eq 'a preview above the selected header is rejected' \
    '' \
    "$(widget_picker_preview_bounds "$widget_headers_xml" '0 1100 1080 1220')"
assert_eq 'a HOME without a widget preview yields no preview bounds' \
    '' \
    "$(widget_picker_preview_bounds "$home_xml" '0 540 1080 660')"

# Expanding a provider can move its header and the following header. The
# expanded hierarchy must be re-resolved by title, or a stale header can skip
# the real preview and associate a later provider's preview instead.
widget_headers_expanded_xml="$TMP_DIR/widget-headers-expanded.xml"
cat > "$widget_headers_expanded_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,200][1080,320]">
      <node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,220][300,260]" />
      <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,265][300,300]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,360][500,660]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,1100][1080,1220]">
      <node index="0" text="Calendar" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,1120][300,1160]" />
      <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,1165][300,1200]" />
    </node>
    <node index="3" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,1300][500,1600]" />
  </node>
</hierarchy>
EOF
assert_eq 'the expanded title header is re-resolved by title' \
    '0 200 1080 320' \
    "$(widget_picker_provider_bounds "$widget_headers_expanded_xml" Clock)"
assert_eq 'a stale collapsed header does not select an expanded provider preview' \
    '' \
    "$(widget_picker_preview_bounds "$widget_headers_expanded_xml" '0 540 1080 660')"
assert_eq 'the expanded title header associates the preview with the selected provider' \
    '80 360 500 660' \
    "$(widget_picker_preview_bounds "$widget_headers_expanded_xml" '0 200 1080 320')"

# CI161: one provider can expose several WidgetCells at the same vertical
# position. The selected consent identity is the widget_name of the exact cell
# that owns the measured preview, never the provider header or the first global
# widget_name. The left/right cells below share a y range, so only the measured
# preview bounds can disambiguate them.
widget_caption_cells_xml="$TMP_DIR/widget-caption-cells.xml"
cat > "$widget_caption_cells_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
      <node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
      <node index="1" text="2 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
    </node>
    <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[60,460][500,860]" />
      <node index="1" text="" class="android.widget.FrameLayout" bounds="[40,860][520,900]">
        <node index="0" text="" class="android.widget.LinearLayout" resource-id="com.launchernos.dotwellabs.debug:id/widget_text_container" bounds="[40,860][520,900]">
          <node index="0" text="Analog clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[180,860][400,900]" />
        </node>
      </node>
    </node>
    <node index="2" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[580,460][1020,860]" />
      <node index="1" text="" class="android.widget.FrameLayout" bounds="[560,860][1040,900]">
        <node index="0" text="" class="android.widget.LinearLayout" resource-id="com.launchernos.dotwellabs.debug:id/widget_text_container" bounds="[560,860][1040,900]">
          <node index="0" text="Digital clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[700,860][920,900]" />
        </node>
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the selected left preview maps to its own Analog clock caption' \
    '60 460 500 860' \
    "$(widget_picker_preview_bounds "$widget_caption_cells_xml" '0 300 1080 420')"
assert_eq 'the left preview caption is Analog clock, not the provider header Clock' \
    'Analog clock' \
    "$(widget_picker_selected_caption "$widget_caption_cells_xml" '60 460 500 860')"
assert_eq 'the same-row right preview maps to its own Digital clock caption' \
    'Digital clock' \
    "$(widget_picker_selected_caption "$widget_caption_cells_xml" '580 460 1020 860')"
assert_eq 'the provider title Clock is not a preview caption' \
    '' \
    "$(widget_picker_selected_caption "$widget_caption_cells_xml" '0 300 1080 420')"

widget_caption_calendar_xml="$TMP_DIR/widget-caption-calendar.xml"
cat > "$widget_caption_calendar_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
      <node index="0" text="Calendar" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
      <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
    </node>
    <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][1040,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][1020,860]" />
      <node index="1" text="" class="android.widget.FrameLayout" bounds="[40,860][1040,900]">
        <node index="0" text="Calendar" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[400,860][680,900]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a provider and widget with the same Calendar name is accepted from the same cell' \
    'Calendar' \
    "$(widget_picker_selected_caption "$widget_caption_calendar_xml" '60 460 1020 860')"

widget_caption_dotwel_xml="$TMP_DIR/widget-caption-dotwel.xml"
cat > "$widget_caption_dotwel_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
      <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
      <node index="1" text="2 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
    </node>
    <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
      <node index="1" text="DotWel Clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[180,860][400,900]" />
    </node>
    <node index="2" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[580,460][1020,860]" />
      <node index="1" text="DotWel Battery" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[700,860][920,900]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the own DotWel group keeps distinct per-cell captions' \
    'DotWel Clock' \
    "$(widget_picker_selected_caption "$widget_caption_dotwel_xml" '60 460 500 860')"
assert_eq 'the other own DotWel cell keeps its own caption' \
    'DotWel Battery' \
    "$(widget_picker_selected_caption "$widget_caption_dotwel_xml" '580 460 1020 860')"

widget_caption_missing_xml="$TMP_DIR/widget-caption-missing.xml"
cat > "$widget_caption_missing_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
  </node>
</hierarchy>
EOF
assert_eq 'a WidgetCell without a widget_name caption fails closed' \
    '' \
    "$(widget_picker_selected_caption "$widget_caption_missing_xml" '60 460 500 860')"

widget_caption_ambiguous_xml="$TMP_DIR/widget-caption-ambiguous.xml"
cat > "$widget_caption_ambiguous_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
    <node index="1" text="Analog clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[180,860][400,900]" />
    <node index="2" text="Digital clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[180,900][400,940]" />
  </node>
</hierarchy>
EOF
assert_eq 'a WidgetCell with two different widget_name captions fails closed' \
    '' \
    "$(widget_picker_selected_caption "$widget_caption_ambiguous_xml" '60 460 500 860')"

widget_caption_unrelated_xml="$TMP_DIR/widget-caption-unrelated.xml"
cat > "$widget_caption_unrelated_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
  </node>
  <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
    <node index="0" text="Digital clock" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[700,860][920,900]" />
  </node>
</hierarchy>
EOF
assert_eq 'a caption from another WidgetCell is never used for the selected preview' \
    '' \
    "$(widget_picker_selected_caption "$widget_caption_unrelated_xml" '60 460 500 860')"

# A provider header can own several variants. The optional Weather cell must be
# identified by its own exact widget_description, never by the header or by
# position, so a Clock at the same row can never be tapped.
widget_description_cells_xml="$TMP_DIR/widget-description-cells.xml"
cat > "$widget_description_cells_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
      <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
      <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
    </node>
    <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[60,460][500,860]" />
      <node index="1" text="Dot matrix clock, opens clock settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[80,860][480,900]" />
    </node>
    <node index="2" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[580,460][1020,860]" />
      <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[600,860][1000,900]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the exact Weather description selects its own measured preview' \
    '580 460 1020 860' \
    "$(widget_picker_description_preview_bounds "$widget_description_cells_xml" 'Weather, opens weather settings')"
assert_eq 'a near-match Weather description is not accepted' \
    '' \
    "$(widget_picker_description_preview_bounds "$widget_description_cells_xml" 'Weather')"
assert_eq 'the Clock description never selects the Weather preview' \
    '60 460 500 860' \
    "$(widget_picker_description_preview_bounds "$widget_description_cells_xml" 'Dot matrix clock, opens clock settings')"

widget_description_duplicate_xml="$TMP_DIR/widget-description-duplicate.xml"
cat > "$widget_description_duplicate_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
    <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[80,860][480,900]" />
  </node>
  <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[580,460][1020,860]" />
    <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[600,860][1000,900]" />
  </node>
</hierarchy>
EOF
assert_eq 'two cells with the same Weather description fail closed' \
    '' \
    "$(widget_picker_description_preview_bounds "$widget_description_duplicate_xml" 'Weather, opens weather settings')"

widget_description_missing_xml="$TMP_DIR/widget-description-missing.xml"
cat > "$widget_description_missing_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[60,460][500,860]" />
    <node index="1" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[180,860][400,900]" />
  </node>
</hierarchy>
EOF
assert_eq 'a Weather cell without an exposed description fails closed' \
    '' \
    "$(widget_picker_description_preview_bounds "$widget_description_missing_xml" 'Weather, opens weather settings')"
assert_eq 'an unknown widget description fails closed' \
    '' \
    "$(widget_picker_description_preview_bounds "$widget_description_cells_xml" 'No such widget description')"

# --- Weather picker collapse-regression fixtures ---------------------------
# CI283 attempt2: the DotWel provider was already expanded but its Weather cell
# was clipped at the bottom, so the strict description/preview helper returned
# nothing. The old loop mistook that for a collapsed provider, tapped the header
# again and collapsed it. The pure decision must now reveal the clipped expanded
# cell by measured scrolling and must never expand an already-expanded provider.

weather_picker_clipped_xml="$TMP_DIR/weather-picker-clipped.xml"
cat > "$weather_picker_clipped_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[239,1441][557,1498]">
        <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,1450][300,1490]" />
        <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,1490][300,1498]" />
      </node>
      <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" content-desc="Weather, opens weather settings" bounds="[69,1610][1011,1920]" />
    </node>
  </node>
</hierarchy>
EOF
weather_picker_clipped_viewport=$(widget_picker_viewport_bounds "$weather_picker_clipped_xml")
assert_eq 'the CI283 clipped expanded Weather picker viewport is measured' \
    '0 350 1080 1820' "$weather_picker_clipped_viewport"
assert_eq 'the strict helper still finds no complete pair in the clipped cell' \
    '' \
    "$(widget_picker_description_preview_bounds "$weather_picker_clipped_xml" 'Weather, opens weather settings')"
assert_eq 'the clipped Weather provider is classified as expanded, not collapsed' \
    'expanded' \
    "$(widget_picker_provider_state "$weather_picker_clipped_xml" '239 1441 557 1498')"
assert_eq 'the clipped expanded Weather cell content is measured for scroll direction' \
    '69 1610 1011 1920' \
    "$(widget_picker_provider_content_bounds "$weather_picker_clipped_xml" '239 1441 557 1498')"
assert_eq 'the clipped expanded Weather cell needs a downward reveal' \
    'down' \
    "$(widget_picker_weather_scroll_direction \
        '69 1610 1011 1920' "$weather_picker_clipped_viewport" '239 1441 557 1498')"
assert_eq 'the measured reveal scroll stays inside the clipped picker list' \
    '540 1528 652' \
    "$(widget_picker_scroll_target_dir "$weather_picker_clipped_xml" down)"
assert_eq 'the opposite reveal scroll is bounded to the same measured list' \
    '540 652 1528' \
    "$(widget_picker_scroll_target_dir "$weather_picker_clipped_xml" up)"
assert_eq 'the loop decision reveals a clipped already-expanded provider instead of collapsing it' \
    'reveal' \
    "$(widget_picker_weather_decision "$weather_picker_clipped_xml" \
        '239 1441 557 1498' '' "$weather_picker_clipped_viewport" 1 0 2 4)"
assert_eq 'the loop decision never expands an already-expanded clipped provider' \
    'reveal' \
    "$(widget_picker_weather_decision "$weather_picker_clipped_xml" \
        '239 1441 557 1498' '' "$weather_picker_clipped_viewport" 0 0 2 4)"
assert_eq 'the clipped expanded provider fails closed after the bounded reveal scrolls' \
    'fail' \
    "$(widget_picker_weather_decision "$weather_picker_clipped_xml" \
        '239 1441 557 1498' '' "$weather_picker_clipped_viewport" 1 4 2 4)"

weather_picker_visible_xml="$TMP_DIR/weather-picker-visible.xml"
cat > "$weather_picker_visible_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[239,600][557,657]">
        <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,610][300,650]" />
        <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,650][300,657]" />
      </node>
      <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[69,769][1011,1080]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[100,790][980,1000]" />
        <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[100,1010][980,1060]" />
        <node index="2" text="Weather" resource-id="com.launchernos.dotwellabs.debug:id/widget_name" class="android.widget.TextView" bounds="[100,1062][980,1078]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
weather_picker_visible_viewport=$(widget_picker_viewport_bounds "$weather_picker_visible_xml")
weather_picker_visible_candidate=$(widget_picker_description_preview_bounds \
    "$weather_picker_visible_xml" 'Weather, opens weather settings')
assert_eq 'after the reveal scroll the exact Weather preview is measured' \
    '100 790 980 1000' "$weather_picker_visible_candidate"
assert_eq 'after the reveal scroll the exact Weather cell is fully visible and selected' \
    'select' \
    "$(widget_picker_weather_decision "$weather_picker_visible_xml" \
        '239 600 557 657' "$weather_picker_visible_candidate" \
        "$weather_picker_visible_viewport" 1 1 2 4)"
assert_eq 'the fully visible Weather cell still exposes its own caption' \
    'Weather' \
    "$(widget_picker_selected_caption "$weather_picker_visible_xml" \
        "$weather_picker_visible_candidate")"

weather_picker_collapsed_xml="$TMP_DIR/weather-picker-collapsed.xml"
cat > "$weather_picker_collapsed_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
        <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
        <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
      </node>
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,900][1080,1020]">
        <node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,920][300,960]" />
        <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,965][300,1000]" />
      </node>
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,1100][500,1400]" />
    </node>
  </node>
</hierarchy>
EOF
weather_picker_collapsed_viewport=$(widget_picker_viewport_bounds "$weather_picker_collapsed_xml")
assert_eq 'a collapsed DotWel provider is classified as collapsed' \
    'collapsed' \
    "$(widget_picker_provider_state "$weather_picker_collapsed_xml" '0 300 1080 420')"
assert_eq 'a collapsed provider never claims the next provider preview as its content' \
    '' \
    "$(widget_picker_provider_content_bounds "$weather_picker_collapsed_xml" '0 300 1080 420')"
assert_eq 'the loop decision expands a genuinely collapsed provider' \
    'expand' \
    "$(widget_picker_weather_decision "$weather_picker_collapsed_xml" \
        '0 300 1080 420' '' "$weather_picker_collapsed_viewport" 0 0 2 4)"

weather_picker_duplicate_xml="$TMP_DIR/weather-picker-duplicate.xml"
cat > "$weather_picker_duplicate_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
        <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
        <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
      </node>
      <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[60,460][500,860]" />
        <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[80,860][480,900]" />
      </node>
      <node index="2" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[560,440][1040,900]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[580,460][1020,860]" />
        <node index="1" text="Weather, opens weather settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[600,860][1000,900]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
weather_picker_duplicate_viewport=$(widget_picker_viewport_bounds "$weather_picker_duplicate_xml")
assert_eq 'duplicate Weather cells never resolve to one strict preview' \
    '' \
    "$(widget_picker_description_preview_bounds "$weather_picker_duplicate_xml" 'Weather, opens weather settings')"
assert_eq 'the loop decision never selects an ambiguous duplicate Weather cell' \
    'reveal' \
    "$(widget_picker_weather_decision "$weather_picker_duplicate_xml" \
        '0 300 1080 420' '' "$weather_picker_duplicate_viewport" 0 0 2 4)"
assert_eq 'an ambiguous Weather provider fails closed after the bounded scrolls' \
    'fail' \
    "$(widget_picker_weather_decision "$weather_picker_duplicate_xml" \
        '0 300 1080 420' '' "$weather_picker_duplicate_viewport" 0 4 2 4)"

weather_picker_wrong_cell_xml="$TMP_DIR/weather-picker-wrong-cell.xml"
cat > "$weather_picker_wrong_cell_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,300][1080,420]">
        <node index="0" text="DotWel Launcher" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,320][300,360]" />
        <node index="1" text="4 widgets" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,365][300,400]" />
      </node>
      <node index="1" text="" class="com.android.launcher3.widget.WidgetCell" bounds="[40,440][520,900]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[60,460][500,860]" />
        <node index="1" text="Dot matrix clock, opens clock settings" resource-id="com.launchernos.dotwellabs.debug:id/widget_description" class="android.widget.TextView" bounds="[80,860][480,900]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
weather_picker_wrong_viewport=$(widget_picker_viewport_bounds "$weather_picker_wrong_cell_xml")
assert_eq 'a wrong-provider cell never resolves to the Weather description' \
    '' \
    "$(widget_picker_description_preview_bounds "$weather_picker_wrong_cell_xml" 'Weather, opens weather settings')"
assert_eq 'the loop decision never selects a wrong-provider cell' \
    'reveal' \
    "$(widget_picker_weather_decision "$weather_picker_wrong_cell_xml" \
        '0 300 1080 420' '' "$weather_picker_wrong_viewport" 0 0 2 4)"

widget_add_xml="$TMP_DIR/widget-add.xml"
cat > "$widget_add_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Add" resource-id="com.launchernos.dotwellabs.debug:id/widget_add_button" class="android.widget.Button" content-desc="Add Clock widget" clickable="true" enabled="true" bounds="[200,800][400,900]" />
</hierarchy>
EOF
assert_eq 'the exposed enabled widget Add button is selected by its resource id' \
    '200 800 400 900' \
    "$(widget_picker_add_button_bounds "$widget_add_xml")"
assert_eq 'an English Add label without the add-button id is rejected' \
    '' \
    "$(widget_picker_add_button_bounds "$home_xml")"

widget_add_disabled_xml="$TMP_DIR/widget-add-disabled.xml"
cat > "$widget_add_disabled_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Add" resource-id="com.launchernos.dotwellabs.debug:id/widget_add_button" class="android.widget.Button" clickable="true" enabled="false" bounds="[200,800][400,900]" />
</hierarchy>
EOF
assert_eq 'a disabled Add button is not a safe tap target' \
    '' \
    "$(widget_picker_add_button_bounds "$widget_add_disabled_xml")"

# CI120 exposed Add at [434,1755][645,1881] on the real picker while the
# navigation bar begins around 1800. The root-100 viewport bottom is 1820, so the
# original Add centre 1818 is unsafe. The safe intersection must be pulled above
# the navigation bar and only tapped when it is still large enough.
widget_add_low_xml="$TMP_DIR/widget-add-low.xml"
cat > "$widget_add_low_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]" />
    <node index="2" text="Add" resource-id="com.launchernos.dotwellabs.debug:id/widget_add_button" class="android.widget.Button" clickable="true" enabled="true" bounds="[434,1755][645,1881]" />
  </node>
</hierarchy>
EOF
widget_add_low_viewport=$(widget_picker_viewport_bounds "$widget_add_low_xml")
assert_eq 'the CI120 Add viewport is remeasured from the exposed Add hierarchy' \
    '0 350 1080 1820' \
    "$widget_add_low_viewport"
assert_eq 'the CI120 partially hidden Add has a safe intersection above the navigation bar' \
    '434 1755 645 1788' \
    "$(widget_add_safe_bounds '434 1755 645 1881' "$widget_add_low_viewport")"
assert_eq 'a fully visible Add keeps a safe tappable intersection' \
    '200 800 400 868' \
    "$(widget_add_safe_bounds '200 800 400 900' "$widget_add_low_viewport")"
assert_eq 'a fully hidden Add below the viewport has no safe intersection' \
    '' \
    "$(widget_add_safe_bounds '434 1830 645 1881' "$widget_add_low_viewport")"
assert_eq 'a barely visible Add leaves no large-enough safe intersection' \
    '' \
    "$(widget_add_safe_bounds '434 1775 645 1881' "$widget_add_low_viewport")"
assert_eq 'an Add outside the horizontal viewport has no safe intersection' \
    '' \
    "$(widget_add_safe_bounds '1100 1755 1300 1881' "$widget_add_low_viewport")"

# A real CI114 picker: the Calendar header sits near the bottom and its preview
# is clipped to 51 px under the navigation bar. The usable viewport is below the
# search bar and 100 px above the root bottom, so the clipped preview must be
# rejected even though its resource id is valid.
widget_picker_clipped_xml="$TMP_DIR/widget-picker-clipped.xml"
cat > "$widget_picker_clipped_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[29,1592][1051,1827]">
        <node index="0" text="Calendar" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,1620][300,1680]" />
        <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,1690][300,1740]" />
      </node>
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[297,1869][783,1920]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the real widgets_search_bar_edit_text bounds are measured' \
    '40 310 1040 350' \
    "$(widget_picker_search_bar_bounds "$widget_picker_clipped_xml")"
assert_eq 'the viewport starts below the search bar and ends 100 px above the root bottom' \
    '0 350 1080 1820' \
    "$(widget_picker_viewport_bounds "$widget_picker_clipped_xml")"
assert_false 'the CI114 clipped 51 px preview is rejected even with a valid id' \
    widget_picker_preview_is_visible '297 1869 783 1920' \
    "$(widget_picker_viewport_bounds "$widget_picker_clipped_xml")"
assert_eq 'the genuine scroll stays inside the measured list above the navigation margin' \
    '540 1528 652' \
    "$(widget_picker_scroll_target "$widget_picker_clipped_xml")"

widget_picker_visible_xml="$TMP_DIR/widget-picker-visible.xml"
cat > "$widget_picker_visible_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/search_bar_container" class="android.widget.FrameLayout" bounds="[0,300][1080,360]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_search_bar_edit_text" class="android.widget.EditText" bounds="[40,310][1040,350]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/primary_widgets_list_view" class="com.android.launcher3.widget.picker.WidgetsRecyclerView" bounds="[0,360][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[29,400][1051,480]">
        <node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,420][300,460]" />
        <node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,465][300,500]" />
      </node>
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" long-clickable="true" bounds="[297,500][783,800]" />
    </node>
  </node>
</hierarchy>
EOF
assert_true 'a fully visible Clock preview above the navigation margin is accepted' \
    widget_picker_preview_is_visible '297 500 783 800' \
    "$(widget_picker_viewport_bounds "$widget_picker_visible_xml")"
assert_false 'a preview above the search bar is rejected' \
    widget_picker_preview_is_visible '297 200 783 400' \
    "$(widget_picker_viewport_bounds "$widget_picker_visible_xml")"
assert_false 'a tall preview whose bottom is under the navigation margin is rejected' \
    widget_picker_preview_is_visible '297 1750 783 1850' \
    "$(widget_picker_viewport_bounds "$widget_picker_visible_xml")"

placed_home_xml="$TMP_DIR/placed-home.xml"
cat > "$placed_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="4:10" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,100][200,160]" />
    <node index="1" text="FRI 21 NOV" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,170][300,210]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" content-desc="" clickable="false" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" clickable="false" long-clickable="true" bounds="[40,400][500,700]" />
    </node>
    <node index="3" text="Phone" class="android.widget.TextView" content-desc="" clickable="true" bounds="[120,1400][240,1460]" />
  </node>
</hierarchy>
EOF
assert_eq 'a new workspace AppWidgetHostView is detected against the pre-widget HOME' \
    '40 400 500 700' \
    "$(home_widget_bounds "$placed_home_xml" "$home_xml")"
assert_eq 'the same AppWidgetHostView already present in the reference is not new' \
    '' \
    "$(home_widget_bounds "$placed_home_xml" "$placed_home_xml")"
assert_eq 'a HOME without an AppWidgetHostView yields no placed-widget bounds' \
    '' \
    "$(home_widget_bounds "$home_xml" "$home_xml")"

# UIAutomator can emit the whole hierarchy on one line, so the host must be
# found from node records, not from the first attribute on the file line.
compact_home_xml="$TMP_DIR/home-compact.xml"
cat > "$compact_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="Phone" class="android.widget.TextView" clickable="true" bounds="[120,1400][240,1460]" /></node></hierarchy>
EOF
assert_eq 'a compact HOME without a host yields no placed-widget bounds' \
    '' \
    "$(home_widget_bounds "$compact_home_xml" "$compact_home_xml")"

compact_placed_home_xml="$TMP_DIR/placed-home-compact.xml"
cat > "$compact_placed_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" clickable="false" long-clickable="true" bounds="[40,400][500,700]" /></node><node index="1" text="Phone" class="android.widget.TextView" clickable="true" bounds="[120,1400][240,1460]" /></node></hierarchy>
EOF
assert_eq 'a compact single-line workspace host is detected against a pretty reference' \
    '40 400 500 700' \
    "$(home_widget_bounds "$compact_placed_home_xml" "$home_xml")"
assert_eq 'the same compact host is not new against an identical reference' \
    '' \
    "$(home_widget_bounds "$compact_placed_home_xml" "$compact_placed_home_xml")"
assert_eq 'an empty reference still treats the current hierarchy as current' \
    '40 400 500 700' \
    "$(home_widget_bounds "$compact_placed_home_xml" '')"

compact_preview_home_xml="$TMP_DIR/placed-home-preview-compact.xml"
cat > "$compact_preview_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,400][1080,520]"><node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,420][300,460]" /><node index="1" text="1 widget" resource-id="com.launchernos.dotwellabs.debug:id/app_subtitle" class="android.widget.TextView" bounds="[100,465][300,500]" /></node><node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,540][500,840]"><node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[80,540][500,840]" /></node></node></hierarchy>
EOF
assert_eq 'a compact sheet-preview host is not a workspace widget' \
    '' \
    "$(home_widget_bounds "$compact_preview_home_xml" "$home_xml")"

compact_mixed_home_xml="$TMP_DIR/placed-home-mixed-compact.xml"
cat > "$compact_mixed_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widgets_list_header" class="com.android.launcher3.widget.picker.WidgetsListHeader" clickable="true" bounds="[0,200][1080,320]"><node index="0" text="Clock" resource-id="com.launchernos.dotwellabs.debug:id/app_title" class="android.widget.TextView" bounds="[100,220][300,260]" /></node><node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,360][500,660]"><node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[80,360][500,660]" /></node><node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,700][1080,1375]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,900][500,1200]" /></node></node></hierarchy>
EOF
assert_eq 'a compact preview host is ignored in favour of the workspace host' \
    '40 900 500 1200' \
    "$(home_widget_bounds "$compact_mixed_home_xml" "$home_xml")"

compact_outside_ws_xml="$TMP_DIR/placed-home-outside-workspace-compact.xml"
cat > "$compact_outside_ws_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]" /><node index="1" text="" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,900][500,1200]" /></node></hierarchy>
EOF
assert_eq 'a host outside a workspace that is present is rejected' \
    '' \
    "$(home_widget_bounds "$compact_outside_ws_xml" "$home_xml")"

# The optional Weather widget is identified by both of its own child ids inside
# a new workspace host. A clock/battery host at another geometry, a Weather id
# elsewhere on the page, a duplicate Weather host, a preview host and a host
# already in the reference all fail closed.
weather_home_ref_xml="$TMP_DIR/weather-home-ref.xml"
cat > "$weather_home_ref_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" bounds="[556,328][1042,738]" />
    </node>
  </node>
</hierarchy>
EOF
weather_home_placed_xml="$TMP_DIR/weather-home-placed.xml"
cat > "$weather_home_placed_xml" <<EOF
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" bounds="[556,328][1042,738]" />
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" bounds="[38,770][524,1170]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_NOT_CONNECTED_CONTENT_DESCRIPTION" class="android.widget.FrameLayout" bounds="[42,774][520,1166]">
          <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" class="android.widget.TextView" bounds="[60,790][300,850]" />
          <node index="1" text="$WEATHER_WIDGET_NOT_CONNECTED_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" class="android.widget.TextView" bounds="[60,860][420,900]" />
          <node index="2" text="$WEATHER_WIDGET_NOT_CONNECTED_ASOF" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" class="android.widget.TextView" bounds="[60,910][420,950]" />
        </node>
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a new workspace host with both Weather child ids yields its measured bounds' \
    '38 770 524 1170' \
    "$(home_weather_widget_bounds "$weather_home_placed_xml" "$weather_home_ref_xml")"
assert_eq 'the same Weather host already in the reference is not new' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_placed_xml" "$weather_home_placed_xml")"
assert_eq 'a page without a Weather child yields no Weather host' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_ref_xml" "$weather_home_ref_xml")"

weather_home_missing_detail_xml="$TMP_DIR/weather-home-missing-detail.xml"
cat > "$weather_home_missing_detail_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[38,770][524,1170]">
        <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" class="android.widget.TextView" bounds="[60,790][300,850]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a host with only the Weather value id fails closed' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_missing_detail_xml" "$weather_home_ref_xml")"

weather_home_outside_host_xml="$TMP_DIR/weather-home-outside-host.xml"
cat > "$weather_home_outside_host_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" class="android.widget.TextView" bounds="[60,790][300,850]" />
      <node index="1" text="No forecast yet" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" class="android.widget.TextView" bounds="[60,860][420,900]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'Weather ids outside any host do not prove a widget' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_outside_host_xml" "$weather_home_ref_xml")"

weather_home_duplicate_xml="$TMP_DIR/weather-home-duplicate.xml"
cat > "$weather_home_duplicate_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[38,770][524,1170]">
        <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[60,790][300,850]" />
        <node index="1" text="No forecast yet" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[60,860][420,900]" />
      </node>
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[556,770][1042,1170]">
        <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[580,790][820,850]" />
        <node index="1" text="No forecast yet" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[580,860][940,900]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'two new Weather hosts fail closed as ambiguous' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_duplicate_xml" "$weather_home_ref_xml")"

weather_home_preview_xml="$TMP_DIR/weather-home-preview.xml"
cat > "$weather_home_preview_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" clickable="true" bounds="[80,360][500,660]">
      <node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[80,360][500,660]">
        <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[100,380][300,440]" />
        <node index="1" text="No forecast yet" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[100,450][420,490]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a Weather-looking host inside the picker preview is rejected' \
    '' \
    "$(home_weather_widget_bounds "$weather_home_preview_xml" "$weather_home_ref_xml")"

assert_true 'the non-overlapping placed Weather host is clear of the existing hosts' \
    home_widget_bounds_clear_of "$weather_home_placed_xml" '38 770 524 1170'
assert_false 'a Weather host overlapping the clock host is rejected' \
    home_widget_bounds_clear_of "$weather_home_ref_xml" '38 700 524 1100'
assert_true 'adjacent Weather bounds do not count as overlap' \
    home_widget_bounds_clear_of "$weather_home_ref_xml" '38 738 524 1138'

weather_off_xml="$TMP_DIR/weather-off.xml"
cat > "$weather_off_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_OFF_CONTENT_DESCRIPTION" clickable="true" bounds="[0,0][500,200]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'the truthful disabled Weather copy is accepted as off' \
    'off' \
    "$(weather_widget_text_is_truthful "$weather_off_xml")"
assert_eq 'the truthful not-connected Weather copy is accepted' \
    'not_connected' \
    "$(weather_widget_text_is_truthful "$weather_home_placed_xml")"

weather_forecast_xml="$TMP_DIR/weather-forecast.xml"
cat > "$weather_forecast_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_NOT_CONNECTED_CONTENT_DESCRIPTION" bounds="[0,0][500,240]">
    <node index="0" text="12°C" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_NOT_CONNECTED_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="$WEATHER_WIDGET_NOT_CONNECTED_ASOF" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'a synthetic Weather temperature is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_forecast_xml")"

weather_off_forecast_number_xml="$TMP_DIR/weather-off-forecast-number.xml"
cat > "$weather_off_forecast_number_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_OFF_CONTENT_DESCRIPTION" bounds="[0,0][500,200]">
    <node index="0" text="12°C" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an off root description with a forecast number is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_off_forecast_number_xml")"

weather_off_stale_xml="$TMP_DIR/weather-off-stale.xml"
cat > "$weather_off_stale_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_OFF_CONTENT_DESCRIPTION" bounds="[0,0][500,240]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="Updated 4:10" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an off Weather tile with a fake update timestamp is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_off_stale_xml")"

weather_off_contradictory_asof_xml="$TMP_DIR/weather-off-contradictory-asof.xml"
cat > "$weather_off_contradictory_asof_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_OFF_CONTENT_DESCRIPTION" bounds="[0,0][500,240]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="$WEATHER_WIDGET_NOT_CONNECTED_ASOF" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an off tile with a not-connected as-of line is rejected as contradictory' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_off_contradictory_asof_xml")"

weather_not_connected_reason_xml="$TMP_DIR/weather-not-connected-reason.xml"
cat > "$weather_not_connected_reason_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_NOT_CONNECTED_CONTENT_DESCRIPTION" bounds="[0,0][500,240]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_NOT_CONNECTED_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="Updated 4:10" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'a not-connected Weather tile with an update timestamp is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_not_connected_reason_xml")"

weather_off_missing_description_xml="$TMP_DIR/weather-off-missing-description.xml"
cat > "$weather_off_missing_description_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" bounds="[0,0][500,200]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an off tile without a root content description is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_off_missing_description_xml")"

weather_off_wrong_description_xml="$TMP_DIR/weather-off-wrong-description.xml"
cat > "$weather_off_wrong_description_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="$WEATHER_WIDGET_NOT_CONNECTED_CONTENT_DESCRIPTION" bounds="[0,0][500,200]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_OFF_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an off tile with the not-connected root description is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_off_wrong_description_xml")"

weather_not_connected_missing_description_xml="$TMP_DIR/weather-not-connected-missing-description.xml"
cat > "$weather_not_connected_missing_description_xml" <<EOF
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" bounds="[0,0][500,240]">
    <node index="0" text="$WEATHER_WIDGET_VALUE_UNKNOWN" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="$WEATHER_WIDGET_NOT_CONNECTED_DETAIL" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="$WEATHER_WIDGET_NOT_CONNECTED_ASOF" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'a not-connected tile without a root content description is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_not_connected_missing_description_xml")"

weather_loading_xml="$TMP_DIR/weather-loading.xml"
cat > "$weather_loading_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="Updating weather" bounds="[0,0][500,200]">
    <node index="0" text="…" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="Updating weather" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'a loading Weather tile is not accepted as off or not connected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_loading_xml")"

weather_unavailable_xml="$TMP_DIR/weather-unavailable.xml"
cat > "$weather_unavailable_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="Weather unavailable" bounds="[0,0][500,240]">
    <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="Weather unavailable" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="Retry later" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an unavailable Weather tile is not accepted as off or not connected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_unavailable_xml")"

weather_unknown_state_xml="$TMP_DIR/weather-unknown-state.xml"
cat > "$weather_unknown_state_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_root" content-desc="--" bounds="[0,0][500,200]">
    <node index="0" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_value" bounds="[40,40][200,120]" />
    <node index="1" text="--" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_detail" bounds="[40,120][480,180]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_weather_asof" bounds="[40,180][480,220]" />
  </node>
</hierarchy>
EOF
assert_eq 'an unknown Weather state is rejected' \
    '' \
    "$(weather_widget_text_is_truthful "$weather_unknown_state_xml")"

# The fixtures above are only valid evidence if they match the shipped copy and
# the provider's resource-to-field mapping. Read the real strings resource and
# provider, and fail loudly on any future copy drift instead of silently
# accepting a stale fixture.
assert_eq 'the off short detail matches the shipped strings resource' \
    "$(prod_string nothingui_weather_state_off_short)" \
    "$WEATHER_WIDGET_OFF_DETAIL"
assert_eq 'the off root content description matches the shipped strings resource' \
    "$(prod_string nothingui_weather_state_off)" \
    "$WEATHER_WIDGET_OFF_CONTENT_DESCRIPTION"
assert_eq 'the not-connected short detail matches the shipped strings resource' \
    "$(prod_string nothingui_weather_state_not_connected_short)" \
    "$WEATHER_WIDGET_NOT_CONNECTED_DETAIL"
assert_eq 'the not-connected as-of copy matches the shipped strings resource' \
    "$(prod_string nothingui_weather_state_not_connected)" \
    "$WEATHER_WIDGET_NOT_CONNECTED_ASOF"
assert_eq 'the not-connected root content description matches the shipped strings resource' \
    "$(prod_string nothingui_weather_state_not_connected_content_description)" \
    "$WEATHER_WIDGET_NOT_CONNECTED_CONTENT_DESCRIPTION"
assert_eq 'the unknown Weather value matches the shipped strings resource' \
    "$(prod_string nothingui_weather_value_unknown)" \
    "$WEATHER_WIDGET_VALUE_UNKNOWN"
assert_true 'the provider maps the off detail to the short visible label' \
    grep -Fq 'detail = context.getString(R.string.nothingui_weather_state_off_short),' \
    "$PROD_WEATHER_PROVIDER"
assert_true 'the provider maps the off root description to the full setup copy' \
    grep -Fq 'contentDescription = context.getString(R.string.nothingui_weather_state_off),' \
    "$PROD_WEATHER_PROVIDER"
assert_true 'the provider maps the not-connected detail to the short visible label' \
    grep -Fq 'detail = context.getString(R.string.nothingui_weather_state_not_connected_short),' \
    "$PROD_WEATHER_PROVIDER"
assert_true 'the provider maps the not-connected as-of line to the shipped copy' \
    grep -Fq 'asOf = context.getString(R.string.nothingui_weather_state_not_connected),' \
    "$PROD_WEATHER_PROVIDER"
assert_true 'the provider maps the not-connected root description to the full accessibility copy' \
    grep -Fq 'R.string.nothingui_weather_state_not_connected_content_description,' \
    "$PROD_WEATHER_PROVIDER"
assert_false 'the provider does not map the off detail to the long setup copy' \
    grep -Fq 'detail = context.getString(R.string.nothingui_weather_state_off),' \
    "$PROD_WEATHER_PROVIDER"
assert_false 'the provider does not map the not-connected detail to the long copy' \
    grep -Fq 'detail = context.getString(R.string.nothingui_weather_state_not_connected),' \
    "$PROD_WEATHER_PROVIDER"

# CI147 regression: the pre-widget HOME already exposes the two own widgets.
# After the third-party Calendar is added, both own hosts remain and the new
# Calendar host appears after them in document order with nested children. The
# detector must select the first eligible unseen host during scanning, not stop
# at the first workspace host and reject it because it already existed.
multi_host_ref_xml="$TMP_DIR/multi-host-ref.xml"
cat > "$multi_host_ref_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Battery" bounds="[556,328][1042,738]" />
    </node>
  </node>
</hierarchy>
EOF
multi_host_placed_xml="$TMP_DIR/multi-host-placed.xml"
cat > "$multi_host_placed_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Battery" bounds="[556,328][1042,738]" />
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,770][524,1401]">
        <node index="0" text="21" class="android.widget.TextView" bounds="[60,800][200,900]" />
        <node index="1" text="" class="android.widget.FrameLayout" bounds="[60,920][500,1380]">
          <node index="0" text="Fri" class="android.widget.TextView" bounds="[80,940][180,1000]" />
        </node>
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'two pre-existing own hosts before a nested Calendar still yield the new Calendar bounds' \
    '38 770 524 1401' \
    "$(home_widget_bounds "$multi_host_placed_xml" "$multi_host_ref_xml")"
assert_eq 'the same new Calendar is found by its selected provider label' \
    '38 770 524 1401' \
    "$(home_widget_bounds "$multi_host_placed_xml" "$multi_host_ref_xml" Calendar)"

# The denser factory HOME can reuse the same geometry on another page. A new
# Calendar on page 2 must not be suppressed by the own Clock at those bounds on
# page 1, and a wrong provider at those bounds must not be accepted.
provider_page_ref_xml="$TMP_DIR/provider-page-ref.xml"
cat > "$provider_page_ref_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" bounds="[38,770][524,1401]" />
    </node>
  </node>
</hierarchy>
EOF
provider_page_calendar_xml="$TMP_DIR/provider-page-calendar.xml"
cat > "$provider_page_calendar_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,770][524,1401]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a new Calendar on another page is not suppressed by the own Clock geometry' \
    '38 770 524 1401' \
    "$(home_widget_bounds "$provider_page_calendar_xml" "$provider_page_ref_xml" Calendar)"
assert_eq 'the provider-label mode rejects a wrong provider at the same bounds' \
    '' \
    "$(home_widget_bounds "$multi_host_placed_xml" "$multi_host_ref_xml" Weather)"
provider_wrong_xml="$TMP_DIR/provider-page-wrong.xml"
cat > "$provider_wrong_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Battery" bounds="[38,770][524,1401]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a Battery host at the Calendar geometry is not a new Calendar' \
    '' \
    "$(home_widget_bounds "$provider_wrong_xml" "$provider_page_ref_xml" Calendar)"
provider_preview_xml="$TMP_DIR/provider-page-preview.xml"
cat > "$provider_preview_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" bounds="[38,770][524,1401]">
      <node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,770][524,1401]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a Calendar preview host is not a placed Calendar' \
    '' \
    "$(home_widget_bounds "$provider_preview_xml" "$provider_page_ref_xml" Calendar)"
provider_outside_xml="$TMP_DIR/provider-page-outside.xml"
cat > "$provider_outside_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]" />
    <node index="1" text="" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,770][524,1401]" />
  </node>
</hierarchy>
EOF
assert_eq 'a Calendar host outside a present workspace is not placed' \
    '' \
    "$(home_widget_bounds "$provider_outside_xml" "$provider_page_ref_xml" Calendar)"
provider_pending_xml="$TMP_DIR/provider-page-pending.xml"
cat > "$provider_pending_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.widget.PendingAppWidgetHostView" content-desc="Calendar" bounds="[38,770][524,1401]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a pending Calendar host is never a completed placement' \
    '' \
    "$(home_widget_bounds "$provider_pending_xml" "$provider_page_ref_xml" Calendar)"
assert_eq 'the provider-label mode still finds a real Calendar after two own hosts' \
    '38 770 524 1401' \
    "$(home_widget_bounds "$multi_host_placed_xml" "$multi_host_ref_xml" Calendar)"

# The real Clock provider header is only a picker selection label. The selected
# widget caption ("Analog clock") is the host identity on HOME. The exact new
# host from CI272 (content-desc Analog clock, bounds 38,107,524,517) must be
# found by the caption, while the header Clock, a wrong provider caption, a
# pre-existing host and a picker preview must all fail closed.
third_party_caption_ref_xml="$TMP_DIR/third-party-caption-ref.xml"
cat > "$third_party_caption_ref_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Clock" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Battery" bounds="[556,328][1042,738]" />
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="DotWel Launcher" bounds="[38,770][524,1180]" />
    </node>
  </node>
</hierarchy>
EOF
third_party_caption_placed_xml="$TMP_DIR/third-party-caption-placed.xml"
cat > "$third_party_caption_placed_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Clock" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Battery" bounds="[556,328][1042,738]" />
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="DotWel Launcher" bounds="[38,770][524,1180]" />
      <node index="3" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Analog clock" bounds="[38,107][524,517]">
        <node index="0" text="10:08" class="android.widget.TextView" bounds="[80,150][480,420]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the CI272 Analog clock host is found by its selected widget caption' \
    '38 107 524 517' \
    "$(home_widget_bounds "$third_party_caption_placed_xml" "$third_party_caption_ref_xml" 'Analog clock')"
assert_eq 'the provider header Clock is not the Analog clock host caption' \
    '' \
    "$(home_widget_bounds "$third_party_caption_placed_xml" "$third_party_caption_ref_xml" Clock)"
assert_eq 'a sibling Digital clock caption is not the Analog clock host' \
    '' \
    "$(home_widget_bounds "$third_party_caption_placed_xml" "$third_party_caption_ref_xml" 'Digital clock')"
assert_eq 'a wrong third-party provider caption is not accepted for the Analog clock host' \
    '' \
    "$(home_widget_bounds "$third_party_caption_placed_xml" "$third_party_caption_ref_xml" Calendar)"
assert_eq 'an Analog clock host already present in the reference is not new' \
    '' \
    "$(home_widget_bounds "$third_party_caption_placed_xml" "$third_party_caption_placed_xml" 'Analog clock')"
third_party_caption_wrong_xml="$TMP_DIR/third-party-caption-wrong.xml"
cat > "$third_party_caption_wrong_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Clock" bounds="[38,107][524,517]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'a Clock host at the exact bounds is not the selected Analog clock host' \
    '' \
    "$(home_widget_bounds "$third_party_caption_wrong_xml" "$third_party_caption_ref_xml" 'Analog clock')"
third_party_caption_preview_xml="$TMP_DIR/third-party-caption-preview.xml"
cat > "$third_party_caption_preview_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" bounds="[38,107][524,517]">
      <node index="0" text="" class="com.android.launcher3.appwidget.LauncherAppWidgetHostView" content-desc="Analog clock" bounds="[38,107][524,517]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'an Analog clock preview host is not a placed Analog clock host' \
    '' \
    "$(home_widget_bounds "$third_party_caption_preview_xml" "$third_party_caption_ref_xml" 'Analog clock')"

# CI159: a third-party Calendar placed on a later page has no launcher
# search_container_workspace header there, so its y=107 top is valid even though
# the first page's header bottom is 312. The check must use the actual placed
# page's workspace/header/dock geometry, not inherit the first-page header.
placed_ci159_first_xml="$TMP_DIR/placed-ci159-first.xml"
cat > "$placed_ci159_first_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="Search" resource-id="com.launchernos.dotwellabs.debug:id/search_container_workspace" class="android.widget.EditText" content-desc="Search" clickable="true" bounds="[22,91][1058,312]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,328][524,738]" />
    </node>
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]">
      <node index="0" text="Phone" class="android.widget.TextView" clickable="true" bounds="[22,1481][281,1674]" />
    </node>
  </node>
</hierarchy>
EOF
placed_ci159_later_xml="$TMP_DIR/placed-ci159-later.xml"
cat > "$placed_ci159_later_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,107][524,738]" />
      <node index="1" text="Gallery" class="android.widget.TextView" clickable="true" bounds="[38,1196][524,1400]" />
      <node index="2" text="Settings" class="android.widget.TextView" clickable="true" bounds="[556,1196][1042,1400]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]">
      <node index="0" text="Phone" class="android.widget.TextView" clickable="true" bounds="[22,1481][281,1674]" />
    </node>
  </node>
</hierarchy>
EOF
assert_true 'the CI159 first-page Calendar sits below the real header and above the dock' \
    home_widget_page_geometry_ok "$placed_ci159_first_xml" '38 328 524 738'
assert_true 'the CI159 no-header later-page Calendar at y=107 is accepted' \
    home_widget_page_geometry_ok "$placed_ci159_later_xml" '38 107 524 738'
assert_eq 'the later-page Gallery/Settings row makes ui_dock_top report 1196' \
    '1196' \
    "$(ui_dock_top "$placed_ci159_later_xml" "$(ui_root_bounds "$placed_ci159_later_xml")")"
assert_false 'a widget that starts inside a real first-page header is rejected' \
    home_widget_page_geometry_ok "$placed_ci159_first_xml" '38 107 524 738'
assert_false 'a widget that crosses the actual dock top is rejected' \
    home_widget_page_geometry_ok "$placed_ci159_first_xml" '38 328 524 1500'
assert_false 'a widget outside the actual workspace is rejected' \
    home_widget_page_geometry_ok "$placed_ci159_later_xml" '38 107 1100 738'

placed_ci159_no_hotseat_xml="$TMP_DIR/placed-ci159-no-hotseat.xml"
cat > "$placed_ci159_no_hotseat_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,107][524,738]" />
    </node>
  </node>
</hierarchy>
EOF
assert_false 'missing actual hotseat geometry fails closed' \
    home_widget_page_geometry_ok "$placed_ci159_no_hotseat_xml" '38 107 524 738'

placed_ci159_no_workspace_xml="$TMP_DIR/placed-ci159-no-workspace.xml"
cat > "$placed_ci159_no_workspace_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Calendar" bounds="[38,328][524,738]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]" />
  </node>
</hierarchy>
EOF
assert_false 'missing actual workspace geometry fails closed' \
    home_widget_page_geometry_ok "$placed_ci159_no_workspace_xml" '38 328 524 738'
assert_false 'malformed placed bounds are rejected' \
    home_widget_page_geometry_ok "$placed_ci159_later_xml" '38 107 524'
assert_false 'non-numeric placed bounds are rejected' \
    home_widget_page_geometry_ok "$placed_ci159_later_xml" '38 107 524 x'
assert_false 'empty placed bounds are rejected' \
    home_widget_page_geometry_ok "$placed_ci159_later_xml" ''

assert_true 'the CI159 first-page Calendar is a genuine selected-provider workspace host' \
    placed_widget_page_is_safe "$placed_ci159_first_xml" "$multi_host_ref_xml" \
    Calendar '38 328 524 738'
assert_true 'the CI159 no-header later-page Calendar is a genuine selected-provider workspace host' \
    placed_widget_page_is_safe "$placed_ci159_later_xml" "$multi_host_ref_xml" \
    Calendar '38 107 524 738'
assert_false 'an absent provider host is not a safe placed widget' \
    placed_widget_page_is_safe "$provider_page_ref_xml" "$multi_host_ref_xml" \
    Calendar '38 328 524 738'
assert_false 'a foreign provider label is not a safe placed widget' \
    placed_widget_page_is_safe "$placed_ci159_later_xml" "$multi_host_ref_xml" \
    Weather '38 107 524 738'
assert_false 'a picker preview host is not a safe placed widget' \
    placed_widget_page_is_safe "$provider_preview_xml" "$provider_page_ref_xml" \
    Calendar '38 770 524 1401'
assert_false 'a mismatched placed bounds value is not a safe placed widget' \
    placed_widget_page_is_safe "$placed_ci159_later_xml" "$multi_host_ref_xml" \
    Calendar '38 200 524 738'

# CI165: bounded horizontal page swipes must use the actual workspace and
# hotseat on the page being swiped. The CI159 later page has no launcher header
# and its ordinary Gallery/Settings icon row makes ui_dock_top report 1196, so a
# swipe that still required the header or the labelled row returned nothing.
assert_eq 'a first-page next swipe stays below the real header and above the hotseat' \
    '864 896 216 896' \
    "$(workspace_page_swipe "$placed_ci159_first_xml" next)"
assert_eq 'a first-page prev swipe uses the same bounded band' \
    '216 896 864 896' \
    "$(workspace_page_swipe "$placed_ci159_first_xml" prev)"
assert_eq 'a no-header later-page next swipe uses the actual hotseat, not icon row 1196' \
    '864 740 216 740' \
    "$(workspace_page_swipe "$placed_ci159_later_xml" next)"
assert_eq 'a no-header later-page prev swipe uses the same bounded band' \
    '216 740 864 740' \
    "$(workspace_page_swipe "$placed_ci159_later_xml" prev)"
assert_eq 'the later-page swipe y is below the hotseat-1196 midpoint and matches hotseat 1481' \
    '740' \
    "$(workspace_page_swipe "$placed_ci159_later_xml" next | awk '{print $2}')"

placed_ci165_offset_xml="$TMP_DIR/placed-ci165-offset.xml"
cat > "$placed_ci165_offset_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[40,120][1040,1800]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[40,1500][1040,1900]" />
  </node>
</hierarchy>
EOF
assert_eq 'a nonzero-origin workspace produces absolute swipe coordinates inside it' \
    '840 810 240 810' \
    "$(workspace_page_swipe "$placed_ci165_offset_xml" next)"
assert_eq 'a nonzero-origin prev swipe keeps the same absolute endpoints' \
    '240 810 840 810' \
    "$(workspace_page_swipe "$placed_ci165_offset_xml" prev)"

assert_eq 'a page swipe without a real workspace fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci159_no_workspace_xml" next)"
assert_eq 'a page swipe without a real hotseat fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci159_no_hotseat_xml" next)"

placed_ci165_bad_ws_xml="$TMP_DIR/placed-ci165-bad-workspace.xml"
cat > "$placed_ci165_bad_ws_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]" />
  </node>
</hierarchy>
EOF
assert_eq 'a malformed workspace fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_bad_ws_xml" next)"

placed_ci165_degenerate_ws_xml="$TMP_DIR/placed-ci165-degenerate-workspace.xml"
cat > "$placed_ci165_degenerate_ws_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,900][1080,900]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]" />
  </node>
</hierarchy>
EOF
assert_eq 'a degenerate workspace fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_degenerate_ws_xml" next)"

placed_ci165_bad_dock_xml="$TMP_DIR/placed-ci165-bad-hotseat.xml"
cat > "$placed_ci165_bad_dock_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,abc][1080,1920]" />
  </node>
</hierarchy>
EOF
assert_eq 'a malformed hotseat fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_bad_dock_xml" next)"

placed_ci165_degenerate_dock_xml="$TMP_DIR/placed-ci165-degenerate-hotseat.xml"
cat > "$placed_ci165_degenerate_dock_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1481]" />
  </node>
</hierarchy>
EOF
assert_eq 'a degenerate hotseat fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_degenerate_dock_xml" next)"

placed_ci165_impossible_xml="$TMP_DIR/placed-ci165-impossible-band.xml"
cat > "$placed_ci165_impossible_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,800][1080,1800]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,400][1080,800]" />
  </node>
</hierarchy>
EOF
assert_eq 'a hotseat above the workspace start is an impossible band' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_impossible_xml" next)"

placed_ci165_header_past_dock_xml="$TMP_DIR/placed-ci165-header-past-dock.xml"
cat > "$placed_ci165_header_past_dock_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="Search" resource-id="com.launchernos.dotwellabs.debug:id/search_container_workspace" class="android.widget.EditText" content-desc="Search" clickable="true" bounds="[22,91][1058,1600]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,0][1080,1920]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" bounds="[0,1481][1080,1920]" />
  </node>
</hierarchy>
EOF
assert_eq 'a real header that reaches past the hotseat is an impossible band' \
    '' \
    "$(workspace_page_swipe "$placed_ci165_header_past_dock_xml" next)"
assert_eq 'an unknown swipe direction fails closed' \
    '' \
    "$(workspace_page_swipe "$placed_ci159_later_xml" sideways)"

# --- pending own-widget fixtures -------------------------------------------
#
# After a denied automatic bind, the fresh layout keeps each own slot as a
# click-to-setup PendingAppWidgetHostView. These fixtures pin the bounds parser
# used to complete at most those two widgets through the standard consent.

pending_home_xml="$TMP_DIR/pending-home.xml"
cat > "$pending_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[540,400][1000,800]" /><node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[40,400][500,800]" /><node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,900][500,1200]" /></node></node></hierarchy>
EOF
assert_eq 'both pending own widgets are measured left-to-right and bound hosts are ignored' \
    "$(printf '40 400 500 800\n540 400 1000 800')" \
    "$(home_pending_widget_bounds "$pending_home_xml")"

pending_preview_xml="$TMP_DIR/pending-preview.xml"
cat > "$pending_preview_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/widget_preview_container" class="com.android.launcher3.widget.WidgetCellPreview" bounds="[40,400][500,800]"><node index="0" text="" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[40,400][500,800]" /></node></node></node></hierarchy>
EOF
assert_eq 'a pending host inside a widget preview is not a HOME pending widget' \
    '' \
    "$(home_pending_widget_bounds "$pending_preview_xml")"

pending_outside_ws_xml="$TMP_DIR/pending-outside-workspace.xml"
cat > "$pending_outside_ws_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]" /><node index="1" text="" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[40,900][500,1200]" /></node></hierarchy>
EOF
assert_eq 'a pending host outside a present workspace is rejected' \
    '' \
    "$(home_pending_widget_bounds "$pending_outside_ws_xml")"

pending_no_ws_xml="$TMP_DIR/pending-no-workspace.xml"
cat > "$pending_no_ws_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="1" text="" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[40,900][500,1200]" /></node></hierarchy>
EOF
assert_eq 'a pending host without an exposed workspace still yields its bounds' \
    '40 900 500 1200' \
    "$(home_pending_widget_bounds "$pending_no_ws_xml")"

pending_bound_only_xml="$TMP_DIR/pending-bound-only.xml"
cat > "$pending_bound_only_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]"><node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]"><node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,400][500,800]" /></node></node></hierarchy>
EOF
assert_eq 'a HOME with no pending widget yields no setup target' \
    '' \
    "$(home_pending_widget_bounds "$pending_bound_only_xml")"

# A per-widget setup round must observe exactly one newly bound own provider.
# The helper requires a numeric id, the running package as both host and provider
# package, and an exact full DotWel provider class. Multiple/mixed records,
# foreign packages, class suffix lookalikes and wrong providers all fail closed.
own_bind_pkg=com.launchernos.dotwellabs.debug
own_bind_before="$TMP_DIR/own-bind-before.txt"
cat > "$own_bind_before" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
EOF
own_bind_clock="$TMP_DIR/own-bind-clock.txt"
cat > "$own_bind_clock" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'exactly one newly bound own clock provider keeps its numeric id' \
    "$(printf '7\tapp.dotwel.widgets.DotWelClockWidgetProvider')" \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_clock" "$own_bind_pkg")"

own_bind_battery="$TMP_DIR/own-bind-battery.txt"
cat > "$own_bind_battery" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=8
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelBatteryWidgetProvider}, profile:0}
EOF
assert_eq 'exactly one newly bound own battery provider keeps its numeric id' \
    "$(printf '8\tapp.dotwel.widgets.DotWelBatteryWidgetProvider')" \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_battery" "$own_bind_pkg")"

own_bind_device="$TMP_DIR/own-bind-device.txt"
cat > "$own_bind_device" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=9
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelDeviceWidgetProvider}, profile:0}
EOF
assert_eq 'exactly one newly bound own device provider keeps its numeric id' \
    "$(printf '9\tapp.dotwel.widgets.DotWelDeviceWidgetProvider')" \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_device" "$own_bind_pkg")"

assert_eq 'an unchanged dump has no own binding' \
    '' \
    "$(own_widget_new_binding "$own_bind_clock" "$own_bind_clock" "$own_bind_pkg")"

own_bind_foreign="$TMP_DIR/own-bind-foreign.txt"
cat > "$own_bind_foreign" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.fake/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'a foreign provider package is rejected even with an own class name' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_foreign" "$own_bind_pkg")"

own_bind_suffix="$TMP_DIR/own-bind-suffix.txt"
sed 's/DotWelClockWidgetProvider/DotWelClockWidgetProviderExtra/' \
    "$own_bind_clock" > "$own_bind_suffix"
assert_eq 'a provider class suffix lookalike is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_suffix" "$own_bind_pkg")"

own_bind_prefix="$TMP_DIR/own-bind-prefix.txt"
sed 's/DotWelClockWidgetProvider/EvilDotWelClockWidgetProvider/' \
    "$own_bind_clock" > "$own_bind_prefix"
assert_eq 'a provider class prefix lookalike is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_prefix" "$own_bind_pkg")"

own_bind_short_class="$TMP_DIR/own-bind-short-class.txt"
sed 's#com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider#com.launchernos.dotwellabs.debug/DotWelClockWidgetProvider#' \
    "$own_bind_clock" > "$own_bind_short_class"
assert_eq 'a non-fully-qualified own provider class is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_short_class" "$own_bind_pkg")"

own_bind_wrong_provider="$TMP_DIR/own-bind-wrong-provider.txt"
sed 's#com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider#com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider#' \
    "$own_bind_clock" > "$own_bind_wrong_provider"
assert_eq 'an unrelated provider is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_wrong_provider" "$own_bind_pkg")"

own_bind_two="$TMP_DIR/own-bind-two.txt"
cat > "$own_bind_two" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
  [2] id=8
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelBatteryWidgetProvider}, profile:0}
EOF
assert_eq 'two newly bound own providers are rejected as multiple records' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_two" "$own_bind_pkg")"

own_bind_mixed="$TMP_DIR/own-bind-mixed.txt"
cat > "$own_bind_mixed" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
  [2] id=8
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.fake/app.dotwel.widgets.DotWelBatteryWidgetProvider}, profile:0}
EOF
assert_eq 'a mixed own/foreign multiline result is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_mixed" "$own_bind_pkg")"

own_bind_foreign_host="$TMP_DIR/own-bind-foreign-host.txt"
cat > "$own_bind_foreign_host" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10301, hostId:1031, pkg:com.other.launcher}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'a new own provider owned by another host is rejected' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_foreign_host" "$own_bind_pkg")"

own_bind_non_numeric="$TMP_DIR/own-bind-non-numeric.txt"
cat > "$own_bind_non_numeric" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=abc
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'a non-numeric widget id is not accepted' \
    '' \
    "$(own_widget_new_binding "$own_bind_before" "$own_bind_non_numeric" "$own_bind_pkg")"

# The optional Weather widget must be the one new binding, with the exact
# Weather provider class. A clock, a mixed pair, a foreign package/host and a
# lookalike class all fail closed, so the gate cannot pass on the accepted own
# clock/battery/device widgets.
weather_bind_ok="$TMP_DIR/weather-bind-ok.txt"
cat > "$weather_bind_ok" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=12
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
EOF
assert_eq 'exactly one newly bound Weather provider is accepted with its numeric id' \
    "$(printf '12\tapp.dotwel.widgets.DotWelWeatherWidgetProvider')" \
    "$(weather_widget_new_binding "$own_bind_before" "$weather_bind_ok" "$own_bind_pkg")"
assert_eq 'a newly bound clock is not accepted as the Weather widget' \
    '' \
    "$(weather_widget_new_binding "$own_bind_before" "$own_bind_clock" "$own_bind_pkg")"
assert_eq 'an unchanged dump has no new Weather binding' \
    '' \
    "$(weather_widget_new_binding "$weather_bind_ok" "$weather_bind_ok" "$own_bind_pkg")"

weather_bind_two="$TMP_DIR/weather-bind-two.txt"
cat > "$weather_bind_two" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=12
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
  [2] id=13
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'a Weather plus clock pair is rejected as multiple records' \
    '' \
    "$(weather_widget_new_binding "$own_bind_before" "$weather_bind_two" "$own_bind_pkg")"

weather_bind_foreign="$TMP_DIR/weather-bind-foreign.txt"
cat > "$weather_bind_foreign" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=12
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.fake/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
EOF
assert_eq 'a foreign package Weather class is rejected' \
    '' \
    "$(weather_widget_new_binding "$own_bind_before" "$weather_bind_foreign" "$own_bind_pkg")"

weather_bind_foreign_host="$TMP_DIR/weather-bind-foreign-host.txt"
cat > "$weather_bind_foreign_host" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=12
    host=HostId{user:0, app:10301, hostId:1031, pkg:com.other.launcher}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
EOF
assert_eq 'a Weather provider owned by another host is rejected' \
    '' \
    "$(weather_widget_new_binding "$own_bind_before" "$weather_bind_foreign_host" "$own_bind_pkg")"

weather_bind_suffix="$TMP_DIR/weather-bind-suffix.txt"
sed 's/DotWelWeatherWidgetProvider/DotWelWeatherWidgetProviderExtra/' \
    "$weather_bind_ok" > "$weather_bind_suffix"
assert_eq 'a Weather class suffix lookalike is rejected' \
    '' \
    "$(weather_widget_new_binding "$own_bind_before" "$weather_bind_suffix" "$own_bind_pkg")"

assert_true 'every prior launcher binding survives the Weather placement' \
    appwidget_preserved_bindings "$own_bind_before" "$weather_bind_ok" "$own_bind_pkg"
assert_true 'all existing bindings survive when the before dump is empty' \
    appwidget_preserved_bindings "$TMP_DIR/does-not-exist" "$weather_bind_ok" "$own_bind_pkg"
weather_bind_replaced="$TMP_DIR/weather-bind-replaced.txt"
cat > "$weather_bind_replaced" <<'EOF'
Widgets:
  [0] id=12
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
EOF
assert_false 'a placement that dropped a prior binding is rejected' \
    appwidget_preserved_bindings "$own_bind_before" "$weather_bind_replaced" "$own_bind_pkg"

home_widgets_xml="$TMP_DIR/home-widgets.xml"
cat > "$home_widgets_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" bounds="[0,300][1080,1375]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,400][500,800]">
        <node index="0" text="3:07" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_clock_time" class="android.widget.TextClock" bounds="[40,400][500,800]" />
      </node>
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[540,400][1000,800]">
        <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_battery_art" class="android.widget.ImageView" content-desc="87%" bounds="[540,400][1000,800]" />
      </node>
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" bounds="[40,820][1040,1100]">
        <node index="0" text="83.0 GB free" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_value" class="android.widget.TextView" bounds="[60,860][420,920]" />
        <node index="1" text="17% used of 100.0 GB" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_detail" class="android.widget.TextView" bounds="[60,940][420,980]" />
        <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_progress" class="android.widget.ProgressBar" bounds="[60,990][420,1000]" />
        <node index="3" text="Wi-Fi settings" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_wifi" class="android.widget.TextView" clickable="true" bounds="[700,860][1000,920]" />
        <node index="4" text="Sound settings" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_sound" class="android.widget.TextView" clickable="true" bounds="[700,930][1000,990]" />
        <node index="5" text="Display settings" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_display" class="android.widget.TextView" clickable="true" bounds="[700,1000][1000,1060]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the HOME widget proof reads the real clock child text' \
    '3:07' "$(home_widget_clock_text "$home_widgets_xml")"
assert_eq 'the HOME widget proof reads the real battery description' \
    '87%' "$(home_widget_battery_description "$home_widgets_xml")"
assert_eq 'the HOME widget proof reads the real device storage value' \
    '83.0 GB free' "$(home_widget_device_storage_value "$home_widgets_xml")"
assert_eq 'the HOME widget proof reads the device storage detail' \
    '17% used of 100.0 GB' "$(home_widget_device_storage_detail "$home_widgets_xml")"
assert_true 'a real formatted device storage pair is accepted' \
    home_widget_device_storage_is_real '83.0 GB free' '17% used of 100.0 GB'
assert_eq 'the device Wi-Fi pill bounds are measured from its real child id' \
    '700 860 1000 920' "$(home_widget_device_action_bounds "$home_widgets_xml" wifi)"
assert_eq 'the device Sound pill bounds are measured from its real child id' \
    '700 930 1000 990' "$(home_widget_device_action_bounds "$home_widgets_xml" sound)"
assert_eq 'the device Display pill bounds are measured from its real child id' \
    '700 1000 1000 1060' "$(home_widget_device_action_bounds "$home_widgets_xml" display)"
assert_eq 'an unknown device action id has no bounds' \
    '' "$(home_widget_device_action_bounds "$home_widgets_xml" bluetooth)"
assert_true 'a live HH:mm clock text is accepted' \
    home_widget_clock_text_is_live '3:07'
assert_true 'a two-digit live clock text is accepted' \
    home_widget_clock_text_is_live '23:59'
assert_false 'an empty clock text is rejected' \
    home_widget_clock_text_is_live ''
assert_false 'a non-time clock text is rejected' \
    home_widget_clock_text_is_live 'soon'
assert_true 'a real percentage battery description is accepted' \
    home_widget_battery_description_is_real '87%'
assert_true 'a full charging battery description is accepted' \
    home_widget_battery_description_is_real '100%, charging'
assert_true 'the explicit unknown battery description is accepted' \
    home_widget_battery_description_is_real '--'
assert_true 'the explicit unknown charging description is accepted' \
    home_widget_battery_description_is_real '--, charging'
assert_false 'an out-of-range battery percentage is rejected' \
    home_widget_battery_description_is_real '101%'
assert_false 'a bare battery number is rejected' \
    home_widget_battery_description_is_real '87'
assert_false 'an empty battery description is rejected' \
    home_widget_battery_description_is_real ''
assert_true 'the short -- unknown storage marker with its localized detail is accepted' \
    home_widget_device_storage_is_real '--' 'Storage unavailable'
assert_false 'the short -- marker without the localized detail is rejected' \
    home_widget_device_storage_is_real '--' ''
assert_false 'the old wide unknown label in the value slot is rejected' \
    home_widget_device_storage_is_real 'Storage unavailable' 'Storage unavailable'
assert_false 'a fabricated storage percentage is rejected' \
    home_widget_device_storage_is_real '42%' ''

home_widgets_missing_child_xml="$TMP_DIR/home-widgets-missing-child.xml"
cat > "$home_widgets_missing_child_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="3:07" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_clock_time" class="android.widget.TextClock" bounds="[40,400][500,800]" />
  </node>
</hierarchy>
EOF
assert_eq 'a missing battery child id is not read as a value' \
    '' "$(home_widget_battery_description "$home_widgets_missing_child_xml")"
assert_false 'a missing battery child id fails the real-value check' \
    home_widget_battery_description_is_real \
    "$(home_widget_battery_description "$home_widgets_missing_child_xml")"

appwidget_before="$TMP_DIR/appwidget-before.txt"
cat > "$appwidget_before" <<'EOF'
AppWidgets:
  AppWidgetId=1:
    provider=ComponentInfo{com.example.one/.One}
EOF
appwidget_after="$TMP_DIR/appwidget-after.txt"
cat > "$appwidget_after" <<'EOF'
AppWidgets:
  AppWidgetId=1:
    provider=ComponentInfo{com.example.one/.One}
  AppWidgetId=2:
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
EOF
assert_eq 'a newly bound app widget provider is reported after placement' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers "$appwidget_before" "$appwidget_after")"
assert_eq 'no new provider is reported when the dump is unchanged' \
    '' \
    "$(appwidget_new_providers "$appwidget_after" "$appwidget_after")"

appwidget_installed="$TMP_DIR/appwidget-installed.txt"
cat > "$appwidget_installed" <<'EOF'
AppWidgets:
  Installed providers:
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
EOF
appwidget_new_instance="$TMP_DIR/appwidget-new-instance.txt"
cat > "$appwidget_new_instance" <<'EOF'
AppWidgets:
  Installed providers:
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
  AppWidgetId=7:
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
EOF
assert_eq 'a new bound instance is reported even when its provider is already installed' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers "$appwidget_installed" "$appwidget_new_instance")"
assert_eq 'an installed provider list without a bound AppWidgetId is not a new widget' \
    '' \
    "$(appwidget_new_providers "$appwidget_installed" "$appwidget_installed")"
assert_eq 'a bound widget instance is found when the before dump is empty' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers '' "$appwidget_new_instance")"

# Current Android prints each widget as "[N] id=N" with the host package in a
# "host=HostId{..., pkg:<package>}" line. The smoke must prove the new id is
# owned by this launcher, not just that some provider appeared.
appwidget_modern_before="$TMP_DIR/appwidget-modern-before.txt"
cat > "$appwidget_modern_before" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10265, hostId:1024, pkg:com.android.launcher3}
    provider=ComponentInfo{com.example.one/.One}
Hosts:
  [0] hostId=HostId{user:0, app:10265, hostId:1024, pkg:com.android.launcher3}
    widgets.size=1
EOF
appwidget_modern_after="$TMP_DIR/appwidget-modern-after.txt"
cat > "$appwidget_modern_after" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10265, hostId:1024, pkg:com.android.launcher3}
    provider=ComponentInfo{com.example.one/.One}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
Hosts:
  [0] hostId=HostId{user:0, app:10265, hostId:1024, pkg:com.android.launcher3}
    widgets.size=1
  [1] hostId=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    widgets.size=1
EOF
assert_eq 'a current-format widget id owned by this launcher is reported' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers "$appwidget_modern_before" "$appwidget_modern_after" com.launchernos.dotwellabs.debug)"
assert_eq 'a new widget id owned by another launcher is rejected' \
    '' \
    "$(appwidget_new_providers "$appwidget_modern_before" "$appwidget_modern_after" com.other.launcher)"
assert_eq 'a current-format new id without an ownership match fails closed' \
    '' \
    "$(appwidget_new_providers "$appwidget_modern_before" "$appwidget_modern_after" com.launchernos.dotwellabs.debug.extra)"
assert_eq 'an unchanged current-format dump reports no new widget' \
    '' \
    "$(appwidget_new_providers "$appwidget_modern_after" "$appwidget_modern_after" com.launchernos.dotwellabs.debug)"

appwidget_hostpackage="$TMP_DIR/appwidget-hostpackage.txt"
cat > "$appwidget_hostpackage" <<'EOF'
AppWidgets:
  AppWidgetId=9:
    hostPackage=com.launchernos.dotwellabs.debug
    provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}
EOF
assert_eq 'a hostPackage line also proves launcher ownership' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers '' "$appwidget_hostpackage" com.launchernos.dotwellabs.debug)"
assert_eq 'a hostPackage owned by another launcher is rejected' \
    '' \
    "$(appwidget_new_providers '' "$appwidget_hostpackage" com.other.launcher)"

# API 37 wraps the provider in ProviderId{cmp:ComponentInfo{...}}. The wrapper is
# only accepted inside a real widget-id block, and the block must still be owned
# by this launcher. Provider catalogs and other hosts must never satisfy placement.
appwidget_api37_before="$TMP_DIR/appwidget-api37-before.txt"
cat > "$appwidget_api37_before" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
Hosts:
  [0] hostId=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    widgets.size=1
EOF
appwidget_api37_after="$TMP_DIR/appwidget-api37-after.txt"
cat > "$appwidget_api37_after" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}, profile:0}
Hosts:
  [0] hostId=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    widgets.size=2
EOF
assert_eq 'an API37 ProviderId wrapper inside a launcher-owned widget-id block is reported' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers "$appwidget_api37_before" "$appwidget_api37_after" com.launchernos.dotwellabs.debug)"
assert_eq 'an API37 ProviderId wrapper owned by another launcher is rejected' \
    '' \
    "$(appwidget_new_providers "$appwidget_api37_before" "$appwidget_api37_after" com.other.launcher)"

appwidget_api37_other_host="$TMP_DIR/appwidget-api37-other-host.txt"
cat > "$appwidget_api37_other_host" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  [1] id=7
    host=HostId{user:0, app:10301, hostId:1031, pkg:com.other.launcher}
    provider=ProviderId{cmp:ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}, profile:0}
EOF
assert_eq 'an API37 wrapper in another launcher host block is rejected' \
    '' \
    "$(appwidget_new_providers "$appwidget_api37_before" "$appwidget_api37_other_host" com.launchernos.dotwellabs.debug)"

appwidget_api37_catalog="$TMP_DIR/appwidget-api37-catalog.txt"
cat > "$appwidget_api37_catalog" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
Installed providers:
  provider=ProviderId{cmp:ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}, profile:0}
  provider=ProviderId{cmp:ComponentInfo{com.example.two/.Two}, profile:0}
EOF
assert_eq 'an API37 provider catalog without a new widget id is not a new widget' \
    '' \
    "$(appwidget_new_providers "$appwidget_api37_before" "$appwidget_api37_catalog" com.launchernos.dotwellabs.debug)"

appwidget_api37_loose_catalog="$TMP_DIR/appwidget-api37-loose-catalog.txt"
cat > "$appwidget_api37_loose_catalog" <<'EOF'
Widgets:
  [0] id=1
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.example.one/.One}, profile:0}
  Provider catalog:
    provider=ProviderId{cmp:ComponentInfo{com.example.two/.Two}, profile:0}
EOF
assert_eq 'an API37 provider catalog after a widget block is not attributed to the old id' \
    '' \
    "$(appwidget_new_providers "$appwidget_api37_before" "$appwidget_api37_loose_catalog" com.launchernos.dotwellabs.debug)"

appwidget_api37_legacy="$TMP_DIR/appwidget-api37-legacy.txt"
cat > "$appwidget_api37_legacy" <<'EOF'
AppWidgets:
  AppWidgetId=9:
    hostPackage=com.launchernos.dotwellabs.debug
    provider=ProviderId{cmp:ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}, profile:0}
EOF
assert_eq 'an API37 wrapper also works in a legacy AppWidgetId block with hostPackage' \
    'provider=ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}' \
    "$(appwidget_new_providers '' "$appwidget_api37_legacy" com.launchernos.dotwellabs.debug)"
assert_eq 'a legacy API37 wrapper owned by another launcher is rejected' \
    '' \
    "$(appwidget_new_providers '' "$appwidget_api37_legacy" com.other.launcher)"

appwidget_api37_no_block="$TMP_DIR/appwidget-api37-no-block.txt"
cat > "$appwidget_api37_no_block" <<'EOF'
Installed providers:
  provider=ProviderId{cmp:ComponentInfo{com.android.deskclock/com.android.alarmclock.DigitalAppWidgetProvider}, profile:0}
EOF
assert_eq 'an API37 wrapper outside any widget-id block is not a bound widget' \
    '' \
    "$(appwidget_new_providers '' "$appwidget_api37_no_block" com.launchernos.dotwellabs.debug)"

# The fresh-HOME proof needs distinct launcher-owned ids, not just provider
# names. The same record-aware parser is reused with an empty before dump.
appwidget_api37_instances="$TMP_DIR/appwidget-api37-instances.txt"
cat > "$appwidget_api37_instances" <<'EOF'
Widgets:
  [0] id=4
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
  [1] id=5
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelBatteryWidgetProvider}, profile:0}
Hosts:
  [0] hostId=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    widgets.size=2
EOF
assert_eq 'API37 launcher-owned clock and battery instances keep distinct ids' \
    "$(printf '4\tprovider=ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}\n5\tprovider=ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelBatteryWidgetProvider}')" \
    "$(appwidget_launcher_instances "$appwidget_api37_instances" com.launchernos.dotwellabs.debug)"
assert_eq 'a provider catalog alone yields no launcher-owned instances' \
    '' \
    "$(appwidget_launcher_instances "$appwidget_api37_no_block" com.launchernos.dotwellabs.debug)"

appwidget_other_host_only="$TMP_DIR/appwidget-other-host-only.txt"
cat > "$appwidget_other_host_only" <<'EOF'
Widgets:
  [0] id=7
    host=HostId{user:0, app:10301, hostId:1031, pkg:com.other.launcher}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}, profile:0}
EOF
assert_eq 'instances owned by another host are rejected' \
    '' \
    "$(appwidget_launcher_instances "$appwidget_other_host_only" com.launchernos.dotwellabs.debug)"

appwidget_legacy_instances="$TMP_DIR/appwidget-legacy-instances.txt"
cat > "$appwidget_legacy_instances" <<'EOF'
AppWidgets:
  AppWidgetId=9:
    hostPackage=com.launchernos.dotwellabs.debug
    provider=ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}
EOF
assert_eq 'a legacy launcher-owned instance keeps its id' \
    "$(printf '9\tprovider=ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider}')" \
    "$(appwidget_launcher_instances "$appwidget_legacy_instances" com.launchernos.dotwellabs.debug)"

# The CI277 failure was the actual API37 row shape: the instance helper kept
# its `<id><TAB><provider>` contract, so a bare `grep -x <id>` never matched.
# These fixtures execute that exact shape and prove the column-aware lookup,
# while the raw helper contract remains unchanged.
appwidget_weather_instance="$TMP_DIR/appwidget-weather-instance.txt"
cat > "$appwidget_weather_instance" <<'EOF'
Widgets:
  [0] id=10
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
Hosts:
  [0] hostId=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    widgets.size=1
EOF
assert_eq 'the exact id 10 row keeps the id<TAB>provider helper contract' \
    "$(printf '10\tprovider=ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}')" \
    "$(appwidget_launcher_instances "$appwidget_weather_instance" com.launchernos.dotwellabs.debug)"
assert_true 'the exact id 10 launcher-owned Weather component is found by its numeric column' \
    appwidget_launcher_instance_is "$appwidget_weather_instance" \
    com.launchernos.dotwellabs.debug 10 \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider
assert_false 'a different numeric id does not match the id 10 Weather binding' \
    appwidget_launcher_instance_is "$appwidget_weather_instance" \
    com.launchernos.dotwellabs.debug 11 \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider
assert_false 'the id 10 binding does not match a different provider class' \
    appwidget_launcher_instance_is "$appwidget_weather_instance" \
    com.launchernos.dotwellabs.debug 10 \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelClockWidgetProvider
assert_false 'the id 10 Weather component is rejected when another host owns the block' \
    appwidget_launcher_instance_is "$appwidget_weather_instance" \
    com.other.launcher 10 \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider
assert_false 'an expected provider in a foreign package is rejected' \
    appwidget_launcher_instance_is "$appwidget_weather_instance" \
    com.launchernos.dotwellabs.debug 10 \
    com.other.launcher/app.dotwel.widgets.DotWelWeatherWidgetProvider

appwidget_weather_malformed="$TMP_DIR/appwidget-weather-malformed.txt"
cat > "$appwidget_weather_malformed" <<'EOF'
Widgets:
  [0] id=ten
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=ProviderId{cmp:ComponentInfo{com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider}, profile:0}
  [1] id=10
    host=HostId{user:0, app:10300, hostId:1030, pkg:com.launchernos.dotwellabs.debug}
    provider=not-a-component
EOF
assert_false 'a non-numeric id is rejected' \
    appwidget_launcher_instance_is "$appwidget_weather_malformed" \
    com.launchernos.dotwellabs.debug ten \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider
assert_false 'a numeric id with a malformed provider is rejected' \
    appwidget_launcher_instance_is "$appwidget_weather_malformed" \
    com.launchernos.dotwellabs.debug 10 \
    com.launchernos.dotwellabs.debug/app.dotwel.widgets.DotWelWeatherWidgetProvider

# --- widget bind consent fixtures ------------------------------------------

widget_bind_consent_xml="$TMP_DIR/widget-bind-consent.xml"
cat > "$widget_bind_consent_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,1920]">
    <node index="0" text="Create widget and allow access?" resource-id="android:id/alertTitle" class="android.widget.TextView" package="com.android.settings" bounds="[80,600][1000,700]" />
    <node index="1" text="After you create the widget, the application can access everything displayed.&#10;&#10;Application: DotWel Launcher&#10;Widget: Calendar&#10;" resource-id="android:id/message" class="android.widget.TextView" package="com.android.settings" bounds="[80,720][1000,980]" />
    <node index="2" text="Always allow DotWel Launcher to create widgets and access their data" resource-id="android:id/alwaysUse" class="android.widget.CheckBox" package="com.android.settings" checkable="true" checked="false" clickable="true" enabled="true" bounds="[80,1000][1000,1060]" />
    <node index="3" text="Cancel" resource-id="android:id/button2" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[100,1100][500,1200]" />
    <node index="4" text="Create" resource-id="android:id/button1" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[600,1100][1000,1200]" />
  </node>
</hierarchy>
EOF
assert_true 'the real launcher/widget bind consent is detected' \
    widget_bind_consent_is_ready "$widget_bind_consent_xml" 'DotWel Launcher' Calendar
assert_eq 'the titlecase consent Create control is measured by android:id/button1' \
    '600 1100 1000 1200' \
    "$(widget_bind_create_button_bounds "$widget_bind_consent_xml" 'DotWel Launcher' Calendar)"
assert_false 'the consent Always allow checkbox starts unchecked' \
    widget_bind_always_allow_is_checked "$widget_bind_consent_xml"

widget_bind_consent_compact_xml="$TMP_DIR/widget-bind-consent-compact.xml"
cat > "$widget_bind_consent_compact_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,1920]"><node index="0" text="Create widget and allow access?" resource-id="android:id/alertTitle" class="android.widget.TextView" package="com.android.settings" bounds="[80,600][1000,700]" /><node index="1" text="Application: DotWel Launcher&#10;Widget: Clock" resource-id="android:id/message" class="android.widget.TextView" package="com.android.settings" bounds="[80,720][1000,980]" /><node index="2" text="Always allow DotWel Launcher" resource-id="android:id/alwaysUse" class="android.widget.CheckBox" package="com.android.settings" checkable="true" checked="false" clickable="true" enabled="true" bounds="[80,1000][1000,1060]" /><node index="3" text="Create" resource-id="android:id/button1" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[600,1100][1000,1200]" /></node></hierarchy>
EOF
assert_true 'a compact single-line titlecase bind consent is detected' \
    widget_bind_consent_is_ready "$widget_bind_consent_compact_xml" 'DotWel Launcher' Clock
assert_eq 'a compact titlecase consent Create control is measured' \
    '600 1100 1000 1200' \
    "$(widget_bind_create_button_bounds "$widget_bind_consent_compact_xml" 'DotWel Launcher' Clock)"

# The actual platform dialog (AllowBindAppWidgetActivity) is a compact dump from
# com.android.settings with all-caps CREATE/CANCEL button labels.
widget_bind_platform_xml="$TMP_DIR/widget-bind-platform.xml"
cat > "$widget_bind_platform_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,1920]"><node index="0" text="Create widget and allow access?" resource-id="android:id/alertTitle" class="android.widget.TextView" package="com.android.settings" bounds="[80,600][1000,700]" /><node index="1" text="After you create the widget, the application can access everything displayed.&#10;&#10;Application: DotWel Launcher&#10;Widget: Calendar&#10;" resource-id="android:id/message" class="android.widget.TextView" package="com.android.settings" bounds="[80,720][1000,980]" /><node index="2" text="Always allow DotWel Launcher to create widgets and access their data" resource-id="android:id/alwaysUse" class="android.widget.CheckBox" package="com.android.settings" checkable="true" checked="false" clickable="true" enabled="true" bounds="[80,1000][1000,1060]" /><node index="3" text="CANCEL" resource-id="android:id/button2" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[100,1100][500,1200]" /><node index="4" text="CREATE" resource-id="android:id/button1" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[600,1100][1000,1200]" /></node></hierarchy>
EOF
assert_true 'the actual uppercase platform bind consent is detected' \
    widget_bind_consent_is_ready "$widget_bind_platform_xml" 'DotWel Launcher' Calendar
assert_eq 'the uppercase platform Create control resolves its measured bounds' \
    '600 1100 1000 1200' \
    "$(widget_bind_create_button_bounds "$widget_bind_platform_xml" 'DotWel Launcher' Calendar)"
assert_false 'the platform consent Always allow checkbox starts unchecked' \
    widget_bind_always_allow_is_checked "$widget_bind_platform_xml"

# CI161: the provider header was Clock but the selected preview was Analog
# clock. Consent must use the captured caption, and Clock/Digital clock must not
# satisfy it even though they name the provider or a sibling preview.
widget_bind_analog_xml="$TMP_DIR/widget-bind-analog.xml"
sed 's/Widget: Calendar/Widget: Analog clock/' "$widget_bind_platform_xml" \
    > "$widget_bind_analog_xml"
assert_true 'the CI161 Analog clock consent is accepted with the captured caption' \
    widget_bind_consent_is_ready "$widget_bind_analog_xml" 'DotWel Launcher' 'Analog clock'
assert_eq 'the CI161 Analog clock consent measures its Create control' \
    '600 1100 1000 1200' \
    "$(widget_bind_create_button_bounds "$widget_bind_analog_xml" 'DotWel Launcher' 'Analog clock')"
assert_false 'the provider header Clock is rejected as the widget caption' \
    widget_bind_consent_is_ready "$widget_bind_analog_xml" 'DotWel Launcher' Clock
assert_eq 'a Clock caption expectation exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_analog_xml" 'DotWel Launcher' Clock)"
assert_false 'the sibling Digital clock caption is rejected for the Analog clock consent' \
    widget_bind_consent_is_ready "$widget_bind_analog_xml" 'DotWel Launcher' 'Digital clock'
assert_eq 'a Digital clock caption expectation exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_analog_xml" 'DotWel Launcher' 'Digital clock')"
assert_false 'the CI161 Analog clock consent still starts with Always allow unchecked' \
    widget_bind_always_allow_is_checked "$widget_bind_analog_xml"

widget_bind_unrelated_xml="$TMP_DIR/widget-bind-unrelated.xml"
cat > "$widget_bind_unrelated_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Delete this widget?" class="android.widget.TextView" bounds="[80,600][1000,700]" />
  <node index="1" text="Create" resource-id="android:id/button1" class="android.widget.Button" clickable="true" bounds="[600,1100][1000,1200]" />
</hierarchy>
EOF
assert_false 'a generic dialog with a Create button is not bind consent' \
    widget_bind_consent_is_ready "$widget_bind_unrelated_xml" 'DotWel Launcher' Calendar
assert_eq 'a generic Create dialog exposes no consent Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_unrelated_xml" 'DotWel Launcher' Calendar)"

widget_bind_other_launcher_xml="$TMP_DIR/widget-bind-other-launcher.xml"
sed 's/Application: DotWel Launcher/Application: Other Launcher/' \
    "$widget_bind_platform_xml" > "$widget_bind_other_launcher_xml"
assert_false 'bind consent whose message names another launcher is rejected' \
    widget_bind_consent_is_ready "$widget_bind_other_launcher_xml" 'DotWel Launcher' Calendar
assert_eq 'a wrong-launcher consent exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_other_launcher_xml" 'DotWel Launcher' Calendar)"

widget_bind_other_widget_xml="$TMP_DIR/widget-bind-other-widget.xml"
sed 's/Widget: Calendar/Widget: Weather/' "$widget_bind_platform_xml" \
    > "$widget_bind_other_widget_xml"
assert_false 'bind consent whose message names another widget is rejected' \
    widget_bind_consent_is_ready "$widget_bind_other_widget_xml" 'DotWel Launcher' Calendar
assert_eq 'a wrong-widget consent exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_other_widget_xml" 'DotWel Launcher' Calendar)"

widget_bind_wrong_package_xml="$TMP_DIR/widget-bind-wrong-package.xml"
sed 's/package="com.android.settings"/package="com.example.fake"/g' \
    "$widget_bind_platform_xml" > "$widget_bind_wrong_package_xml"
assert_false 'bind consent outside the system Settings package is rejected' \
    widget_bind_consent_is_ready "$widget_bind_wrong_package_xml" 'DotWel Launcher' Calendar
assert_eq 'a wrong-package consent exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_wrong_package_xml" 'DotWel Launcher' Calendar)"

widget_bind_loose_text_xml="$TMP_DIR/widget-bind-loose-text.xml"
cat > "$widget_bind_loose_text_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,1920]"><node index="0" text="Create widget and allow access?" resource-id="android:id/alertTitle" class="android.widget.TextView" package="com.android.settings" bounds="[80,600][1000,700]" /><node index="1" text="After you create the widget, the application can access everything displayed." resource-id="android:id/message" class="android.widget.TextView" package="com.android.settings" bounds="[80,720][1000,980]" /><node index="2" text="Application: DotWel Launcher" class="android.widget.TextView" package="com.android.settings" bounds="[80,1000][1000,1040]" /><node index="3" text="Widget: Calendar" class="android.widget.TextView" package="com.android.settings" bounds="[80,1040][1000,1080]" /><node index="4" text="Always allow DotWel Launcher" resource-id="android:id/alwaysUse" class="android.widget.CheckBox" package="com.android.settings" checkable="true" checked="false" clickable="true" enabled="true" bounds="[80,1100][1000,1160]" /><node index="5" text="CREATE" resource-id="android:id/button1" class="android.widget.Button" package="com.android.settings" clickable="true" enabled="true" bounds="[600,1100][1000,1200]" /></node></hierarchy>
EOF
assert_false 'launcher/widget text outside the dialog message is rejected' \
    widget_bind_consent_is_ready "$widget_bind_loose_text_xml" 'DotWel Launcher' Calendar
assert_eq 'loose launcher/widget text exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_loose_text_xml" 'DotWel Launcher' Calendar)"

widget_bind_no_create_xml="$TMP_DIR/widget-bind-no-create.xml"
sed '/android:id\/button1/d' "$widget_bind_consent_xml" > "$widget_bind_no_create_xml"
assert_false 'bind consent without android:id/button1 is rejected' \
    widget_bind_consent_is_ready "$widget_bind_no_create_xml" 'DotWel Launcher' Calendar
assert_eq 'bind consent without android:id/button1 has no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_no_create_xml" 'DotWel Launcher' Calendar)"

widget_bind_checked_xml="$TMP_DIR/widget-bind-checked.xml"
sed 's/checked="false"/checked="true"/' "$widget_bind_consent_xml" \
    > "$widget_bind_checked_xml"
assert_true 'a checked Always allow control is detected so the flow can fail closed' \
    widget_bind_always_allow_is_checked "$widget_bind_checked_xml"

widget_bind_disabled_xml="$TMP_DIR/widget-bind-disabled.xml"
sed 's/\(resource-id="android:id\/button1"[^>]*\)enabled="true"/\1enabled="false"/' \
    "$widget_bind_platform_xml" > "$widget_bind_disabled_xml"
assert_false 'bind consent with a disabled Create control is rejected' \
    widget_bind_consent_is_ready "$widget_bind_disabled_xml" 'DotWel Launcher' Calendar
assert_eq 'a disabled Create control exposes no tap target' \
    '' \
    "$(widget_bind_create_button_bounds "$widget_bind_disabled_xml" 'DotWel Launcher' Calendar)"

# The two own providers inherit the application label, so their per-widget
# consent names "DotWel Launcher" as both the application and the widget. The
# pending setup accepts only this exact dialog with an unchecked Always allow.
own_widget_consent_xml="$TMP_DIR/own-widget-consent.xml"
sed 's/Widget: Calendar/Widget: DotWel Launcher/' "$widget_bind_consent_xml" \
    > "$own_widget_consent_xml"
assert_true 'the own-provider consent names the launcher as both app and widget' \
    widget_bind_consent_is_ready "$own_widget_consent_xml" 'DotWel Launcher' 'DotWel Launcher'
assert_eq 'the own-provider consent Create control is measured' \
    '600 1100 1000 1200' \
    "$(widget_bind_create_button_bounds "$own_widget_consent_xml" 'DotWel Launcher' 'DotWel Launcher')"
assert_false 'the own-provider consent starts with Always allow unchecked' \
    widget_bind_always_allow_is_checked "$own_widget_consent_xml"

own_widget_other_xml="$TMP_DIR/own-widget-other-widget.xml"
sed 's/Widget: DotWel Launcher/Widget: Weather/' "$own_widget_consent_xml" \
    > "$own_widget_other_xml"
assert_false 'an own-provider setup that opens another widget consent is rejected' \
    widget_bind_consent_is_ready "$own_widget_other_xml" 'DotWel Launcher' 'DotWel Launcher'

own_widget_cancel_xml="$TMP_DIR/own-widget-cancel.xml"
sed '/android:id\/button1/d' "$own_widget_consent_xml" > "$own_widget_cancel_xml"
assert_false 'a cancel-only own-widget dialog is not accepted as setup' \
    widget_bind_consent_is_ready "$own_widget_cancel_xml" 'DotWel Launcher' 'DotWel Launcher'
assert_eq 'a cancel-only own-widget dialog exposes no Create target' \
    '' \
    "$(widget_bind_create_button_bounds "$own_widget_cancel_xml" 'DotWel Launcher' 'DotWel Launcher')"

own_widget_checked_xml="$TMP_DIR/own-widget-checked.xml"
sed 's/checked="false"/checked="true"/' "$own_widget_consent_xml" \
    > "$own_widget_checked_xml"
assert_true 'a checked Always allow own-widget consent is detected so setup fails closed' \
    widget_bind_always_allow_is_checked "$own_widget_checked_xml"


# --- HOME long-press geometry fixtures -------------------------------------

assert_eq 'the HOME long-press target is the empty centre between header and dock' \
    '540 834' \
    "$(home_longpress_target "$actual_home_xml")"
longpress_target=$(home_longpress_target "$actual_home_xml")
longpress_y=$(printf '%s\n' "$longpress_target" | awk '{ print $2 }')
if [ "$longpress_y" -gt 294 ] && [ "$longpress_y" -lt 1375 ]; then
    pass 'the HOME long-press target avoids the header and dock bands'
else
    fail "the HOME long-press target $longpress_y is not between the header and dock"
fi
assert_true 'the measured HOME centre is free of labelled clickable items' \
    ui_point_is_free "$actual_home_xml" 540 834

occupied_home_xml="$TMP_DIR/occupied-home.xml"
awk '
    /<node index="6"/ && !done {
        print "    <node index=\"7\" text=\"Play Store\" class=\"android.widget.TextView\" content-desc=\"\" clickable=\"true\" bounds=\"[400,700][700,900]\" />"
        done = 1
    }
    { print }
' "$actual_home_xml" > "$occupied_home_xml"
assert_false 'a labelled clickable item at the centre is not free' \
    ui_point_is_free "$occupied_home_xml" 540 834
assert_eq 'the HOME long-press walks away from an occupied centre' \
    '540 927' \
    "$(home_longpress_target "$occupied_home_xml")"

blocked_home_xml="$TMP_DIR/blocked-home.xml"
awk '
    /<node index="6"/ && !done {
        print "    <node index=\"7\" text=\"Widget\" class=\"android.widget.TextView\" content-desc=\"\" clickable=\"true\" bounds=\"[0,370][1080,1299]\" />"
        done = 1
    }
    { print }
' "$actual_home_xml" > "$blocked_home_xml"
assert_false 'a HOME whose whole long-press band is occupied has no unsafe fallback' \
    home_longpress_target "$blocked_home_xml"

empty_xml="$TMP_DIR/empty.xml"
printf '<hierarchy rotation="0"></hierarchy>\n' > "$empty_xml"
assert_false 'an empty hierarchy cannot produce a HOME long-press target' \
    home_longpress_target "$empty_xml"

# CI155 real HOME: root 1080x1920, a full-root workspace, a hotseat at y=1481
# and three non-clickable widget hosts labelled "DotWel Launcher". The third
# host is the Device card [38,770][1042,1180], so 540,896 is inside it even
# though it is neither clickable nor labelled by text. The long-press must
# reject that point and find the empty band between the Device card and dock.
real155_home_xml="$TMP_DIR/real155-home.xml"
cat > "$real155_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/workspace" class="com.android.launcher3.Workspace" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
      <node index="0" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" clickable="false" bounds="[38,328][524,738]" />
      <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" clickable="false" bounds="[556,328][1042,738]" />
      <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="DotWel Launcher" clickable="false" bounds="[38,770][1042,1180]" />
    </node>
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/hotseat" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,1481][1080,1920]">
      <node index="0" text="Phone" class="android.widget.TextView" content-desc="" clickable="true" bounds="[22,1481][281,1674]" />
      <node index="1" text="Messaging" class="android.widget.TextView" content-desc="" clickable="true" bounds="[281,1481][540,1674]" />
      <node index="2" text="Contacts" class="android.widget.TextView" content-desc="" clickable="true" bounds="[540,1481][799,1674]" />
      <node index="3" text="WebView Browser Tester" class="android.widget.TextView" content-desc="" clickable="true" bounds="[799,1481][1058,1674]" />
    </node>
  </node>
</hierarchy>
EOF
assert_false 'a non-clickable widget host at 540,896 is occupied' \
    ui_point_is_free "$real155_home_xml" 540 896
real155_target=$(home_longpress_target "$real155_home_xml")
assert_eq 'the CI155 HOME long-press target lands below the Device card' \
    '540 1300' "$real155_target"
real155_y=$(printf '%s\n' "$real155_target" | awk '{ print $2 }')
if [ "$real155_y" -gt 1180 ] && [ "$real155_y" -lt 1481 ]; then
    pass 'the CI155 long-press target is below the Device card and above the dock'
else
    fail "the CI155 long-press target $real155_y is not in the 1180..1481 band"
fi
set -- $real155_target
assert_true 'the CI155 long-press target is demonstrably free' \
    ui_point_is_free "$real155_home_xml" "$1" "$2"

pending_free_xml="$TMP_DIR/pending-free.xml"
cat > "$pending_free_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="com.android.launcher3.widget.PendingAppWidgetHostView" clickable="false" bounds="[400,700][700,900]" />
  </node>
</hierarchy>
EOF
assert_false 'a non-clickable pending host at 540,834 is occupied' \
    ui_point_is_free "$pending_free_xml" 540 834

unlabelled_host_xml="$TMP_DIR/unlabelled-host.xml"
cat > "$unlabelled_host_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" clickable="false" bounds="[400,700][700,900]" />
  </node>
</hierarchy>
EOF
assert_false 'an unlabelled non-clickable widget host at 540,834 is occupied' \
    ui_point_is_free "$unlabelled_host_xml" 540 834

all_widgets_xml="$TMP_DIR/all-widgets-home.xml"
cat > "$all_widgets_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="app.lawnchair.LawnchairAppWidgetHostView" clickable="false" bounds="[0,300][1080,1481]" />
    <node index="1" text="Phone" class="android.widget.TextView" clickable="true" bounds="[22,1481][281,1674]" />
  </node>
</hierarchy>
EOF
assert_false 'a HOME whose whole long-press band is widget hosts has no unsafe fallback' \
    home_longpress_target "$all_widgets_xml"

# --- static regression on the smoke flow -----------------------------------

drawer_body="$TMP_DIR/exercise_app_drawer.sh"
sed -n '/^exercise_app_drawer() {/,/^}/p' "$SMOKE" > "$drawer_body"

open_body="$TMP_DIR/open_app_drawer.sh"
sed -n '/^open_app_drawer() {/,/^}/p' "$SMOKE" > "$open_body"

target_body="$TMP_DIR/drawer_target_for_dump.sh"
sed -n '/^drawer_target_for_dump() (/,/^)/p' "$SMOKE" > "$target_body"

assert_true 'the drawer search taps the clickable Settings result node' \
    grep -Fq "ui_clickable_label_bounds \"\$ARTIFACTS/appdrawer-search.xml\" 'Settings'" "$drawer_body"
assert_true 'the Settings launch polls the exact resumed package' \
    grep -Fq 'wait_for_foreground com.android.settings "$ARTIFACTS/activities-app-launch.txt"' "$drawer_body"
assert_false 'the drawer flow never launches Settings directly with am start' \
    grep -Fq 'am start' "$drawer_body"
assert_false 'the Settings foreground check never greps the whole activity dump' \
    grep -Fq 'grep -Fq '"'"'com.android.settings/'"'"' "$ARTIFACTS/activities-app-launch.txt"' "$drawer_body"
assert_true 'the drawer opens with a bounded attempt loop' \
    grep -Fq 'max_attempts=4' "$open_body"
assert_true 'each drawer attempt waits for launcher idle' \
    grep -Fq 'wait_for_launcher_idle "$ARTIFACTS/appdrawer-attempt-$attempt-idle.txt"' "$open_body"
assert_true 'each drawer attempt computes the measured target' \
    grep -Fq 'drawer_target_for_dump' "$open_body"
assert_true 'each drawer attempt polls the real drawer state' \
    grep -Fq 'drawer_is_ready "$ARTIFACTS/appdrawer-attempt-$attempt.xml"' "$open_body"
assert_true 'each drawer attempt requires a change from the pre-swipe HOME' \
    grep -Fq '"$ARTIFACTS/appdrawer-attempt-$attempt-before.xml"' "$open_body"
assert_true 'each drawer attempt records its swipe and artifacts' \
    grep -Fq 'appdrawer-swipe-log.txt' "$open_body"
assert_true 'each drawer attempt captures before XML and PNG' \
    grep -Fq 'appdrawer-attempt-$attempt-before' "$open_body"
assert_false 'the drawer swipe no longer starts at the old 75 percent dock hit region' \
    grep -Fq 'height * 3 / 4' "$open_body"
assert_true 'the drawer target measures the QSB top from the HOME dump' \
    grep -Fq 'ui_qsb_top' "$target_body"
assert_true 'the drawer target measures the dock icon bottom from the HOME dump' \
    grep -Fq 'ui_dock_bottom' "$target_body"
assert_true 'the drawer target passes the measured dock band and QSB to the geometry' \
    grep -Fq '"$dock_top" "$dock_bottom" "$qsb_top"' "$target_body"
assert_true 'the drawer target rejects a header by deriving the QSB after the dock bottom' \
    grep -Fq 'qsb_top=$(ui_qsb_top "$xml" "$dock_bottom")' "$target_body"
assert_true 'the drawer swipe logs its duration' \
    grep -Fq 'duration=%s' "$open_body"
assert_true 'the drawer swipe uses a bounded 1500 ms duration for MOVE delivery' \
    grep -Fq 'swipe_duration=1500' "$open_body"
assert_true 'the drawer swipe passes the logged duration to adb' \
    grep -Fq 'input swipe "$1" "$2" "$3" "$4" "$swipe_duration"' "$open_body"

# --- static regression on the real HOME role consent capture ---------------

consent_body="$TMP_DIR/verify_default_home_consent.sh"
sed -n '/^verify_default_home_consent() {/,/^}/p' "$SMOKE" > "$consent_body"

assert_true 'the smoke captures the settings default-launcher warning' \
    grep -Fq 'role-consent-settings.xml' "$consent_body"
assert_true 'the smoke taps the warning, not a guessed coordinate' \
    grep -Fq 'tap_center_of_bounds "$_vdhc_warning"' "$consent_body"
assert_true 'the smoke waits for the real platform consent screen' \
    grep -Fq 'ui_cancel_bounds' "$consent_body"
assert_true 'the smoke captures the consent XML and screenshot' \
    grep -Fq 'role-consent.png' "$consent_body"
assert_true 'the smoke cancels the platform consent screen' \
    grep -Fq 'tap_center_of_bounds "$_vdhc_cancel"' "$consent_body"
assert_true 'the smoke proves the role holder list is unchanged after cancel' \
    grep -Fq 'role-consent-after.sorted' "$consent_body"
assert_false 'the consent capture does not grant the role itself' \
    grep -Fq 'add-role-holder' "$consent_body"

announcement_body="$TMP_DIR/ui_assert_no_inherited_announcements.sh"
sed -n '/^ui_assert_no_inherited_announcements() (/,/^)/p' "$SMOKE" > "$announcement_body"
assert_true 'the settings smoke checks the captured hierarchy for inherited announcements' \
    grep -Fq 'ui_assert_no_inherited_announcements' "$consent_body"
assert_true 'the announcement check looks for the inherited Lawnchair card' \
    grep -Fq "'Lawnchair'" "$announcement_body"
assert_true 'the announcement check looks for the sneak peek card' \
    grep -Fq "'sneak peek'" "$announcement_body"
assert_true 'the announcement check looks for the important announcement cards' \
    grep -Fq "'important announcement'" "$announcement_body"
assert_true 'the announcement check is case-insensitive' \
    grep -Fq 'grep -Fqi' "$announcement_body"
announcement_check_line=$(grep -n 'ui_assert_no_inherited_announcements' "$consent_body" | sed -n '1s/:.*//p')
settings_screenshot_line=$(grep -n 'capture_screenshot_to role-consent-settings.png' "$consent_body" | sed -n '1s/:.*//p')
warning_tap_line=$(grep -n 'tap_center_of_bounds "$_vdhc_warning"' "$consent_body" | sed -n '1s/:.*//p')
if [ -n "$announcement_check_line" ] && [ -n "$settings_screenshot_line" ] &&
    [ -n "$warning_tap_line" ] &&
    [ "$settings_screenshot_line" -lt "$announcement_check_line" ] &&
    [ "$announcement_check_line" -lt "$warning_tap_line" ]; then
    pass 'the clean settings screenshot and announcement check run before the warning tap'
else
    fail 'the clean settings screenshot and announcement check run before the warning tap'
fi

consent_call_line=$(grep -n '^verify_default_home_consent$' "$SMOKE" | sed -n '1s/:.*//p')
grant_line=$(grep -n 'add-role-holder' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$consent_call_line" ] && [ -n "$grant_line" ] &&
    [ "$consent_call_line" -lt "$grant_line" ]; then
    pass 'the consent capture runs before the smoke grants the role'
else
    fail 'the consent capture runs before the smoke grants the role'
fi

# --- static regression on the real grid and widget-picker capture ----------

grid_body="$TMP_DIR/capture_grid_settings.sh"
sed -n '/^capture_grid_settings() {/,/^}/p' "$SMOKE" > "$grid_body"

widgets_body="$TMP_DIR/capture_widgets_picker.sh"
sed -n '/^capture_widgets_picker() {/,/^}/p' "$SMOKE" > "$widgets_body"

primary_restore_body="$TMP_DIR/restore_primary_home.sh"
sed -n '/^restore_primary_home() {/,/^}/p' "$SMOKE" > "$primary_restore_body"

clean_home_body="$TMP_DIR/capture_clean_home_theme.sh"
sed -n '/^capture_clean_home_theme() {/,/^}/p' "$SMOKE" > "$clean_home_body"

home_verify_body="$TMP_DIR/verify_nothing_home.sh"
sed -n '/^verify_nothing_home() {/,/^}/p' "$SMOKE" > "$home_verify_body"

home_widgets_body="$TMP_DIR/verify_home_widgets.sh"
sed -n '/^verify_home_widgets() {/,/^}/p' "$SMOKE" > "$home_widgets_body"

primary_home_ready_body="$TMP_DIR/primary_home_is_ready.sh"
sed -n '/^primary_home_is_ready() (/,/^)/p' "$SMOKE" > "$primary_home_ready_body"

own_widget_setup_body="$TMP_DIR/complete_own_widget_setup.sh"
sed -n '/^complete_own_widget_setup() {/,/^}/p' "$SMOKE" > "$own_widget_setup_body"

search_pages_body="$TMP_DIR/search_home_pages_for_widget.sh"
sed -n '/^search_home_pages_for_widget() {/,/^}/p' "$SMOKE" > "$search_pages_body"

device_settings_body="$TMP_DIR/exercise_device_settings_shortcuts.sh"
sed -n '/^exercise_device_settings_shortcuts() {/,/^}/p' "$SMOKE" \
    > "$device_settings_body"

resolve_settings_body="$TMP_DIR/resolve_settings_action_component.sh"
sed -n '/^resolve_settings_action_component() (/,/^)/p' "$SMOKE" \
    > "$resolve_settings_body"

assert_true 'the own-widget setup accepts only one exact own provider record' \
    grep -Fq 'own_widget_new_binding' "$own_widget_setup_body"
assert_false 'the own-widget setup has no substring provider acceptance' \
    grep -Eq 'case "\$_cows_new"|\*app\.dotwel\.widgets\.DotWel(Clock|Battery)WidgetProvider\*' \
    "$own_widget_setup_body"
assert_true 'the own-widget setup requires the exact AllowBindAppWidgetActivity' \
    grep -Fq 'com.android.settings .AllowBindAppWidgetActivity' "$own_widget_setup_body"
assert_false 'the own-widget setup never accepts any Settings package as the consent' \
    grep -Fq 'foreground_is "$ARTIFACTS/own-widget-activity' "$own_widget_setup_body"
assert_true 'the own-widget setup requires the real launcher HOME after Create' \
    grep -Fq '"$PKG" "$LAUNCHER_ACTIVITY"' "$own_widget_setup_body"
assert_true 'the own-widget setup measures the pending count before the round' \
    grep -Fq '_cows_pending_before_count=' "$own_widget_setup_body"
assert_true 'the own-widget setup finishes a round only after a one-pending decrease' \
    grep -Fq '[ "$_cows_remaining_count" -eq "$((_cows_pending_before_count - 1))" ]' \
    "$own_widget_setup_body"
assert_true 'the own-widget setup fails when the one-pending decrease is not observed' \
    grep -Fq '_cows_round_finished' "$own_widget_setup_body"
assert_true 'the own-widget setup keeps at most three rounds' \
    grep -Fq '_cows_max_rounds=3' "$own_widget_setup_body"
assert_true 'the own-widget setup keeps bounded polling' \
    grep -Fq '_cows_max_polls=12' "$own_widget_setup_body"
assert_true 'the own-widget setup refuses a checked Always allow' \
    grep -Fq 'widget_bind_always_allow_is_checked' "$own_widget_setup_body"
assert_true 'the own-widget setup taps only the measured Create control' \
    grep -Fq 'tap_center_of_bounds "$_cows_create"' "$own_widget_setup_body"
assert_true 'the own-widget setup captures before, consent and after XML' \
    grep -Fq 'own-widget-before-$_cows_round.xml' "$own_widget_setup_body"
assert_true 'the own-widget setup captures before, consent and after PNG' \
    grep -Fq 'own-widget-consent-$_cows_round.png' "$own_widget_setup_body"
assert_true 'the own-widget setup captures the final after XML and PNG' \
    grep -Fq 'own-widget-after.xml' "$own_widget_setup_body"
assert_false 'the own-widget setup never binds or edits the database directly' \
    grep -Eq 'bindAppWidget|addItemToDatabase|LauncherSettings|content://|sqlite' \
    "$own_widget_setup_body"

assert_true 'the clean home capture uses system dark and light modes' \
    grep -Fq 'for _ccht_mode in yes no; do' "$clean_home_body"
assert_true 'the clean home capture switches the emulator night mode' \
    grep -Fq 'cmd uimode night "$_ccht_mode"' "$clean_home_body"
assert_true 'the clean home capture requires the borderless date strip' \
    grep -Fq 'does not expose the NothingUI date strip' "$clean_home_body"
assert_true 'the clean home capture stores dark and light XML evidence' \
    grep -Fq 'clean-home-$_ccht_name.xml' "$clean_home_body"
assert_true 'the clean home capture stores dark and light PNG evidence' \
    grep -Fq 'clean-home-$_ccht_name.png' "$clean_home_body"
assert_true 'the clean home capture restores the previous night mode' \
    grep -Fq 'cmd uimode night "$_ccht_night_value"' "$clean_home_body"
assert_true 'the clean home capture returns HOME' \
    grep -Fq 'return_home clean-home' "$clean_home_body"
assert_false 'the clean home capture never adds a widget' \
    grep -Eq 'widget_picker|bindAppWidget|addItemToDatabase' "$clean_home_body"

assert_true 'the HOME verification asserts the date strip and live clock' \
    grep -Fq 'date strip and live clock widget' "$home_verify_body"
assert_true 'the HOME verification proves both original widgets are bound' \
    grep -Fq 'verify_home_widgets' "$home_verify_body"
assert_true 'the widget binding check dumps the real appwidget host' \
    grep -Fq 'dumpsys appwidget' "$home_widgets_body"
assert_true 'the widget binding check requires the clock provider' \
    grep -Fq 'DotWelClockWidgetProvider' "$home_widgets_body"
assert_true 'the widget binding check requires the battery provider' \
    grep -Fq 'DotWelBatteryWidgetProvider' "$home_widgets_body"
assert_true 'the widget binding check requires the device provider' \
    grep -Fq 'DotWelDeviceWidgetProvider' "$home_widgets_body"
assert_true 'the widget binding check requires a launcher-owned instance id' \
    grep -Fq 'appwidget_launcher_instances' "$home_widgets_body"
assert_true 'the widget binding check requires distinct clock and battery ids' \
    grep -Fq '_vhw_clock_id" != "$_vhw_battery_id' "$home_widgets_body"
assert_true 'the widget binding check requires the device id to differ from both own ids' \
    grep -Fq '_vhw_device_id" != "$_vhw_clock_id' "$home_widgets_body"
assert_true 'the widget binding check requires the real clock child id' \
    grep -Fq 'nothingui_clock_time' "$home_widgets_body"
assert_true 'the widget binding check requires the real battery child id' \
    grep -Fq 'nothingui_battery_art' "$home_widgets_body"
assert_true 'the widget binding check requires the real device storage child ids' \
    grep -Fq 'nothingui_device_storage_value' "$home_widgets_body"
assert_true 'the widget binding check requires the real device progress child id' \
    grep -Fq 'nothingui_device_storage_progress' "$home_widgets_body"
assert_true 'the widget binding check requires live clock text' \
    grep -Fq 'home_widget_clock_text_is_live' "$home_widgets_body"
assert_true 'the widget binding check requires a real battery description' \
    grep -Fq 'home_widget_battery_description_is_real' "$home_widgets_body"
assert_true 'the widget binding check requires the real device storage pair' \
    grep -Fq 'home_widget_device_storage_is_real "$_vhw_device_value" "$_vhw_device_detail"' \
    "$home_widgets_body"

# --- executed primary-HOME readiness fixtures (CI269) ---------------------
# CI269 returned from the read-only grid settings and verify_nothing_home saw
# the date pill plus battery/device hosts but not the clock while the launcher
# was still reinflating a PendingAppWidgetHostView. Readiness must retry on
# fresh live state, but a permanently missing clock must still fail closed.
assert_true 'the primary HOME readiness predicate is extractable' \
    test -s "$primary_home_ready_body"

ready_missing_clock_xml="$TMP_DIR/ready-missing-clock.xml"
cat > "$ready_missing_clock_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="MON 23 NOV" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_date" class="android.widget.TextView" bounds="[40,100][500,180]" />
    <node index="1" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="com.android.launcher3.widget.PendingAppWidgetHostView" bounds="[40,400][500,800]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_battery_art" class="android.widget.ImageView" bounds="[540,400][1000,800]" />
    <node index="3" text="42%" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_value" class="android.widget.TextView" bounds="[40,900][500,1000]" />
    <node index="4" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_progress" class="android.widget.ProgressBar" bounds="[40,1020][500,1060]" />
  </node>
</hierarchy>
EOF
ready_clock_xml="$TMP_DIR/ready-clock.xml"
cat > "$ready_clock_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="MON 23 NOV" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_date" class="android.widget.TextView" bounds="[40,100][500,180]" />
    <node index="1" text="3:07" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_clock_time" class="android.widget.TextClock" bounds="[40,400][500,800]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_battery_art" class="android.widget.ImageView" bounds="[540,400][1000,800]" />
    <node index="3" text="42%" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_value" class="android.widget.TextView" bounds="[40,900][500,1000]" />
    <node index="4" text="" resource-id="com.launchernos.dotwellabs.debug:id/nothingui_device_storage_progress" class="android.widget.ProgressBar" bounds="[40,1020][500,1060]" />
  </node>
</hierarchy>
EOF
assert_false 'a pending-reinflation HOME is not primary-ready without the clock' \
    sh -c '. "$1"; . "$2"; primary_home_is_ready "$3"' \
    sh "$LIB" "$primary_home_ready_body" "$ready_missing_clock_xml"
assert_true 'the same HOME is primary-ready once the real clock text returns' \
    sh -c '. "$1"; . "$2"; primary_home_is_ready "$3"' \
    sh "$LIB" "$primary_home_ready_body" "$ready_clock_xml"

home_readiness_harness="$TMP_DIR/home-readiness-harness.sh"
cat > "$home_readiness_harness" <<'EOF'
set -eu
. "$1"
. "$2"
. "$3"
ARTIFACTS=$4
MODE=$5
MISSING_XML=$6
CLOCK_XML=$7
PKG=com.launchernos.dotwellabs.debug
LAUNCHER_ACTIVITY=app.lawnchair.LawnchairLauncher
HOME_ROLE=android.app.role.HOME
COUNTER=$ARTIFACTS/capture-count
ACTIVITIES=$ARTIFACTS/launcher-activities.txt
mkdir -p "$ARTIFACTS"
cat > "$ACTIVITIES" <<'DUMP'
  * Task{abc #1 type=home}
    mResumedActivity: ActivityRecord{abc u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t1}
    topResumedActivity=ActivityRecord{abc u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t1}
DUMP
sleep() { :; }
fail() { printf 'fail:%s\n' "$*" >&2; exit 1; }
adb_cmd() {
    case "$*" in
        *'dumpsys activity activities'*) cat "$ACTIVITIES" ;;
        *'dumpsys appwidget'*) printf 'appwidget dump\n' ;;
        *'get-role-holders'*) printf '%s\n' "$PKG" ;;
        *'resolve-activity'*) printf '%s/%s\n' "$PKG" "$LAUNCHER_ACTIVITY" ;;
        *) : ;;
    esac
}
capture_ui_xml() {
    n=0
    [ ! -f "$COUNTER" ] || n=$(cat "$COUNTER")
    n=$((n + 1))
    printf '%s\n' "$n" > "$COUNTER"
    if [ "$MODE" = transient ] && [ "$n" -ge 5 ]; then
        cp "$CLOCK_XML" "$ARTIFACTS/$1"
    else
        cp "$MISSING_XML" "$ARTIFACTS/$1"
    fi
    return 0
}
capture_screenshot_to() {
    mkdir -p "$ARTIFACTS"
    printf 'png:%s\n' "$1" > "$ARTIFACTS/$1"
}
verify_home_widgets() {
    printf 'verified\n' > "$ARTIFACTS/home-widgets-verified.txt"
}
verify_nothing_home
EOF

ready_transient_dir="$TMP_DIR/ready-transient"
if sh "$home_readiness_harness" "$LIB" "$primary_home_ready_body" \
    "$home_verify_body" "$ready_transient_dir" transient \
    "$ready_missing_clock_xml" "$ready_clock_xml"; then
    pass 'readiness accepts a transiently pending clock that returns on a fresh capture'
else
    fail 'readiness accepts a transiently pending clock that returns on a fresh capture'
fi
assert_true 'the transient run records the no-clock then clock-ready transition' \
    sh -c 'grep -Fq "attempt=1 " "$1/home-readiness-log.txt" &&
        grep -Fq "clock=no" "$1/home-readiness-log.txt" &&
        grep -Fq "attempt=5 " "$1/home-readiness-log.txt" &&
        grep -Fq "clock=yes" "$1/home-readiness-log.txt"' sh "$ready_transient_dir"
assert_true 'the transient run captures a fresh XML and PNG for every attempt' \
    sh -c '[ -s "$1/home-readiness-1.xml" ] && [ -s "$1/home-readiness-1.png" ] &&
        [ -s "$1/home-readiness-5.xml" ] && [ -s "$1/home-readiness-5.png" ] &&
        ! cmp -s "$1/home-readiness-1.xml" "$1/home-readiness-5.xml"' sh "$ready_transient_dir"
assert_true 'the transient run captures foreground and appwidget diagnostics per attempt' \
    sh -c '[ -s "$1/activities-home-readiness-1.txt" ] &&
        [ -s "$1/appwidget-home-readiness-1.txt" ] &&
        [ -s "$1/activities-home-readiness-5.txt" ] &&
        [ -s "$1/appwidget-home-readiness-5.txt" ]' sh "$ready_transient_dir"
assert_true 'the transient run promotes the ready attempt to home.xml and home.png' \
    sh -c 'cmp -s "$1/home.xml" "$1/home-readiness-5.xml" &&
        cmp -s "$1/home.png" "$1/home-readiness-5.png"' sh "$ready_transient_dir"

ready_permanent_dir="$TMP_DIR/ready-permanent"
if sh "$home_readiness_harness" "$LIB" "$primary_home_ready_body" \
    "$home_verify_body" "$ready_permanent_dir" permanent \
    "$ready_missing_clock_xml" "$ready_clock_xml"; then
    fail 'a permanently missing clock never becomes primary-ready'
else
    pass 'a permanently missing clock never becomes primary-ready'
fi
assert_true 'the permanent failure keeps polling beyond the old four captures' \
    grep -Fq 'attempt=5 ' "$ready_permanent_dir/home-readiness-log.txt"
assert_true 'the permanent failure retains a bounded failure summary' \
    sh -c '[ -s "$1/home-readiness-failure.txt" ] &&
        grep -Fq "bounded attempts" "$1/home-readiness-failure.txt"' \
    sh "$ready_permanent_dir"
assert_false 'the permanent failure never promotes a clock-less page to home.xml' \
    test -s "$ready_permanent_dir/home.xml"
assert_true 'the permanent failure never emits a success evidence file' \
    test ! -e "$ready_permanent_dir/home-nothing.txt"

assert_true 'the clean home capture requires the SYSTEM theme choice' \
    grep -Fq 'assert_settings_theme_choice_system' "$clean_home_body"
assert_true 'the clean home capture proves widgets for each dark/light XML' \
    grep -Fq 'verify_home_widgets "$ARTIFACTS/clean-home-$_ccht_name.xml"' \
    "$clean_home_body"
assert_true 'the clean home capture stores per-mode widget evidence' \
    grep -Fq 'clean-home-$_ccht_name-widgets-verified.txt' "$clean_home_body"

assert_true 'the grid capture uses the real Home screen grid deep link' \
    grep -Fq 'lawnchair://settings/home-screen-grid' "$grid_body"
assert_true 'the grid capture uses the existing PreferenceActivity' \
    grep -Fq '_cgs_component="$PKG/$PREFERENCES_ACTIVITY"' "$grid_body"
assert_true 'the grid capture starts the existing activity with the deep link data' \
    grep -Fq 'am start -W' "$grid_body"
assert_true 'the grid capture passes the deep link URI to am start' \
    grep -Fq -- '-d "$_cgs_url"' "$grid_body"
assert_true 'the grid capture stores grid-settings.xml evidence' \
    grep -Fq 'grid-settings.xml' "$grid_body"
assert_true 'the grid capture stores grid-settings.png evidence' \
    grep -Fq 'grid-settings.png' "$grid_body"
assert_true 'the grid capture asserts the real grid readiness helper' \
    grep -Fq 'grid_settings_is_ready' "$grid_body"
assert_true 'the grid capture proves Apply is still disabled' \
    grep -Fq 'grid_apply_is_unchanged' "$grid_body"
assert_true 'the grid capture keeps the last failed readiness screenshot before failing' \
    grep -Fq 'grid-settings-attempt-$_cgs_last.png' "$grid_body"
assert_false 'the grid capture never taps a control or Apply' \
    grep -Fq 'tap_center_of_bounds' "$grid_body"
assert_false 'the grid capture never writes a preference' \
    grep -Eq 'settings put|shared_prefs|onChange|prefs\.' "$grid_body"
assert_true 'the grid capture returns HOME after the read-only screen' \
    grep -Fq 'return_home grid-settings' "$grid_body"
assert_true 'the grid capture re-verifies the actual HOME' \
    grep -Fq 'verify_nothing_home' "$grid_body"

assert_true 'the widgets capture uses a real long-press gesture' \
    grep -Fq 'input swipe "$1" "$2" "$1" "$2" 1000' "$widgets_body"
assert_true 'the widgets capture measures the empty target from HOME' \
    grep -Fq 'home_longpress_target' "$widgets_body"
assert_true 'the widgets capture selects Widgets by measured bounds' \
    grep -Fq 'ui_clickable_label_bounds' "$widgets_body"
assert_true 'the widgets capture uses the real Widgets option label' \
    grep -Fq "'Widgets'" "$widgets_body"
assert_true 'the widgets capture requires the real HOME popup' \
    grep -Fq 'home_popup_is_ready' "$widgets_body"
assert_true 'the popup readiness uses the real popup_container id' \
    grep -Fq 'popup_container' "$LIB"
assert_true 'the popup readiness uses clickable system_shortcut rows' \
    grep -Fq 'system_shortcut' "$LIB"
assert_false 'the popup readiness no longer guesses popup class names' \
    grep -Eq 'OptionsPopupView|DeepShortcutView' "$LIB"
assert_true 'the widgets capture stores the last failed popup PNG before BACK' \
    grep -Fq 'home-popup-attempt-$_cwp_attempt-last.png' "$widgets_body"
assert_true 'the widgets capture requires the native picker and not HOME' \
    grep -Fq 'widget_picker_is_ready' "$widgets_body"
assert_true 'the widgets capture compares the picker against the pre-long-press HOME' \
    grep -Fq 'home-before-widgets-attempt' "$widgets_body"
assert_true 'the widgets capture stores home-popup.xml evidence' \
    grep -Fq 'home-popup.xml' "$widgets_body"
assert_true 'the widgets capture stores widgets-picker.xml evidence' \
    grep -Fq 'widgets-picker.xml' "$widgets_body"
assert_true 'the widgets capture stores home-popup.png evidence' \
    grep -Fq 'home-popup.png' "$widgets_body"
assert_true 'the widgets capture stores widgets-picker.png evidence' \
    grep -Fq 'widgets-picker.png' "$widgets_body"
assert_false 'the widgets capture never starts the picker activity directly' \
    grep -Eq 'am start.*(AppWidgetPickActivity|ACTION_APPWIDGET_PICK|widgetpicker)' "$widgets_body"
assert_false 'the widgets capture never writes a preference' \
    grep -Eq 'settings put|shared_prefs|onChange|prefs\.' "$widgets_body"
assert_true 'the widgets capture returns HOME after the picker' \
    grep -Fq 'return_home widgets-picker' "$widgets_body"
assert_true 'the widgets capture re-verifies the actual HOME' \
    grep -Fq 'verify_nothing_home' "$widgets_body"
assert_true 'the widgets capture is bounded' \
    grep -Fq '_cwp_max_attempts=3' "$widgets_body"
assert_true 'the widgets capture selects a real provider header with widgets' \
    grep -Fq 'widget_picker_provider_bounds' "$widgets_body"
assert_true 'the widgets capture prefers the system Clock/Calendar providers' \
    grep -Fq 'for _cwp_title in Clock Calendar' "$widgets_body"
assert_true 'the widgets capture measures the expanded provider preview' \
    grep -Fq 'widget_picker_preview_bounds' "$widgets_body"
assert_true 'the widgets capture re-resolves the expanded provider header by title' \
    grep -Fq '_cwp_candidate_header=$(widget_picker_provider_bounds' "$widgets_body"
assert_true 'the widgets capture keeps the re-resolved header for the preview' \
    grep -Fq '_cwp_header=$_cwp_candidate_header' "$widgets_body"
assert_true 'the widgets capture taps the measured preview, not a fixed point' \
    grep -Fq 'tap_center_of_bounds "$_cwp_preview"' "$widgets_body"
assert_true 'the widgets capture remeasures the safe viewport after exposing Add' \
    grep -Fq 'widget_picker_viewport_bounds "$_cwp_add_xml"' "$widgets_body"
assert_true 'the widgets capture intersects the Add button with the safe viewport' \
    grep -Fq 'widget_add_safe_bounds' "$widgets_body"
assert_true 'the widgets capture taps the safe Add intersection, not a fixed point' \
    grep -Fq 'tap_center_of_bounds "$_cwp_safe_add"' "$widgets_body"
assert_false 'the widgets capture never taps the unsafe original Add centre' \
    grep -Fq 'tap_center_of_bounds "$_cwp_add"' "$widgets_body"
assert_true 'the widgets capture bounds the measured Add re-scroll attempts' \
    grep -Fq '_cwp_max_add_scrolls=3' "$widgets_body"
assert_true 'the widgets capture re-resolves Add after a measured list scroll' \
    grep -Fq 'widgets-add-scroll-$_cwp_add_scroll.xml' "$widgets_body"
assert_true 'the widgets capture detects the exact launcher/widget bind consent' \
    grep -Fq 'widget_bind_consent_is_ready' "$widgets_body"
assert_true 'the widgets capture requires the launcher identity and captured widget caption' \
    grep -Fq '"$EXPECTED_LABEL" "$_cwp_widget_caption"' "$widgets_body"
assert_true 'the widgets capture reads the selected caption from the measured preview WidgetCell' \
    grep -Fq 'widget_picker_selected_caption' "$widgets_body"
assert_true 'the widgets capture fails closed when the selected caption is missing or ambiguous' \
    grep -Fq 'exposes no unambiguous widget_name caption' "$widgets_body"
assert_true 'the widgets capture uses the selected widget caption for the new HOME host identity' \
    grep -Fq '"$_cwp_candidate_xml" "$_cwp_ref" "$_cwp_widget_caption"' "$widgets_body"
assert_false 'the widgets capture never uses the provider header for the new HOME host identity' \
    grep -Fq '"$_cwp_candidate_xml" "$_cwp_ref" "$_cwp_provider_title"' "$widgets_body"
assert_false 'the widgets capture never passes the provider header to consent as the widget name' \
    grep -Fq '"$EXPECTED_LABEL" "$_cwp_provider_title"' "$widgets_body"
assert_true 'the widgets capture stores the bind consent XML' \
    grep -Fq 'widgets-bind-consent.xml' "$widgets_body"
assert_true 'the widgets capture stores the bind consent PNG' \
    grep -Fq 'widgets-bind-consent.png' "$widgets_body"
assert_true 'the widgets capture measures the android:id/button1 Create control' \
    grep -Fq 'widget_bind_create_button_bounds' "$widgets_body"
create_bounds_context=$(grep -A2 -F 'widget_bind_create_button_bounds' "$widgets_body" || true)
printf '%s\n' "$create_bounds_context" > "$TMP_DIR/create-bounds-context.txt"
assert_true 'the widgets capture passes the launcher/captured caption to the Create bounds' \
    grep -Fq '"$EXPECTED_LABEL" "$_cwp_widget_caption"' "$TMP_DIR/create-bounds-context.txt"
assert_true 'the widgets capture taps the measured Create control' \
    grep -Fq 'tap_center_of_bounds "$_cwp_bind_create"' "$widgets_body"
assert_true 'the widgets capture refuses a checked Always allow control' \
    grep -Fq 'widget_bind_always_allow_is_checked' "$widgets_body"
assert_true 'the widgets capture proves the new appwidget id is launcher-owned' \
    grep -Fq '"$ARTIFACTS/widgets-appwidget-after.txt" "$PKG"' "$widgets_body"
assert_true 'the widgets capture launches Settings for the survival check' \
    grep -Fq 'android.settings.SETTINGS' "$widgets_body"
assert_true 'the widgets capture waits for the exact Settings foreground' \
    grep -Fq 'wait_for_foreground com.android.settings' "$widgets_body"
assert_true 'the widgets capture captures the Settings launch evidence' \
    grep -Fq 'widgets-settings-launched.xml' "$widgets_body"
assert_true 'the widgets capture captures the provider expansion XML and PNG' \
    grep -Fq 'widgets-provider.xml' "$widgets_body"
assert_true 'the widgets capture captures the exposed Add XML and PNG' \
    grep -Fq 'widgets-add.xml' "$widgets_body"
assert_true 'the widgets capture captures the placed HOME XML and PNG' \
    grep -Fq 'widgets-home-placed.xml' "$widgets_body"
assert_true 'the widgets capture captures HOME after the survival key press' \
    grep -Fq 'widgets-home-after-home.xml' "$widgets_body"
assert_true 'the widgets capture proves a new real workspace AppWidgetHostView' \
    grep -Fq 'home_widget_bounds' "$widgets_body"
assert_true 'the widgets capture proves a new bound app widget provider' \
    grep -Fq 'appwidget_new_providers' "$widgets_body"
assert_true 'the widgets capture validates the widget on the actual placed page geometry' \
    grep -Fq 'placed_widget_page_is_safe' "$widgets_body"
assert_true 'the widgets capture passes the placed page, reference, selected caption and bounds' \
    grep -Fq '"$_cwp_placed" "$_cwp_ref" "$_cwp_widget_caption"' "$widgets_body"
assert_false 'the widgets capture never passes the provider header to the placed-page identity' \
    grep -Fq '"$_cwp_placed" "$_cwp_ref" "$_cwp_provider_title"' "$widgets_body"
assert_false 'the widgets capture never inherits the first-page header band' \
    grep -Fq '_cwp_ref_header_bottom' "$widgets_body"
assert_false 'the widgets capture never inherits the first-page dock band' \
    grep -Fq '_cwp_ref_dock_top' "$widgets_body"
assert_true 'the widgets capture focuses the real picker search input' \
    grep -Fq 'widget_picker_search_bar_bounds' "$widgets_body"
assert_true 'the widgets capture types Clock into the real picker search' \
    grep -Fq 'input text Clock' "$widgets_body"
assert_true 'the widgets capture rejects a preview outside the measured viewport' \
    grep -Fq 'widget_picker_preview_is_visible' "$widgets_body"
assert_true 'the widgets capture scrolls the measured widget list when the preview is clipped' \
    grep -Fq 'widget_picker_scroll_target' "$widgets_body"
assert_true 'the widgets capture fails when the Add button is not exposed' \
    grep -Fq 'the widget Add button was not exposed' "$widgets_body"
assert_false 'the widgets capture has no ordinary swipe drag fallback' \
    grep -Fq 'widget_drop_target' "$widgets_body"
assert_false 'the widgets capture never swipes a preview to a fixed workspace point' \
    grep -Fq 'input swipe "$_cwp_px"' "$widgets_body"
assert_true 'the widgets capture saves the last failed placement stage before cleanup' \
    grep -Fq 'widgets-add-last' "$widgets_body"
assert_false 'the widgets capture never binds a widget or edits the database directly' \
    grep -Eq 'bindAppWidget|addItemToDatabase|LauncherSettings|content://|sqlite' "$widgets_body"
assert_false 'the widgets capture never uses a fixed Add tap coordinate' \
    grep -Eq 'input tap [0-9]+ [0-9]+' "$widgets_body"
assert_true 'the widgets capture identifies the placed host by its selected widget caption' \
    grep -Fq '"$_cwp_ref" "$_cwp_widget_caption"' "$widgets_body"
assert_false 'the widgets capture never identifies the placed host by the provider title' \
    grep -Fq '"$_cwp_ref" "$_cwp_provider_title"' "$widgets_body"
assert_true 'the widgets capture re-proves exact placed bounds by the selected caption' \
    grep -Fq '"$_cwp_search_xml" "$_cwp_ref" "$_cwp_widget_caption"' "$widgets_body"
assert_false 'the widgets capture never re-proves placed bounds by the provider title' \
    grep -Fq '"$_cwp_search_xml" "$_cwp_ref" "$_cwp_provider_title"' "$widgets_body"
assert_false 'the widgets capture never uses bounds-only widget identity' \
    grep -Fq 'home_has_widget_bounds' "$SMOKE"
assert_true 'the widgets capture searches measured HOME pages during initial placement' \
    grep -Fq 'search_home_pages_for_widget \' "$widgets_body"
assert_true 'the widgets capture passes the selected caption to initial page discovery' \
    grep -Fq '"$_cwp_widget_caption" "$_cwp_ref" "$_cwp_last_xml"' "$widgets_body"
assert_false 'the widgets capture never passes the provider title to page discovery' \
    grep -Fq '"$_cwp_provider_title" "$_cwp_ref"' "$widgets_body"
assert_true 'the widgets capture bounds initial page discovery to three advances' \
    grep -Fq '[ "$_shw_page" -lt 3 ]' "$search_pages_body"
assert_true 'the page search requires the launcher to be resumed before a swipe' \
    grep -Fq 'foreground_is_component' "$search_pages_body"
assert_true 'the page search refuses to swipe while any non-launcher activity owns the foreground' \
    grep -Fq '"$PKG" "$LAUNCHER_ACTIVITY"' "$search_pages_body"
assert_true 'the page search proves a real workspace host by the selected widget caption' \
    grep -Fq 'home_widget_bounds "$_shw_xml" "$_shw_ref" "$_shw_label"' \
    "$search_pages_body"
assert_true 'the page search stores XML and PNG evidence per page' \
    grep -Fq '$_shw_prefix-page-$_shw_page.xml' "$search_pages_body"
assert_true 'the page search logs every measured advance' \
    grep -Fq '$_shw_prefix-swipe-$_shw_next.txt' "$search_pages_body"
assert_true 'the widgets capture stores the placement and survival page log' \
    grep -Fq 'widgets-page-log.txt' "$widgets_body"
assert_true 'the widgets capture records the initial placement page' \
    grep -Fq 'placement-page=' "$widgets_body"
assert_true 'the widgets capture records the survival page' \
    grep -Fq 'survival-page=' "$widgets_body"
assert_true 'the widgets capture re-proves the exact placed bounds after page navigation' \
    grep -Fq '_cwp_recheck_bounds' "$widgets_body"
assert_true 'the widgets capture restores the primary HOME through the normal HOME key' \
    grep -Fq 'restore_primary_home widgets-primary' "$widgets_body"
assert_true 'the primary HOME restore keys HOME rather than resetting or moving workspace items' \
    grep -Fq 'KEYCODE_HOME' "$primary_restore_body"
assert_true 'the primary HOME restore polls the real primary-page readiness' \
    grep -Fq 'primary_home_is_ready' "$primary_restore_body"
assert_false 'the primary HOME restore never clears, moves or deletes workspace items' \
    grep -Eq 'pm clear|deleteItem|moveItem|addItemToDatabase|LauncherSettings|content://|sqlite' \
    "$primary_restore_body"
recheck_line=$(grep -n '_cwp_recheck_bounds' "$widgets_body" | sed -n '1s/:.*//p')
restore_line=$(grep -n 'restore_primary_home widgets-primary' "$widgets_body" |
    sed -n '1s/:.*//p')
primary_assert_line=$(grep -n 'verify_nothing_home' "$widgets_body" |
    sed -n '1s/:.*//p')
if [ -n "$recheck_line" ] && [ -n "$restore_line" ] && [ -n "$primary_assert_line" ] &&
    [ "$recheck_line" -lt "$restore_line" ] &&
    [ "$restore_line" -lt "$primary_assert_line" ]; then
    pass 'third-party proof completes before the primary HOME restore, which precedes verify_nothing_home'
else
    fail 'third-party proof completes before the primary HOME restore, which precedes verify_nothing_home'
fi
assert_true 'the device settings check taps each measured pill child bound' \
    grep -Fq 'tap_center_of_bounds "$_eds_bounds"' "$device_settings_body"
assert_true 'the device settings check measures the real device child ids' \
    grep -Fq 'home_widget_device_action_bounds' "$device_settings_body"
assert_true 'the device settings check resolves destinations through the platform' \
    grep -Fq 'resolve_settings_action_component' "$device_settings_body"
assert_true 'the device settings resolver falls back to the top-level Settings action' \
    grep -Fq 'android.settings.SETTINGS' "$resolve_settings_body"
assert_true 'the device settings check requires the platform-resolved component' \
    grep -Fq 'foreground_is_component' "$device_settings_body"
assert_true 'the device settings check captures the resulting activity UI' \
    grep -Fq 'device-settings-$_eds_action.xml' "$device_settings_body"
assert_true 'the device settings check captures the resulting activity PNG' \
    grep -Fq 'device-settings-$_eds_action.png' "$device_settings_body"
assert_true 'the device settings check returns HOME after every shortcut' \
    grep -Fq 'return_home "device-settings-$_eds_action"' "$device_settings_body"
assert_true 'the device settings check re-reads all three own widget ids' \
    grep -Fq '_eds_device_after' "$device_settings_body"
assert_false 'the device settings check never writes a setting' \
    grep -Eq 'settings put|shared_prefs|onChange|prefs\.' "$device_settings_body"
assert_false 'the device settings check never binds a widget directly' \
    grep -Eq 'bindAppWidget|addItemToDatabase|LauncherSettings|content://|sqlite' \
    "$device_settings_body"

placed_line=$(grep -n 'widgets-home-placed.xml' "$widgets_body" | sed -n '1s/:.*//p')
consent_line=$(grep -n 'widgets-bind-consent.xml' "$widgets_body" | sed -n '1s/:.*//p')
settings_line=$(grep -n 'android.settings.SETTINGS' "$widgets_body" | sed -n '1s/:.*//p')
home_key_line=$(grep -n 'return_home widgets-picker' "$widgets_body" | sed -n '1s/:.*//p')
after_home_line=$(grep -n 'widgets-home-after-home.xml' "$widgets_body" | sed -n '1s/:.*//p')
if [ -n "$consent_line" ] && [ -n "$placed_line" ] && [ -n "$settings_line" ] &&
    [ -n "$home_key_line" ] && [ -n "$after_home_line" ] &&
    [ "$consent_line" -lt "$placed_line" ] &&
    [ "$placed_line" -lt "$settings_line" ] &&
    [ "$settings_line" -lt "$home_key_line" ] &&
    [ "$home_key_line" -lt "$after_home_line" ]; then
    pass 'consent is handled before placement, and the placed widget is re-checked after Settings and HOME'
else
    fail 'consent is handled before placement, and the placed widget is re-checked after Settings and HOME'
fi

clean_home_call_line=$(grep -n '^capture_clean_home_theme$' "$SMOKE" | sed -n '1s/:.*//p')
device_settings_call_line=$(grep -n '^exercise_device_settings_shortcuts$' "$SMOKE" | sed -n '1s/:.*//p')
grid_call_line=$(grep -n '^capture_grid_settings$' "$SMOKE" | sed -n '1s/:.*//p')
widgets_call_line=$(grep -n '^capture_widgets_picker$' "$SMOKE" | sed -n '1s/:.*//p')
drawer_call_line=$(grep -n '^exercise_app_drawer$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$clean_home_call_line" ] && [ -n "$device_settings_call_line" ] &&
    [ -n "$grid_call_line" ] && [ -n "$widgets_call_line" ] &&
    [ -n "$drawer_call_line" ] &&
    [ "$clean_home_call_line" -lt "$device_settings_call_line" ] &&
    [ "$device_settings_call_line" -lt "$grid_call_line" ] &&
    [ "$grid_call_line" -lt "$widgets_call_line" ] &&
    [ "$widgets_call_line" -lt "$drawer_call_line" ]; then
    pass 'the clean-home, device-settings, grid and widget captures run before the existing drawer flow'
else
    fail 'the clean-home, device-settings, grid and widget captures run before the existing drawer flow'
fi

assert_true 'the role consent cancel flow is still present' \
    grep -Fq 'verify_default_home_consent' "$SMOKE"
assert_true 'the drawer still uses the bounded 1500 ms swipe' \
    grep -Fq 'swipe_duration=1500' "$SMOKE"
assert_true 'the drawer still has four bounded attempts' \
    grep -Fq 'max_attempts=4' "$SMOKE"
assert_true 'the exact Settings foreground check is still present' \
    grep -Fq 'wait_for_foreground com.android.settings' "$SMOKE"

# --- static regression on the real Play settings theme capture ---------------

settings_theme_body="$TMP_DIR/capture_settings_theme.sh"
sed -n '/^capture_settings_theme() {/,/^}/p' "$SMOKE" > "$settings_theme_body"

settings_theme_pref_body="$TMP_DIR/assert_settings_theme_choice_system.sh"
sed -n '/^assert_settings_theme_choice_system() {/,/^}/p' "$SMOKE" \
    > "$settings_theme_pref_body"

assert_true 'the settings theme capture opens the real PreferenceActivity' \
    grep -Fq -- '-n "$PKG/$PREFERENCES_ACTIVITY"' "$settings_theme_body"
assert_true 'the settings theme capture uses the system night yes/no modes' \
    grep -Fq 'for _cst_mode in yes no; do' "$settings_theme_body"
assert_true 'the settings theme capture switches the emulator night mode' \
    grep -Fq 'cmd uimode night "$_cst_mode"' "$settings_theme_body"
assert_true 'the settings theme capture requires the SYSTEM theme choice' \
    grep -Fq 'assert_settings_theme_choice_system' "$settings_theme_body"
assert_true 'the settings theme preference check reads the real pref file' \
    grep -Fq 'run-as "$PKG" cat' "$settings_theme_pref_body"
assert_true 'the settings theme preference check requires system' \
    grep -Fq '[ "$_ast_value" = system ]' "$settings_theme_pref_body"
assert_true 'the settings theme capture stores dark and light XML evidence' \
    grep -Fq 'settings-theme-$_cst_name.xml' "$settings_theme_body"
assert_true 'the settings theme capture stores dark and light PNG evidence' \
    grep -Fq 'settings-theme-$_cst_name.png' "$settings_theme_body"
assert_true 'the settings theme capture rejects the diagnostic sample' \
    grep -Fq 'rendered the diagnostic sample' "$settings_theme_body"
assert_true 'the settings theme capture restores the previous night mode' \
    grep -Fq 'cmd uimode night "$_cst_night_value"' "$settings_theme_body"
assert_true 'the settings theme capture returns HOME' \
    grep -Fq 'return_home settings-theme' "$settings_theme_body"
assert_false 'the settings theme capture never passes the sample extra' \
    grep -Fq 'THEME_SAMPLE_EXTRA' "$settings_theme_body"
assert_false 'the settings theme capture never writes a preference' \
    grep -Eq 'settings put|putString|putBoolean|editSp' "$settings_theme_body"

# --- theme refresh readiness fixtures ---------------------------------------

theme_refresh_log="$TMP_DIR/theme-refresh.log"
cat > "$theme_refresh_log" <<'EOF'
01-01 00:00:00.000 D/DotWelTheme: theme-refresh night=false resolvedDark=false expected=AppTheme.DarkMainColor source=init activity=app.lawnchair.LawnchairLauncher suppliedNight=n/a appNight=false
01-01 00:00:01.000 D/DotWelTheme: theme-refresh night=false resolvedDark=false expected=AppTheme.DarkMainColor source=config activity=app.lawnchair.LawnchairLauncher suppliedNight=true appNight=true
01-01 00:00:02.000 D/DotWelTheme: theme-refresh night=true resolvedDark=false expected=AppTheme.DarkMainColor source=config-post activity=app.lawnchair.LawnchairLauncher suppliedNight=true appNight=true
01-01 00:00:03.000 D/DotWelTheme: theme-refresh night=true resolvedDark=true expected=AppTheme.Dark source=config activity=app.lawnchair.LawnchairLauncher suppliedNight=true appNight=true
01-01 00:00:04.000 D/DotWelTheme: theme-refresh night=true resolvedDark=true expected=AppTheme.Dark source=config activity=com.android.settings/.Settings suppliedNight=true appNight=true
01-01 00:00:05.000 D/DotWelTheme: theme-refresh night=false resolvedDark=false expected=AppTheme source=config activity=app.lawnchair.LawnchairLauncher suppliedNight=false appNight=false
EOF

theme_dark_line=$(theme_refresh_line \
    "$theme_refresh_log" true true app.lawnchair.LawnchairLauncher) || theme_dark_line=
theme_dark_stamp=$(printf '%s\n' "$theme_dark_line" |
    sed -n 's/^\([^ ]* [^ ]*\).*/\1/p')
assert_eq 'theme readiness selects the launcher dark line' \
    '01-01 00:00:03.000' "$theme_dark_stamp"

theme_light_line=$(theme_refresh_line \
    "$theme_refresh_log" false false app.lawnchair.LawnchairLauncher) || theme_light_line=
theme_light_stamp=$(printf '%s\n' "$theme_light_line" |
    sed -n 's/^\([^ ]* [^ ]*\).*/\1/p')
assert_eq 'theme readiness selects the launcher light line' \
    '01-01 00:00:05.000' "$theme_light_stamp"

theme_stale_dark_line=$(theme_refresh_line \
    "$theme_refresh_log" true false app.lawnchair.LawnchairLauncher) || theme_stale_dark_line=
theme_stale_dark_stamp=$(printf '%s\n' "$theme_stale_dark_line" |
    sed -n 's/^\([^ ]* [^ ]*\).*/\1/p')
assert_eq 'theme readiness does not accept night without resolved dark' \
    '01-01 00:00:02.000' "$theme_stale_dark_stamp"

assert_false 'theme readiness rejects another activity with the same state' \
    theme_refresh_line "$theme_refresh_log" true true com.example.Other
assert_false 'theme readiness rejects a missing trace file' \
    theme_refresh_line "$TMP_DIR/missing-theme-refresh.log" true true \
    app.lawnchair.LawnchairLauncher

theme_no_activity_log="$TMP_DIR/theme-refresh-no-activity.log"
cat > "$theme_no_activity_log" <<'EOF'
01-01 00:00:00.000 D/DotWelTheme: theme-refresh night=true resolvedDark=true expected=AppTheme.Dark source=config suppliedNight=true appNight=true
EOF
assert_false 'theme readiness rejects a trace without the activity field' \
    theme_refresh_line "$theme_no_activity_log" true true app.lawnchair.LawnchairLauncher

# --- static regression on the real Play native popup/drawer captures ---------

native_theme_body="$TMP_DIR/capture_native_surfaces_theme.sh"
sed -n '/^capture_native_surfaces_theme() {/,/^}/p' "$SMOKE" > "$native_theme_body"

native_theme_state_body="$TMP_DIR/wait_for_native_theme_state.sh"
sed -n '/^wait_for_native_theme_state() {/,/^}/p' "$SMOKE" > "$native_theme_state_body"

native_popup_body="$TMP_DIR/capture_native_home_popup.sh"
sed -n '/^capture_native_home_popup() {/,/^}/p' "$SMOKE" > "$native_popup_body"

native_theme_helper_body="$TMP_DIR/theme_refresh_line.sh"
sed -n '/^theme_refresh_line() (/,/^)/p' "$LIB" > "$native_theme_helper_body"

assert_true 'the native surfaces capture uses the system night yes/no modes' \
    grep -Fq 'for _cnst_mode in yes no; do' "$native_theme_body"
assert_true 'the native surfaces capture switches the emulator night mode' \
    grep -Fq 'cmd uimode night "$_cnst_mode"' "$native_theme_body"
assert_true 'the native surfaces capture checks the emulator night result' \
    grep -Fq '_cnst_actual_night' "$native_theme_body"
assert_true 'the native surfaces capture waits for resolved native theme readiness' \
    grep -Fq 'wait_for_native_theme_state' "$native_theme_body"
assert_true 'the native theme readiness reads the debug-only theme trace' \
    grep -Fq 'DotWelTheme:D' "$native_theme_state_body"
assert_true 'the native theme readiness requires expected night and resolved dark state' \
    grep -Fq 'night=$night resolvedDark=$dark' "$native_theme_helper_body"
assert_true 'the native theme readiness filters to the launcher activity' \
    grep -Fq 'activity=$activity ' "$native_theme_helper_body"
assert_true 'the native theme readiness uses the shared filtered helper' \
    grep -Fq 'theme_refresh_line' "$native_theme_state_body"
assert_true 'the native theme readiness checks the actual launcher activity' \
    grep -Fq '"$LAUNCHER_ACTIVITY"' "$native_theme_state_body"
assert_true 'the native theme readiness excludes earlier capture lines' \
    grep -Fq '_wnst_baseline' "$native_theme_state_body"
assert_true 'the native theme readiness retains a failure screenshot' \
    grep -Fq 'native-theme-$_wnst_label-failure.png' "$native_theme_state_body"
assert_true 'the native theme readiness retains the current activities' \
    grep -Fq 'native-theme-$_wnst_label-activities.txt' "$native_theme_state_body"
assert_true 'the native theme readiness retains the current night mode' \
    grep -Fq 'native-theme-$_wnst_label-system-night-now.txt' "$native_theme_state_body"
assert_true 'the native theme readiness reports the expected state on failure' \
    grep -Fq 'expected night=%s resolvedDark=%s activity=%s' "$native_theme_state_body"
assert_true 'the native theme readiness still fails after the bounded poll' \
    grep -Fq 'return 1' "$native_theme_state_body"
assert_true 'the native surfaces capture stores the resolved theme state' \
    grep -Fq 'native-theme-$_cnst_name-system-night.txt' "$native_theme_body"
assert_true 'the native surfaces capture requires the SYSTEM theme choice' \
    grep -Fq 'assert_settings_theme_choice_system' "$native_theme_body"
assert_true 'the native surfaces capture opens the real HOME popup' \
    grep -Fq 'capture_native_home_popup "$_cnst_name"' "$native_theme_body"
assert_true 'the native surfaces capture opens the real app drawer' \
    grep -Fq 'open_app_drawer' "$native_theme_body"
assert_true 'the native surfaces capture stores dark and light popup XML evidence' \
    grep -Fq 'native-popup-$_cnhp_name.xml' "$native_popup_body"
assert_true 'the native surfaces capture stores dark and light popup PNG evidence' \
    grep -Fq 'native-popup-$_cnhp_name.png' "$native_popup_body"
assert_true 'the native surfaces capture stores dark and light drawer XML evidence' \
    grep -Fq 'native-drawer-$_cnst_name.xml' "$native_theme_body"
assert_true 'the native surfaces capture stores dark and light drawer PNG evidence' \
    grep -Fq 'native-drawer-$_cnst_name.png' "$native_theme_body"
assert_true 'the native popup capture uses the real HOME long-press target' \
    grep -Fq 'home_longpress_target' "$native_popup_body"
assert_true 'the native popup capture requires the real popup hierarchy' \
    grep -Fq 'home_popup_is_ready' "$native_popup_body"
assert_true 'the native popup capture uses a real long-press gesture' \
    grep -Fq 'input swipe' "$native_popup_body"
assert_true 'the native popup capture requires the Widgets option' \
    grep -Fq 'Widgets' "$native_popup_body"
assert_true 'the native surfaces capture restores the previous night mode' \
    grep -Fq 'cmd uimode night "$_cnst_night_value"' "$native_theme_body"
assert_true 'the native surfaces capture returns HOME' \
    grep -Fq 'return_home native-surfaces' "$native_theme_body"
assert_false 'the native surfaces capture never passes the sample extra' \
    grep -Fq 'THEME_SAMPLE_EXTRA' "$native_theme_body"
assert_false 'the native surfaces capture never writes a preference' \
    grep -Eq 'settings put|putString|putBoolean|editSp' "$native_theme_body"
assert_false 'the native surfaces capture never starts a popup activity directly' \
    grep -Eq 'am start.*(popup|Popup)' "$native_theme_body"

settings_theme_call_line=$(grep -n '^capture_settings_theme$' "$SMOKE" | sed -n '1s/:.*//p')
native_surfaces_call_line=$(grep -n '^capture_native_surfaces_theme$' "$SMOKE" | sed -n '1s/:.*//p')
sample_call_line=$(grep -n '^capture_theme_sample dark$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$settings_theme_call_line" ] && [ -n "$native_surfaces_call_line" ] &&
    [ -n "$sample_call_line" ] &&
    [ "$settings_theme_call_line" -lt "$native_surfaces_call_line" ] &&
    [ "$native_surfaces_call_line" -lt "$sample_call_line" ]; then
    pass 'the real settings and native surface captures run before the diagnostic sample'
else
    fail 'the real settings and native surface captures run before the diagnostic sample'
fi

# --- drawer bottom boundary fixtures ---------------------------------------

nav_window="$TMP_DIR/nav-window.txt"
cat > "$nav_window" <<'EOF'
  Window #0 Window{abc u0 NavigationBar0}:
    mDisplayId=0
    mFrame=[0,1824][1080,1920]
EOF
assert_eq 'the navigation bar frame is the measured safe-area edge' \
    '0 1824 1080 1920' "$(ui_navigation_bar_bounds "$nav_window")"

nav_display="$TMP_DIR/nav-display.txt"
cat > "$nav_display" <<'EOF'
  mDisplayFrames=DisplayFrames{mCurrent=Rect(0, 0 - 1080, 1920) mStable=Rect(0, 0 - 1080, 1824)}
EOF
assert_eq 'the stable display frame is the navigation fallback' \
    '0 1824 1080 1920' "$(ui_navigation_bar_bounds "$nav_display")"

nav_insets="$TMP_DIR/nav-insets.txt"
cat > "$nav_insets" <<'EOF'
  InsetsSource id=1 type=navigationBars frame=[0,1794][1080,1920] visible=true
    associated with Taskbar
  InsetsSource id=2 type=statusBars frame=[0,0][1080,72] visible=true
EOF
assert_eq 'the modern InsetsSource navigationBars frame is measured' \
    '0 1794 1080 1920' "$(ui_navigation_bar_bounds "$nav_insets")"

nav_insets_hidden="$TMP_DIR/nav-insets-hidden.txt"
cat > "$nav_insets_hidden" <<'EOF'
  InsetsSource id=1 type=navigationBars frame=[0,1794][1080,1920] visible=false
EOF
assert_eq 'an invisible InsetsSource navigationBars frame does not guess' \
    '' "$(ui_navigation_bar_bounds "$nav_insets_hidden")"

nav_insets_rect="$TMP_DIR/nav-insets-rect.txt"
cat > "$nav_insets_rect" <<'EOF'
  InsetsSource type=navigationBars frame=Rect(0, 1794 - 1080, 1920) visible=true
EOF
assert_eq 'modern Rect frame syntax is measured' \
    '0 1794 1080 1920' "$(ui_navigation_bar_bounds "$nav_insets_rect")"

# Current AOSP WallpaperManagerService.dump/dumpWallpaper format: System, Lock
# and Fallback sections, each entry " User <id>: id=<wallpaperId>: mWhich=...".
wallpaper_dump="$TMP_DIR/wallpaper-dump.txt"
cat > "$wallpaper_dump" <<'EOF'
WallpaperManagerService:
mDefaultWallpaperComponent=null
mImageWallpaper=com.android.systemui.wallpapers.ImageWallpaper
System wallpaper state:
 User 0: id=41: mWhich=1: mSystemWasBoth=false: mBindSource=SET_STATIC
 Display state:
  displayId=0
  mWidth=1080
  mHeight=1920
  mPadding=Rect(0, 0 - 0, 0)
  mCropHint=Rect(0, 0 - 0, 0)
  mName=/data/system/users/0/wallpaper
  mAllowBackup=true
  mWallpaperComponent=null
  mWallpaperDimAmount=0.0
  isColorExtracted=false
  mUidToDimAmount:
Lock wallpaper state:
 User 0: id=12: mWhich=2: mSystemWasBoth=false: mBindSource=SET_STATIC
 Display state:
  displayId=0
Fallback wallpaper state:
 User 0: id=1: mWhich=1: mSystemWasBoth=false: mBindSource=INITIALIZE_FALLBACK
EOF
assert_eq 'current-format separate Home and lock IDs are measured' \
    '41 12' "$(wallpaper_ids_from_dump "$wallpaper_dump")"
assert_eq 'the current user may be supplied explicitly' \
    '41 12' "$(wallpaper_ids_from_dump "$wallpaper_dump" 0)"

wallpaper_dump_shared="$TMP_DIR/wallpaper-dump-shared.txt"
cat > "$wallpaper_dump_shared" <<'EOF'
System wallpaper state:
 User 0: id=41: mWhich=1: mSystemWasBoth=false: mBindSource=SET_STATIC
Lock wallpaper state:
Fallback wallpaper state:
 User 0: id=1: mWhich=1: mSystemWasBoth=false: mBindSource=INITIALIZE_FALLBACK
EOF
assert_eq 'an empty Lock section reports a shared lock, never the fallback' \
    '41 -' "$(wallpaper_ids_from_dump "$wallpaper_dump_shared")"

wallpaper_dump_users="$TMP_DIR/wallpaper-dump-users.txt"
cat > "$wallpaper_dump_users" <<'EOF'
System wallpaper state:
 User 0: id=41: mWhich=1: mSystemWasBoth=false: mBindSource=SET_STATIC
 User 10: id=99: mWhich=1: mSystemWasBoth=false: mBindSource=SET_STATIC
Lock wallpaper state:
 User 0: id=12: mWhich=2: mSystemWasBoth=false: mBindSource=SET_STATIC
 User 10: id=88: mWhich=2: mSystemWasBoth=false: mBindSource=SET_STATIC
Fallback wallpaper state:
 User 0: id=1: mWhich=1: mSystemWasBoth=false: mBindSource=INITIALIZE_FALLBACK
EOF
assert_eq 'the current user row is selected among multiple users' \
    '41 12' "$(wallpaper_ids_from_dump "$wallpaper_dump_users" 0)"
assert_eq 'another explicitly requested user is selected' \
    '99 88' "$(wallpaper_ids_from_dump "$wallpaper_dump_users" 10)"
assert_eq 'multiple users without a current user is ambiguous' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_users")"
assert_eq 'a missing requested user fails closed' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_users" 7)"

wallpaper_dump_fallback="$TMP_DIR/wallpaper-dump-fallback.txt"
cat > "$wallpaper_dump_fallback" <<'EOF'
System wallpaper state:
Lock wallpaper state:
Fallback wallpaper state:
 User 0: id=7: mWhich=1: mSystemWasBoth=false: mBindSource=INITIALIZE_FALLBACK
EOF
assert_eq 'a fallback-only dump is not a Home wallpaper' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_fallback" 0)"

wallpaper_dump_missing="$TMP_DIR/wallpaper-dump-missing.txt"
cat > "$wallpaper_dump_missing" <<'EOF'
WallpaperManagerService:
mDefaultWallpaperComponent=null
Lock wallpaper state:
 User 0: id=12: mWhich=2: mSystemWasBoth=false: mBindSource=SET_STATIC
EOF
assert_eq 'a missing System section fails closed even with a lock row' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_missing" 0)"

wallpaper_dump_empty_system="$TMP_DIR/wallpaper-dump-empty-system.txt"
cat > "$wallpaper_dump_empty_system" <<'EOF'
System wallpaper state:
Lock wallpaper state:
 User 0: id=12: mWhich=2: mSystemWasBoth=false: mBindSource=SET_STATIC
EOF
assert_eq 'a System section without a current-user row fails closed' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_empty_system" 0)"

wallpaper_dump_legacy="$TMP_DIR/wallpaper-dump-legacy.txt"
cat > "$wallpaper_dump_legacy" <<'EOF'
  mCurrentUserId=0
  mWallpaperId: 41
  mLockWallpaperId: 40
EOF
assert_eq 'the compatible legacy Home and lock fields are still measured' \
    '41 40' "$(wallpaper_ids_from_dump "$wallpaper_dump_legacy")"

wallpaper_dump_home_only="$TMP_DIR/wallpaper-dump-home-only.txt"
cat > "$wallpaper_dump_home_only" <<'EOF'
  Home wallpaper ID: 41
EOF
assert_eq 'a Home-only legacy dump reports no invented lock ID' \
    '41 -' "$(wallpaper_ids_from_dump "$wallpaper_dump_home_only")"

wallpaper_dump_none="$TMP_DIR/wallpaper-dump-none.txt"
printf 'no wallpaper ids here\n' > "$wallpaper_dump_none"
assert_eq 'an unmeasurable wallpaper dump prints nothing' \
    '' "$(wallpaper_ids_from_dump "$wallpaper_dump_none")"

assert_true 'an unchanged lock ID is preserved' \
    wallpaper_lock_preserved 41 40 40
assert_false 'a moved lock ID is rejected' \
    wallpaper_lock_preserved 41 40 39
assert_true 'a shared lock materialises as the prior Home ID' \
    wallpaper_lock_preserved 41 - 41
assert_false 'a still-absent lock after a changed Home is not preservation' \
    wallpaper_lock_preserved 41 - -
assert_false 'a shared lock may not take the new Home ID' \
    wallpaper_lock_preserved 41 - 42

wallpaper_dump_component="$TMP_DIR/wallpaper-dump-component.txt"
cat > "$wallpaper_dump_component" <<'EOF'
System wallpaper state:
 User 0: id=41: mWhich=1: mSystemWasBoth=false
   mWallpaperComponent=ComponentInfo{com.launchernos.dotwellabs.debug/app.nothingui.wallpaper.DotFieldWallpaperService}
Lock wallpaper state:
 User 0: id=12: mWhich=2: mSystemWasBoth=false
   mWallpaperComponent=ComponentInfo{com.example.other/.LockWallpaperService}
EOF
assert_eq 'the active System wallpaper component is normalized' \
    'com.launchernos.dotwellabs.debug/app.nothingui.wallpaper.DotFieldWallpaperService' \
    "$(wallpaper_component_from_dump "$wallpaper_dump_component")"
assert_eq 'a null System component is equivalent absence' \
    '' "$(wallpaper_component_from_dump "$wallpaper_dump")"
wallpaper_dump_component_lockonly="$TMP_DIR/wallpaper-dump-component-lockonly.txt"
cat > "$wallpaper_dump_component_lockonly" <<'EOF'
System wallpaper state:
 User 0: id=41: mWhich=1
Lock wallpaper state:
 User 0: id=12: mWhich=2
   mWallpaperComponent=ComponentInfo{com.example.other/.LockWallpaperService}
EOF
assert_eq 'a component only in the Lock section is not the active wallpaper' \
    '' "$(wallpaper_component_from_dump "$wallpaper_dump_component_lockonly")"
assert_eq 'an unmeasurable component dump prints nothing' \
    '' "$(wallpaper_component_from_dump "$wallpaper_dump_none")"

# The wallpaper preview must reveal the below-the-fold credit, licence and
# controls through the measured settings scroll before asserting them. The
# initial unscrolled XML is not evidence for offscreen content.
wallpaper_body="$TMP_DIR/capture_wallpaper_gallery.sh"
sed -n '/^capture_wallpaper_gallery() {/,/^}/p' "$SMOKE" > "$wallpaper_body"
assert_true 'the wallpaper preview reads the revealed CC BY 4.0 attribution XML' \
    grep -Fq "'CC BY 4.0' \"\$_cwg_credit_xml\"" "$wallpaper_body"
assert_true 'the wallpaper preview reads the revealed CC BY 4.0 licence URL XML' \
    grep -Fq "'https://creativecommons.org/licenses/by/4.0/' \"\$_cwg_license_xml\"" \
    "$wallpaper_body"
attribution_line=$(grep -n 'Copyright (c) 2024 Tecdrop. CC BY 4.0.' "$wallpaper_body" |
    sed -n '1s/:.*//p')
credit_assert_line=$(grep -n "'CC BY 4.0' \"\$_cwg_credit_xml\"" "$wallpaper_body" |
    sed -n '1s/:.*//p')
license_line=$(grep -n 'License: https://creativecommons.org/licenses/by/4.0/' \
    "$wallpaper_body" | sed -n '1s/:.*//p')
license_url_line=$(grep -n "'https://creativecommons.org/licenses/by/4.0/' \"\$_cwg_license_xml\"" \
    "$wallpaper_body" | sed -n '1s/:.*//p')
apply_line=$(grep -n "_cwg_measure_control 'Apply to Home screen'" "$wallpaper_body" |
    sed -n '1s/:.*//p')
cancel_line=$(grep -n "_cwg_measure_control 'Cancel preview'" "$wallpaper_body" |
    sed -n '1s/:.*//p')
if [ -n "$attribution_line" ] && [ -n "$credit_assert_line" ] &&
    [ -n "$license_line" ] && [ -n "$license_url_line" ] &&
    [ -n "$apply_line" ] && [ -n "$cancel_line" ] &&
    [ "$attribution_line" -lt "$credit_assert_line" ] &&
    [ "$license_line" -lt "$license_url_line" ] &&
    [ "$apply_line" -lt "$cancel_line" ]; then
    pass 'the wallpaper preview reveals attribution/licence/Apply before asserting them'
else
    fail 'the wallpaper preview reveals attribution/licence/Apply before asserting them'
fi

# Settings scroll fixtures: the real scrollable container and safe viewport are
# measured, a clipped control is not tappable evidence, and the scroll gesture
# stays inside the measured band.
settings_scroll_xml="$TMP_DIR/settings-scroll.xml"
cat > "$settings_scroll_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" scrollable="false" bounds="[0,0][1080,1920]">
    <node index="0" class="android.view.View" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" text="Apply to Home screen" class="android.widget.Button" clickable="true" bounds="[40,1700][1040,1780]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the settings scroll container is measured from the scrollable node' \
    '0 72 1080 1794' "$(ui_scroll_container_bounds "$settings_scroll_xml" 1794)"
assert_eq 'the settings scroll container is clipped to the navigation top' \
    '0 72 1080 1700' "$(ui_scroll_container_bounds "$settings_scroll_xml" 1700)"
assert_eq 'a control fully inside the viewport is tappable evidence' \
    '40 1700 1040 1780' \
    "$(ui_clickable_label_within "$settings_scroll_xml" 'Apply to Home screen' '0 72 1080 1794')"
assert_eq 'a control clipped by the viewport is not tappable evidence' \
    '' \
    "$(ui_clickable_label_within "$settings_scroll_xml" 'Apply to Home screen' '0 72 1080 1750')"
assert_eq 'the settings scroll gesture stays inside the measured band' \
    '540 1450 416' "$(settings_scroll_target "$settings_scroll_xml" 1794)"
assert_eq 'the upward settings scroll gesture stays inside the measured band' \
    '540 416 1450' "$(settings_scroll_target_up "$settings_scroll_xml" 1794)"

settings_no_scroll="$TMP_DIR/settings-no-scroll.xml"
cat > "$settings_no_scroll" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" scrollable="false" bounds="[0,0][1080,1920]" />
</hierarchy>
EOF
assert_eq 'a settings screen without a scrollable node has no scroll target' \
    '' "$(settings_scroll_target "$settings_no_scroll" 1794)"

# At the end of the content UiAutomator reports the real scrolling surface as
# `android.widget.ScrollView scrollable="false"`. That exact known class in the
# app package is the only fallback viewport; the strict scrollable reading still
# wins first and every other node is ignored.
scroll_pkg=com.launchernos.dotwellabs.debug
settings_scroll_limit="$TMP_DIR/settings-scroll-limit.xml"
cat > "$settings_scroll_limit" <<EOF
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="$scroll_pkg" scrollable="false" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="$scroll_pkg" scrollable="false" bounds="[0,0][1080,1920]">
      <node index="0" class="android.widget.FrameLayout" package="$scroll_pkg" clickable="true" bounds="[84,1447][572,1573]">
        <node index="0" text="Preview live wallpaper" class="android.widget.TextView" package="$scroll_pkg" clickable="false" bounds="[84,1447][572,1573]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'an at-limit ScrollView is not a strict scrollable target' \
    '' "$(ui_scroll_container_bounds "$settings_scroll_limit" 1794)"
assert_eq 'the known at-limit ScrollView is measured in the app package' \
    '0 0 1080 1794' "$(ui_known_scroll_container_bounds "$settings_scroll_limit" 1794 "$scroll_pkg")"
assert_eq 'the known at-limit ScrollView is clipped to the navigation top' \
    '0 0 1080 1700' "$(ui_known_scroll_container_bounds "$settings_scroll_limit" 1700 "$scroll_pkg")"
assert_eq 'the known at-limit ScrollView is measured without a navigation top' \
    '0 0 1080 1920' "$(ui_known_scroll_container_bounds "$settings_scroll_limit" '' "$scroll_pkg")"
assert_eq 'a fully contained clickable ancestor is measured after scrolling' \
    '84 1447 572 1573' \
    "$(ui_clickable_label_within "$settings_scroll_limit" 'Preview live wallpaper' \
        "$(ui_known_scroll_container_bounds "$settings_scroll_limit" 1794 "$scroll_pkg")")"
assert_eq 'the known-container fallback requires an expected package' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit" 1794)"

settings_scroll_limit_crossed="$TMP_DIR/settings-scroll-limit-crossed.xml"
sed 's/\[84,1447\]\[572,1573\]/[84,1678][572,1804]/g' \
    "$settings_scroll_limit" > "$settings_scroll_limit_crossed"
assert_eq 'the initial control crossing the navigation top is not tappable evidence' \
    '' \
    "$(ui_clickable_label_within "$settings_scroll_limit_crossed" 'Preview live wallpaper' \
        "$(ui_known_scroll_container_bounds "$settings_scroll_limit_crossed" 1794 "$scroll_pkg")")"

settings_scroll_limit_root="$TMP_DIR/settings-scroll-limit-root.xml"
cat > "$settings_scroll_limit_root" <<EOF
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="$scroll_pkg" scrollable="false" bounds="[0,0][1080,1920]" />
</hierarchy>
EOF
assert_eq 'a root-only non-scrollable node is not a viewport' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit_root" 1794 "$scroll_pkg")"

settings_scroll_limit_view="$TMP_DIR/settings-scroll-limit-view.xml"
cat > "$settings_scroll_limit_view" <<EOF
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.view.View" package="$scroll_pkg" scrollable="false" bounds="[0,0][1080,1920]" />
</hierarchy>
EOF
assert_eq 'an arbitrary non-scrollable view is not a viewport' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit_view" 1794 "$scroll_pkg")"

settings_scroll_limit_no_bounds="$TMP_DIR/settings-scroll-limit-no-bounds.xml"
cat > "$settings_scroll_limit_no_bounds" <<EOF
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.ScrollView" package="$scroll_pkg" scrollable="false" />
</hierarchy>
EOF
assert_eq 'a known ScrollView without measured bounds is not a viewport' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit_no_bounds" 1794 "$scroll_pkg")"

settings_scroll_limit_zero="$TMP_DIR/settings-scroll-limit-zero.xml"
sed 's/\[0,0\]\[1080,1920\]/[0,0][0,0]/g' \
    "$settings_scroll_limit" > "$settings_scroll_limit_zero"
assert_eq 'a known ScrollView with zero bounds is not a viewport' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit_zero" 1794 "$scroll_pkg")"

settings_scroll_limit_wrong_pkg="$TMP_DIR/settings-scroll-limit-wrong-pkg.xml"
sed "s/package=\"$scroll_pkg\"/package=\"com.example.other\"/g" \
    "$settings_scroll_limit" > "$settings_scroll_limit_wrong_pkg"
assert_eq 'a known ScrollView in a wrong package is not a viewport' \
    '' "$(ui_known_scroll_container_bounds "$settings_scroll_limit_wrong_pkg" 1794 "$scroll_pkg")"

known_scroll_body="$TMP_DIR/ui_known_scroll_container_bounds.sh"
sed -n '/^ui_known_scroll_container_bounds() (/,/^)/p' "$LIB" > "$known_scroll_body"
assert_true 'the known-container fallback only accepts the real ScrollView class' \
    grep -Fq 'attr($0, "class") != "android.widget.ScrollView"' "$known_scroll_body"
assert_true 'the known-container fallback is scoped to the app package' \
    grep -Fq 'attr($0, "package") != want_pkg' "$known_scroll_body"
assert_true 'the known-container fallback requires non-scrollable at-limit state' \
    grep -Fq 'attr($0, "scrollable") != "false"' "$known_scroll_body"
assert_true 'the known-container fallback rejects zero or negative bounds' \
    grep -Fq 'if (w <= 0 || h <= 0) return -1' "$known_scroll_body"

measure_body="$TMP_DIR/_cwg_measure_control.sh"
sed -n '/^_cwg_measure_control() {/,/^}/p' "$SMOKE" > "$measure_body"
strict_viewport_line=$(grep -n 'ui_scroll_container_bounds "\$_cmc_xml" "\$_cwg_nav_top"' \
    "$measure_body" | sed -n '1s/:.*//p')
fallback_viewport_line=$(grep -n 'ui_known_scroll_container_bounds' \
    "$measure_body" | sed -n '1s/:.*//p')
if [ -n "$strict_viewport_line" ] && [ -n "$fallback_viewport_line" ] &&
    [ "$strict_viewport_line" -lt "$fallback_viewport_line" ] &&
    grep -Fq '"$PKG"' "$measure_body"; then
    pass 'the measured helper tries the strict scrollable viewport before the known fallback'
else
    fail 'the measured helper tries the strict scrollable viewport before the known fallback'
fi

nav_none="$TMP_DIR/nav-none.txt"
printf 'no window data here\n' > "$nav_none"
assert_eq 'an unmeasurable navigation bar prints nothing' \
    '' "$(ui_navigation_bar_bounds "$nav_none")"

drawer_xml="$TMP_DIR/drawer-bottom.xml"
cat > "$drawer_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" clickable="false" bounds="[0,0][1080,1920]">
    <node index="1" text="Search" resource-id="com.launchernos.dotwellabs.debug:id/search_container_all_apps" class="android.widget.EditText" clickable="true" bounds="[0,1850][1080,1920]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/apps_list_view" class="androidx.recyclerview.widget.RecyclerView" clickable="false" bounds="[0,300][1080,1920]">
      <node index="0" text="Alpha" class="android.widget.TextView" clickable="true" bounds="[40,1600][300,1700]" />
      <node index="1" text="Zulu" class="android.widget.TextView" clickable="true" bounds="[40,1720][300,1830]" />
      <node index="2" text="Z" class="android.widget.TextView" clickable="false" bounds="[40,1800][100,1860]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the drawer list bounds are measured from the real list id' \
    '0 300 1080 1920' "$(drawer_list_bounds "$drawer_xml")"
assert_eq 'the final row ignores the sibling search bar and non-clickable headers' \
    '40 1720 300 1830' "$(drawer_last_row_bounds "$drawer_xml" '0 300 1080 1920')"
assert_eq 'the scroll signature is stable for the same hierarchy' \
    "$(drawer_scroll_signature "$drawer_xml" '0 300 1080 1920')" \
    "$(drawer_scroll_signature "$drawer_xml" '0 300 1080 1920')"
drawer_moved="$TMP_DIR/drawer-moved.xml"
sed 's/\[40,1600\]\[300,1700\]/[40,1500][300,1600]/' "$drawer_xml" > "$drawer_moved"
assert_false 'the scroll signature changes when a row moves' \
    test "$(drawer_scroll_signature "$drawer_xml" '0 300 1080 1920')" = \
    "$(drawer_scroll_signature "$drawer_moved" '0 300 1080 1920')"

assert_eq 'the scroll gesture stays above the navigation bar' \
    '540 1634 540 490' "$(drawer_scroll_swipe_target '0 300 1080 1920' 1824)"
assert_eq 'a degenerate list has no safe scroll gesture' \
    '' "$(drawer_scroll_swipe_target '0 500 1080 400' 1824)"

# Source wiring: the Play-gated bottom clip lives in the drawer recycler, keeps
# clipToPadding=false for top overflow, and reuses the existing home gate.
RECYCLER="$ROOT_DIR/src/com/android/launcher3/allapps/AllAppsRecyclerView.java"
CLIP="$ROOT_DIR/lawnchair/src/app/nothingui/drawer/AllAppsBottomClip.kt"
RV_LAYOUT="$ROOT_DIR/res/layout/all_apps_rv_layout.xml"
assert_true 'the drawer recycler clips children to the reserved bottom' \
    grep -Fq 'AllAppsBottomClip.INSTANCE.clipBottom' "$RECYCLER"
assert_true 'the drawer bottom clip reuses the Play home gate' \
    grep -Fq 'NothingUiFeature.INSTANCE.getHomeEnabled()' "$RECYCLER"
assert_true 'the drawer bottom clip saves and restores the canvas' \
    grep -Fq 'canvas.restoreToCount(saveCount)' "$RECYCLER"
assert_true 'the drawer bottom clip is the pure geometry helper' \
    grep -Fq 'fun clipBottom(enabled: Boolean, height: Int, paddingBottom: Int): Int' "$CLIP"
assert_true 'the drawer layout still allows top padding overflow' \
    grep -Fq 'android:clipToPadding="false"' "$RV_LAYOUT"
assert_false 'the drawer layout does not globally enable clipToPadding' \
    grep -Fq 'android:clipToPadding="true"' "$RV_LAYOUT"

# Live-wallpaper preview readiness: only a real platform picker with a measured
# action control is accepted; the settings gallery, HOME, empty and unknown
# captures fail closed.
live_preview_ok="$TMP_DIR/live-preview-ok.xml"
cat > "$live_preview_ok" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" package="com.android.wallpaper" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="1" text="Set wallpaper" class="android.widget.Button" clickable="true" bounds="[100,1700][980,1800]" />
    <node index="2" text="Cancel" class="android.widget.Button" clickable="true" bounds="[40,1820][300,1900]" />
  </node>
</hierarchy>
EOF
assert_true 'a platform live-wallpaper preview is accepted' \
    live_wallpaper_preview_is_ready "$live_preview_ok"

live_preview_google="$TMP_DIR/live-preview-google.xml"
sed 's/com.android.wallpaper/com.google.android.apps.wallpaper/; s/Set wallpaper/Set on Home screen/' \
    "$live_preview_ok" > "$live_preview_google"
assert_true 'the Google wallpaper picker preview is accepted' \
    live_wallpaper_preview_is_ready "$live_preview_google"

live_preview_gallery="$TMP_DIR/live-preview-gallery.xml"
cat > "$live_preview_gallery" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="" package="com.launchernos.dotwellabs.debug" class="android.widget.FrameLayout" bounds="[0,0][1080,1920]">
    <node index="1" text="Preview live wallpaper" class="android.widget.Button" clickable="true" bounds="[40,1400][1040,1500]" />
  </node>
</hierarchy>
EOF
assert_false 'the settings gallery is not a system preview' \
    live_wallpaper_preview_is_ready "$live_preview_gallery"

live_preview_unknown="$TMP_DIR/live-preview-unknown.xml"
sed 's/com.android.wallpaper/com.example.unknown/' "$live_preview_ok" \
    > "$live_preview_unknown"
assert_false 'an unknown package fails closed' \
    live_wallpaper_preview_is_ready "$live_preview_unknown"

live_preview_no_control="$TMP_DIR/live-preview-no-control.xml"
sed '/text="Set wallpaper"/d; /text="Cancel"/d' "$live_preview_ok" \
    > "$live_preview_no_control"
assert_false 'a preview without a measured action fails closed' \
    live_wallpaper_preview_is_ready "$live_preview_no_control"
assert_false 'an empty capture is not a preview' \
    live_wallpaper_preview_is_ready "$TMP_DIR/live-preview-missing.xml"

# Transition-only log evidence: only a fresh visibility=true line for this
# engine proves it became visible. Surface creation alone, hidden-only, empty
# and unrelated logs fail closed.
live_log_visible="$TMP_DIR/live-log-visible.txt"
printf 'D/DotFieldWallpaper( 123): visibility=true\n' > "$live_log_visible"
assert_true 'a visibility transition proves the engine became visible' \
    live_wallpaper_became_visible "$live_log_visible"
live_log_surface="$TMP_DIR/live-log-surface.txt"
printf 'D/DotFieldWallpaper( 123): surface=created 1080x2400\n' > "$live_log_surface"
assert_false 'surface creation alone is not a visible engine' \
    live_wallpaper_became_visible "$live_log_surface"
live_log_hidden="$TMP_DIR/live-log-hidden.txt"
printf 'D/DotFieldWallpaper( 123): visibility=false\n' > "$live_log_hidden"
assert_false 'a hidden-only log is not a visible engine' \
    live_wallpaper_became_visible "$live_log_hidden"
assert_false 'an empty log fails closed' \
    live_wallpaper_became_visible "$TMP_DIR/live-log-missing.txt"
live_log_unrelated="$TMP_DIR/live-log-unrelated.txt"
printf 'D/Other( 123): visibility=true\n' > "$live_log_unrelated"
assert_false 'an unrelated log fails closed' \
    live_wallpaper_became_visible "$live_log_unrelated"

# Preview-only boundary: the pre-preview baseline is captured read-only and the
# fresh evidence is only the appended tail. A stale visibility line in the
# baseline, a missing baseline and a rotated buffer all fail closed.
live_log_baseline="$TMP_DIR/live-log-baseline.txt"
cat > "$live_log_baseline" <<'EOF'
D/DotFieldWallpaper( 123): visibility=true posted=1 drawn=0 pending=false drawing=false
I/ActivityManager( 500): stale shared buffer line
EOF
live_log_full="$TMP_DIR/live-log-full.txt"
cp "$live_log_baseline" "$live_log_full"
printf 'D/DotFieldWallpaper( 123): visibility=true posted=2 drawn=1 pending=true drawing=false\n' \
    >> "$live_log_full"
live_log_preview="$TMP_DIR/live-log-preview.txt"
assert_true 'the baseline boundary isolates only the appended tail' \
    live_wallpaper_preview_log_after "$live_log_baseline" "$live_log_full" "$live_log_preview"
assert_false 'the stale pre-preview visibility line is not in the fresh slice' \
    grep -Fq 'drawn=0' "$live_log_preview"
assert_true 'the fresh appended visibility line is accepted' \
    live_wallpaper_became_visible "$live_log_preview"

live_log_stale_full="$TMP_DIR/live-log-stale-full.txt"
cp "$live_log_baseline" "$live_log_stale_full"
printf 'I/ActivityManager( 500): no new engine transition yet\n' >> "$live_log_stale_full"
live_log_stale_preview="$TMP_DIR/live-log-stale-preview.txt"
assert_true 'the boundary still isolates the appended tail without a transition' \
    live_wallpaper_preview_log_after "$live_log_baseline" "$live_log_stale_full" \
    "$live_log_stale_preview"
assert_false 'a stale pre-preview visibility line cannot prove a fresh preview' \
    live_wallpaper_became_visible "$live_log_stale_preview"

live_log_rotated="$TMP_DIR/live-log-rotated.txt"
sed '1d' "$live_log_full" > "$live_log_rotated"
assert_false 'a rotated buffer without an exact prefix boundary fails closed' \
    live_wallpaper_preview_log_after "$live_log_baseline" "$live_log_rotated" \
    "$TMP_DIR/live-log-rotated-preview.txt"
assert_false 'a missing baseline fails closed' \
    live_wallpaper_preview_log_after "$TMP_DIR/live-log-no-baseline.txt" "$live_log_full" \
    "$TMP_DIR/live-log-no-baseline-preview.txt"

# Source wiring: measure the action, open the platform preview, retain pixels
# and transition logs, then require Back to leave the IDs unchanged.
live_body="$TMP_DIR/live_wallpaper_preview.sh"
sed -n '/^_cwg_preview_live_wallpaper() {/,/^}/p' "$SMOKE" > "$live_body"
assert_true 'the live preview action is measured before tapping' \
    grep -Fq "_cwg_measure_control 'Preview live wallpaper'" "$live_body"
assert_true 'the system preview readiness is checked' \
    grep -Fq 'live_wallpaper_preview_is_ready' "$live_body"
assert_true 'the live preview pixels are retained' \
    grep -Fq 'live-wallpaper-preview.png' "$live_body"
assert_true 'the engine transition log is required' \
    grep -Fq 'live_wallpaper_became_visible' "$live_body"
assert_false 'the preview phase never clears the shared logcat buffer' \
    grep -Fq 'logcat -c' "$live_body"
assert_true 'the preview keeps a read-only pre-tap logcat baseline' \
    grep -Fq 'live-wallpaper-logcat-before.txt' "$live_body"
assert_true 'the preview evidence is sliced after the baseline boundary' \
    grep -Fq 'live_wallpaper_preview_log_after' "$live_body"
assert_true 'visibility is proven from the fresh preview-only slice' \
    grep -Fq 'live-wallpaper-logcat-preview.txt' "$live_body"
assert_true 'Cancel/Back must leave the wallpaper IDs unchanged' \
    grep -Fq '_cpl_ids_after' "$live_body"
assert_true 'the live preview is exercised by the gallery capture' \
    grep -Fq '_cwg_preview_live_wallpaper' "$SMOKE"

# --- live-wallpaper apply/destination/pause-resume safety fixtures ----------
#
# Per-engine transition correlation: the engine stamps a stable identity token
# and the smoke derives only the freshly appended tail for each phase.

live_engine_log="$TMP_DIR/live-engine.log"
cat > "$live_engine_log" <<'EOF'
D/DotFieldWallpaper( 123): visibility=true engine=7 posted=1 drawn=0 pending=false drawing=false
I/Other( 500): unrelated line
D/DotFieldWallpaper( 123): visibility=false engine=7 posted=5 drawn=4 pending=false drawing=false
D/DotFieldWallpaper( 123): visibility=true engine=7 posted=6 drawn=4 pending=false drawing=false
D/DotFieldWallpaper( 123): visibility=false engine=7 posted=20 drawn=18 pending=false drawing=false
EOF
assert_eq 'the per-engine visibility parser reads the drawn counter' \
    '4' "$(live_wallpaper_visible_drawn "$live_engine_log" 7)"
assert_eq 'the hidden parser reads the quiescent hide drawn counter' \
    '18' "$(live_wallpaper_hidden_drawn "$live_engine_log" 7)"
assert_true 'a single applied engine is correlated' \
    live_wallpaper_single_engine "$live_engine_log"
live_resume_ok="$TMP_DIR/resume-ok.log"
printf 'D/DotFieldWallpaper( 123): visibility=true engine=7 posted=6 drawn=4 pending=false drawing=false\n' \
    > "$live_resume_ok"
assert_true 'a clean resume slice matches the hidden drawn count' \
    live_wallpaper_resume_unchanged "$live_resume_ok" 7 4
assert_false 'a resume with a different drawn count is rejected' \
    live_wallpaper_resume_unchanged "$live_engine_log" 7 99
assert_true 'the second hide proves resumed frames increased the drawn count' \
    live_wallpaper_hidden_frame_increase "$live_engine_log" 7 4

live_no_resume="$TMP_DIR/live-no-resume.log"
printf 'D/DotFieldWallpaper( 123): visibility=false engine=7 posted=5 drawn=4 pending=false drawing=false\n' \
    > "$live_no_resume"
assert_false 'a hidden-only slice never proves a resume' \
    live_wallpaper_resume_unchanged "$live_no_resume" 7 4

live_mixed="$TMP_DIR/live-mixed.log"
cat > "$live_mixed" <<'EOF'
D/DotFieldWallpaper( 123): visibility=false engine=7 posted=5 drawn=4 pending=false drawing=false
D/DotFieldWallpaper( 123): visibility=false engine=8 posted=2 drawn=1 pending=false drawing=false
EOF
assert_false 'a mixed preview/applied engine slice fails closed' \
    live_wallpaper_single_engine "$live_mixed"
assert_false 'a mixed engine slice cannot supply a unique hidden engine' \
    live_wallpaper_hidden_engine "$live_mixed"

live_busy_hide="$TMP_DIR/live-busy-hide.log"
printf 'D/DotFieldWallpaper( 123): visibility=false engine=7 posted=5 drawn=4 pending=true drawing=true\n' \
    > "$live_busy_hide"
assert_false 'a hidden transition with pending/drawing true is not quiescent' \
    live_wallpaper_hidden_drawn "$live_busy_hide" 7
assert_false 'a pending/drawing hide cannot prove a later frame increase' \
    live_wallpaper_hidden_frame_increase "$live_busy_hide" 7 0

live_equal_hide="$TMP_DIR/live-equal-hide.log"
printf 'D/DotFieldWallpaper( 123): visibility=false engine=7 posted=20 drawn=4 pending=false drawing=false\n' \
    > "$live_equal_hide"
assert_false 'a second hide with no new drawn frame is rejected' \
    live_wallpaper_hidden_frame_increase "$live_equal_hide" 7 4

# Stale visible evidence: a pre-baseline visible line must not satisfy a phase.
live_stale_baseline="$TMP_DIR/live-stale-baseline.log"
printf 'D/DotFieldWallpaper( 123): visibility=true engine=7 posted=6 drawn=4 pending=false drawing=false\n' \
    > "$live_stale_baseline"
live_stale_full="$TMP_DIR/live-stale-full.log"
cp "$live_stale_baseline" "$live_stale_full"
printf 'I/ActivityManager( 500): no fresh resume yet\n' >> "$live_stale_full"
live_stale_slice="$TMP_DIR/live-stale-slice.log"
assert_true 'the phase boundary isolates the appended tail' \
    live_wallpaper_preview_log_after "$live_stale_baseline" "$live_stale_full" "$live_stale_slice"
assert_false 'a stale pre-baseline visible transition cannot prove a resume' \
    live_wallpaper_resume_unchanged "$live_stale_slice" 7 4

# Exact Dot Field title and package readiness.
live_dotfield_ok="$TMP_DIR/live-dotfield-ok.xml"
cat > "$live_dotfield_ok" <<'EOF'
<hierarchy>
  <node text="Dot Field (Live)" package="com.android.wallpaper.livepicker" class="android.widget.TextView" bounds="[100,100][900,200]" />
  <node text="Set wallpaper" package="com.android.wallpaper.livepicker" class="android.widget.Button" clickable="true" bounds="[386,1638][693,1773]" />
</hierarchy>
EOF
assert_true 'the exact Dot Field (Live) livepicker preview is accepted' \
    live_wallpaper_preview_is_dotfield "$live_dotfield_ok"
live_dotfield_notitle="$TMP_DIR/live-dotfield-notitle.xml"
sed 's/Dot Field (Live)/Image Wallpaper/' "$live_dotfield_ok" > "$live_dotfield_notitle"
assert_false 'a preview without the exact Dot Field title is rejected' \
    live_wallpaper_preview_is_dotfield "$live_dotfield_notitle"
live_dotfield_wrongpkg="$TMP_DIR/live-dotfield-wrongpkg.xml"
sed 's/com.android.wallpaper.livepicker/com.example.other/g' "$live_dotfield_ok" \
    > "$live_dotfield_wrongpkg"
assert_false 'a preview from another picker package is rejected' \
    live_wallpaper_preview_is_dotfield "$live_dotfield_wrongpkg"

# Destination dialog: only the exact measured Home screen control is usable.
live_destination_home="$TMP_DIR/live-destination-home.xml"
cat > "$live_destination_home" <<'EOF'
<hierarchy>
  <node text="Home screen" class="android.widget.Button" clickable="true" bounds="[200,800][900,900]" />
  <node text="Home and lock screen" class="android.widget.Button" clickable="true" bounds="[200,920][900,1020]" />
</hierarchy>
EOF
assert_eq 'the exact Home screen destination is measured' \
    '200 800 900 900' "$(live_wallpaper_destination_bounds "$live_destination_home" 1000)"
assert_false 'a dialog that also offers Home and lock is not ambiguous' \
    live_wallpaper_destination_ambiguous "$live_destination_home"
live_destination_lockonly="$TMP_DIR/live-destination-lockonly.xml"
cat > "$live_destination_lockonly" <<'EOF'
<hierarchy>
  <node text="Home and lock screen" class="android.widget.Button" clickable="true" bounds="[200,800][900,900]" />
  <node text="Lock screen" class="android.widget.Button" clickable="true" bounds="[200,920][900,1020]" />
</hierarchy>
EOF
assert_eq 'a lock-only destination never yields Home screen bounds' \
    '' "$(live_wallpaper_destination_bounds "$live_destination_lockonly" 1000)"
assert_true 'a lock-only destination is ambiguous and must fail closed' \
    live_wallpaper_destination_ambiguous "$live_destination_lockonly"
live_destination_dupe="$TMP_DIR/live-destination-dupe.xml"
cat > "$live_destination_dupe" <<'EOF'
<hierarchy>
  <node text="Home screen" class="android.widget.Button" clickable="true" bounds="[200,800][900,900]" />
  <node text="Home screen" class="android.widget.Button" clickable="true" bounds="[200,920][900,1020]" />
</hierarchy>
EOF
assert_eq 'duplicate Home screen destinations yield no bounds' \
    '' "$(live_wallpaper_destination_bounds "$live_destination_dupe" 1000)"
assert_true 'duplicate Home screen destinations are ambiguous' \
    live_wallpaper_destination_ambiguous "$live_destination_dupe"
live_destination_clipped="$TMP_DIR/live-destination-clipped.xml"
cat > "$live_destination_clipped" <<'EOF'
<hierarchy>
  <node text="Home screen" class="android.widget.Button" clickable="true" bounds="[200,1080][900,1180]" />
</hierarchy>
EOF
assert_eq 'a Home screen destination below the navigation top is rejected' \
    '' "$(live_wallpaper_destination_bounds "$live_destination_clipped" 1000)"
assert_eq 'a non-numeric navigation top fails closed' \
    '' "$(live_wallpaper_destination_bounds "$live_destination_home" bogus)"

# System wallpaper proof: our service must be in the System section, never only
# in the Lock/Fallback section or absent.
live_dumpsys_active="$TMP_DIR/live-dumpsys-active.txt"
cat > "$live_dumpsys_active" <<'EOF'
System wallpaper state:
 User 0: id=42: mWhich=1: mSystemWasBoth=false
   mWallpaperComponent=ComponentInfo{com.launchernos.dotwellabs.debug/app.nothingui.wallpaper.DotFieldWallpaperService}
Lock wallpaper state:
 User 0: id=41: mWhich=2
EOF
assert_true 'the DotField service is proven active in the System wallpaper state' \
    live_wallpaper_service_active "$live_dumpsys_active"
live_dumpsys_lockonly="$TMP_DIR/live-dumpsys-lockonly.txt"
cat > "$live_dumpsys_lockonly" <<'EOF'
System wallpaper state:
 User 0: id=42: mWhich=1
Lock wallpaper state:
 User 0: id=41: mWhich=2
   mWallpaperComponent=ComponentInfo{com.launchernos.dotwellabs.debug/app.nothingui.wallpaper.DotFieldWallpaperService}
EOF
assert_false 'a service only in the Lock section is not an applied System wallpaper' \
    live_wallpaper_service_active "$live_dumpsys_lockonly"
assert_false 'an absent service fails closed' \
    live_wallpaper_service_active "$TMP_DIR/live-dumpsys-missing.txt"

# Source wiring for the runtime apply and pause/resume gate.
SERVICE_ENGINE="$ROOT_DIR/lawnchair/src/app/nothingui/wallpaper/DotFieldWallpaperService.kt"
apply_body="$TMP_DIR/live_wallpaper_apply.sh"
sed -n '/^_cwg_apply_live_wallpaper() {/,/^}/p' "$SMOKE" > "$apply_body"
pause_body="$TMP_DIR/live_wallpaper_pause.sh"
sed -n '/^_cwg_live_pause_resume() {/,/^}/p' "$SMOKE" > "$pause_body"
assert_true 'the runtime live apply is exercised after the static applies' \
    awk '/_cwg_apply_wallpaper .Pitch Black./ { seen = 1 }
         /_cwg_apply_wallpaper .Wireframe Torus./ { if (seen) seen = 2 }
         /^    _cwg_apply_live_wallpaper$/ { if (seen == 2) ok = 1 }
         END { exit(ok ? 0 : 1) }' "$SMOKE"
assert_true 'the live apply requires the exact Dot Field preview' \
    grep -Fq 'live_wallpaper_preview_is_dotfield' "$apply_body"
assert_true 'the Set wallpaper control is measured inside the display above the navigation bar' \
    grep -Fq "ui_clickable_label_within \"\$_cal_preview_xml\" 'Set wallpaper' \"\$_cal_viewport\"" "$apply_body"
assert_true 'the destination is resolved only through the measured Home screen helper' \
    grep -Fq 'live_wallpaper_destination_bounds' "$apply_body"
assert_true 'an ambiguous destination fails closed instead of tapping a lock choice' \
    grep -Fq 'live_wallpaper_destination_ambiguous' "$apply_body"
assert_false 'the apply never taps a Home and lock destination' \
    grep -Fq 'tap_center_of_bounds "Home and lock' "$apply_body"
assert_false 'the apply never uses a direct wallpaper component setter' \
    grep -Fq 'setWallpaperComponent' "$apply_body"
assert_false 'the apply never uses a shell wallpaper setter or service binding' \
    grep -Eq 'cmd wallpaper|service call wallpaper|bindService' "$apply_body"
assert_true 'the applied System service is proven through dumpsys' \
    grep -Fq 'live_wallpaper_service_active' "$apply_body"
assert_true 'the lock wallpaper is preserved through the existing parser' \
    grep -Fq 'wallpaper_lock_preserved' "$apply_body"
assert_true 'the pause/resume gate launches the opaque device Settings screen' \
    grep -Fq 'am start -W -a android.settings.SETTINGS' "$pause_body"
assert_true 'the pause proves the measured resumed Settings activity' \
    grep -Fq 'wait_for_foreground com.android.settings' "$pause_body"
assert_true 'the pause/resume correlates one engine token' \
    grep -Fq 'live_wallpaper_single_engine' "$pause_body"
assert_true 'the pause requires a quiescent hidden engine' \
    grep -Fq 'live_wallpaper_hidden_engine' "$pause_body"
assert_true 'the resume requires the exact hidden drawn count' \
    grep -Fq 'live_wallpaper_resume_unchanged' "$pause_body"
assert_true 'the second hide requires a larger drawn count' \
    grep -Fq 'live_wallpaper_hidden_frame_increase' "$pause_body"
assert_false 'the pause/resume phase never clears the shared logcat buffer' \
    grep -Fq 'logcat -c' "$pause_body"
assert_true 'the service stamps transitions with a per-engine identity token' \
    grep -Fq 'engine=$engineToken' "$SERVICE_ENGINE"

# Focused structure regression for the frame protocol. This checks the exact
# lock placement (not concurrency behaviour): gate+enqueue share one lock,
# teardown removes queued callbacks and waits for an in-flight draw, and the
# draw publishes completion under the same lock before requesting another.
SERVICE="$ROOT_DIR/lawnchair/src/app/nothingui/wallpaper/DotFieldWallpaperService.kt"
assert_true 'the frame service has one engine lock' \
    grep -Fq 'private val lock = ReentrantLock()' "$SERVICE"
request_body="$TMP_DIR/dot-field-request.txt"
sed -n '/private fun requestFrame(immediate: Boolean)/,/^        }$/p' "$SERVICE" > "$request_body"
assert_true 'requestFrame gates under the engine lock' \
    grep -Fq 'lock.withLock' "$request_body"
assert_true 'requestFrame gates on the pure policy under that lock' \
    grep -Fq 'if (!policy.canDraw()) return' "$request_body"
assert_true 'requestFrame marks the frame pending under that lock' \
    grep -Fq 'framePending = true' "$request_body"
assert_true 'requestFrame enqueues under the same lock' \
    grep -Fq 'handler.post' "$request_body"
cancel_body="$TMP_DIR/dot-field-cancel.txt"
sed -n '/private fun cancelAndAwaitIdle()/,/^        }$/p' "$SERVICE" > "$cancel_body"
assert_true 'teardown removes every queued callback under the lock' \
    grep -Fq 'removeCallbacksAndMessages(null)' "$cancel_body"
assert_true 'teardown waits for an in-flight draw' \
    grep -Fq 'while (drawing)' "$cancel_body"
assert_true 'teardown awaits the idle condition so the worker can finish' \
    grep -Fq 'idle.await()' "$cancel_body"
assert_false 'the service no longer has an unsynchronized stopFrames helper' \
    grep -Fq 'private fun stopFrames' "$SERVICE"
assert_true 'visibility false uses the cancel-and-await protocol' \
    sed -n '/override fun onVisibilityChanged/,/^        }$/p' "$SERVICE" |
    grep -Fq 'cancelAndAwaitIdle()'
assert_true 'surface destruction uses the cancel-and-await protocol' \
    sed -n '/override fun onSurfaceDestroyed/,/^        }$/p' "$SERVICE" |
    grep -Fq 'cancelAndAwaitIdle()'
assert_true 'engine destruction uses the cancel-and-await protocol' \
    sed -n '/override fun onDestroy()/,/^        }$/p' "$SERVICE" |
    grep -Fq 'cancelAndAwaitIdle()'
draw_body="$TMP_DIR/dot-field-draw.txt"
sed -n '/private fun drawFrame()/,/^        }$/p' "$SERVICE" > "$draw_body"
assert_true 'the draw separates the locked begin-frame gate' \
    grep -Fq 'private fun beginFrame(): Boolean' "$SERVICE"
finish_body="$TMP_DIR/dot-field-finish.txt"
sed -n '/private fun finishFrame(drew: Boolean)/,/^        }$/p' "$SERVICE" > "$finish_body"
assert_true 'the draw clears in-flight under the lock' \
    grep -Fq 'drawing = false' "$finish_body"
assert_true 'the draw notifies a waiting teardown under the lock' \
    grep -Fq 'idle.signalAll()' "$finish_body"
assert_true 'transition logs carry cumulative posted/drawn counters' \
    grep -Fq 'posted=$postedFrames drawn=$drawnFrames' "$SERVICE"
assert_false 'the frame draw never logs per frame' \
    grep -Fq 'logTransition' "$draw_body"

# --- customization measured-control fixtures --------------------------------

cust_xml="$TMP_DIR/customization-dashboard.xml"
cat > "$cust_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="Customize launcher" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,100][500,150]" />
    <node index="1" text="" resource-id="" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="true" enabled="true" bounds="[20,150][1060,240]">
      <node index="0" text="Icon size and home screen" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,160][900,220]" />
    </node>
    <node index="2" text="Browse widgets" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="true" enabled="true" bounds="[40,300][1000,400]" />
    <node index="3" text="100%" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[900,500][1040,540]" />
    <node index="4" text="" resource-id="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,560][1040,640]" />
    <node index="5" text="70%" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[900,850][1040,890]" />
    <node index="6" text="" resource-id="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,910][1040,990]" />
    <node index="7" text="" resource-id="com.launchernos.dotwellabs.debug:id/app_widget" class="com.android.launcher3.widget.LauncherAppWidgetHostView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,1200][500,1500]" />
  </node>
</hierarchy>
EOF
assert_eq 'the only exact Customize launcher label is measured' \
    '40 100 500 150' "$(ui_unique_label_bounds "$cust_xml" 'Customize launcher')"
assert_eq 'the unique clickable category uses its measured clickable ancestor' \
    '20 150 1060 240' "$(ui_unique_clickable_label_bounds "$cust_xml" 'Icon size and home screen')"
assert_eq 'the unique direct Browse widgets control is measured' \
    '40 300 1000 400' "$(ui_unique_clickable_label_bounds "$cust_xml" 'Browse widgets')"
assert_eq 'the top SeekBar is measured instead of the lower slider' \
    '40 560 1040 640' "$(ui_top_slider_bounds "$cust_xml")"
assert_eq 'the top slider percentage is uniquely associated' \
    '100' "$(ui_slider_percent "$cust_xml" '40 560 1040 640')"
assert_eq 'the measured widget host bounds are retained' \
    '40 1200 500 1500' "$(ui_widget_host_bounds "$cust_xml")"
assert_eq 'an exact label absent from the hierarchy is unresolved' \
    '' "$(ui_unique_label_bounds "$cust_xml" 'Home screen')"
assert_eq 'an out-of-range slider percentage is not guessed' \
    '' "$(ui_slider_percent "$cust_xml" '40 9999 1040 9999')"

cust_one_point="$TMP_DIR/customization-one-point.xml"
cat > "$cust_one_point" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="76%" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[900,500][1040,540]" />
    <node index="1" text="" resource-id="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,560][1040,640]" />
    <node index="2" text="77%" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[900,850][1040,890]" />
    <node index="3" text="" resource-id="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[40,910][1040,990]" />
  </node>
</hierarchy>
EOF
assert_eq 'the actual 76 percent home icon label is measured' \
    '76' "$(ui_slider_percent "$cust_one_point" '40 560 1040 640')"
assert_eq 'the actual 77 percent home icon label is measured' \
    '77' "$(ui_slider_percent "$cust_one_point" '40 910 1040 990')"

cust_dupes="$TMP_DIR/customization-dupes.xml"
cat > "$cust_dupes" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="Customize launcher" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" clickable="false" bounds="[40,100][500,150]" />
    <node index="1" text="Customize launcher" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" clickable="false" bounds="[40,200][500,250]" />
    <node index="2" text="Browse widgets" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" clickable="true" bounds="[40,300][1000,400]" />
    <node index="3" text="Browse widgets" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" clickable="true" bounds="[40,450][1000,550]" />
    <node index="4" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" bounds="[40,600][1040,680]" />
    <node index="5" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" bounds="[40,600][1040,680]" />
    <node index="6" text="100%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,540][1040,580]" />
    <node index="7" text="110%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,550][1040,590]" />
  </node>
</hierarchy>
EOF
assert_eq 'duplicate exact labels are ambiguous and unresolved' \
    '' "$(ui_unique_label_bounds "$cust_dupes" 'Customize launcher')"
assert_eq 'duplicate clickable entries are ambiguous and unresolved' \
    '' "$(ui_unique_clickable_label_bounds "$cust_dupes" 'Browse widgets')"
assert_eq 'two sliders sharing the top edge are ambiguous' \
    '' "$(ui_top_slider_bounds "$cust_dupes")"

cust_ambiguous="$TMP_DIR/customization-ambiguous.xml"
cat > "$cust_ambiguous" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="100%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,500][1040,540]" />
    <node index="1" text="110%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,510][1040,550]" />
    <node index="2" text="40%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,520][1040,560]" />
    <node index="3" text="160%" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" bounds="[900,530][1040,570]" />
    <node index="4" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" bounds="[40,560][1040,640]" />
  </node>
</hierarchy>
EOF
assert_eq 'several percentages above the slider are ambiguous' \
    '' "$(ui_slider_percent "$cust_ambiguous" '40 560 1040 640')"

cust_focus="$TMP_DIR/customization-focus.xml"
cat > "$cust_focus" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" focused="true" bounds="[40,560][1040,640]" />
    <node index="1" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" focused="false" bounds="[40,910][1040,990]" />
    <node index="2" text="Browse widgets" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" focused="true" bounds="[40,300][1000,400]" />
  </node>
</hierarchy>
EOF
assert_eq 'only the actual focused SeekBar is accepted' \
    '40 560 1040 640' "$(ui_focused_slider_bounds "$cust_focus")"

cust_focus_none="$TMP_DIR/customization-focus-none.xml"
cat > "$cust_focus_none" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" focused="false" bounds="[40,560][1040,640]" />
    <node index="1" text="Browse widgets" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" focused="true" bounds="[40,300][1000,400]" />
  </node>
</hierarchy>
EOF
assert_eq 'a focused non-slider is not a focused SeekBar' \
    '' "$(ui_focused_slider_bounds "$cust_focus_none")"

cust_focus_two="$TMP_DIR/customization-focus-two.xml"
cat > "$cust_focus_two" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" focused="true" bounds="[40,560][1040,640]" />
    <node index="1" text="" class="android.widget.SeekBar" package="com.launchernos.dotwellabs.debug" focused="true" bounds="[40,910][1040,990]" />
  </node>
</hierarchy>
EOF
assert_eq 'two focused sliders are ambiguous and unresolved' \
    '' "$(ui_focused_slider_bounds "$cust_focus_two")"

# DataStore Preferences fixtures: map entry { key = "home_icon_size_factor",
# value = Preference { float } }. The encoded float bytes are the exact
# little-endian IEEE-754 values for 0.76, 0.77, 0.80, 0.49 and 1.6. A raw text
# file that merely contains the key must never be accepted.
ds76="$TMP_DIR/preferences-76.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\134\217\102\077' > "$ds76"
ds77="$TMP_DIR/preferences-77.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\270\036\105\077' > "$ds77"
ds80="$TMP_DIR/preferences-80.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\315\314\114\077' > "$ds80"
ds_two_entries="$TMP_DIR/preferences-76-and-lock.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\134\217\102\077\012\026\012\020\154\157\143\153\137\150\157\155\145\137\163\143\162\145\145\156\022\002\010\001' > "$ds_two_entries"
ds_target_second="$TMP_DIR/preferences-lock-and-76.pb"
printf '%b' '\012\026\012\020\154\157\143\153\137\150\157\155\145\137\163\143\162\145\145\156\022\002\010\001\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\134\217\102\077' > "$ds_target_second"
ds_low="$TMP_DIR/preferences-49.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\110\341\372\076' > "$ds_low"
ds_high="$TMP_DIR/preferences-160.pb"
printf '%b' '\012\036\012\025\150\157\155\145\137\151\143\157\156\137\163\151\172\145\137\146\141\143\164\157\162\022\005\025\315\314\314\077' > "$ds_high"
ds_fake="$TMP_DIR/preferences-fake.pb"
printf 'home_icon_size_factor 0.80' > "$ds_fake"
: > "$TMP_DIR/preferences-empty.pb"

assert_eq 'the datastore parser reads an actual stored 76 factor' \
    '76 5c8f423f' "$(datastore_float_factor "$ds76" 'home_icon_size_factor')"
assert_eq 'the datastore parser reads an actual stored 77 factor' \
    '77 b81e453f' "$(datastore_float_factor "$ds77" 'home_icon_size_factor')"
assert_eq 'the datastore parser distinguishes a stored 80 from a 76 label' \
    '80 cdcc4c3f' "$(datastore_float_factor "$ds80" 'home_icon_size_factor')"
assert_eq 'the datastore parser reads only the exact key among other entries' \
    '76 5c8f423f' "$(datastore_float_factor "$ds_two_entries" 'home_icon_size_factor')"
assert_eq 'the datastore parser finds a matching key after an earlier entry' \
    '76 5c8f423f' "$(datastore_float_factor "$ds_target_second" 'home_icon_size_factor')"
assert_eq 'a stored factor below the range is rejected' \
    '' "$(datastore_float_factor "$ds_low" 'home_icon_size_factor')"
assert_eq 'a stored factor above the range is rejected' \
    '' "$(datastore_float_factor "$ds_high" 'home_icon_size_factor')"
assert_eq 'a raw text key is not misread as a stored factor' \
    '' "$(datastore_float_factor "$ds_fake" 'home_icon_size_factor')"
assert_eq 'a missing datastore key is unresolved' \
    '' "$(datastore_float_factor "$ds76" 'drawer_icon_size_factor')"
assert_eq 'an empty datastore file is unresolved' \
    '' "$(datastore_float_factor "$TMP_DIR/preferences-empty.pb" 'home_icon_size_factor')"

assert_eq 'the measured bounds top edge is extracted for ordering' \
    '920' "$(ui_bounds_top_y '84 920 409 973')"
assert_eq 'a bounds string with fewer than four numbers is unresolved' \
    '' "$(ui_bounds_top_y '84 920 409')"
assert_eq 'a bounds string with a non-numeric token is unresolved' \
    '' "$(ui_bounds_top_y '84 top 409 973')"
assert_eq 'an empty bounds string is unresolved' \
    '' "$(ui_bounds_top_y '')"

# CI211 settings-theme-dark.xml shape: the label node has a clickable ancestor
# whose measured bounds are the actual tap target. The known parent/label
# numbers (category 42 1009 1038 1198, label 84 920 409 973) keep the fixture
# aligned with the real settings dashboard ancestry.
cust_ci211="$TMP_DIR/customization-ci211-settings-theme-dark.xml"
cat > "$cust_ci211" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" text="" resource-id="" class="android.view.ViewGroup" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="true" enabled="true" bounds="[42,1009][1038,1198]">
      <node index="0" text="Icon size and home screen" resource-id="" class="android.widget.TextView" package="com.launchernos.dotwellabs.debug" content-desc="" clickable="false" enabled="true" bounds="[84,920][409,973]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the CI211 theme-dark label uses its measured clickable ancestor' \
    '42 1009 1038 1198' \
    "$(ui_unique_clickable_label_bounds "$cust_ci211" 'Icon size and home screen')"

# Execute the actual production order-check function under `sh -eu` with real
# 4-number measured strings. A quoted bounds string must not leave an unbound
# positional, and a genuinely out-of-order layout must fail.
customization_order_body="$TMP_DIR/customization_controls_in_order.sh"
sed -n '/^customization_controls_in_order() {/,/^}/p' "$SMOKE" > "$customization_order_body"
assert_true 'the production order-check function is extractable' \
    test -s "$customization_order_body"
run_customization_order() {
    sh -eu -c '. "$1"; . "$2"; customization_controls_in_order "$3" "$4" "$5"' \
        sh "$LIB" "$customization_order_body" "$1" "$2" "$3"
}
if run_customization_order '84 920 409 973' '84 1000 1000 1080' '84 1200 1000 1300'; then
    pass 'the executed order check accepts real 4-number measured bounds under sh -eu'
else
    fail 'the executed order check accepts real 4-number measured bounds under sh -eu'
fi
if run_customization_order '84 1200 409 1300' '84 1000 1000 1080' '84 920 1000 973'; then
    fail 'the executed order check rejects a reversed control order under sh -eu'
else
    pass 'the executed order check rejects a reversed control order under sh -eu'
fi
if run_customization_order '84 920 409' '84 1000 1000 1080' '84 1200 1000 1300'; then
    fail 'the executed order check rejects an unresolved bounds string under sh -eu'
else
    pass 'the executed order check rejects an unresolved bounds string under sh -eu'
fi

# --- weather settings helper fixtures --------------------------------------

weather_ui_xml="$TMP_DIR/weather-ui.xml"
cat > "$weather_ui_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" class="android.widget.EditText" text="" content-desc="Location label" clickable="true" enabled="true" bounds="[40,200][1040,300]" />
      <node index="1" class="android.widget.EditText" text="not-a-number" clickable="true" enabled="true" bounds="[40,320][1040,420]" />
      <node index="2" class="android.widget.EditText" text="10.0000" clickable="true" enabled="true" bounds="[40,440][1040,540]" />
      <node index="3" text="I understand and want to enable weather setup" checkable="true" checked="false" enabled="true" bounds="[40,560][1040,640]" />
      <node index="4" class="android.widget.Button" clickable="false" enabled="false" bounds="[40,660][1040,760]">
        <node index="0" class="android.widget.TextView" text="Save and enable" clickable="false" enabled="true" bounds="[80,680][500,740]" />
      </node>
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'all three weather EditText fields are measured in order' \
    '40 200 1040 300
40 320 1040 420
40 440 1040 540' "$(ui_edit_text_bounds "$weather_ui_xml")"
assert_eq 'the weather consent checkbox is the only unique checkable control' \
    '40 560 1040 640' "$(ui_unique_checkable_bounds "$weather_ui_xml")"
assert_eq 'the weather consent checkbox reports its unchecked state' \
    'false' "$(ui_unique_checkable_checked "$weather_ui_xml")"

weather_checkbox_pair_xml="$TMP_DIR/weather-checkbox-pair.xml"
cat > "$weather_checkbox_pair_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" checkable="true" checked="true" bounds="[40,560][1040,640]">
    <node index="0" checkable="true" checked="true" bounds="[40,570][120,630]" />
  </node>
</hierarchy>
EOF
assert_eq 'agreeing toggleable row and inner checkbox use the larger row bounds' \
    '40 560 1040 640' "$(ui_unique_checkable_bounds "$weather_checkbox_pair_xml")"
assert_eq 'agreeing toggleable row and inner checkbox report the same state' \
    'true' "$(ui_unique_checkable_checked "$weather_checkbox_pair_xml")"
weather_checkbox_mixed_xml="$TMP_DIR/weather-checkbox-mixed.xml"
cat > "$weather_checkbox_mixed_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" checkable="true" checked="true" bounds="[40,560][1040,640]" />
  <node index="1" checkable="true" checked="false" bounds="[40,570][120,630]" />
</hierarchy>
EOF
assert_eq 'mixed checkable states are ambiguous and fail closed' \
    '' "$(ui_unique_checkable_state "$weather_checkbox_mixed_xml")"
assert_eq 'a disabled button ancestor disables its text label' \
    'false' "$(ui_unique_label_enabled "$weather_ui_xml" 'Save and enable')"

weather_enabled_xml="$TMP_DIR/weather-enabled.xml"
cat > "$weather_enabled_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.Button" clickable="true" enabled="true" bounds="[40,660][1040,760]">
    <node index="0" class="android.widget.TextView" text="Save and enable" clickable="false" enabled="true" bounds="[80,680][500,740]" />
  </node>
</hierarchy>
EOF
assert_eq 'an enabled button label reports enabled' \
    'true' "$(ui_unique_label_enabled "$weather_enabled_xml" 'Save and enable')"

weather_duplicate_enabled_xml="$TMP_DIR/weather-duplicate-enabled.xml"
cat > "$weather_duplicate_enabled_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.TextView" text="Save and enable" enabled="false" bounds="[1,2][3,4]" />
  <node index="1" class="android.widget.TextView" text="Save and enable" enabled="true" bounds="[5,6][7,8]" />
</hierarchy>
EOF
assert_eq 'duplicate button labels do not yield an enabled state' \
    '' "$(ui_unique_label_enabled "$weather_duplicate_enabled_xml" 'Save and enable')"

assert_true 'a fully measured control inside the viewport is tappable' \
    ui_bounds_within '40 200 1040 300' '0 72 1080 1794'
assert_false 'a control clipped by the navigation top is not tappable' \
    ui_bounds_within '40 1700 1040 1800' '0 72 1080 1794'
assert_false 'a malformed control rectangle is not tappable' \
    ui_bounds_within '40 200 1040' '0 72 1080 1794'

ime_shown_dump="$TMP_DIR/ime-shown.dump"
cat > "$ime_shown_dump" <<'EOF'
InputMethodManagerService
  mCurMethodId=com.google.android.inputmethod.latin/.LatinIME
  mInputShown=true
EOF
ime_hidden_dump="$TMP_DIR/ime-hidden.dump"
cat > "$ime_hidden_dump" <<'EOF'
InputMethodManagerService
  mCurMethodId=com.google.android.inputmethod.latin/.LatinIME
  mInputShown=false
EOF
assert_true 'a shown IME is detected from dumpsys input_method' \
    ime_is_shown "$ime_shown_dump"
assert_false 'a hidden IME is not detected as shown' \
    ime_is_shown "$ime_hidden_dump"
assert_false 'missing IME evidence fails closed as hidden' \
    ime_is_shown "$TMP_DIR/ime-missing.dump"

assert_eq 'the weather cache filename matches the production URL-safe base64 name' \
    'NjAuMDAwMCwxMC4wMDAw' "$(weather_cache_filename '60.0000,10.0000')"
assert_eq 'an empty weather cache key has no filename' \
    '' "$(weather_cache_filename '')"

weather_missing_json="$TMP_DIR/weather-missing.json"
assert_eq 'a missing weather consent record is reported as missing' \
    'missing' "$(weather_consent_state "$weather_missing_json")"
weather_disabled_json="$TMP_DIR/weather-disabled.json"
printf '%s\n' '{"version":1,"enabled":false,"generation":3,"label":null,"latitude":null,"longitude":null}' \
    > "$weather_disabled_json"
assert_eq 'a valid disabled weather record reports disabled and its generation' \
    'disabled|3' "$(weather_consent_state "$weather_disabled_json")"
weather_enabled_json="$TMP_DIR/weather-enabled.json"
printf '%s\n' '{"version":1,"enabled":true,"generation":4,"label":"Emulator test","latitude":"60.0000","longitude":"10.0000"}' \
    > "$weather_enabled_json"
assert_eq 'a valid enabled weather record reports only the synthetic location' \
    'enabled|4|Emulator test|60.0000|10.0000' \
    "$(weather_consent_state "$weather_enabled_json")"
weather_corrupt_json="$TMP_DIR/weather-corrupt.json"
printf '%s\n' '{"version":2,"enabled":true,"generation":4,"label":"Emulator test","latitude":"60.0000","longitude":"10.0000"}' \
    > "$weather_corrupt_json"
assert_eq 'an unexpected weather record version fails closed' \
    'malformed' "$(weather_consent_state "$weather_corrupt_json")"
weather_null_enabled_json="$TMP_DIR/weather-null-enabled.json"
printf '%s\n' '{"version":1,"enabled":true,"generation":4,"label":null,"latitude":null,"longitude":null}' \
    > "$weather_null_enabled_json"
assert_eq 'an enabled record without a stored location fails closed' \
    'malformed' "$(weather_consent_state "$weather_null_enabled_json")"

# The real CI297 first Weather screen exposed only the privacy notice and the
# Terms/Source/License links. The Location label and Latitude fields sat below
# the fold and were absent from the composed hierarchy even across 10 identical
# captures, so the old single-snapshot identity that demanded the notice and
# fields at once could never pass. Provenance is now proven in two stages: the
# initial mode-correct notice, then a real measured scroll to each field on the
# same screen. The notice text is the shipped runtime value, so this fixture
# cannot drift into a short or invented notice.
weather_notice_297_xml="$TMP_DIR/weather-notice-297.xml"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">'
    printf '%s\n' '    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">'
    printf '%s\n' '      <node index="0" class="android.widget.TextView" text="Weather" bounds="[84,140][300,200]" />'
    printf '%s\n' '      <node index="1" class="android.widget.TextView" text="Before you enable" bounds="[84,260][996,320]" />'
    printf '      <node index="2" class="android.widget.TextView" text="%s" bounds="[84,340][996,1180]" />\n' \
        "$debug_privacy"
    printf '%s\n' '      <node index="3" class="android.widget.TextView" text="Terms of Service" clickable="true" bounds="[84,1220][420,1280]" />'
    printf '%s\n' '      <node index="4" class="android.widget.TextView" text="Source" clickable="true" bounds="[440,1220][700,1280]" />'
    printf '%s\n' '      <node index="5" class="android.widget.TextView" text="License" clickable="true" bounds="[720,1220][996,1280]" />'
    printf '%s\n' '    </node>'
    printf '%s\n' '  </node>'
    printf '%s\n' '</hierarchy>'
} > "$weather_notice_297_xml"

# Post-measured-scroll captures of that same screen. The privacy title is now
# offscreen, but each real labelled field is exposed in its own capture.
weather_location_field_xml="$TMP_DIR/weather-fields-location.xml"
cat > "$weather_location_field_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" class="android.widget.EditText" text="" content-desc="Location label" clickable="true" enabled="true" bounds="[126,600][954,740]" />
    </node>
  </node>
</hierarchy>
EOF
weather_latitude_field_xml="$TMP_DIR/weather-fields-latitude.xml"
cat > "$weather_latitude_field_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" class="android.widget.EditText" text="" content-desc="Latitude" clickable="true" enabled="true" bounds="[126,800][954,940]" />
    </node>
  </node>
</hierarchy>
EOF

assert_true 'the actual CI297 long-notice initial screen is the mode-correct Weather privacy identity' \
    weather_settings_notice_identity "$weather_notice_297_xml" debug
assert_false 'the initial notice screen is not the complete Weather destination by itself' \
    weather_settings_fields_identity "$weather_notice_297_xml" "$weather_notice_297_xml"
assert_false 'the post-scroll fields shape is not the privacy-notice identity' \
    weather_settings_notice_identity "$weather_location_field_xml" debug
assert_true 'the post-scroll Location label field satisfies the field identity' \
    weather_settings_field_identity "$weather_location_field_xml" 'Location label'
assert_true 'the post-scroll Latitude field satisfies the field identity' \
    weather_settings_field_identity "$weather_latitude_field_xml" 'Latitude'
assert_true 'two-stage provenance accepts the real notice plus both measured-scroll fields' \
    weather_settings_screen_provenance "$weather_notice_297_xml" \
    "$weather_location_field_xml" "$weather_latitude_field_xml" debug
assert_false 'provenance rejects a privacy notice with no measured Location field' \
    weather_settings_screen_provenance "$weather_notice_297_xml" \
    "$weather_notice_297_xml" "$weather_latitude_field_xml" debug
assert_false 'provenance rejects a measured Location field with no Latitude field' \
    weather_settings_screen_provenance "$weather_notice_297_xml" \
    "$weather_location_field_xml" "$weather_notice_297_xml" debug
assert_false 'provenance rejects one artifact reused as its own proof' \
    weather_settings_screen_provenance "$weather_notice_297_xml" \
    "$weather_notice_297_xml" "$weather_notice_297_xml" debug

weather_wrongmode_xml="$TMP_DIR/weather-wrongmode.xml"
cat > "$weather_wrongmode_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.TextView" text="Weather" bounds="[84,140][300,200]" />
  <node index="1" class="android.widget.TextView" text="Before you enable" bounds="[84,260][996,320]" />
  <node index="2" class="android.widget.TextView" text="When an enabled forecast is requested, those selected coordinates and the IP address of this device are shared with MET Norway (met.no) only while the Home screen is visible and unlocked." bounds="[84,340][996,980]" />
  <node index="3" class="android.widget.TextView" text="Terms of Service" clickable="true" bounds="[84,1020][420,1080]" />
</hierarchy>
EOF
assert_false 'the release notice is rejected for the debug runtime mode' \
    weather_settings_notice_identity "$weather_wrongmode_xml" debug
assert_true 'the release notice is accepted only for the release mode' \
    weather_settings_notice_identity "$weather_wrongmode_xml" release
assert_false 'a fake/wrong-mode notice cannot complete the debug provenance' \
    weather_settings_screen_provenance "$weather_wrongmode_xml" \
    "$weather_location_field_xml" "$weather_latitude_field_xml" debug

weather_title_only_xml="$TMP_DIR/weather-title-only.xml"
cat > "$weather_title_only_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.TextView" text="Weather" bounds="[84,140][300,200]" />
</hierarchy>
EOF
assert_false 'a Weather title alone is not the privacy identity' \
    weather_settings_notice_identity "$weather_title_only_xml" debug

weather_wrongscreen_xml="$TMP_DIR/weather-wrongscreen.xml"
cat > "$weather_wrongscreen_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.TextView" text="Customize launcher" bounds="[84,140][700,200]" />
  <node index="1" class="android.widget.TextView" text="Icon size and home screen" clickable="true" bounds="[84,260][996,320]" />
  <node index="2" class="android.widget.EditText" text="" content-desc="Latitude" bounds="[126,400][954,540]" />
</hierarchy>
EOF
assert_false 'a different settings screen is not the Weather privacy identity' \
    weather_settings_notice_identity "$weather_wrongscreen_xml" debug
assert_false 'a different settings screen cannot satisfy the measured field identity' \
    weather_settings_field_identity "$weather_wrongscreen_xml" 'Location label'

weather_noprivacy_xml="$TMP_DIR/weather-noprivacy.xml"
cat > "$weather_noprivacy_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="" content-desc="Latitude" bounds="[126,1826][954,1966]" />
</hierarchy>
EOF
assert_false 'a hierarchy without the unique privacy heading is not the Weather destination' \
    weather_settings_notice_identity "$weather_noprivacy_xml" debug

# A clipped field must still be associated with its stable label rather than its
# visible position, even before the measured scroll reaches it.
weather_initial_xml="$TMP_DIR/weather-initial.xml"
cat > "$weather_initial_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" class="android.widget.TextView" text="Before you enable" bounds="[84,300][996,360]" />
      <node index="1" class="android.widget.TextView" text="Weather is off until you explicitly save and enable a location." bounds="[84,380][996,500]" />
      <node index="2" class="android.widget.TextView" text="Terms of Service" clickable="true" bounds="[84,520][400,580]" />
      <node index="3" class="android.widget.TextView" text="Source" clickable="true" bounds="[420,520][700,580]" />
      <node index="4" class="android.widget.TextView" text="License" clickable="true" bounds="[720,520][996,580]" />
      <node index="5" class="android.widget.TextView" text="Weather" bounds="[84,700][300,760]" />
      <node index="6" class="android.widget.EditText" text="" content-desc="Location label" clickable="true" enabled="true" bounds="[126,1636][954,1776]" />
      <node index="7" class="android.widget.EditText" text="" content-desc="Latitude" clickable="true" enabled="true" bounds="[126,1826][954,1966]" />
      <node index="8" class="android.widget.EditText" text="" content-desc="Longitude" clickable="true" enabled="true" bounds="[126,2016][954,2156]" />
      <node index="9" class="android.widget.Button" clickable="true" enabled="false" bounds="[84,2206][996,2326]" />
    </node>
  </node>
</hierarchy>
EOF
assert_true 'the clipped Location label is associated by its label' \
    weather_settings_field_identity "$weather_initial_xml" 'Location label'
assert_eq 'the clipped Latitude field is associated by its label' \
    '126 1826 954 1966' \
    "$(ui_labelled_edit_text_bounds "$weather_initial_xml" 'Latitude')"
assert_eq 'the initially empty Latitude field reports an empty draft' \
    '' "$(ui_labelled_edit_text_text "$weather_initial_xml" 'Latitude')"

weather_descendant_xml="$TMP_DIR/weather-descendant.xml"
cat > "$weather_descendant_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="60.0000" bounds="[40,320][1040,420]">
    <node index="0" class="android.widget.TextView" text="Latitude" bounds="[60,330][200,370]" />
  </node>
  <node index="1" class="android.widget.EditText" text="10.0000" bounds="[40,440][1040,540]">
    <node index="0" class="android.widget.TextView" text="Longitude" bounds="[60,450][200,490]" />
  </node>
</hierarchy>
EOF
assert_eq 'a populated field is associated through its descendant label' \
    '40 320 1040 420|60.0000' \
    "$(ui_labelled_edit_text_state "$weather_descendant_xml" 'Latitude')"
assert_eq 'a populated longitude field is not confused with latitude' \
    '40 440 1040 540|10.0000' \
    "$(ui_labelled_edit_text_state "$weather_descendant_xml" 'Longitude')"

weather_sibling_xml="$TMP_DIR/weather-sibling.xml"
cat > "$weather_sibling_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.view.ViewGroup" bounds="[0,0][1080,600]">
    <node index="0" class="android.widget.TextView" text="Latitude" bounds="[40,300][200,340]" />
    <node index="1" class="android.widget.EditText" text="60.0000" bounds="[40,320][1040,420]" />
    <node index="2" class="android.widget.TextView" text="Longitude" bounds="[40,430][220,470]" />
    <node index="3" class="android.widget.EditText" text="10.0000" bounds="[40,450][1040,550]" />
  </node>
</hierarchy>
EOF
assert_eq 'a preceding sibling label associates with the next field' \
    '40 320 1040 420|60.0000' \
    "$(ui_labelled_edit_text_state "$weather_sibling_xml" 'Latitude')"
assert_eq 'a later sibling label does not shift latitude to longitude' \
    '40 450 1040 550|10.0000' \
    "$(ui_labelled_edit_text_state "$weather_sibling_xml" 'Longitude')"

weather_duplicate_label_xml="$TMP_DIR/weather-duplicate-label.xml"
cat > "$weather_duplicate_label_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="60.0000" content-desc="Latitude" bounds="[40,320][1040,420]">
    <node index="0" class="android.widget.TextView" text="Latitude" bounds="[60,330][200,370]" />
  </node>
</hierarchy>
EOF
assert_eq 'the same label exposed twice for one field still associates that field' \
    '40 320 1040 420|60.0000' \
    "$(ui_labelled_edit_text_state "$weather_duplicate_label_xml" 'Latitude')"

weather_duplicate_field_xml="$TMP_DIR/weather-duplicate-field.xml"
cat > "$weather_duplicate_field_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="" content-desc="Latitude" bounds="[40,320][1040,420]" />
  <node index="1" class="android.widget.EditText" text="" content-desc="Latitude" bounds="[40,440][1040,540]" />
</hierarchy>
EOF
assert_eq 'duplicate field labels fail closed instead of picking one' \
    '' "$(ui_labelled_edit_text_state "$weather_duplicate_field_xml" 'Latitude')"
assert_eq 'an absent field label yields no field' \
    '' "$(ui_labelled_edit_text_state "$weather_initial_xml" 'Not a field')"

# A focus tap on the Longitude field is real only while that EditText reports
# focused="true". The blurred fixture below swaps the focus attribute to the
# latitude field, so a capture named "blurred" can be asserted instead of
# assumed. The hint-tap fixture keeps Longitude focused, reproducing why tapping
# a non-focusable hint text could never prove a blurred state.
weather_focused_xml="$TMP_DIR/weather-longitude-focused.xml"
cat > "$weather_focused_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="60.0000" content-desc="Latitude" focused="false" bounds="[40,320][1040,420]" />
  <node index="1" class="android.widget.EditText" text="10.0000" content-desc="Longitude" focused="true" bounds="[40,440][1040,540]" />
</hierarchy>
EOF
assert_eq 'the focused longitude capture reports measured focus' \
    'true' "$(ui_labelled_edit_text_focused "$weather_focused_xml" 'Longitude')"
assert_eq 'the latitude field is not focused in the focused capture' \
    'false' "$(ui_labelled_edit_text_focused "$weather_focused_xml" 'Latitude')"
assert_eq 'the focused helper does not change the existing state format' \
    '40 440 1040 540|10.0000' \
    "$(ui_labelled_edit_text_state "$weather_focused_xml" 'Longitude')"

weather_blurred_xml="$TMP_DIR/weather-longitude-blurred.xml"
cat > "$weather_blurred_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="60.0000" content-desc="Latitude" focused="true" bounds="[40,320][1040,420]" />
  <node index="1" class="android.widget.EditText" text="10.0000" content-desc="Longitude" focused="false" bounds="[40,440][1040,540]" />
</hierarchy>
EOF
assert_eq 'the longitude field is measurably blurred after focus moves' \
    'false' "$(ui_labelled_edit_text_focused "$weather_blurred_xml" 'Longitude')"
assert_eq 'the measured latitude field took focus from longitude' \
    'true' "$(ui_labelled_edit_text_focused "$weather_blurred_xml" 'Latitude')"
assert_eq 'moving focus does not change the latitude draft' \
    '60.0000' "$(ui_labelled_edit_text_text "$weather_blurred_xml" 'Latitude')"

weather_hint_tap_xml="$TMP_DIR/weather-hint-tap-still-focused.xml"
cat > "$weather_hint_tap_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" class="android.widget.EditText" text="10.0000" content-desc="Longitude" focused="true" bounds="[40,440][1040,540]" />
  <node index="1" class="android.widget.TextView" text="Use 4 decimal places or fewer." bounds="[40,560][1040,600]" />
</hierarchy>
EOF
assert_eq 'a hint tap that leaves longitude focused cannot prove a blur' \
    'true' "$(ui_labelled_edit_text_focused "$weather_hint_tap_xml" 'Longitude')"
assert_eq 'an ambiguous or missing field reports no focus state' \
    '' "$(ui_labelled_edit_text_focused "$weather_blurred_xml" 'Not a field')"

assert_eq 'a target below the viewport scrolls down' \
    'down' "$(weather_target_scroll_direction '126 1826 954 1966' '0 72 1080 1794')"
assert_eq 'a target above the viewport scrolls up' \
    'up' "$(weather_target_scroll_direction '126 10 954 60' '0 72 1080 1794')"
assert_eq 'a target clipped at the bottom scrolls down' \
    'down' "$(weather_target_scroll_direction '126 1750 954 1890' '0 72 1080 1794')"
assert_eq 'a target clipped at the top scrolls up' \
    'up' "$(weather_target_scroll_direction '126 40 954 180' '0 72 1080 1794')"
assert_eq 'a malformed target has no inferred scroll direction' \
    '' "$(weather_target_scroll_direction '126 100 954' '0 72 1080 1794')"

# CI250: the enabled screen keeps its saved status and a clipped Disable action
# in the top hierarchy while the success message is not composed below the fold.
# A raw grep of that XML cannot prove the action, and the clipped Disable is not
# a tappable identity until the measured scroll reveals it.
weather_enabled_top_xml="$TMP_DIR/weather-enabled-top.xml"
cat > "$weather_enabled_top_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">
    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">
      <node index="0" class="android.widget.TextView" text="Weather setup is enabled for Emulator test (60.0000, 10.0000). This debug build has network requests disabled, so no coordinates or device IP address are sent and no forecast is requested. Disabling clears this location cache. The shared provider throttle is kept." bounds="[84,1600][996,1780]" />
      <node index="1" class="android.widget.Button" text="Disable and clear location" clickable="true" enabled="true" bounds="[84,1901][996,1920]" />
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the CI250 enabled top hierarchy measures its clipped Disable action' \
    '84 1901 996 1920' \
    "$(ui_unique_label_bounds "$weather_enabled_top_xml" 'Disable and clear location')"
assert_false 'the CI250 clipped Disable action is not tappable without scrolling' \
    ui_bounds_within '84 1901 996 1920' '0 72 1080 1794'
assert_eq 'the CI250 enabled status is already visible in the top hierarchy' \
    '84 1600 996 1780' \
    "$(ui_unique_label_bounds "$weather_enabled_top_xml" 'Weather setup is enabled for Emulator test (60.0000, 10.0000). This debug build has network requests disabled, so no coordinates or device IP address are sent and no forecast is requested. Disabling clears this location cache. The shared provider throttle is kept.')"
assert_eq 'the CI250 success message is absent from the unscrolled hierarchy' \
    '' \
    "$(ui_unique_label_bounds "$weather_enabled_top_xml" 'Weather setup saved. This debug build has network requests disabled, so no forecast is requested.')"

# Realistic CI300 shape: the long privacy notice leaves the top-of-screen
# snapshot without the saved line or a tappable Disable control. The measured
# post-action reveal on the SAME screen contains exactly one actionable Disable
# control and the shipped saved line. Post-action provenance must accept that
# measured reveal and reject the stale pre-scroll snapshot.
weather_enabled_scrolled_xml="$TMP_DIR/weather-enabled-scrolled.xml"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">'
    printf '%s\n' '    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">'
    printf '%s\n' '      <node index="0" class="android.widget.Button" text="Disable and clear location" clickable="true" enabled="true" bounds="[84,900][996,1020]" />'
    printf '      <node index="1" class="android.widget.TextView" text="%s" bounds="[84,1040][996,1200]" />\n' \
        "$(prod_string dotwel_weather_message_enabled_debug)"
    printf '%s\n' '    </node>'
    printf '%s\n' '  </node>'
    printf '%s\n' '</hierarchy>'
} > "$weather_enabled_scrolled_xml"

weather_disabled_scrolled_xml="$TMP_DIR/weather-disabled-scrolled.xml"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.FrameLayout" package="com.launchernos.dotwellabs.debug" bounds="[0,0][1080,1920]">'
    printf '%s\n' '    <node index="0" class="android.widget.ScrollView" package="com.launchernos.dotwellabs.debug" scrollable="true" bounds="[0,72][1080,1794]">'
    printf '%s\n' '      <node index="0" class="android.widget.Button" text="Save and enable" clickable="true" enabled="false" bounds="[84,900][996,1020]" />'
    printf '      <node index="1" class="android.widget.TextView" text="%s" bounds="[84,1040][996,1200]" />\n' \
        "$(prod_string dotwel_weather_message_disabled)"
    printf '%s\n' '    </node>'
    printf '%s\n' '  </node>'
    printf '%s\n' '</hierarchy>'
} > "$weather_disabled_scrolled_xml"

weather_enabled_status_only_xml="$TMP_DIR/weather-enabled-status-only.xml"
{
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.TextView" text="Weather setup is enabled for Emulator test (60.0000, 10.0000). This debug build has network requests disabled, so no coordinates or device IP address are sent and no forecast is requested." bounds="[84,800][996,1000]" />'
    printf %s\n '</hierarchy>'
} > "$weather_enabled_status_only_xml"

weather_enabled_no_control_xml="$TMP_DIR/weather-enabled-no-control.xml"
{
    printf '%s\n' '<hierarchy rotation="0">'
    printf '  <node index="0" class="android.widget.TextView" text="%s" bounds="[84,900][996,1060]" />\n' \
        "$(prod_string dotwel_weather_message_enabled_debug)"
    printf '%s\n' '</hierarchy>'
} > "$weather_enabled_no_control_xml"

weather_enabled_duplicate_control_xml="$TMP_DIR/weather-enabled-duplicate-control.xml"
{
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.Button" text="Disable and clear location" clickable="true" enabled="true" bounds="[84,700][996,820]" />'
    printf '%s\n' '  <node index="1" class="android.widget.Button" text="Disable and clear location" clickable="true" enabled="true" bounds="[84,840][996,960]" />'
    printf '  <node index="2" class="android.widget.TextView" text="%s" bounds="[84,980][996,1140]" />\n' \
        "$(prod_string dotwel_weather_message_enabled_debug)"
    printf '%s\n' '</hierarchy>'
} > "$weather_enabled_duplicate_control_xml"

weather_enabled_disabled_control_xml="$TMP_DIR/weather-enabled-disabled-control.xml"
{
    printf '%s\n' '<hierarchy rotation="0">'
    printf '%s\n' '  <node index="0" class="android.widget.Button" text="Disable and clear location" clickable="true" enabled="false" bounds="[84,700][996,820]" />'
    printf '  <node index="1" class="android.widget.TextView" text="%s" bounds="[84,840][996,1000]" />\n' \
        "$(prod_string dotwel_weather_message_enabled_debug)"
    printf '%s\n' '</hierarchy>'
} > "$weather_enabled_disabled_control_xml"

weather_action_activities="$TMP_DIR/weather-action-activities-preferences.txt"
printf '%s\n' '  mResumedActivity: ActivityRecord{9f3a1b u0 com.launchernos.dotwellabs.debug/app.lawnchair.ui.preferences.PreferenceActivity t42}' \
    > "$weather_action_activities"
weather_action_activities_wrong="$TMP_DIR/weather-action-activities-launcher.txt"
printf '%s\n' '  mResumedActivity: ActivityRecord{9f3a1c u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t42}' \
    > "$weather_action_activities_wrong"

weather_enabled_consent='enabled|4|Emulator test|60.0000|10.0000'
weather_disabled_consent='disabled|5'
weather_enabled_consent_no_label='enabled|4||60.0000|10.0000'

assert_true 'the measured long-notice enabled reveal exposes the actionable Disable and shipped saved line' \
    weather_enabled_action_identity "$weather_enabled_scrolled_xml" debug
assert_false 'the stale pre-scroll notice snapshot is not the enabled action identity' \
    weather_enabled_action_identity "$weather_notice_297_xml" debug
assert_false 'the stale status-only snapshot without the saved line is not the enabled action identity' \
    weather_enabled_action_identity "$weather_enabled_top_xml" debug
assert_false 'the status-only enabled shape without the saved line is not the enabled action identity' \
    weather_enabled_action_identity "$weather_enabled_status_only_xml" debug
assert_false 'a measured enabled reveal without the Disable control fails closed' \
    weather_enabled_action_identity "$weather_enabled_no_control_xml" debug
assert_false 'a duplicate Disable control is not a unique actionable identity' \
    weather_enabled_action_identity "$weather_enabled_duplicate_control_xml" debug
assert_false 'a disabled Disable control is not actionable' \
    weather_enabled_action_identity "$weather_enabled_disabled_control_xml" debug
assert_false 'the enabled action identity rejects the other build-mode copy' \
    weather_enabled_action_identity "$weather_enabled_scrolled_xml" release

assert_true 'the long-notice initial capture plus the measured enabled reveal proves the same screen action' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"
assert_false 'post-action provenance rejects the pre-scroll snapshot as the measured reveal' \
    weather_action_screen_provenance enable "$weather_enabled_top_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"
assert_false 'post-action provenance rejects a wrong resumed activity' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities_wrong" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"
assert_false 'post-action provenance rejects a mismatched package/activity pair' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.LawnchairLauncher \
    debug "$weather_enabled_consent"
assert_false 'post-action provenance rejects a disabled store for an enabled action' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_disabled_consent"
assert_false 'post-action provenance rejects an enabled store with no saved label' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent_no_label"
assert_false 'post-action provenance rejects a missing store record' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug ''
assert_false 'post-action provenance rejects one artifact reused as its own proof' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_enabled_scrolled_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"
assert_false 'post-action provenance rejects the wrong build-mode notice' \
    weather_action_screen_provenance enable "$weather_enabled_scrolled_xml" \
    "$weather_wrongmode_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"

assert_true 'the measured long-notice disable reveal exposes the unique Save and enable control and shipped disabled line' \
    weather_disabled_action_identity "$weather_disabled_scrolled_xml"
assert_false 'a disable reveal without the Save and enable control fails closed' \
    weather_disabled_action_identity "$weather_enabled_scrolled_xml"
assert_true 'the long-notice initial capture plus the measured disable reveal proves the same screen action' \
    weather_action_screen_provenance disable "$weather_disabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_disabled_consent"
assert_false 'post-action provenance rejects a still-enabled store for a disable action' \
    weather_action_screen_provenance disable "$weather_disabled_scrolled_xml" \
    "$weather_notice_297_xml" "$weather_action_activities" \
    com.launchernos.dotwellabs.debug app.lawnchair.ui.preferences.PreferenceActivity \
    debug "$weather_enabled_consent"

# The pure action constants must stay tied to the shipped runtime values so a
# copy change fails here instead of drifting the post-action identity.
assert_eq 'the enabled action saved line is the shipped debug message prefix' \
    "$WEATHER_ACTION_ENABLED_SAVED" \
    'Weather setup saved.'
assert_eq 'the disabled action saved line is the shipped disabled message prefix' \
    "$WEATHER_ACTION_DISABLED_SAVED" \
    'Weather disabled.'
assert_eq 'the Disable control constant is the shipped label' \
    "$WEATHER_ACTION_DISABLE_CONTROL" "$(prod_string dotwel_weather_disable)"
assert_eq 'the Save and enable control constant is the shipped label' \
    "$WEATHER_ACTION_ENABLE_CONTROL" "$(prod_string dotwel_weather_enable)"
prod_string_contains dotwel_weather_message_enabled_debug \
    "$WEATHER_ACTION_ENABLED_SAVED" \
    'the shipped enabled message begins with the action saved line'
prod_string_contains dotwel_weather_message_disabled \
    "$WEATHER_ACTION_DISABLED_SAVED" \
    'the shipped disabled message begins with the action saved line'
prod_string_contains dotwel_weather_message_enabled_debug \
    "$WEATHER_PRIVACY_NOTICE_DEBUG_OFF" \
    'the shipped enabled debug message carries the network-off disclosure'

# Execute the actual post-action poll with stubbed device calls. A durable
# enabled record alone must not pass while the success line is unreachable; it
# must pass only after the measured reveal exposes the line and the real action
# identity, and a total miss must retain failure evidence.
weather_poll_body="$TMP_DIR/weather_poll_action_state.sh"
sed -n '/^_weather_poll_action_state() {/,/^}/p' "$SMOKE" > "$weather_poll_body"
assert_true 'the weather post-action poll function is extractable' \
    test -s "$weather_poll_body"
weather_poll_harness="$TMP_DIR/weather-poll-harness.sh"
cat > "$weather_poll_harness" <<'EOF'
set -eu
. "$1"
ARTIFACTS=$2
MEASURE_MODE=$3
sleep() { :; }
_weather_capture_consent() {
    printf 'enabled|4|Emulator test|60.0000|10.0000\n'
}
capture_ui_xml() {
    mkdir -p "$ARTIFACTS"
    printf 'xml\n' > "$ARTIFACTS/$1"
}
capture_screenshot_to() {
    mkdir -p "$ARTIFACTS"
    printf 'png\n' > "$ARTIFACTS/$1"
}
fail() { return 1; }
poll_measure_calls=0
_weather_measure_control() {
    if [ "$MEASURE_MODE" = reveal ]; then
        poll_measure_calls=$((poll_measure_calls + 1))
        [ "$poll_measure_calls" -ge 2 ] || return 1
        _weather_visible_xml="$ARTIFACTS/message.xml"
        printf 'message\n' > "$_weather_visible_xml"
        return 0
    fi
    return 1
}
ui_unique_label_bounds() {
    [ -s "$1" ] || return 0
    [ "$2" = 'Disable and clear location' ] || return 0
    printf '84 1901 996 1920\n'
}
if _weather_poll_action_state enable enabled 'message' \
    'Disable and clear location'; then
    printf 'result=ok\nmessage=%s\n' "$_weather_action_message"
else
    printf 'result=fail\n'
fi
EOF
weather_poll_absent=$(sh "$weather_poll_harness" "$weather_poll_body" \
    "$TMP_DIR/weather-poll-absent" absent) ||
    weather_poll_absent=
case "$weather_poll_absent" in
    *result=fail*)
        pass 'an unrevealed below-fold success line cannot pass from durable state alone'
        ;;
    *)
        fail 'an unrevealed below-fold success line cannot pass from durable state alone'
        ;;
esac
assert_true 'a failed poll retains the final poll XML and failure PNG' \
    test -s "$TMP_DIR/weather-poll-absent/weather-enabled-failure.png"
weather_poll_reveal=$(sh "$weather_poll_harness" "$weather_poll_body" \
    "$TMP_DIR/weather-poll-reveal" reveal) ||
    weather_poll_reveal=
case "$weather_poll_reveal" in
    *result=ok*message=*)
        pass 'the poll passes after the measured reveal exposes the message and identity'
        ;;
    *)
        fail 'the poll passes after the measured reveal exposes the message and identity'
        ;;
esac

# --- executable app-private probe/seed fixtures ----------------------------
# Simulate adb's argument joining and the device shell/run-as boundary. adb
# joins every argument after `shell` with spaces, so the old
# `run-as PKG sh -c "test -f path"` becomes `sh -c test -f path`; the inner
# `sh -c` runs only `test` and reports a real file missing. The fake run-as
# switches to the app data directory, so a wrong-UID/outside-path write is
# detectable in the separate device root.
weather_probe_body="$TMP_DIR/weather-private-probe.sh"
awk '/^_weather_probe_private_file\(\) \{/ { f = 1 }
     /^_weather_viewport\(\)/ { f = 0 }
     f' "$SMOKE" > "$weather_probe_body"
assert_true 'the app-private probe/seed functions are extractable' \
    test -s "$weather_probe_body"
assert_true 'the extracted probe block includes the seed helper' \
    grep -Fq '_weather_seed_cache() {' "$weather_probe_body"

weather_probe_harness="$TMP_DIR/weather-probe-harness.sh"
cat > "$weather_probe_harness" <<'EOF'
set -eu
BODY=$1
ROOT=$2
MODE=$3
LIB_FILE=$4
. "$LIB_FILE"
APPDIR="$ROOT/app"
DEVICE_ROOT="$ROOT/device"
FAKE_BIN="$ROOT/bin"
ARTIFACTS="$ROOT/artifacts"
mkdir -p "$APPDIR/no_backup/dotwel-weather-private/consent" \
    "$APPDIR/no_backup/dotwel-weather-private/cache" \
    "$DEVICE_ROOT/no_backup/dotwel-weather-private/cache" \
    "$FAKE_BIN" "$ARTIFACTS"
cat > "$FAKE_BIN/run-as" <<'RUNAS'
#!/bin/sh
pkg=$1
shift
if [ "${FAKE_PROBE_ERROR:-0}" = 1 ] && [ "$1" = test ]; then
    printf 'fake-run-as: transport failure\n' >&2
    exit 2
fi
cd "$APPDIR" || exit 1
exec "$@"
RUNAS
chmod +x "$FAKE_BIN/run-as"
export APPDIR
adb_cmd() {
    [ "$1" = shell ] || return 2
    shift
    if [ "$#" -eq 1 ]; then
        joined=$1
    else
        joined=
        for arg in "$@"; do
            joined="$joined${joined:+ }$arg"
        done
    fi
    (
        cd "$DEVICE_ROOT" || exit 1
        PATH="$FAKE_BIN:$PATH" FAKE_PROBE_ERROR="${FAKE_PROBE_ERROR:-0}" \
            sh -c "$joined"
    )
}
PKG=com.launchersim.debug
WEATHER_CONSENT_REL=no_backup/dotwel-weather-private/consent/consent-state.json
fail() {
    printf 'probe harness failure: %s\n' "$*" >&2
    exit 1
}
. "$BODY"
case "$MODE" in
    present)
        printf '%s\n' '{"version":1,"enabled":false,"generation":4,"label":null,"latitude":null,"longitude":null}' \
            > "$APPDIR/$WEATHER_CONSENT_REL"
        printf 'state=%s\n' "$(_weather_capture_consent present)"
        ;;
    absent)
        printf 'state=%s\n' "$(_weather_capture_consent absent)"
        ;;
    error)
        FAKE_PROBE_ERROR=1
        export FAKE_PROBE_ERROR
        printf 'state=%s\n' "$(_weather_capture_consent error)"
        ;;
    misquote)
        printf 'x\n' > "$APPDIR/$WEATHER_CONSENT_REL"
        misquote_rc=0
        adb_cmd shell run-as "$PKG" sh -c \
            "test -f '$WEATHER_CONSENT_REL'" || misquote_rc=$?
        printf 'misquote_rc=%s\n' "$misquote_rc"
        printf 'direct=%s\n' \
            "$(_weather_probe_private_file "$WEATHER_CONSENT_REL" direct)"
        ;;
    seed)
        cache_rel=no_backup/dotwel-weather-private/cache/fixture.weather
        if _weather_seed_cache "$cache_rel"; then
            printf 'seed=ok\n'
        else
            printf 'seed=failed\n'
        fi
        cp "$APPDIR/$cache_rel" "$ARTIFACTS/seed-readback.txt" 2>/dev/null || true
        printf 'seeded=%s\n' \
            "$(_weather_probe_private_file "$cache_rel" seeded)"
        rm -f "$APPDIR/$cache_rel"
        if _weather_cache_exists "$cache_rel" cleared; then
            printf 'cleared=present\n'
        else
            printf 'cleared=absent\n'
        fi
        ;;
esac
EOF

weather_probe_present=$(sh "$weather_probe_harness" "$weather_probe_body" \
    "$TMP_DIR/weather-probe-present" present "$LIB") ||
    weather_probe_present=
assert_eq 'an existing app-private consent file is not reported missing' \
    'state=disabled|4' "$weather_probe_present"
assert_true 'the existing-file probe records a zero exit' \
    grep -Fq 'exit=0' \
    "$TMP_DIR/weather-probe-present/artifacts/weather-probe-present.txt"

weather_probe_absent=$(sh "$weather_probe_harness" "$weather_probe_body" \
    "$TMP_DIR/weather-probe-absent-run" absent "$LIB") ||
    weather_probe_absent=
assert_eq 'a genuinely absent consent file is reported missing' \
    'state=missing' "$weather_probe_absent"
assert_true 'the absent probe records exit 1 with empty stderr' \
    grep -Fq 'exit=1' \
    "$TMP_DIR/weather-probe-absent-run/artifacts/weather-probe-absent.txt"
assert_true 'the absent probe lists the private directory as evidence' \
    grep -Fq 'private-directory-listing:' \
    "$TMP_DIR/weather-probe-absent-run/artifacts/weather-probe-absent.txt"

weather_probe_error=$(sh "$weather_probe_harness" "$weather_probe_body" \
    "$TMP_DIR/weather-probe-error" error "$LIB") ||
    weather_probe_error=
assert_eq 'a run-as/transport error is not reported as a missing file' \
    'state=probe-error' "$weather_probe_error"
assert_true 'the error probe retains the nonzero exit and stderr' \
    grep -Fq 'exit=2' \
    "$TMP_DIR/weather-probe-error/artifacts/weather-probe-error.txt"
assert_true 'the error probe retains the transport stderr text' \
    grep -Fq 'fake-run-as: transport failure' \
    "$TMP_DIR/weather-probe-error/artifacts/weather-probe-error.txt"
assert_true 'the error probe still lists the private directory' \
    grep -Fq 'private-directory-listing:' \
    "$TMP_DIR/weather-probe-error/artifacts/weather-probe-error.txt"

weather_probe_misquote=$(sh "$weather_probe_harness" "$weather_probe_body" \
    "$TMP_DIR/weather-probe-misquote" misquote "$LIB") ||
    weather_probe_misquote=
assert_eq 'the adb join misquote reproduces the false-missing probe' \
    'misquote_rc=1
direct=present' "$weather_probe_misquote"

weather_probe_seed=$(sh "$weather_probe_harness" "$weather_probe_body" \
    "$TMP_DIR/weather-probe-seed" seed "$LIB") ||
    weather_probe_seed=
assert_eq 'the cache fixture is created through the quoted app shell and cleared' \
    'seed=ok
seeded=present
cleared=absent' "$weather_probe_seed"
assert_true 'the seeded cache content round-trips exactly' \
    grep -Fq 'synthetic fixture for the cache-clear gate; not weather data' \
    "$TMP_DIR/weather-probe-seed/artifacts/seed-readback.txt"
assert_false 'the seed never writes to the outer device-shell path' \
    test -e \
    "$TMP_DIR/weather-probe-seed/device/no_backup/dotwel-weather-private/cache/fixture.weather"

# --- static regression on the weather widget placement gate -----------------

weather_widget_body="$TMP_DIR/capture_weather_widget.sh"
sed -n '/^capture_weather_widget() {/,/^}/p' "$SMOKE" > "$weather_widget_body"
[ -s "$weather_widget_body" ] || fail 'the weather widget gate body is present'

assert_true 'the weather widget gate checks the exact numeric id and Weather component' \
    grep -Fq 'appwidget_launcher_instance_is' "$weather_widget_body"
assert_false 'the weather widget gate never greps a bare id against the id<TAB>provider rows' \
    grep -Fq 'grep -qx "$_cww_new_id"' "$weather_widget_body"
assert_true 'the weather widget gate uses the state-aware picker decision' \
    grep -Fq 'widget_picker_weather_decision' "$weather_widget_body"
assert_true 'the weather widget gate branches on select, expand and reveal' \
    grep -Fq 'reveal|search)' "$weather_widget_body"
assert_false 'the weather widget gate never expands just because the strict pair is absent' \
    grep -Fq '[ -z "$_cww_candidate" ]' "$weather_widget_body"
assert_true 'the weather widget gate re-resolves a fresh XML after every expansion' \
    grep -Fq 'could not capture fresh picker XML after expanding Weather' \
    "$weather_widget_body"
assert_true 'the weather widget gate captures a PNG after every expansion' \
    grep -Fq 'weather-widget-expand-$_cww_expand.png' "$weather_widget_body"
assert_true 'the weather widget gate captures a PNG after every reveal scroll' \
    grep -Fq 'weather-widget-scroll-$_cww_scroll.png' "$weather_widget_body"
assert_true 'the weather widget tap uses the same two-stage destination confirmation' \
    grep -Fq '_weather_confirm_settings_screen weather-widget-tap' \
    "$weather_widget_body"
assert_false 'the weather widget tap no longer uses the single-snapshot identity' \
    grep -Fq 'weather_settings_screen_identity' "$weather_widget_body"

# --- static regression on the weather runtime gate --------------------------

weather_body="$TMP_DIR/capture_weather_settings.sh"
sed -n '/^# --- Weather settings runtime gate/,/^capture_drawer_attempt/p' \
    "$SMOKE" > "$weather_body"
[ -s "$weather_body" ] || fail 'the weather gate body is present'

assert_true 'the weather gate opens the real PreferenceActivity' \
    grep -Fq -- '-n "$PKG/$PREFERENCES_ACTIVITY"' "$weather_body"
assert_true 'the weather gate measures the Home screen preferences entry' \
    grep -Fq "clickable 'Icon size and home screen'" "$weather_body"
assert_true 'the weather gate taps the visible Weather settings entry' \
    grep -Fq "clickable 'Weather settings'" "$weather_body"
assert_true 'the weather gate measures all three real EditText fields by label' \
    grep -Fq "_weather_measure_field 'Longitude'" "$weather_body"
assert_false 'the weather gate never keys fields by their visible document index' \
    grep -Fq '_weather_measure_edit_text' "$weather_body"
assert_true 'the weather gate uses the two-stage destination confirmation' \
    grep -Fq '_weather_confirm_settings_screen' "$weather_body"
assert_false 'the weather gate no longer uses the single-snapshot identity' \
    grep -Fq 'weather_settings_screen_identity' "$weather_body"
assert_true 'stage one proves the exact resumed Preferences activity' \
    grep -Fq 'foreground_is_component "$_wcss_act" "$PKG" "$PREFERENCES_ACTIVITY"' \
    "$weather_body"
assert_true 'stage one requires the mode-correct privacy-notice identity' \
    grep -Fq 'weather_settings_notice_identity "$_wcss_xml" "$_wcss_mode"' \
    "$weather_body"
assert_true 'stage one retains the initial notice XML' \
    grep -Fq 'weather-$_wcss_tag-screen-notice.xml' "$weather_body"
assert_true 'stage one retains the initial notice PNG' \
    grep -Fq 'weather-$_wcss_tag-screen-notice.png' "$weather_body"
assert_true 'stage two measures the real Location label field' \
    grep -Fq "_weather_measure_field 'Location label'" "$weather_body"
assert_true 'stage two measures the real Latitude field' \
    grep -Fq "_weather_measure_field 'Latitude'" "$weather_body"
assert_true 'stage two retains the post-scroll fields XML' \
    grep -Fq 'weather-$_wcss_tag-screen-fields.xml' "$weather_body"
assert_true 'stage two retains the post-scroll fields PNG' \
    grep -Fq 'weather-$_wcss_tag-screen-fields.png' "$weather_body"
assert_true 'stage two re-proves the exact resumed activity after scrolling' \
    grep -Fq 'weather-$_wcss_tag-screen-fields-activities.txt' "$weather_body"
assert_true 'the combined provenance requires the notice and both fields' \
    grep -Fq 'weather_settings_screen_provenance' "$weather_body"
assert_true 'the fresh privacy copy is read from the retained initial notice XML' \
    grep -Fq 'grep -Fq '"'"'Before you enable'"'"' "$_weather_screen_notice_xml"' \
    "$weather_body"
assert_false 'the fresh privacy copy is not read from a post-scroll hierarchy' \
    grep -Fq 'grep -Fq '"'"'Before you enable'"'"' "$ARTIFACTS/weather-fresh.xml"' \
    "$weather_body"
assert_true 'the weather gate retains an immediate PNG for every screen probe' \
    grep -Fq 'weather-$_wcss_tag-screen-$_wcss_attempt.png' "$weather_body"
assert_true 'the weather gate retains a timeout/failure PNG' \
    grep -Fq 'weather-$_wws_tag-screen-failure.png' "$weather_body"
assert_true 'the weather gate scrolls from the measured target direction' \
    grep -Fq '_weather_scroll_direction' "$weather_body"
assert_true 'the weather gate captures post-action consent and PNG before asserting' \
    grep -Fq '_weather_capture_action_evidence enabled-postaction' "$weather_body"
assert_true 'the weather gate captures post-disable consent and PNG before asserting' \
    grep -Fq '_weather_capture_action_evidence disabled-postaction' "$weather_body"
assert_true 'the enabled poll records durable consent on every attempt' \
    grep -Fq '$_wpas_tag-poll-$_wpas_attempt' "$weather_body"
assert_true 'the enabled poll polls the real enabled state and message' \
    grep -Fq '_weather_poll_action_state enable enabled' "$weather_body"
assert_true 'the disabled poll polls the real disabled state and message' \
    grep -Fq '_weather_poll_action_state disable disabled' "$weather_body"
assert_true 'the enabled success message is the shipped debug setup-only confirmation' \
    grep -Fq "WEATHER_ENABLED_MESSAGE='$(prod_string dotwel_weather_message_enabled_debug)'" "$weather_body"
assert_true 'the runtime gate asserts the real debug network-off privacy copy' \
    grep -Fq "This debug build has network requests disabled" "$weather_body"
assert_true 'the runtime gate asserts the real device-IP disclosure' \
    grep -Fq "the IP address of this device" "$weather_body"
assert_true 'the runtime gate asserts the debug enabled status says nothing is sent' \
    grep -Fq 'no coordinates or device IP address are sent' "$weather_body"
assert_true 'the disabled success message is a shared exact constant' \
    grep -Fq "WEATHER_DISABLED_MESSAGE='Weather disabled. The location and its cached forecast were cleared; the shared provider throttle was kept.'" "$weather_body"
assert_true 'the enabled poll reveals the message through measured scrolling' \
    grep -Fq '_weather_measure_control label "$_wpas_message"' "$weather_body"
assert_true 'the enabled poll requires the real enabled control identity' \
    grep -Fq 'ui_unique_label_bounds "$_wpas_xml" "$_wpas_identity"' "$weather_body"
assert_true 'the action poll retains the scrolled message XML and PNG' \
    grep -Fq 'weather-$_wpas_tag-message-visible.png' "$weather_body"
assert_true 'the action poll retains a failure XML and PNG' \
    grep -Fq 'weather-$_wpas_tag-failure.png' "$weather_body"
assert_false 'the weather gate never greps the success message from an unscrolled XML' \
    grep -Eq "grep -Fq 'Weather (setup saved|disabled)\\." "$weather_body"
assert_true 'the enabled post-action proof reads the measured poll reveal' \
    grep -Fq '_cws_enabled_message=$_weather_action_message' "$weather_body"
assert_true 'the enabled post-action provenance uses the measured reveal and retained notice' \
    grep -Fq 'weather_action_screen_provenance enable "$_cws_enabled_message"' \
    "$weather_body"
assert_true 'the enabled post-action provenance re-proves the exact resumed Preferences' \
    grep -Fq 'weather-enabled-action-activities.txt' "$weather_body"
assert_true 'the enabled post-action provenance requires the mode and matching store' \
    grep -Fq '"$WEATHER_RUNTIME_NOTICE_MODE" \' "$weather_body" &&
    grep -Fq '"$_cws_consent"; then' "$weather_body"
assert_false 'the enabled gate never greps the offscreen Disable from the pre-scroll snapshot' \
    grep -Fq "'Disable and clear location' \"\$ARTIFACTS/weather-enabled.xml\"" \
    "$weather_body"
assert_false 'the enabled gate never greps the saved label from the pre-scroll snapshot' \
    grep -Fq "'Emulator test' \"\$ARTIFACTS/weather-enabled.xml\"" "$weather_body"
assert_true 'the enabled gate still retains the pre-scroll audit capture unchanged' \
    grep -Fq '_weather_snapshot enabled' "$weather_body"
assert_true 'the disabled post-action proof reads the measured poll reveal' \
    grep -Fq '_cws_disabled_message=$_weather_action_message' "$weather_body"
assert_true 'the disabled post-action provenance uses the measured reveal and retained notice' \
    grep -Fq 'weather_action_screen_provenance disable "$_cws_disabled_message"' \
    "$weather_body"
assert_true 'the disabled post-action provenance re-proves the exact resumed Preferences' \
    grep -Fq 'weather-disabled-action-activities.txt' "$weather_body"
assert_false 'the disabled gate never greps Save and enable from the pre-scroll snapshot' \
    grep -Fq "grep -Fq 'Save and enable' \"\$ARTIFACTS/weather-disabled.xml\"" \
    "$weather_body"
assert_true 'the disabled gate still retains the pre-scroll audit capture unchanged' \
    grep -Fq '_weather_snapshot disabled' "$weather_body"
assert_true 'the valid longitude keeps a focused capture before blur' \
    grep -Fq 'weather-valid-longitude-focused.png' "$weather_body"
assert_true 'the focused capture is asserted to report Longitude focused' \
    grep -Fq "weather-valid-longitude-focused.xml\" 'Longitude')\" = true" \
    "$weather_body"
assert_true 'focus is moved to the measured latitude field' \
    grep -Fq "_weather_measure_field 'Latitude' valid-blur-field" "$weather_body"
assert_true 'the keyboard is dismissed after focus moves' \
    grep -Fq '_weather_hide_ime valid-blur' "$weather_body"
assert_true 'the blurred capture asserts Longitude is not focused' \
    grep -Fq "weather-valid-longitude-blurred.xml\" 'Longitude')\" = false" \
    "$weather_body"
assert_true 'the blurred capture asserts latitude took focus unchanged' \
    grep -Fq "weather-valid-longitude-blurred.xml\" 'Latitude')\" = true" \
    "$weather_body"
assert_true 'the valid longitude keeps a blurred capture after focus moves' \
    grep -Fq 'weather-valid-longitude-blurred.png' "$weather_body"
assert_false 'the blurred capture is not named from a hint tap' \
    grep -Fq 'valid-blur-target' "$weather_body"
assert_true 'the blurred valid longitude asserts no semantic validation error' \
    grep -Fq 'the valid longitude field exposed a semantic validation error after blur' "$weather_body"
assert_true 'the weather gate measures the existing draft before typing' \
    grep -Fq 'the weather field $_wty_tag still held' "$weather_body"
assert_true 'the weather gate clears a measured existing draft before typing' \
    grep -Fq 'KEYCODE_MOVE_END' "$weather_body"
assert_true 'the weather gate uses the measured consent checkbox state' \
    grep -Fq '_weather_measure_checkbox' "$weather_body"
assert_true 'the weather gate dismisses a shown IME instead of guessing' \
    grep -Fq '_weather_hide_ime' "$weather_body"
assert_true 'the weather gate proves Back returns to the Home screen preferences' \
    grep -Fq '_weather_back_to_home_screen' "$weather_body"
assert_true 'the weather gate reads the app-private consent store' \
    grep -Fq 'WEATHER_CONSENT_REL' "$weather_body"
assert_true 'the weather gate reads the app-private cache path' \
    grep -Fq 'WEATHER_CACHE_REL' "$weather_body"
assert_true 'the app-private probe calls run-as test without sh -c' \
    grep -Fq 'adb_cmd shell run-as "$PKG" test -f "$_wpp_path"' "$weather_body"
assert_false 'the app-private probe never uses an unquoted run-as sh -c' \
    grep -Fq 'run-as "$PKG" sh -c' "$weather_body"
assert_true 'the probe records its exit and stderr evidence' \
    grep -Fq 'weather-probe-$_wpp_tag.txt' "$weather_body"
assert_true 'the probe lists the private directory after a failed test' \
    grep -Fq 'private-directory-listing:' "$weather_body"
assert_true 'the consent reader maps a probe failure to probe-error' \
    grep -Fq '_wcc_state=probe-error' "$weather_body"
assert_true 'the cache seed builds one fully quoted device command' \
    grep -Fq 'weather_app_shell_command "$PKG" "$_wsc_script"' "$weather_body"
assert_true 'the cache seed pipes the fixture into the single quoted command' \
    grep -Fq 'adb_cmd shell "$_wsc_command"' "$weather_body"
assert_true 'the cache seed reads back and compares the exact bytes' \
    grep -Fq 'cmp -s "$_wsc_expected" "$_wsc_actual"' "$weather_body"
assert_false 'the cache seed never writes through an unquoted sh -c' \
    grep -Fq 'sh -c "mkdir -p' "$weather_body"
assert_true 'the weather gate derives the production cache filename' \
    grep -Fq 'weather_cache_filename' "$weather_body"
assert_true 'the weather gate seeds a synthetic cache fixture only' \
    grep -Fq 'synthetic fixture for the cache-clear gate' "$weather_body"
assert_true 'the weather gate force-stops and relaunches for persistence' \
    grep -Fq '_weather_restart' "$weather_body"
assert_true 'the weather gate requires the fresh Enable control to be disabled' \
    grep -Fq "= false ] ||" "$weather_body"
assert_true 'the weather gate checks the saved synthetic label' \
    grep -Fq '|Emulator test|60.0000|10.0000' "$weather_body"
assert_true 'the weather gate checks the disabled final state' \
    grep -Fq '_cws_final' "$weather_body"
assert_true 'the weather gate retains complete screen PNGs' \
    grep -Fq 'weather-fresh.png' "$weather_body"
assert_true 'the weather gate retains enabled and disabled PNGs' \
    grep -Fq 'weather-enabled.png' "$weather_body"
assert_true 'the weather gate checks the no-backup backed-up file boundary' \
    grep -Fq 'weather-backed-up-prefs.xml' "$weather_body"
assert_false 'the weather gate never guesses a tap coordinate' \
    grep -Eq 'input tap [0-9]' "$weather_body"
assert_false 'the weather gate never clears app data or uninstalls' \
    grep -Eq 'pm clear|adb .*uninstall|run-as "\$PKG" rm -rf' "$weather_body"
assert_false 'the weather gate never opens a browser or provider link' \
    grep -Eq 'android.intent.action.VIEW|https?://|Terms of Service|ProviderLink' "$weather_body"
assert_false 'the weather gate never performs a network request' \
    grep -Eq 'curl|wget|OkHttp|MetWeatherRepository' "$weather_body"
assert_false 'the weather gate never requests a location permission' \
    grep -Eq 'ACCESS_(FINE|COARSE|BACKGROUND)_LOCATION' "$weather_body"
assert_false 'the weather gate never binds a widget or edits the workspace' \
    grep -Eq 'bindAppWidget|LauncherSettings|content://|sqlite|launcher.db' "$weather_body"
assert_false 'the weather gate never writes a preference directly' \
    grep -Eq 'settings put|putString|putBoolean|\.apply\(\)|commit\(\)' "$weather_body"

weather_call_line=$(grep -n '^capture_weather_settings$' "$SMOKE" | sed -n '1s/:.*//p')
customize_call_line=$(grep -n '^capture_customization_settings$' "$SMOKE" | sed -n '1s/:.*//p')
device_shortcuts_line=$(grep -n '^exercise_device_settings_shortcuts$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$weather_call_line" ] && [ -n "$customize_call_line" ] &&
    [ -n "$device_shortcuts_line" ] &&
    [ "$customize_call_line" -lt "$weather_call_line" ] &&
    [ "$weather_call_line" -lt "$device_shortcuts_line" ]; then
    pass 'the weather gate runs after the customization gate and before device shortcuts'
else
    fail 'the weather gate runs after the customization gate and before device shortcuts'
fi

# --- static regression on the customization runtime gate --------------------

customization_body="$TMP_DIR/capture_customization_settings.sh"
sed -n '/^capture_customization_settings() {/,/^}/p' "$SMOKE" > "$customization_body"

assert_true 'the customization gate opens the real PreferenceActivity' \
    grep -Fq -- '-n "$PKG/$PREFERENCES_ACTIVITY"' "$customization_body"
assert_false 'the customization gate passes no diagnostic sample extra' \
    grep -Fq 'THEME_SAMPLE_EXTRA' "$customization_body"
assert_true 'the customization gate requires the unique dashboard entries' \
    grep -Fq "'Icon size and home screen'" "$customization_body"
assert_true 'the customization gate requires the top slider and percentage' \
    grep -Fq 'ui_top_slider_bounds' "$customization_body"
assert_true 'the customization gate requires a unique Browse widgets control' \
    grep -Fq "'Browse widgets'" "$customization_body"
assert_true 'the customization gate opens the real native picker helper' \
    grep -Fq 'widget_picker_is_ready' "$customization_body"
assert_true 'the customization gate proves Back returns the primary HOME' \
    grep -Fq 'primary_home_is_ready' "$customization_body"
assert_true 'the customization gate repeats an explicit Browse tap' \
    grep -Fq 'second explicit Browse widgets tap' "$customization_body"
assert_true 'the customization gate sends ordinary HOME repeats' \
    grep -Fq 'KEYCODE_HOME' "$customization_body"
assert_true 'the customization gate bounds TAB focus to 12 steps' \
    grep -Fq 'while [ "$_ccs_tab" -lt 12 ]' "$customization_body"
assert_true 'the customization gate requires an actually focused SeekBar' \
    grep -Fq 'ui_focused_slider_bounds' "$customization_body"
assert_true 'the customization gate calls the measured order helper' \
    grep -Fq 'customization_controls_in_order' "$customization_body"
assert_false 'the customization gate never sets a quoted bounds positional' \
    grep -Eq 'set -- "?\$_ccs_(customize|slider|browse)"' "$customization_body"
assert_true 'the customization gate compares restored widget-host bounds' \
    grep -Fq 'customization-widget-host-bounds-baseline.sorted' "$customization_body"
assert_true 'the customization gate compares Home/Lock wallpaper IDs' \
    grep -Fq 'wallpaper_ids_from_dump' "$customization_body"
assert_true 'the customization gate compares the normalized wallpaper component' \
    grep -Fq 'wallpaper_component_from_dump' "$customization_body"
assert_false 'the customization gate never claims a lock preference value proof' \
    grep -Fq 'lock_home_screen=present' "$customization_body"
assert_true 'the customization gate steps the focused slider with DPAD' \
    grep -Fq 'KEYCODE_DPAD_RIGHT' "$customization_body"
assert_true 'the customization gate expects exactly one one-percentage-point step' \
    grep -Fq '_ccs_expected_percent=$((_ccs_initial_percent + 1))' "$customization_body"
assert_true 'the customization gate uses a one-percentage-point reverse step' \
    grep -Fq '_ccs_expected_percent=$((_ccs_initial_percent - 1))' "$customization_body"
assert_true 'the customization gate rejects any delta other than one point' \
    grep -Fq '[ "$_ccs_delta" -eq 1 ] || [ "$_ccs_delta" -eq -1 ]' "$customization_body"
assert_true 'the customization gate compares the numeric stored factor' \
    grep -Fq 'datastore_float_factor' "$customization_body"
assert_true 'the customization gate checks the stored factor after the step' \
    grep -Fq 'customization-datastore-factor-after-step.txt' "$customization_body"
assert_true 'the customization gate checks the restored stored factor' \
    grep -Fq 'customization-datastore-factor-restored.txt' "$customization_body"
assert_true 'the customization gate compares the exact stored float bytes' \
    grep -Fq '_ccs_ds_restored_hex' "$customization_body"
assert_false 'the customization gate never raw-compares the datastore file' \
    grep -Eq 'cmp .*datastore.*\.pb' "$customization_body"
assert_true 'the customization gate restores the original percentage' \
    grep -Fq 'restored' "$customization_body"

HOME_SCREEN_PREFS="$ROOT_DIR/lawnchair/src/app/lawnchair/ui/preferences/destinations/HomeScreenPreferences.kt"
customize_block="$TMP_DIR/home-screen-customize.kt"
sed -n '/customize_launcher_label/,/browse_widgets_label/p' \
    "$HOME_SCREEN_PREFS" > "$customize_block"
assert_true 'the Play home icon slider uses one-percentage-point steps' \
    grep -Fq 'step = 0.01f' "$customize_block"
assert_true 'the Play home icon slider keeps the full 50-150 range' \
    grep -Fq 'valueRange = 0.5F..1.5F' "$customize_block"
non_play_block="$TMP_DIR/home-screen-non-play.kt"
sed -n '/if (!isPlayStoreFlavor()) {/,/show_labels/p' \
    "$HOME_SCREEN_PREFS" > "$non_play_block"
assert_true 'the non-Play icon slider keeps its inherited 0.1 step' \
    grep -Fq 'step = 0.1f' "$non_play_block"
assert_true 'the pure slider math regression test exists' \
    test -f "$ROOT_DIR/tests/unit/java/app/lawnchair/ui/preferences/components/controls/SliderValueMathTest.kt"
assert_true 'the slider math is extracted into a pure production file' \
    test -f "$ROOT_DIR/lawnchair/src/app/lawnchair/ui/preferences/components/controls/SliderValueMath.kt"
assert_true 'the customization gate retains HOME before/after PNG evidence' \
    grep -Fq 'customization-home-after-size.png' "$customization_body"
assert_false 'the customization gate never writes a preference' \
    grep -Eq 'settings put|putString|putBoolean|editSp|commit\(\)|\.apply\(\)' \
    "$customization_body"
assert_false 'the customization gate never binds a widget directly' \
    grep -Eq 'bindAppWidget|addItemToDatabase|LauncherSettings|content://|sqlite' \
    "$customization_body"
assert_false 'the customization gate never guesses a tap coordinate' \
    grep -Eq 'input tap [0-9]' "$customization_body"

customize_state_line=$(grep -n '^capture_customization_settings$' "$SMOKE" | sed -n '1s/:.*//p')
clean_line=$(grep -n '^capture_clean_home_theme$' "$SMOKE" | sed -n '1s/:.*//p')
widgets_call_line=$(grep -n '^capture_widgets_picker$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$clean_line" ] && [ -n "$customize_state_line" ] &&
    [ -n "$widgets_call_line" ] &&
    [ "$clean_line" -lt "$customize_state_line" ] &&
    [ "$customize_state_line" -lt "$widgets_call_line" ]; then
    pass 'the customization gate runs after the own-home baseline and before third-party placement'
else
    fail 'the customization gate runs after the own-home baseline and before third-party placement'
fi

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke tests passed\n'
