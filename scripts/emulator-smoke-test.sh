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
assert_eq 'the drawer swipe starts above the measured dock, not at 75 percent' \
    '540 1208 540 384' \
    "$(drawer_swipe_target 1080 1920 1400)"
assert_eq 'the drawer swipe falls back to 55 percent without a dock measurement' \
    '540 1056 540 384' \
    "$(drawer_swipe_target 1080 1920 '')"
assert_eq 'a high dock still keeps the swipe above it' \
    '540 1608 540 384' \
    "$(drawer_swipe_target 1080 1920 1800)"
assert_false 'an invalid display width cannot produce a swipe target' \
    drawer_swipe_target 0 1920 1400

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

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke tests passed\n'
