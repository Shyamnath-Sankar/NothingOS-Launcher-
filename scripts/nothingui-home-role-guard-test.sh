#!/bin/sh
# Tests for scripts/nothingui-home-role-guard.sh.
# Run with: sh scripts/nothingui-home-role-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-home-role-guard.sh"
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
    fail 'nothingui-home-role-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt" <<'EOF'
package app.nothingui.settings

object DefaultHomeRolePolicy {
    const val MIN_SDK_FOR_ROLE_MANAGER = 29

    enum class Action {
        REQUEST_ROLE,
        OPEN_HOME_SETTINGS,
    }

    fun resolve(sdkInt: Int, roleAvailable: Boolean, roleHeld: Boolean): Action {
        return if (sdkInt >= MIN_SDK_FOR_ROLE_MANAGER && roleAvailable && !roleHeld) {
            Action.REQUEST_ROLE
        } else {
            Action.OPEN_HOME_SETTINGS
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/settings/DefaultHomeRoleConsent.kt" <<'EOF'
package app.nothingui.settings

object DefaultHomeRoleConsent {
    fun requestRole(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        roleManager.isRoleAvailable(RoleManager.ROLE_HOME)
        roleManager.isRoleHeld(RoleManager.ROLE_HOME)
        val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME)
        activity.startActivityForResult(intent, REQUEST_HOME_ROLE)
        return true
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

fun PreferencesSetDefaultLauncherWarning() {
    val roleRequested = isPlayStoreFlavor() && DefaultHomeRoleConsent.requestRole(context)
    if (!roleRequested) {
        Intent(Settings.ACTION_HOME_SETTINGS)
        (context as? Activity)?.finish()
    }
}
EOF
}

run_guard() {
    sh "$GUARD" "$1" >/dev/null 2>&1
}

expect_pass() {
    name=$1
    root=$2
    if run_guard "$root"; then
        pass "$name"
    else
        fail "$name"
    fi
}

expect_fail() {
    name=$1
    root=$2
    if run_guard "$root"; then
        fail "$name"
    else
        pass "$name"
    fi
}

positive="$TMP_DIR/positive"
write_fixture "$positive"
expect_pass 'the Play-only native role consent slice passes' "$positive"

api_gate="$TMP_DIR/api-gate"
write_fixture "$api_gate"
sed 's/sdkInt >= MIN_SDK_FOR_ROLE_MANAGER/sdkInt >= 0/' \
    "$api_gate/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt" > "$api_gate/policy.tmp"
mv "$api_gate/policy.tmp" "$api_gate/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt"
expect_fail 'a missing API gate is rejected' "$api_gate"

role_state="$TMP_DIR/role-state"
write_fixture "$role_state"
sed 's/roleAvailable && !roleHeld/roleAvailable/' \
    "$role_state/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt" > "$role_state/policy.tmp"
mv "$role_state/policy.tmp" "$role_state/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt"
expect_fail 'an already-held role must not be re-requested' "$role_state"

play_gate="$TMP_DIR/play-gate"
write_fixture "$play_gate"
sed 's/isPlayStoreFlavor() && DefaultHomeRoleConsent.requestRole(context)/DefaultHomeRoleConsent.requestRole(context)/' \
    "$play_gate/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" > "$play_gate/dashboard.tmp"
mv "$play_gate/dashboard.tmp" "$play_gate/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"
expect_fail 'a non-Play role request is rejected' "$play_gate"

fallback="$TMP_DIR/fallback"
write_fixture "$fallback"
sed '/Settings.ACTION_HOME_SETTINGS/d' \
    "$fallback/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" > "$fallback/dashboard.tmp"
mv "$fallback/dashboard.tmp" "$fallback/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"
expect_fail 'a missing Home settings fallback is rejected' "$fallback"

privileged="$TMP_DIR/privileged"
write_fixture "$privileged"
printf '\n// cmd role add-role-holder\n' \
    >> "$privileged/lawnchair/src/app/nothingui/settings/DefaultHomeRoleConsent.kt"
expect_fail 'a privileged role bypass is rejected' "$privileged"

startup="$TMP_DIR/startup"
write_fixture "$startup"
write_file "$startup/lawnchair/src/app/lawnchair/LauncherStartup.kt" <<'EOF'
package app.lawnchair

fun autoRequestHomeRole() {
    DefaultHomeRoleConsent.requestRole(context)
}
EOF
expect_fail 'a startup auto-request is rejected' "$startup"

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'nothingui-home-role-guard-test: all tests passed\n'
