#!/bin/sh
# Static guard for the temporary debug-only app-drawer gesture trace.
#
# Proves, without Gradle or a device, that:
# - the trace is gated to debug Play builds by the channel flavor, not enabled
#   for release or github/nightly;
# - the selected touch-controller factory records controller classes and the
#   navigation mode;
# - the central state-change controller records DOWN/UP interception and the
#   drag start/end decisions, but never logs per-MOVE events;
# - the smoke script captures the trace after every swipe attempt regardless of
#   drawer readiness.
#
# Usage: scripts/nothingui-drawer-trace-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-drawer-trace-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-drawer-trace-guard: %s\n' "$*" >&2
    exit 1
}

TRACE_FILE="$ROOT/src/com/android/launcher3/touch/DotwelDrawerTrace.java"
CONTROLLER_FILE="$ROOT/src/com/android/launcher3/touch/AbstractStateChangeTouchController.java"
LAUNCHER_FILE="$ROOT/src/com/android/launcher3/Launcher.java"
SMOKE_FILE="$ROOT/scripts/emulator-smoke.sh"

for file in "$TRACE_FILE" "$CONTROLLER_FILE" "$LAUNCHER_FILE" "$SMOKE_FILE"; do
    [ -f "$file" ] || fail "missing $file"
done

grep -Fq 'BuildConfig.DEBUG && "play".equals(BuildConfig.FLAVOR_channel)' "$TRACE_FILE" ||
    fail "the drawer trace is not gated to debug Play builds"
grep -Fq 'Log.d(TAG, message)' "$TRACE_FILE" ||
    fail "the drawer trace does not write to logcat"
grep -Fq 'TAG = "DotwelDrawerTrace"' "$TRACE_FILE" ||
    fail "the drawer trace does not use the DotwelDrawerTrace tag"

grep -Fq 'factory controllers=' "$LAUNCHER_FILE" ||
    fail "the touch-controller factory does not record selected controllers"
grep -Fq 'navigationMode=' "$LAUNCHER_FILE" ||
    fail "the touch-controller factory does not record the navigation mode"

grep -Fq 'intercept action=DOWN' "$CONTROLLER_FILE" ||
    fail "the state-change controller does not record DOWN interception"
grep -Fq 'intercept action=UP' "$CONTROLLER_FILE" ||
    fail "the state-change controller does not record UP interception"
grep -Fq 'dragStart startDisplacement=' "$CONTROLLER_FILE" ||
    fail "the state-change controller does not record drag start"
grep -Fq 'dragEnd velocity=' "$CONTROLLER_FILE" ||
    fail "the state-change controller does not record drag end"
if grep -Fq 'ACTION_MOVE' "$CONTROLLER_FILE"; then
    fail "the state-change controller must not log per-MOVE events"
fi

grep -Fq 'logcat -d -s DotwelDrawerTrace' "$SMOKE_FILE" ||
    fail "the smoke script does not capture the DotwelDrawerTrace tag"
grep -Fq 'capture_drawer_trace "$attempt"' "$SMOKE_FILE" ||
    fail "the smoke script does not capture the trace after each swipe attempt"

printf 'nothingui-drawer-trace-guard: OK\n'
