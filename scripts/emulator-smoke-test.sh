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

widget_add_xml="$TMP_DIR/widget-add.xml"
cat > "$widget_add_xml" <<'EOF'
<hierarchy rotation="0">
  <node index="0" text="Add" resource-id="com.launchernos.dotwellabs.debug:id/widget_add_button" class="android.widget.Button" content-desc="Add Clock widget" clickable="true" bounds="[200,800][400,900]" />
</hierarchy>
EOF
assert_eq 'the exposed widget Add button is selected by its resource id' \
    '200 800 400 900' \
    "$(widget_picker_add_button_bounds "$widget_add_xml")"
assert_eq 'an English Add label without the add-button id is rejected' \
    '' \
    "$(widget_picker_add_button_bounds "$home_xml")"

placed_home_xml="$TMP_DIR/placed-home.xml"
cat > "$placed_home_xml" <<'EOF'
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" content-desc="" clickable="false" bounds="[0,0][1080,1920]">
    <node index="0" text="4:10" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,100][200,160]" />
    <node index="1" text="FRI 21 NOV" class="android.widget.TextView" content-desc="" clickable="false" bounds="[40,170][300,210]" />
    <node index="2" text="" resource-id="com.launchernos.dotwellabs.debug:id/appwidget" class="app.lawnchair.LawnchairAppWidgetHostView" content-desc="Clock" clickable="false" long-clickable="true" bounds="[40,400][500,700]" />
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

assert_eq 'the widget drag fallback targets the measured right workspace, away from centre' \
    '810 834' \
    "$(widget_drop_target "$actual_home_xml")"

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
assert_false 'a HOME whose whole drop band is occupied has no unsafe widget drop target' \
    widget_drop_target "$blocked_home_xml"

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
    grep -Fq 'am start' "$widgets_body"
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
assert_true 'the widgets capture taps the measured preview, not a fixed point' \
    grep -Fq 'tap_center_of_bounds "$_cwp_preview"' "$widgets_body"
assert_true 'the widgets capture taps the measured Add button, not a fixed point' \
    grep -Fq 'tap_center_of_bounds "$_cwp_add"' "$widgets_body"
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
assert_true 'the widgets capture has a measured drag fallback' \
    grep -Fq 'widget_drop_target' "$widgets_body"
assert_true 'the widgets capture saves the last failed placement stage before cleanup' \
    grep -Fq 'widgets-add-last' "$widgets_body"
assert_false 'the widgets capture never binds a widget or edits the database directly' \
    grep -Eq 'bindAppWidget|addItemToDatabase|LauncherSettings|content://|sqlite' "$widgets_body"
assert_false 'the widgets capture never uses a fixed Add tap coordinate' \
    grep -Eq 'input tap [0-9]+ [0-9]+' "$widgets_body"

placed_line=$(grep -n 'widgets-home-placed.xml' "$widgets_body" | sed -n '1s/:.*//p')
home_key_line=$(grep -n 'return_home widgets-picker' "$widgets_body" | sed -n '1s/:.*//p')
after_home_line=$(grep -n 'widgets-home-after-home.xml' "$widgets_body" | sed -n '1s/:.*//p')
if [ -n "$placed_line" ] && [ -n "$home_key_line" ] && [ -n "$after_home_line" ] &&
    [ "$placed_line" -lt "$home_key_line" ] &&
    [ "$home_key_line" -lt "$after_home_line" ]; then
    pass 'the placed widget is captured before HOME and re-checked after HOME'
else
    fail 'the placed widget is captured before HOME and re-checked after HOME'
fi

grid_call_line=$(grep -n '^capture_grid_settings$' "$SMOKE" | sed -n '1s/:.*//p')
widgets_call_line=$(grep -n '^capture_widgets_picker$' "$SMOKE" | sed -n '1s/:.*//p')
drawer_call_line=$(grep -n '^exercise_app_drawer$' "$SMOKE" | sed -n '1s/:.*//p')
if [ -n "$grid_call_line" ] && [ -n "$widgets_call_line" ] && [ -n "$drawer_call_line" ] &&
    [ "$grid_call_line" -lt "$widgets_call_line" ] &&
    [ "$widgets_call_line" -lt "$drawer_call_line" ]; then
    pass 'the grid and widget captures run before the existing drawer flow'
else
    fail 'the grid and widget captures run before the existing drawer flow'
fi

assert_true 'the role consent cancel flow is still present' \
    grep -Fq 'verify_default_home_consent' "$SMOKE"
assert_true 'the drawer still uses the bounded 1500 ms swipe' \
    grep -Fq 'swipe_duration=1500' "$SMOKE"
assert_true 'the drawer still has four bounded attempts' \
    grep -Fq 'max_attempts=4' "$SMOKE"
assert_true 'the exact Settings foreground check is still present' \
    grep -Fq 'wait_for_foreground com.android.settings' "$SMOKE"

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke tests passed\n'
