#!/bin/sh
# Executable mock-adb regression for the real open_app_drawer orchestration.
#
# The live smoke once reused POSIX global helper variables, so capture_ui_xml
# reset the outer swipe-loop counter and the "bounded" four-attempt loop could
# swipe forever. Pure fixture tests could not see that. This test sources the
# real script (function definitions only), puts a mock adb on PATH that always
# returns an unchanged HOME hierarchy, and requires the orchestration to fail
# after exactly four swipes with per-attempt evidence, inside a short timeout.
#
# Run with: sh scripts/emulator-smoke-drawer-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SMOKE="$SCRIPT_DIR/emulator-smoke.sh"

# shellcheck source=emulator-smoke-lib.sh
. "$SCRIPT_DIR/emulator-smoke-lib.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/bin"
ARTIFACTS="$TMP_DIR/artifacts"
mkdir -p "$MOCK_BIN" "$ARTIFACTS"

HOME_XML="$TMP_DIR/home.xml"
cat > "$HOME_XML" <<'EOF'
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

LAUNCHER_DUMP="$TMP_DIR/launcher.dump"
cat > "$LAUNCHER_DUMP" <<'EOF'
ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
  * Task{abc #1 type=home}
    topResumedActivity=ActivityRecord{abc u0 com.launchernos.dotwellabs.debug/app.lawnchair.LawnchairLauncher t1}
EOF

ADB_LOG="$TMP_DIR/adb.log"
: > "$ADB_LOG"

cat > "$MOCK_BIN/adb" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_ADB_LOG"
case "$*" in
    "shell dumpsys activity activities")
        cat "$MOCK_LAUNCHER_DUMP"
        ;;
    "shell wm size")
        printf 'Physical size: 1080x1920\n'
        ;;
    "shell uiautomator dump "*)
        exit 0
        ;;
    "pull "*)
        cp "$MOCK_HOME_XML" "$3"
        ;;
    "shell rm -f "*)
        exit 0
        ;;
    "exec-out screencap -p")
        printf 'PNG'
        ;;
    "logcat -d -v threadtime")
        printf 'mock logcat\n'
        ;;
    "logcat -d -s DotwelDrawerTrace")
        printf 'mock drawer trace\n'
        ;;
    *)
        exit 0
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/adb"

# The orchestration's retry delays are real; the regression only needs the
# control flow, so keep it fast without changing the production script.
cat > "$MOCK_BIN/sleep" <<'MOCK'
#!/bin/sh
exit 0
MOCK
chmod +x "$MOCK_BIN/sleep"

RUNNER="$TMP_DIR/run-open-drawer.sh"
cat > "$RUNNER" <<'RUNNER'
#!/bin/sh
set -eu
export _EMULATOR_SMOKE_SOURCE_ONLY=1
export _EMULATOR_SMOKE_SCRIPT_DIR="$SMOKE_SCRIPT_DIR"
export ARTIFACTS="$SMOKE_ARTIFACTS"
. "$SMOKE_PATH"
open_app_drawer
printf 'unexpected success: open_app_drawer returned 0\n' >&2
exit 42
RUNNER
chmod +x "$RUNNER"

# A failed readiness loop must reach the real fail() (exit 1), not a timeout.
set +e
run_with_timeout 30 env \
    SMOKE_PATH="$SMOKE" \
    SMOKE_SCRIPT_DIR="$SCRIPT_DIR" \
    SMOKE_ARTIFACTS="$ARTIFACTS" \
    MOCK_ADB_LOG="$ADB_LOG" \
    MOCK_LAUNCHER_DUMP="$LAUNCHER_DUMP" \
    MOCK_HOME_XML="$HOME_XML" \
    PATH="$MOCK_BIN:$PATH" \
    "$RUNNER" > "$TMP_DIR/runner.out" 2> "$TMP_DIR/runner.err"
status=$?
set -e

failures=0

pass() {
    printf 'ok - %s\n' "$1"
}

fail() {
    failures=$((failures + 1))
    printf 'not ok - %s\n' "$1" >&2
}

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

assert_file() {
    name=$1
    path=$2
    if [ -s "$path" ]; then
        pass "$name"
    else
        fail "$name (missing or empty: $path)"
    fi
}

assert_exists() {
    name=$1
    path=$2
    if [ -f "$path" ]; then
        pass "$name"
    else
        fail "$name (missing: $path)"
    fi
}

assert_eq 'the failed drawer loop exits through fail(), not a timeout' \
    '1' "$status"

swipe_count=$(grep -c 'shell input swipe' "$ADB_LOG" || true)
assert_eq 'the failed drawer loop performs exactly four swipes' \
    '4' "$swipe_count"

assert_file 'the launcher-idle evidence exists' \
    "$ARTIFACTS/appdrawer-launcher-idle.txt"
assert_file 'failure evidence retains the logcat capture' \
    "$ARTIFACTS/logcat.txt"
assert_file 'failure evidence retains the screenshot capture' \
    "$ARTIFACTS/screenshot.png"

attempt=1
while [ "$attempt" -le 4 ]; do
    assert_file "attempt $attempt records its pre-swipe XML" \
        "$ARTIFACTS/appdrawer-attempt-$attempt-before.xml"
    assert_file "attempt $attempt records its pre-swipe PNG" \
        "$ARTIFACTS/appdrawer-attempt-$attempt-before.png"
    assert_file "attempt $attempt records its post-swipe XML" \
        "$ARTIFACTS/appdrawer-attempt-$attempt.xml"
    assert_file "attempt $attempt records its post-swipe PNG" \
        "$ARTIFACTS/appdrawer-attempt-$attempt.png"
    assert_file "attempt $attempt records the debug drawer trace" \
        "$ARTIFACTS/appdrawer-trace-$attempt.txt"
    assert_exists "attempt $attempt records its swipe command" \
        "$ARTIFACTS/appdrawer-swipe-$attempt.txt"
    if grep -Fq "attempt=$attempt " "$ARTIFACTS/appdrawer-swipe-log.txt"; then
        pass "attempt $attempt is recorded in the swipe log"
    else
        fail "attempt $attempt is recorded in the swipe log"
    fi
    attempt=$((attempt + 1))
done

if grep -Fq 'emulator-smoke: FAIL: app drawer did not expose' "$TMP_DIR/runner.err"; then
    pass 'the terminal failure names the exhausted drawer loop'
else
    fail 'the terminal failure names the exhausted drawer loop'
fi

if grep -Fq "emulator-smoke: evidence: $ARTIFACTS" "$TMP_DIR/runner.err"; then
    pass 'the terminal failure points at the retained evidence directory'
else
    fail 'the terminal failure points at the retained evidence directory'
fi

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all emulator-smoke drawer tests passed\n'
