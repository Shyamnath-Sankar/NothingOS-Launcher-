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
    copy_file 'lawnchair/src/app/lawnchair/ui/preferences/destinations/WeatherPreferences.kt'
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
printf '\n// OkHttpClient must not appear here\n' >>"$FIXTURE/lawnchair/src/app/nothingui/weather/WeatherHomeRuntime.kt"
expect_fail 'a runtime that constructs a transport is rejected'

if [ "$failures" -ne 0 ]; then
    printf 'nothingui-weather-guard-test: %s failure(s)\n' "$failures" >&2
    exit 1
fi

printf 'nothingui-weather-guard-test: all passed\n'
