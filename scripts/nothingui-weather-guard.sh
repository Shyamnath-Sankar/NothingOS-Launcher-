#!/bin/sh
# Static guard for the Weather HOME lifecycle hookup.
#
# Proves, without Gradle or an Android build, that:
# - screen-off clears both gates and drops the queued consent read/work;
# - screen-on and user-present re-query PowerManager and KeyguardManager and do
#   not trust an earlier unlock;
# - weather hides at a state-transition start and only returns after a
#   completed NORMAL transition;
# - pause and destroy unregister without shutting the process-wide owner down;
# - a closed runtime owner is never reused;
# - production still uses the explicit NoNetworkWeatherWork placeholder and
#   constructs no provider, transport or device-location source.
#
# Usage: scripts/nothingui-weather-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-weather-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-weather-guard: %s\n' "$*" >&2
    exit 1
}

LAUNCHER="$ROOT/lawnchair/src/app/lawnchair/LawnchairLauncher.kt"
OWNER="$ROOT/lawnchair/src/app/nothingui/weather/WeatherHomeOwner.kt"
RUNTIME="$ROOT/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
PREFS="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/WeatherPreferences.kt"
WIDGET_PROVIDER="$ROOT/lawnchair/src/app/dotwel/widgets/DotWelWeatherWidgetProvider.kt"
WIDGET_MODEL="$ROOT/lawnchair/src/app/nothingui/weather/WeatherWidgetRender.kt"
WIDGET_LAYOUT="$ROOT/lawnchair/res/layout/nothingui_widget_weather.xml"
WIDGET_INFO="$ROOT/lawnchair/res/xml/nothingui_weather_widget_info.xml"
PLAY_MANIFEST="$ROOT/play/AndroidManifest.xml"
DEFAULT_LAYOUT="$ROOT/play/res/xml/default_workspace_4x5.xml"

for file in "$LAUNCHER" "$OWNER" "$RUNTIME" "$PREFS" "$WIDGET_PROVIDER" \
    "$WIDGET_MODEL" "$WIDGET_LAYOUT" "$WIDGET_INFO" "$PLAY_MANIFEST" "$DEFAULT_LAYOUT"; do
    [ -f "$file" ] || fail "missing required file: ${file#"$ROOT"/}"
done

require_text() {
    file=$1
    text=$2
    message=$3
    grep -Fq -- "$text" "$file" || fail "$message"
}

forbid_text() {
    file=$1
    text=$2
    message=$3
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

section() {
    file=$1
    start=$2
    sed -n "/$start/,/^    }/p" "$file"
}

# --- Launcher lifecycle hookup -------------------------------------------

require_text "$LAUNCHER" 'Intent.ACTION_SCREEN_OFF -> owner.onScreenOff()' \
    'SCREEN_OFF must call the owner screen-off handler'
require_text "$LAUNCHER" 'Intent.ACTION_SCREEN_ON,' \
    'SCREEN_ON must be handled with a fresh system recheck'
require_text "$LAUNCHER" 'Intent.ACTION_USER_PRESENT,' \
    'USER_PRESENT must be handled with a fresh system recheck'
require_text "$LAUNCHER" '-> refreshWeatherScreenState()' \
    'SCREEN_ON and USER_PRESENT must share the system recheck'

refresh=$(section "$LAUNCHER" 'private fun refreshWeatherScreenState')
printf '%s\n' "$refresh" | grep -Fq 'PowerManager::class.java' ||
    fail 'refreshWeatherScreenState must query PowerManager'
printf '%s\n' "$refresh" | grep -Fq 'isInteractive' ||
    fail 'refreshWeatherScreenState must read PowerManager.isInteractive'
printf '%s\n' "$refresh" | grep -Fq 'KeyguardManager::class.java' ||
    fail 'refreshWeatherScreenState must query KeyguardManager'
printf '%s\n' "$refresh" | grep -Fq 'isKeyguardLocked' ||
    fail 'refreshWeatherScreenState must read KeyguardManager.isKeyguardLocked'
printf '%s\n' "$refresh" | grep -Fq 'WeatherScreenPolicy.evaluate' ||
    fail 'refreshWeatherScreenState must use the shared screen policy'

require_text "$LAUNCHER" 'override fun onStateTransitionStart' \
    'weather must react at a state-transition start'
require_text "$LAUNCHER" 'weatherSurface.onTransitionStart()' \
    'a transition start must invalidate the HOME confirmation'
require_text "$LAUNCHER" 'weatherSurface.onTransitionComplete(finalState == LauncherState.NORMAL)' \
    'only a completed NORMAL transition may confirm HOME'

start=$(section "$LAUNCHER" 'private fun startWeatherHome')
printf '%s\n' "$start" | grep -Fq 'refreshWeatherScreenState()' ||
    fail 'startWeatherHome must recheck the system screen state'
printf '%s\n' "$start" | grep -Fq 'registerWeatherStateListener()' ||
    fail 'startWeatherHome must register the state listener'

stop=$(section "$LAUNCHER" 'private fun stopWeatherHome')
printf '%s\n' "$stop" | grep -Fq 'unregisterWeatherStateListener()' ||
    fail 'stopWeatherHome must unregister the state listener'
printf '%s\n' "$stop" | grep -Fq 'unregisterWeatherScreenReceiver()' ||
    fail 'stopWeatherHome must unregister the screen receiver'
printf '%s\n' "$stop" | grep -Fq 'setHomeVisible(false)' ||
    fail 'stopWeatherHome must hide the HOME surface'
if printf '%s\n' "$stop" | grep -Fq 'shutdown()'; then
    fail 'stopWeatherHome must not permanently shut the shared owner down'
fi
forbid_text "$LAUNCHER" 'weatherHomeOwner.shutdown(' \
    'the launcher must never permanently close the process-wide owner'

require_text "$LAUNCHER" 'weatherSurface.onResume(' \
    'resume must use the HOME surface tracker'
require_text "$LAUNCHER" 'stateManager.state != stateManager.currentStableState' \
    'resume must not confirm HOME during a transition'

# --- Owner gates and consent resolution ----------------------------------

screen_off=$(section "$OWNER" 'fun setScreenInteractive')
printf '%s\n' "$screen_off" | grep -Fq 'userPresent = false' ||
    fail 'screen-off must clear the user-present gate'
printf '%s\n' "$screen_off" | grep -Fq 'invalidateReadLocked(reread = true)' ||
    fail 'screen-off must invalidate a queued consent read for a later retry'
printf '%s\n' "$screen_off" | grep -Fq 'controller.setScreenOn(false)' ||
    fail 'screen-off must clear the controller screen gate'
printf '%s\n' "$screen_off" | grep -Fq 'controller.setUserPresent(false)' ||
    fail 'screen-off must clear the controller user-present gate'

user_present=$(section "$OWNER" 'fun setUserPresent')
printf '%s\n' "$user_present" | grep -Fq 'val effective = value && screenInteractive' ||
    fail 'user-present must require an interactive screen'
printf '%s\n' "$user_present" | grep -Fq 'controller.setUserPresent(effective)' ||
    fail 'the controller must receive the gated user-present value'

require_text "$OWNER" 'fun onScreenOff()' \
    'the owner must expose an explicit screen-off handler'
require_text "$OWNER" 'WeatherHomeConsentPolicy.choose(loaded, lastObservedConsent)' \
    'stale consent must use the conservative policy'

# --- Runtime placeholder and singleton safety ----------------------------

require_text "$RUNTIME" 'NoNetworkWeatherWork' \
    'production must keep the explicit no-network work placeholder'
require_text "$RUNTIME" 'WeatherHomeRuntimePolicy.shouldReuseOwner' \
    'a closed runtime owner must not be reused'
forbid_text "$RUNTIME" 'OkHttp' 'the runtime must construct no HTTP transport'
forbid_text "$RUNTIME" 'MetWeatherRepository' 'the runtime must construct no repository'
forbid_text "$RUNTIME" 'WeatherHttpTransport' 'the runtime must construct no transport'
forbid_text "$RUNTIME" 'LocationManager' 'the runtime must not read device location'
forbid_text "$RUNTIME" 'WorkManager' 'the runtime must not schedule work'
forbid_text "$RUNTIME" 'AlarmManager' 'the runtime must not schedule an alarm'

require_text "$PREFS" 'WeatherHomeRuntime.observeConsent(appContext, state)' \
    'settings must share the same process-wide owner'

# --- Shared render publication -------------------------------------------

require_text "$RUNTIME" 'WeatherWidgetStateStore.onSession(created.current())' \
    'the runtime must publish the initial session to the widget render state'
require_text "$RUNTIME" 'WeatherWidgetStateStore.onSession(session)' \
    'the runtime must publish every session change to the widget render state'
require_text "$RUNTIME" 'WeatherWidgetStateStore.onResult(result)' \
    'the runtime must publish every result to the widget render state'

# --- Render-only weather widget ------------------------------------------

require_text "$WIDGET_PROVIDER" 'class DotWelWeatherWidgetProvider : AppWidgetProvider()' \
    'the Play weather widget provider is missing'
require_text "$WIDGET_PROVIDER" 'override fun onUpdate' \
    'the weather widget does not render on update'
require_text "$WIDGET_PROVIDER" 'override fun onAppWidgetOptionsChanged' \
    'the weather widget does not render on resize'
require_text "$WIDGET_PROVIDER" 'fun refreshAll' \
    'the weather widget cannot be refreshed by the shared runtime'
require_text "$WIDGET_PROVIDER" 'WeatherWidgetStateStore.render()' \
    'the weather widget does not read the shared render state'
require_text "$WIDGET_PROVIDER" 'updateAppWidget(' \
    'the weather widget does not use full RemoteViews updates'
forbid_text "$WIDGET_PROVIDER" 'partiallyUpdateAppWidget' \
    'the weather widget uses partial RemoteViews updates'
require_text "$WIDGET_PROVIDER" 'PreferenceActivity.createIntent(context, WeatherSettings)' \
    'the weather tile does not open the real weather settings destination'
require_text "$WIDGET_PROVIDER" 'PendingIntent.FLAG_IMMUTABLE' \
    'the weather tile tap does not use an immutable PendingIntent'

# A widget broadcast must never start a load, construct a network/transport,
# schedule background work, register a receiver or read the device location.
for forbidden in \
    'requestLoad' 'WeatherLoadWork' 'WeatherSessionController' 'MetWeatherRepository' \
    'OkHttp' 'WeatherHttpTransport' 'WeatherConsentStore' 'LocationManager' \
    'WorkManager' 'AlarmManager' 'registerReceiver' 'CoroutineScope' 'launch(' \
    'Thread(' 'Executor' 'WakeLock' 'Service' 'SharedPreferences' 'DataStore' \
    'Log.' 'println' 'printStackTrace'; do
    forbid_text "$WIDGET_PROVIDER" "$forbidden" \
        "the weather widget references a forbidden load/background/location/log symbol: $forbidden"
done

require_text "$WIDGET_MODEL" 'data class WeatherWidgetForecast' \
    'the coordinate-free widget forecast model is missing'
require_text "$WIDGET_MODEL" 'object WeatherWidgetText' \
    'the widget text helpers are missing'
require_text "$WIDGET_MODEL" 'WeatherFailureReason.CACHE_MISS -> WeatherWidgetOutcome.NotConnected' \
    'the no-network cache miss must render provider-not-connected, not a forecast'
for forbidden in 'WeatherCoordinates' '.location' 'latitude' 'longitude' 'cacheKey'; do
    forbid_text "$WIDGET_MODEL" "$forbidden" \
        "the widget render model references private location data: $forbidden"
done

require_text "$WIDGET_LAYOUT" 'nothingui_weather_surface' \
    'the weather layout has no rounded tile surface'
require_text "$WIDGET_LAYOUT" 'nothingui_weather_value' \
    'the weather layout has no temperature value'
require_text "$WIDGET_LAYOUT" 'nothingui_weather_detail' \
    'the weather layout has no condition line'
require_text "$WIDGET_LAYOUT" 'nothingui_weather_asof' \
    'the weather layout has no as-of line'
if grep -Eq '<View([[:space:]]|>|$)' "$WIDGET_LAYOUT"; then
    fail 'the weather layout uses an unsupported bare View in a RemoteViews layout'
fi

require_text "$WIDGET_INFO" 'android:initialLayout="@layout/nothingui_widget_weather"' \
    'the weather widget metadata does not use the weather layout'
require_text "$WIDGET_INFO" 'android:updatePeriodMillis="0"' \
    'the weather widget must not request a periodic update'
require_text "$WIDGET_INFO" 'android:resizeMode="horizontal|vertical"' \
    'the weather widget is not resizable to 2x1 and 2x2'
require_text "$WIDGET_INFO" 'android:minResizeHeight="40dp"' \
    'the weather widget cannot shrink to a compact one-row size'

require_text "$PLAY_MANIFEST" 'app.dotwel.widgets.DotWelWeatherWidgetProvider' \
    'the Play manifest does not register the weather widget'
if ! grep -A6 'app.dotwel.widgets.DotWelWeatherWidgetProvider' "$PLAY_MANIFEST" |
    grep -Fq 'android:exported="false"'; then
    fail 'the weather widget receiver is exported or has no exported=false declaration'
fi
require_text "$PLAY_MANIFEST" '@xml/nothingui_weather_widget_info' \
    'the Play manifest does not point the weather receiver at its metadata'
forbid_text "$DEFAULT_LAYOUT" 'DotWelWeatherWidgetProvider' \
    'the weather widget must remain user-placeable and must not be auto-seeded'

printf 'nothingui-weather-guard: ok\n'
