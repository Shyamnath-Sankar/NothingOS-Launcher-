#!/bin/sh
# Tests for scripts/nothingui-weather-guard.sh.
# Run with: sh scripts/nothingui-weather-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
GUARD="$SCRIPT_DIR/nothingui-weather-guard.sh"
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

if [ ! -f "$GUARD" ]; then
    fail 'nothingui-weather-guard.sh exists'
    exit 1
fi

FIXTURE="$TMP_DIR/root"
OUT="$TMP_DIR/guard.out"

copy_file() {
    rel=$1
    mkdir -p "$FIXTURE/$(dirname "$rel")"
    cp "$REPO_ROOT/$rel" "$FIXTURE/$rel"
}

reset_fixture() {
    rm -rf "$FIXTURE"
    copy_file 'lawnchair/src/app/lawnchair/LawnchairLauncher.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherHomeOwner.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherWorkFactory.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherRuntimeSessionProvider.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherSettingsCopy.kt'
    copy_file 'lawnchair/src/app/lawnchair/ui/preferences/destinations/WeatherPreferences.kt'
    copy_file 'lawnchair/src/app/lawnchair/ui/preferences/destinations/HomeScreenPreferences.kt'
    copy_file 'lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt'
    copy_file 'lawnchair/src/app/nothingui/weather/WeatherWidgetRender.kt'
    copy_file 'lawnchair/res/layout/nothingui_widget_weather.xml'
    copy_file 'lawnchair/res/xml/nothingui_weather_widget_info.xml'
    copy_file 'lawnchair/res/values/strings.xml'
    copy_file 'play/AndroidManifest.xml'
    copy_file 'play/res/xml/default_workspace_4x5.xml'
}

run_guard() {
    if sh "$GUARD" "$FIXTURE" >"$OUT" 2>&1; then
        return 0
    fi
    return 1
}

expect_pass() {
    if run_guard; then
        pass "$1"
    else
        fail "$1"
        sed 's/^/    /' "$OUT" >&2
    fi
}

expect_fail() {
    if run_guard; then
        fail "$1 (guard unexpectedly passed)"
    else
        pass "$1"
    fi
}

reset_fixture
expect_pass 'the real launcher hookup passes the weather guard'

reset_fixture
sed -i 's/Intent.ACTION_SCREEN_OFF -> owner.onScreenOff()/Intent.ACTION_SCREEN_OFF -> Unit/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
expect_fail 'a missing SCREEN_OFF handler is rejected'

reset_fixture
sed -i 's/KeyguardManager::class.java/Context::class.java/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
expect_fail 'a screen recheck without KeyguardManager is rejected'

reset_fixture
sed -i 's/weatherSurface.onTransitionStart()/Unit/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
expect_fail 'a transition start that does not hide weather is rejected'

reset_fixture
sed -i 's/weatherHomeOwner.setHomeVisible(false)/weatherHomeOwner.shutdown()\n        weatherHomeOwner.setHomeVisible(false)/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
expect_fail 'shutting the shared owner down on pause is rejected'

reset_fixture
sed -i '/fun setScreenInteractive/,/^    }/ s/userPresent = false/userPresent = true/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeOwner.kt"
expect_fail 'screen-off that keeps a stale user-present gate is rejected'

reset_fixture
sed -i 's/WeatherHomeRuntimePolicy.shouldReuseOwner/instance != null/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'reusing a closed runtime owner is rejected'

reset_fixture
sed -i 's/WeatherNetworkMode.isEnabled(BuildConfig.DEBUG)/true/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a runtime that bypasses the build-policy boundary is rejected'

reset_fixture
sed -i 's/WeatherRuntimeSessionProvider { synchronized(lock) { instance } }/WeatherRuntimeSessionProvider { null }/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a runtime that does not resolve the current owner session is rejected'

reset_fixture
sed -i 's/instance = null/instance = current/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a runtime that keeps a replaced owner live is rejected'

reset_fixture
sed -i 's/WeatherPrivateStorage.cacheDirectory(context.noBackupFilesDir)/context.cacheDir/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a weather cache outside the no-backup directory is rejected'

reset_fixture
sed -i 's/WeatherPrivateStorage.throttleDirectory(context.noBackupFilesDir)/context.cacheDir/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a throttle store outside the no-backup directory is rejected'

reset_fixture
sed -i 's/fun isEnabled(debugBuild: Boolean): Boolean = true/fun isEnabled(debugBuild: Boolean): Boolean = false/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherWorkFactory.kt"
expect_fail 'a work factory that disables the live path is rejected'

reset_fixture
sed -i 's/val current = owner() ?: return WeatherSession.DISABLED/val current = owner()!!/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherRuntimeSessionProvider.kt"
expect_fail 'a session provider that does not fail closed before the owner exists is rejected'

reset_fixture
printf '\n// requestLoad()\n' >>"$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a weather widget broadcast that starts a load is rejected'

reset_fixture
printf '\n// WeatherHttpTransport\n' >>"$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a weather widget that constructs a transport is rejected'

reset_fixture
sed -i 's/updateAppWidget(appWidgetId, views)/partiallyUpdateAppWidget(appWidgetId, views)/' \
    "$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a weather widget partial update is rejected'

reset_fixture
sed -i 's/PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE/PendingIntent.FLAG_UPDATE_CURRENT/' \
    "$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a mutable weather widget PendingIntent is rejected'

reset_fixture
sed -i 's/PreferenceActivity.createIntent(context, WeatherSettings)/Intent()/' \
    "$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a weather tile that does not open the real weather settings is rejected'

reset_fixture
sed -i 's/android:updatePeriodMillis="0"/android:updatePeriodMillis="1800000"/' \
    "$FIXTURE/lawnchair/res/xml/nothingui_weather_widget_info.xml"
expect_fail 'a periodic weather widget update is rejected'

reset_fixture
printf '\n<View />\n' >>"$FIXTURE/lawnchair/res/layout/nothingui_widget_weather.xml"
expect_fail 'a bare View in the weather RemoteViews layout is rejected'

reset_fixture
sed -i 's/<string name="nothingui_weather_state_off_short">Off<\/string>/<string name="nothingui_weather_state_off_short">Weather off · tap to set up<\/string>/' \
    "$FIXTURE/lawnchair/res/values/strings.xml"
expect_fail 'long setup copy in the short off label is rejected'

reset_fixture
sed -i 's/android:maxLines="2"/android:maxLines="1"/' \
    "$FIXTURE/lawnchair/res/layout/nothingui_widget_weather.xml"
expect_fail 'a compact weather status that cannot wrap is rejected'

reset_fixture
sed -i 's/detail = context.getString(R.string.nothingui_weather_state_off_short),/detail = context.getString(R.string.nothingui_weather_state_off),/' \
    "$FIXTURE/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
expect_fail 'a widget detail that reintroduces the long off copy is rejected'

reset_fixture
printf '\n// longitude\n' >>"$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherWidgetRender.kt"
expect_fail 'a widget render model that can carry a location is rejected'

reset_fixture
sed -i '/app.dotwel.widgets.DotWelWeatherWidgetProvider/,/<\/receiver>/ s/android:exported="false"/android:exported="true"/' \
    "$FIXTURE/play/AndroidManifest.xml"
expect_fail 'an exported weather widget receiver is rejected'

reset_fixture
sed -i '/android:label="@string\/nothingui_weather_widget_label"/d' \
    "$FIXTURE/play/AndroidManifest.xml"
expect_fail 'a weather widget receiver without its picker label is rejected'

reset_fixture
sed -i 's|<string name="nothingui_weather_widget_label">Weather</string>|<string name="nothingui_weather_widget_label">DotWel Launcher</string>|' \
    "$FIXTURE/lawnchair/res/values/strings.xml"
expect_fail 'a weather widget picker label other than Weather is rejected'

reset_fixture
printf '\n<appwidget launcher:className="app.dotwel.widgets.DotWelWeatherWidgetProvider" />\n' \
    >>"$FIXTURE/play/res/xml/default_workspace_4x5.xml"
expect_fail 'auto-seeding the weather widget into the default layout is rejected'

reset_fixture
sed -i 's/R.string.dotwel_weather_privacy_notice_debug/R.string.dotwel_weather_privacy_notice_release/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherSettingsCopy.kt"
expect_fail 'a debug privacy notice that reuses release copy is rejected'

reset_fixture
sed -i 's/R.string.dotwel_weather_message_enabled_debug/R.string.dotwel_weather_message_enabled_release/' \
    "$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherSettingsCopy.kt"
expect_fail 'a debug enabled confirmation that reuses release copy is rejected'

reset_fixture
sed -i 's/WeatherSettingsCopy.networkEnabled(BuildConfig.DEBUG)/true/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/ui/preferences/destinations/WeatherPreferences.kt"
expect_fail 'a settings screen that ignores the build mode is rejected'

reset_fixture
sed -i 's/WeatherSettingsCopy.settingsDescription(networkEnabled)/R.string.dotwel_weather_settings_description_release/' \
    "$FIXTURE/lawnchair/src/app/lawnchair/ui/preferences/destinations/HomeScreenPreferences.kt"
expect_fail 'a Home-screen subtitle that ignores the build mode is rejected'

reset_fixture
sed -i 's/coordinates and the IP address of this device/selected coordinates/' \
    "$FIXTURE/lawnchair/res/values/strings.xml"
expect_fail 'a privacy notice that hides the device-IP transmission is rejected'

reset_fixture
sed -i 's/network requests disabled/network available/' \
    "$FIXTURE/lawnchair/res/values/strings.xml"
expect_fail 'a debug notice that hides the network-off mode is rejected'

reset_fixture
sed -i 's/never replaced by a made-up value/instead of showing a stale or made-up value/' \
    "$FIXTURE/lawnchair/res/values/strings.xml"
expect_fail 'a forecast notice that denies the marked stale display is rejected'

if [ "$failures" -ne 0 ]; then
    printf 'nothingui-weather-guard-test: %s failure(s)\n' "$failures" >&2
    exit 1
fi

printf 'nothingui-weather-guard-test: all passed\n'
