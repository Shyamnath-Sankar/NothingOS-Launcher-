#!/bin/sh
# Focused regression tests for scripts/emulator-smoke-lib.sh and the app-launch
# foreground check in scripts/emulator-smoke.sh.
# Run with: sh scripts/emulator-smoke-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB="$SCRIPT_DIR/emulator-smoke-lib.sh"
SMOKE="$SCRIPT_DIR/emulator-smoke.sh"
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
assert_true 'the drawer swipe uses a 500 ms duration for MOVE delivery' \
    grep -Fq 'swipe_duration=500' "$open_body"
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
consent_call_line=$(grep -n '^verify_default_home_consent$' "$SMOKE" | sed -n '1s/:.*//p')
grant_line=$(grep -n 'add-role-holder' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$consent_call_line" ] && [ -n "$grant_line" ] &&
    [ "$consent_call_line" -lt "$grant_line" ]; then
    pass 'the consent capture runs before the smoke grants the role'
else
    fail 'the consent capture runs before the smoke grants the role'
fi

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke tests passed\n'
