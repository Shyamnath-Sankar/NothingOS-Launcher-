#!/bin/sh
# Static guard for the P8 Play-only default-home role consent slice.
#
# Proves, without Gradle or an emulator, that:
# - the pure policy requests the platform role only on API 29+ when the role is
#   available and not already held, and otherwise chooses the Home settings
#   fallback;
# - the Android helper uses RoleManager.ROLE_HOME and its own consent intent,
#   never a privileged `cmd role` bypass;
# - the existing PreferencesSetDefaultLauncherWarning is the only UI entry point,
#   is Play-gated, and keeps the inherited ACTION_HOME_SETTINGS fallback;
# - no startup/application/launcher code auto-requests the role.
#
# Usage: scripts/nothingui-home-role-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-home-role-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-home-role-guard: %s\n' "$*" >&2
    exit 1
}

POLICY="$ROOT/lawnchair/src/app/nothingui/settings/DefaultHomeRolePolicy.kt"
CONSENT="$ROOT/lawnchair/src/app/nothingui/settings/DefaultHomeRoleConsent.kt"
DASHBOARD="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"

for file in "$POLICY" "$CONSENT" "$DASHBOARD"; do
    [ -f "$file" ] || fail "missing $file"
done

grep -q 'MIN_SDK_FOR_ROLE_MANAGER = 29' "$POLICY" ||
    fail "RoleManager consent must start at API 29"

grep -q 'enum class Action' "$POLICY" ||
    fail "the policy must expose an explicit action"

grep -q 'REQUEST_ROLE' "$POLICY" ||
    fail "the policy must request the native role"

grep -q 'OPEN_HOME_SETTINGS' "$POLICY" ||
    fail "the policy must keep the Home settings fallback"

grep -q 'sdkInt >= MIN_SDK_FOR_ROLE_MANAGER' "$POLICY" ||
    fail "the policy must gate the role request on the API level"

grep -q 'roleAvailable && !roleHeld' "$POLICY" ||
    fail "the policy must require an available, unowned role"

grep -q 'RoleManager.ROLE_HOME' "$CONSENT" ||
    fail "the helper must use the platform HOME role"

grep -q 'isRoleAvailable' "$CONSENT" ||
    fail "the helper must check role availability"

grep -q 'isRoleHeld' "$CONSENT" ||
    fail "the helper must check whether the role is already held"

grep -q 'createRequestRoleIntent' "$CONSENT" ||
    fail "the helper must use the platform consent intent"

grep -q 'Build.VERSION_CODES.Q' "$CONSENT" ||
    fail "the helper must guard RoleManager behind API 29"

grep -q 'startActivityForResult' "$CONSENT" ||
    fail "the helper must start the consent screen from the settings activity"

if grep -Eq 'add-role-holder|remove-role-holder|cmd role' "$CONSENT"; then
    fail "the helper must not use a privileged role bypass"
fi

grep -q 'isPlayStoreFlavor() && DefaultHomeRoleConsent.requestRole(context)' "$DASHBOARD" ||
    fail "the warning must request the role only on the Play channel"

grep -q 'Settings.ACTION_HOME_SETTINGS' "$DASHBOARD" ||
    fail "the warning must keep the Home settings fallback"

grep -q 'if (!roleRequested)' "$DASHBOARD" ||
    fail "the warning must fall back when the role dialog cannot be shown"

grep -q '(context as? Activity)?.finish()' "$DASHBOARD" ||
    fail "the warning must keep the inherited settings close behavior"

# The role consent entry point must be the user tap in settings. A reference in
# any launcher/application/startup source file would be an automatic request.
helper_refs=$(
    grep -R -l 'DefaultHomeRoleConsent' \
        --include='*.kt' --include='*.java' \
        "$ROOT/lawnchair/src" "$ROOT/src" "$ROOT/quickstep/src" 2>/dev/null |
        sort || true
)
expected_helper_refs=$(printf '%s\n%s\n' "$CONSENT" "$DASHBOARD" | sort)
if [ "$helper_refs" != "$expected_helper_refs" ]; then
    printf 'unexpected DefaultHomeRoleConsent references:\n%s\n' "$helper_refs" >&2
    fail "the role consent helper must only be referenced by the settings warning"
fi

printf 'nothingui-home-role-guard: OK\n'
