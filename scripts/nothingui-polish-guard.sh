#!/bin/sh
# Static guard for the Play polish checkpoint:
# - the unset drawer-opacity default is opaque on Play and inherited on
#   github/nightly, without changing the key or any saved value;
# - every opacity consumer reads the same `drawerOpacity` preference;
# - Play gains ONE Main/Launcher settings entry backed by the existing
#   PreferenceActivity, while HOME stays on the launcher activity and the
#   inherited APPLICATION_PREFERENCES / lawnchair://settings filters survive;
# - the dashboard re-checks the default-home status on resume and only asks the
#   platform role from the user tap, with a guarded Home settings fallback.
#
# Usage: scripts/nothingui-polish-guard.sh [repo-root]
set -eu

usage() {
    printf 'usage: %s [repo-root]\n' "$0" >&2
    exit 2
}

[ "$#" -le 1 ] || usage

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

[ -d "$ROOT" ] || {
    printf 'nothingui-polish-guard: cannot read repo root: %s\n' "$ROOT" >&2
    exit 2
}

fail() {
    printf 'nothingui-polish-guard: %s\n' "$*" >&2
    exit 1
}

DEFAULTS="$ROOT/lawnchair/src/app/nothingui/drawer/DrawerOpacityDefaults.kt"
PREFERENCE_MANAGER="$ROOT/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt"
BASE_PREFERENCES="$ROOT/lawnchair/src/app/lawnchair/preferences/BasePreferenceManager.kt"
DRAWER_PREFERENCES="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/AppDrawerPreferences.kt"
LAWNCHAIR_UTILS="$ROOT/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt"
SCRIM_VIEW="$ROOT/lawnchair/src/app/lawnchair/views/LawnchairScrimView.kt"
ALLAPPS_VIEW="$ROOT/src/com/android/launcher3/allapps/ActivityAllAppsContainerView.java"
PLAY_MANIFEST="$ROOT/play/AndroidManifest.xml"
BASE_MANIFEST="$ROOT/lawnchair/AndroidManifest.xml"
PLAY_STRINGS="$ROOT/play/res/values/strings.xml"
DASHBOARD="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"

for file in "$DEFAULTS" "$PREFERENCE_MANAGER" "$BASE_PREFERENCES" \
    "$DRAWER_PREFERENCES" "$LAWNCHAIR_UTILS" "$SCRIM_VIEW" "$ALLAPPS_VIEW" \
    "$PLAY_MANIFEST" "$BASE_MANIFEST" "$PLAY_STRINGS" "$DASHBOARD"; do
    [ -f "$file" ] || fail "missing $file"
done

# --- Drawer opacity -------------------------------------------------------

grep -Fq 'const val INHERITED_DEFAULT = 0.5f' "$DEFAULTS" ||
    fail "the inherited drawer-opacity default is not 0.5"
grep -Fq 'const val PLAY_DEFAULT = 1.0f' "$DEFAULTS" ||
    fail "the Play drawer-opacity default is not opaque"
grep -Fq 'if (playStoreFlavor) PLAY_DEFAULT else INHERITED_DEFAULT' "$DEFAULTS" ||
    fail "the drawer-opacity default is not gated by the Play flavor"

grep -Fq '"pref_drawerOpacity"' "$PREFERENCE_MANAGER" ||
    fail "the inherited pref_drawerOpacity key was renamed"
grep -Fq 'DrawerOpacityDefaults.forPlayFlavor(isPlayStoreFlavor())' "$PREFERENCE_MANAGER" ||
    fail "the drawer-opacity preference does not use the Play-gated default"

# Unset reads the default; an existing key must still win.
grep -Fq 'sp.getFloat(key, defaultValue)' "$BASE_PREFERENCES" ||
    fail "FloatPref no longer falls back to its default only when the key is unset"
if grep -Eq '(putFloat|editSp).*pref_drawerOpacity' "$PREFERENCE_MANAGER" "$BASE_PREFERENCES"; then
    fail "startup code must not write the drawer-opacity default over a saved value"
fi

grep -Fq 'prefs.drawerOpacity.getAdapter()' "$DRAWER_PREFERENCES" ||
    fail "the opacity slider no longer uses the drawerOpacity preference"
grep -Fq 'prefs.drawerOpacity.get()' "$LAWNCHAIR_UTILS" ||
    fail "the drawer text/background opacity consumer no longer uses drawerOpacity"
grep -Fq 'pm.drawerOpacity.subscribeValues' "$SCRIM_VIEW" ||
    fail "the scrim consumer no longer subscribes to drawerOpacity"
grep -Fq 'pref.getDrawerOpacity().get()' "$ALLAPPS_VIEW" ||
    fail "the all-apps header opacity no longer reads drawerOpacity"

# --- Play settings launcher entry ----------------------------------------

activity_block() {
    awk '
        BEGIN { RS = "</activity>" }
        /<activity/ && /PreferenceActivity/ { print $0 "</activity>"; exit }
    ' "$1"
}

settings_block=$(activity_block "$PLAY_MANIFEST")
[ -n "$settings_block" ] || fail "the Play overlay does not declare PreferenceActivity"

printf '%s\n' "$settings_block" | grep -Fq 'android.intent.action.MAIN' ||
    fail "PreferenceActivity is missing the MAIN action"
printf '%s\n' "$settings_block" | grep -Fq 'android.intent.category.LAUNCHER' ||
    fail "PreferenceActivity is missing the LAUNCHER category"
if printf '%s\n' "$settings_block" | grep -Fq 'android.intent.category.HOME'; then
    fail "the settings entry must not claim HOME"
fi
printf '%s\n' "$settings_block" | grep -Fq 'android:label="@string/play_settings_label"' ||
    fail "the settings entry does not use the clear Play settings label"
printf '%s\n' "$settings_block" | grep -Fq 'tools:replace="android:label"' ||
    fail "the Play activity label override is not explicit"
grep -Fq 'name="play_settings_label"' "$PLAY_STRINGS" ||
    fail "the Play settings label string is missing"

count=$(grep -c 'app.lawnchair.ui.preferences.PreferenceActivity' "$PLAY_MANIFEST" || true)
[ "$count" -eq 1 ] || fail "expected exactly one PreferenceActivity declaration in Play"
if grep -Fq 'activity-alias' "$PLAY_MANIFEST"; then
    fail "settings must not add a second alias entry"
fi

grep -Fq 'android.intent.action.APPLICATION_PREFERENCES' "$BASE_MANIFEST" ||
    fail "APPLICATION_PREFERENCES disappeared from PreferenceActivity"
grep -Fq 'android:scheme="lawnchair"' "$BASE_MANIFEST" ||
    fail "the lawnchair://settings deep link disappeared"

launcher_block=$(awk '
    BEGIN { RS = "</activity>" }
    /<activity/ && /LawnchairLauncher/ { print $0 "</activity>"; exit }
' "$PLAY_MANIFEST")
printf '%s\n' "$launcher_block" | grep -Fq 'android.intent.category.HOME' ||
    fail "the launcher activity no longer resolves HOME"

# --- Default-home dashboard status ---------------------------------------

grep -Fq 'context.isDefaultLauncher()' "$DASHBOARD" ||
    fail "the dashboard does not use the existing default-launcher check"
grep -Fq 'LifecycleResumeEffect(Unit)' "$DASHBOARD" ||
    fail "the dashboard does not refresh the default status on resume"
grep -Fq 'if (!defaultLauncher)' "$DASHBOARD" ||
    fail "the dashboard does not branch on the refreshed default status"
grep -Fq 'isPlayStoreFlavor() && DefaultHomeRoleConsent.requestRole(context)' "$DASHBOARD" ||
    fail "the role request is not user-tap and Play gated"
grep -Fq 'Settings.ACTION_HOME_SETTINGS' "$DASHBOARD" ||
    fail "the Home settings fallback is missing"
grep -Fq 'runCatching' "$DASHBOARD" ||
    fail "the Home settings fallback is not guarded"
if grep -Fq 'DefaultHomeRoleConsent.requestRole' "$ROOT/lawnchair/src/app/lawnchair/LawnchairApp.kt" 2>/dev/null; then
    fail "the role must not be requested automatically at startup"
fi

printf 'nothingui-polish-guard: OK\n'
