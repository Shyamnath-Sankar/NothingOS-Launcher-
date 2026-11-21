#!/bin/sh
# Tests for scripts/nothingui-drawer-trace-guard.sh.
# Run with: sh scripts/nothingui-drawer-trace-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-drawer-trace-guard.sh"
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
    fail 'nothingui-drawer-trace-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/src/com/android/launcher3/touch/DotwelDrawerTrace.java" <<'EOF'
package com.android.launcher3.touch;

import android.util.Log;

import com.android.launcher3.BuildConfig;

public final class DotwelDrawerTrace {
    public static final String TAG = "DotwelDrawerTrace";
    public static final boolean ENABLED =
            BuildConfig.DEBUG && "play".equals(BuildConfig.FLAVOR_channel);

    public static void log(String message) {
        if (ENABLED) {
            Log.d(TAG, message);
        }
    }
}
EOF

    write_file "$root/src/com/android/launcher3/touch/AbstractStateChangeTouchController.java" <<'EOF'
package com.android.launcher3.touch;

class AbstractStateChangeTouchController {
    void intercept() {
        DotwelDrawerTrace.log("intercept action=DOWN decision=accept state=");
        DotwelDrawerTrace.log("intercept action=UP noIntercept=");
    }

    void dragStart(float startDisplacement) {
        DotwelDrawerTrace.log("dragStart startDisplacement=" + startDisplacement);
    }

    void dragEnd(float velocity) {
        DotwelDrawerTrace.log("dragEnd velocity=" + velocity);
    }
}
EOF

    write_file "$root/src/com/android/launcher3/Launcher.java" <<'EOF'
package com.android.launcher3;

class Launcher {
    void createTouchControllers() {
        DotwelDrawerTrace.log("factory controllers=" + "a" + " navigationMode=" + "threebutton");
    }
}
EOF

    write_file "$root/scripts/emulator-smoke.sh" <<'EOF'
#!/bin/sh
capture_drawer_trace() (
    attempt=$1
    adb_cmd logcat -d -s DotwelDrawerTrace > "$ARTIFACTS/appdrawer-trace-$attempt.txt" 2>/dev/null || true
)
open_app_drawer() {
    capture_drawer_trace "$attempt"
}
EOF
}

run_guard() {
    sh "$GUARD" "$1" > "$TMP_DIR/out" 2> "$TMP_DIR/err"
}

expect_pass() {
    name=$1
    root=$2
    if run_guard "$root"; then
        pass "$name"
    else
        fail "$name (expected success)"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

expect_fail_contains() {
    name=$1
    root=$2
    needle=$3
    if run_guard "$root"; then
        fail "$name (expected failure)"
        return
    fi
    if grep -Fq "$needle" "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (failure did not mention '$needle')"
        cat "$TMP_DIR/err" >&2
    fi
}

clean="$TMP_DIR/clean"
write_fixture "$clean"
expect_pass 'clean debug Play-gated trace fixture passes' "$clean"

bad_nav="$TMP_DIR/bad-nav"
cp -R "$clean" "$bad_nav"
write_file "$bad_nav/src/com/android/launcher3/Launcher.java" <<'EOF'
package com.android.launcher3;

class Launcher {
    void createTouchControllers() {
        DotwelDrawerTrace.log("factory controllers=" + "a"
                + " navigationMode=" + DisplayController.getNavigationMode(this).name);
    }
}
EOF
expect_fail_contains 'invalid navigation-mode .name field access fails' \
    "$bad_nav" 'invalid .name field access'

bad_state="$TMP_DIR/bad-state"
cp -R "$clean" "$bad_state"
write_file "$bad_state/src/com/android/launcher3/touch/AbstractStateChangeTouchController.java" <<'EOF'
package com.android.launcher3.touch;

class AbstractStateChangeTouchController {
    void intercept() {
        DotwelDrawerTrace.log("intercept action=DOWN decision=accept state="
                + mLauncher.getStateManager().getState().name);
        DotwelDrawerTrace.log("intercept action=UP noIntercept=");
    }

    void dragStart(float startDisplacement) {
        DotwelDrawerTrace.log("dragStart startDisplacement=" + startDisplacement);
    }

    void dragEnd(float velocity) {
        DotwelDrawerTrace.log("dragEnd velocity=" + velocity);
    }
}
EOF
expect_fail_contains 'invalid LauncherState .name field access fails' \
    "$bad_state" 'invalid .name field access'

release_on="$TMP_DIR/release-on"
cp -R "$clean" "$release_on"
write_file "$release_on/src/com/android/launcher3/touch/DotwelDrawerTrace.java" <<'EOF'
package com.android.launcher3.touch;

import android.util.Log;

import com.android.launcher3.BuildConfig;

public final class DotwelDrawerTrace {
    public static final String TAG = "DotwelDrawerTrace";
    public static final boolean ENABLED = "play".equals(BuildConfig.FLAVOR_channel);

    public static void log(String message) {
        if (ENABLED) {
            Log.d(TAG, message);
        }
    }
}
EOF
expect_fail_contains 'a trace without the debug gate fails' \
    "$release_on" 'not gated to debug Play builds'

move_log="$TMP_DIR/move-log"
cp -R "$clean" "$move_log"
write_file "$move_log/src/com/android/launcher3/touch/AbstractStateChangeTouchController.java" <<'EOF'
package com.android.launcher3.touch;

class AbstractStateChangeTouchController {
    void intercept() {
        DotwelDrawerTrace.log("intercept action=DOWN decision=accept state=");
        DotwelDrawerTrace.log("intercept action=UP noIntercept=");
    }

    void dragStart(float startDisplacement) {
        DotwelDrawerTrace.log("dragStart startDisplacement=" + startDisplacement);
    }

    void dragEnd(float velocity) {
        DotwelDrawerTrace.log("dragEnd velocity=" + velocity);
    }

    void drag() {
        DotwelDrawerTrace.log("ACTION_MOVE");
    }
}
EOF
expect_fail_contains 'per-MOVE logging fails' "$move_log" 'must not log per-MOVE events'

no_trace="$TMP_DIR/no-trace"
cp -R "$clean" "$no_trace"
write_file "$no_trace/scripts/emulator-smoke.sh" <<'EOF'
#!/bin/sh
open_app_drawer() {
    :
}
EOF
expect_fail_contains 'missing per-attempt trace capture fails' \
    "$no_trace" 'does not capture the DotwelDrawerTrace tag'

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-drawer-trace guard tests passed\n'
