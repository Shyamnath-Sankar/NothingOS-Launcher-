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
    </node>
  </node>
</hierarchy>
EOF
assert_eq 'the HOME widget proof reads the real clock child text' \
    '3:07' "$(home_widget_clock_text "$home_widgets_xml")"
assert_eq 'the HOME widget proof reads the real battery description' \
    '87%' "$(home_widget_battery_description "$home_widgets_xml")"
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

clean_home_body="$TMP_DIR/capture_clean_home_theme.sh"
sed -n '/^capture_clean_home_theme() {/,/^}/p' "$SMOKE" > "$clean_home_body"

home_verify_body="$TMP_DIR/verify_nothing_home.sh"
sed -n '/^verify_nothing_home() {/,/^}/p' "$SMOKE" > "$home_verify_body"

home_widgets_body="$TMP_DIR/verify_home_widgets.sh"
sed -n '/^verify_home_widgets() {/,/^}/p' "$SMOKE" > "$home_widgets_body"

own_widget_setup_body="$TMP_DIR/complete_own_widget_setup.sh"
sed -n '/^complete_own_widget_setup() {/,/^}/p' "$SMOKE" > "$own_widget_setup_body"

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
assert_true 'the own-widget setup keeps at most two rounds' \
    grep -Fq '_cows_max_rounds=2' "$own_widget_setup_body"
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
assert_true 'the widget binding check requires a launcher-owned instance id' \
    grep -Fq 'appwidget_launcher_instances' "$home_widgets_body"
assert_true 'the widget binding check requires distinct clock and battery ids' \
    grep -Fq '_vhw_clock_id" != "$_vhw_battery_id' "$home_widgets_body"
assert_true 'the widget binding check requires the real clock child id' \
    grep -Fq 'nothingui_clock_time' "$home_widgets_body"
assert_true 'the widget binding check requires the real battery child id' \
    grep -Fq 'nothingui_battery_art' "$home_widgets_body"
assert_true 'the widget binding check requires live clock text' \
    grep -Fq 'home_widget_clock_text_is_live' "$home_widgets_body"
assert_true 'the widget binding check requires a real battery description' \
    grep -Fq 'home_widget_battery_description_is_real' "$home_widgets_body"
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
assert_true 'the widgets capture requires the launcher identity and widget name' \
    grep -Fq '"$EXPECTED_LABEL" "$_cwp_provider_title"' "$widgets_body"
assert_true 'the widgets capture stores the bind consent XML' \
    grep -Fq 'widgets-bind-consent.xml' "$widgets_body"
assert_true 'the widgets capture stores the bind consent PNG' \
    grep -Fq 'widgets-bind-consent.png' "$widgets_body"
assert_true 'the widgets capture measures the android:id/button1 Create control' \
    grep -Fq 'widget_bind_create_button_bounds' "$widgets_body"
create_bounds_context=$(grep -A2 -F 'widget_bind_create_button_bounds' "$widgets_body" || true)
printf '%s\n' "$create_bounds_context" > "$TMP_DIR/create-bounds-context.txt"
assert_true 'the widgets capture passes the launcher/widget identity to the Create bounds' \
    grep -Fq '"$EXPECTED_LABEL" "$_cwp_provider_title"' "$TMP_DIR/create-bounds-context.txt"
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
assert_true 'the widgets capture keeps the placed widget above the measured dock' \
    grep -Fq 'ui_dock_top' "$widgets_body"
assert_true 'the widgets capture keeps the placed widget below the measured header' \
    grep -Fq 'ui_header_bottom' "$widgets_body"
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
grid_call_line=$(grep -n '^capture_grid_settings$' "$SMOKE" | sed -n '1s/:.*//p')
widgets_call_line=$(grep -n '^capture_widgets_picker$' "$SMOKE" | sed -n '1s/:.*//p')
drawer_call_line=$(grep -n '^exercise_app_drawer$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$clean_home_call_line" ] && [ -n "$grid_call_line" ] &&
    [ -n "$widgets_call_line" ] && [ -n "$drawer_call_line" ] &&
    [ "$clean_home_call_line" -lt "$grid_call_line" ] &&
    [ "$grid_call_line" -lt "$widgets_call_line" ] &&
    [ "$widgets_call_line" -lt "$drawer_call_line" ]; then
    pass 'the clean-home, grid and widget captures run before the existing drawer flow'
else
    fail 'the clean-home, grid and widget captures run before the existing drawer flow'
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

# --- static regression on the real Play native popup/drawer captures ---------

native_theme_body="$TMP_DIR/capture_native_surfaces_theme.sh"
sed -n '/^capture_native_surfaces_theme() {/,/^}/p' "$SMOKE" > "$native_theme_body"

native_popup_body="$TMP_DIR/capture_native_home_popup.sh"
sed -n '/^capture_native_home_popup() {/,/^}/p' "$SMOKE" > "$native_popup_body"

assert_true 'the native surfaces capture uses the system night yes/no modes' \
    grep -Fq 'for _cnst_mode in yes no; do' "$native_theme_body"
assert_true 'the native surfaces capture switches the emulator night mode' \
    grep -Fq 'cmd uimode night "$_cnst_mode"' "$native_theme_body"
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

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke tests passed\n'
