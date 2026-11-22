#!/bin/sh
# Static guard for the Play-only NothingUI clock/battery home widgets.
#
# Usage: scripts/nothingui-widget-guard.sh [repo-root]
#
# This is deliberately source-level: the launcher build is not available in every environment.
# It pins the Play-only registration, native TextClock, real sticky battery source, API 37 bitmap
# budget, fresh-install seeding, slim QSB/icon defaults and third-party attribution. A fixture test
# (nothingui-widget-guard-test.sh) proves each assertion can fail.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

fail() {
    printf 'nothingui-widget-guard: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [ -f "$ROOT/$1" ] || fail "missing required file: $1"
}

require_grep() {
    file=$1
    needle=$2
    message=$3
    grep -Fq "$needle" "$ROOT/$file" || fail "$message"
}

forbid_grep() {
    file=$1
    needle=$2
    message=$3
    if grep -Fq "$needle" "$ROOT/$file"; then
        fail "$message"
    fi
}

WIDGET_DIR=lawnchair/src/app/nothingui/widgets
CLOCK_PROVIDER=$WIDGET_DIR/NothingUiClockWidgetProvider.kt
BATTERY_PROVIDER=$WIDGET_DIR/NothingUiBatteryWidgetProvider.kt
BATTERY_MONITOR=$WIDGET_DIR/NothingUiBatteryMonitor.kt
BATTERY_ART=$WIDGET_DIR/NothingUiBatteryArt.kt
BUDGET=$WIDGET_DIR/NothingUiWidgetBudget.kt
DOT_TEXT=$WIDGET_DIR/DotText.kt
CLOCK_LAYOUT=lawnchair/res/layout/nothingui_widget_clock.xml
BATTERY_LAYOUT=lawnchair/res/layout/nothingui_widget_battery.xml
CLOCK_INFO=lawnchair/res/xml/nothingui_clock_widget_info.xml
BATTERY_INFO=lawnchair/res/xml/nothingui_battery_widget_info.xml
PLAY_MANIFEST=play/AndroidManifest.xml
DEFAULT_LAYOUT=play/res/xml/default_workspace_4x5.xml
PLAY_CONFIG=play/res/values/config.xml
PLAY_DIMENS=play/res/values/dimens.xml
LAUNCHER=lawnchair/src/app/lawnchair/LawnchairLauncher.kt
PARSER=src/com/android/launcher3/AutoInstallsLayout.java
NOTICE=NOTICE.md
MIT=licenses/third-party/dotline-widgets-MIT.txt

for file in \
    "$CLOCK_PROVIDER" "$BATTERY_PROVIDER" "$BATTERY_MONITOR" "$BATTERY_ART" \
    "$BUDGET" "$DOT_TEXT" "$CLOCK_LAYOUT" "$BATTERY_LAYOUT" "$CLOCK_INFO" \
    "$BATTERY_INFO" "$PLAY_MANIFEST" "$DEFAULT_LAYOUT" "$PLAY_CONFIG" \
    "$PLAY_DIMENS" "$LAUNCHER" "$PARSER" "$NOTICE" "$MIT"; do
    require_file "$file"
done

# Play-only registration. Both receivers must be present and not exported; a manifest receiver
# also must not claim the sticky battery action, which cannot be delivered to a manifest receiver.
require_grep "$PLAY_MANIFEST" 'app.nothingui.widgets.NothingUiClockWidgetProvider' \
    "the Play manifest does not register the clock widget"
require_grep "$PLAY_MANIFEST" 'app.nothingui.widgets.NothingUiBatteryWidgetProvider' \
    "the Play manifest does not register the battery widget"
for receiver in NothingUiClockWidgetProvider NothingUiBatteryWidgetProvider; do
    if ! grep -A6 "app.nothingui.widgets.$receiver" "$ROOT/$PLAY_MANIFEST" |
        grep -Fq 'android:exported="false"'; then
        fail "$receiver is exported or has no exported=false declaration"
    fi
done
forbid_grep "$PLAY_MANIFEST" 'android.intent.action.BATTERY_CHANGED' \
    "the Play manifest tries to receive sticky BATTERY_CHANGED"
forbid_grep "$PLAY_MANIFEST" 'BATTERY_STATS' \
    "the Play manifest adds the privileged BATTERY_STATS permission"

# Clock: native TextClock, bundled Doto OFL, correct 12/24-hour formats, no alarm/foreground hack.
require_grep "$CLOCK_LAYOUT" '<TextClock' \
    "the clock widget is not a native TextClock"
require_grep "$CLOCK_LAYOUT" 'android:format12Hour="h:mm"' \
    "the clock widget does not use a 12-hour h:mm format"
require_grep "$CLOCK_LAYOUT" 'android:format24Hour="HH:mm"' \
    "the clock widget does not use a 24-hour HH:mm format"
require_grep "$CLOCK_LAYOUT" '@font/doto_bold' \
    "the clock widget does not use the bundled Doto font"
require_grep "$CLOCK_LAYOUT" 'android:autoSizeTextType="uniform"' \
    "the clock widget does not scale to the 2x2 cell"
require_grep "$CLOCK_INFO" 'android:updatePeriodMillis="0"' \
    "the clock widget should rely on TextClock, not a periodic update"
forbid_grep "$CLOCK_PROVIDER" 'AlarmManager' \
    "the clock widget uses an alarm instead of TextClock"
forbid_grep "$CLOCK_PROVIDER" 'Service' \
    "the clock widget uses a service instead of TextClock"

# Battery: real sticky system broadcast, safe unknown fallback, full updates, resize refresh.
require_grep "$BATTERY_PROVIDER" 'Intent.ACTION_BATTERY_CHANGED' \
    "the battery widget does not use the sticky battery broadcast"
require_grep "$BATTERY_PROVIDER" 'BatteryManager.EXTRA_LEVEL' \
    "the battery widget does not read the real battery level"
require_grep "$BATTERY_PROVIDER" 'BatteryManager.EXTRA_SCALE' \
    "the battery widget does not read the real battery scale"
require_grep "$BATTERY_PROVIDER" 'UNKNOWN_PERCENT' \
    "the battery widget has no unknown-value fallback"
require_grep "$BATTERY_PROVIDER" 'onAppWidgetOptionsChanged' \
    "the battery widget does not refresh on resize"
require_grep "$BATTERY_PROVIDER" 'updateAppWidget(' \
    "the battery widget does not use full RemoteViews updates"
forbid_grep "$BATTERY_PROVIDER" 'partiallyUpdateAppWidget' \
    "the battery widget uses partial RemoteViews updates"
require_grep "$BATTERY_PROVIDER" 'ACTION_POWER_USAGE_SUMMARY' \
    "the battery widget does not use a safe battery settings tap"
forbid_grep "$BATTERY_PROVIDER" 'Random' \
    "the battery widget contains fake/random data"

# Lifecycle-bounded receiver: BATTERY_CHANGED is sticky and cannot be a manifest receiver.
require_grep "$BATTERY_MONITOR" 'ContextCompat.registerReceiver' \
    "the battery monitor does not register a receiver"
require_grep "$BATTERY_MONITOR" 'RECEIVER_NOT_EXPORTED' \
    "the battery monitor receiver is not non-exported"
require_grep "$BATTERY_MONITOR" 'Intent.ACTION_BATTERY_CHANGED' \
    "the battery monitor does not listen for BATTERY_CHANGED"
forbid_grep "$BATTERY_MONITOR" 'Service' \
    "the battery monitor uses a service"
forbid_grep "$BATTERY_MONITOR" 'WakeLock' \
    "the battery monitor holds a wake lock"

# API 37 budget: display bounds from WindowMetrics, 6x cap, bounded art, no displayMetrics budget.
require_grep "$BUDGET" 'currentWindowMetrics' \
    "the widget budget does not use WindowMetrics"
require_grep "$BUDGET" 'CAP_FACTOR = 6L' \
    "the widget budget does not apply the API 37 6x cap"
require_grep "$BUDGET" 'MAX_DIMENSION_PX' \
    "the widget art is not bounded to the widget size"
forbid_grep "$BUDGET" 'displayMetrics' \
    "the widget budget still reads displayMetrics"
require_grep "$BATTERY_ART" 'ARGB_8888' \
    "the battery art is not rendered as an explicit bitmap"
forbid_grep "$BATTERY_ART" 'Random' \
    "the battery art contains fake/random data"

# Adapted MIT renderer must keep the attribution and stay in our package.
require_grep "$DOT_TEXT" 'package app.nothingui.widgets' \
    "DotText was not adapted into our widget package"
require_grep "$DOT_TEXT" 'MAX_BYTES' \
    "DotText has no bitmap cache bound"
require_grep "$MIT" 'MIT License' \
    "the dotline-widgets MIT license text is missing"
require_grep "$MIT" 'oceansde012' \
    "the dotline-widgets copyright holder is missing"
require_grep "$MIT" 'b53a12aaf09f3572582dbd2c4278ea65f6a83306' \
    "the dotline-widgets source commit is missing"
require_grep "$NOTICE" 'dotline-widgets' \
    "NOTICE.md does not mention the adapted dotline-widgets renderer"

# Fresh-install Play default: both 2x2 widgets, variant-safe package, no Google clock.
require_grep "$DEFAULT_LAYOUT" 'app.nothingui.widgets.NothingUiClockWidgetProvider' \
    "the fresh Play layout does not seed the clock widget"
require_grep "$DEFAULT_LAYOUT" 'app.nothingui.widgets.NothingUiBatteryWidgetProvider' \
    "the fresh Play layout does not seed the battery widget"
require_grep "$DEFAULT_LAYOUT" 'launcher:packageName="@string/launcher_component"' \
    "the fresh Play layout does not resolve the variant applicationId"
require_grep "$DEFAULT_LAYOUT" 'launcher:x="0"' \
    "the fresh Play layout does not place the clock at x=0"
require_grep "$DEFAULT_LAYOUT" 'launcher:x="2"' \
    "the fresh Play layout does not place the battery at x=2"
require_grep "$DEFAULT_LAYOUT" 'launcher:y="1"' \
    "the fresh Play layout does not place the widgets below the date strip"
forbid_grep "$DEFAULT_LAYOUT" 'com.google.android.deskclock' \
    "the fresh Play layout still seeds the Google desk clock"
require_grep "$PARSER" 'resolveComponentPackage' \
    "the default-layout parser cannot resolve a resource package name"
require_grep "$PARSER" '@string/' \
    "the default-layout parser does not recognize resource package names"
require_grep "$PARSER" 'mContext.getPackageName()' \
    "the default-layout parser does not use the running variant package"

# Play-only sizing: smaller home icons and a real 48dp QSB, drawer unchanged.
require_grep "$PLAY_CONFIG" 'config_default_home_icon_size_factor' \
    "the Play icon factor override is missing"
require_grep "$PLAY_CONFIG" '0.76' \
    "the Play home icon factor is not 0.76"
forbid_grep "$PLAY_CONFIG" 'config_default_drawer_icon_size_factor' \
    "the Play override also enlarges the drawer"
require_grep "$PLAY_DIMENS" 'name="qsb_widget_height"' \
    "the Play QSB height override is missing"
require_grep "$PLAY_DIMENS" '48dp' \
    "the Play QSB is not 48dp"

# Lifecycle wiring must be Play-gated and symmetrical.
require_grep "$LAUNCHER" 'NothingUiBatteryMonitor.start' \
    "the launcher never starts the battery monitor"
require_grep "$LAUNCHER" 'NothingUiBatteryMonitor.stop' \
    "the launcher never stops the battery monitor"
if ! grep -B4 -A2 'NothingUiBatteryMonitor.start' "$ROOT/$LAUNCHER" |
    grep -Fq 'NothingUiFeature.homeEnabled'; then
    fail "the battery monitor is not gated by the Play home flag"
fi

printf 'nothingui-widget-guard: OK\n'
