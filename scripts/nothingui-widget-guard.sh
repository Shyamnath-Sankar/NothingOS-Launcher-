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
WIDGET_MONITOR=$WIDGET_DIR/NothingUiWidgetMonitor.kt
WIDGET_COLORS=$WIDGET_DIR/NothingUiWidgetColors.kt
BATTERY_ART=$WIDGET_DIR/NothingUiBatteryArt.kt
BUDGET=$WIDGET_DIR/NothingUiWidgetBudget.kt
DOT_TEXT=$WIDGET_DIR/DotText.kt
CLOCK_LAYOUT=lawnchair/res/layout/nothingui_widget_clock.xml
BATTERY_LAYOUT=lawnchair/res/layout/nothingui_widget_battery.xml
CLOCK_TILE_DARK=lawnchair/res/drawable/nothingui_widget_tile_dark.xml
CLOCK_TILE_LIGHT=lawnchair/res/drawable/nothingui_widget_tile_light.xml
COLORS=lawnchair/res/values/colors.xml
CLOCK_INFO=lawnchair/res/xml/nothingui_clock_widget_info.xml
BATTERY_INFO=lawnchair/res/xml/nothingui_battery_widget_info.xml
PLAY_MANIFEST=play/AndroidManifest.xml
DEFAULT_LAYOUT=play/res/xml/default_workspace_4x5.xml
PLAY_CONFIG=play/res/values/config.xml
PLAY_DIMENS=play/res/values/dimens.xml
LAUNCHER=lawnchair/src/app/lawnchair/LawnchairLauncher.kt
PARSER=src/com/android/launcher3/AutoInstallsLayout.java
PARSER_RESOLVER=src/com/android/launcher3/WidgetPackageResolver.java
NOTICE=NOTICE.md
MIT=licenses/third-party/dotline-widgets-MIT.txt

for file in \
    "$CLOCK_PROVIDER" "$BATTERY_PROVIDER" "$WIDGET_MONITOR" "$WIDGET_COLORS" \
    "$BATTERY_ART" "$BUDGET" "$DOT_TEXT" "$CLOCK_LAYOUT" "$BATTERY_LAYOUT" \
    "$CLOCK_TILE_DARK" "$CLOCK_TILE_LIGHT" "$COLORS" "$CLOCK_INFO" \
    "$BATTERY_INFO" "$PLAY_MANIFEST" "$DEFAULT_LAYOUT" "$PLAY_CONFIG" \
    "$PLAY_DIMENS" "$LAUNCHER" "$PARSER" "$PARSER_RESOLVER" "$NOTICE" "$MIT"; do
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

# Clock import, runtime tile surface and both-widget refresh.
forbid_grep "$CLOCK_PROVIDER" 'android.app.AlarmClock' \
    "the clock widget imports the wrong AlarmClock namespace"
require_grep "$CLOCK_PROVIDER" 'android.provider.AlarmClock' \
    "the clock widget does not use android.provider.AlarmClock"
require_grep "$CLOCK_PROVIDER" 'NothingUiWidgetColors' \
    "the clock widget does not use the widget colour pair"
forbid_grep "$CLOCK_PROVIDER" 'NothingUiHomeChrome' \
    "the clock widget still reads the launcher theme attributes"
require_grep "$CLOCK_PROVIDER" 'setBackgroundResource' \
    "the clock widget does not apply its rounded tile at runtime"
require_grep "$CLOCK_PROVIDER" 'fun refreshAll' \
    "the clock widget cannot be refreshed by the lifecycle monitor"
require_grep "$CLOCK_LAYOUT" 'nothingui_clock_surface' \
    "the clock layout has no tile surface view"
for layout in "$CLOCK_LAYOUT" "$BATTERY_LAYOUT"; do
    if grep -Eq '<View([[:space:]]|>|$)' "$ROOT/$layout"; then
        fail "$layout uses an unsupported bare View in a RemoteViews layout"
    fi
done
require_grep "$CLOCK_LAYOUT" '<ImageView' \
    "the clock tile is not a RemoteViews-supported ImageView"
require_grep "$CLOCK_LAYOUT" 'nothingui_widget_tile_dark' \
    "the clock layout has no default rounded tile"
require_grep "$CLOCK_TILE_DARK" 'nothingui_widget_surface_dark' \
    "the dark clock tile does not use the dark surface token"
require_grep "$CLOCK_TILE_LIGHT" 'nothingui_widget_surface_light' \
    "the light clock tile does not use the light surface token"
require_grep "$COLORS" 'nothingui_widget_surface_dark' \
    "the dark widget surface colour is missing"
require_grep "$COLORS" 'nothingui_widget_surface_light' \
    "the light widget surface colour is missing"

# Widget colours: stored light/dark/system resolution, not launcher theme attributes.
require_grep "$WIDGET_COLORS" 'Utilities.isDarkTheme' \
    "the widget colours do not resolve the stored launcher theme"
forbid_grep "$WIDGET_COLORS" 'Themes.getAttrBoolean' \
    "the widget colours still read launcher theme attributes"
forbid_grep "$WIDGET_COLORS" 'R.attr.isMainColorDark' \
    "the widget colours still read the isMainColorDark attribute"
forbid_grep "$CLOCK_PROVIDER" 'isMainColorDark' \
    "the clock provider still reads the isMainColorDark attribute"
forbid_grep "$BATTERY_PROVIDER" 'isMainColorDark' \
    "the battery provider still reads the isMainColorDark attribute"
require_grep "$WIDGET_COLORS" 'NothingUiPalette.Gray900' \
    "the dark widget surface is not the charcoal token"
require_grep "$WIDGET_COLORS" 'NothingUiPalette.Paper' \
    "the light widget surface is not the paper token"
require_grep "$WIDGET_COLORS" 'NothingUiPalette.Ink' \
    "the light widget content is not the ink token"
require_grep "$WIDGET_COLORS" 'NothingUiPalette.White' \
    "the dark widget content is not the white token"

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
require_grep "$BATTERY_PROVIDER" 'NothingUiWidgetColors' \
    "the battery widget does not use the widget colour pair"
forbid_grep "$BATTERY_PROVIDER" 'NothingUiHomeChrome' \
    "the battery widget still reads the launcher theme attributes"

# Power events carry no level/scale, so they must re-read the sticky battery broadcast.
if grep -A3 'Intent.ACTION_POWER_CONNECTED' "$ROOT/$BATTERY_PROVIDER" |
    grep -Fq 'refreshAll(context, intent)'; then
    fail "the battery provider passes the power intent into BatteryState.from"
fi
if ! grep -A3 'Intent.ACTION_POWER_CONNECTED' "$ROOT/$BATTERY_PROVIDER" |
    grep -Fq 'refreshAll(context)'; then
    fail "the battery provider does not re-read the sticky battery on power events"
fi

# Lifecycle-bounded monitor: BATTERY_CHANGED is sticky and cannot be a manifest receiver.
require_grep "$WIDGET_MONITOR" 'ContextCompat.registerReceiver' \
    "the widget monitor does not register a receiver"
require_grep "$WIDGET_MONITOR" 'RECEIVER_NOT_EXPORTED' \
    "the widget monitor receiver is not non-exported"
require_grep "$WIDGET_MONITOR" 'Intent.ACTION_BATTERY_CHANGED' \
    "the widget monitor does not listen for BATTERY_CHANGED"
require_grep "$WIDGET_MONITOR" 'Intent.ACTION_CONFIGURATION_CHANGED' \
    "the widget monitor does not refresh on configuration changes"
require_grep "$WIDGET_MONITOR" 'NothingUiClockWidgetProvider.refreshAll' \
    "the widget monitor does not refresh the clock widget"
require_grep "$WIDGET_MONITOR" 'NothingUiBatteryWidgetProvider.refreshAll' \
    "the widget monitor does not refresh the battery widget"
if grep -A3 'Intent.ACTION_POWER_CONNECTED' "$ROOT/$WIDGET_MONITOR" |
    grep -Fq 'NothingUiBatteryWidgetProvider.refreshAll(appContext, intent)'; then
    fail "the widget monitor passes the power intent into BatteryState.from"
fi
if ! grep -A3 'Intent.ACTION_POWER_CONNECTED' "$ROOT/$WIDGET_MONITOR" |
    grep -Fq 'NothingUiBatteryWidgetProvider.refreshAll(appContext)'; then
    fail "the widget monitor does not re-read the sticky battery on power events"
fi
forbid_grep "$WIDGET_MONITOR" 'Service' \
    "the widget monitor uses a service"
forbid_grep "$WIDGET_MONITOR" 'WakeLock' \
    "the widget monitor holds a wake lock"

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
require_grep "$BATTERY_ART" 'surfaceColor' \
    "the battery art does not draw the circular face from the surface token"
require_grep "$BATTERY_ART" 'contentColor' \
    "the battery art does not draw its glyphs from the content token"
require_grep "$BATTERY_ART" 'drawCircle' \
    "the battery art does not draw the circular face"
require_grep "$BATTERY_ART" '"$percent%"' \
    "the battery art does not show the percent unit"
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
require_grep "$PARSER" 'getAttributeResourceValue(parser, ATTR_PACKAGE_NAME, 0)' \
    "the default-layout parser does not read the compiled package resource id"
require_grep "$PARSER" 'WidgetPackageResolver.resolve' \
    "the default-layout parser does not use the resource-id resolver"
require_grep "$PARSER_RESOLVER" 'launcherComponentResourceId' \
    "the package resolver does not special-case the launcher_component resource id"
require_grep "$PARSER_RESOLVER" 'contextPackage' \
    "the package resolver does not use the running variant package"
require_grep "$PARSER_RESOLVER" '@string/' \
    "the package resolver does not keep the text-fixture string fallback"
require_grep "$PARSER" 'mContext.getPackageName()' \
    "the default-layout parser does not use the running variant package"
forbid_grep "$PARSER" 'com.launchernos.dotwellabs' \
    "the default-layout parser hardcodes the applicationId"
forbid_grep "$PARSER_RESOLVER" 'com.launchernos.dotwellabs' \
    "the package resolver hardcodes the applicationId"

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
require_grep "$LAUNCHER" 'NothingUiWidgetMonitor.start' \
    "the launcher never starts the widget monitor"
require_grep "$LAUNCHER" 'NothingUiWidgetMonitor.stop' \
    "the launcher never stops the widget monitor"
forbid_grep "$LAUNCHER" 'NothingUiBatteryMonitor' \
    "the launcher still references the battery-only monitor"
if ! grep -B4 -A2 'NothingUiWidgetMonitor.start' "$ROOT/$LAUNCHER" |
    grep -Fq 'NothingUiFeature.homeEnabled'; then
    fail "the widget monitor is not gated by the Play home flag"
fi

printf 'nothingui-widget-guard: OK\n'
