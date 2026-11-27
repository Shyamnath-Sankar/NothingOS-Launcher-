#!/bin/sh
# Tests for scripts/nothingui-polish-guard.sh.
# Run with: sh scripts/nothingui-polish-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-polish-guard.sh"
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

[ -f "$GUARD" ] || {
    fail 'nothingui-polish-guard.sh exists'
    exit 1
}

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/lawnchair/src/app/nothingui/drawer/DrawerOpacityDefaults.kt" <<'EOF'
package app.nothingui.drawer

object DrawerOpacityDefaults {
    const val INHERITED_DEFAULT = 0.5f
    const val PLAY_DEFAULT = 1.0f

    fun forPlayFlavor(playStoreFlavor: Boolean): Float =
        if (playStoreFlavor) PLAY_DEFAULT else INHERITED_DEFAULT
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt" <<'EOF'
package app.lawnchair.preferences

import app.lawnchair.ui.util.isPlayStoreFlavor
import app.nothingui.drawer.DrawerOpacityDefaults

class PreferenceManager {
    val drawerOpacity = FloatPref(
        "pref_drawerOpacity",
        DrawerOpacityDefaults.forPlayFlavor(isPlayStoreFlavor()),
        recreate,
    )
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/preferences/BasePreferenceManager.kt" <<'EOF'
package app.lawnchair.preferences

class BasePreferenceManager {
    inner class FloatPref {
        override fun get(): Float {
            currentValue = sp.getFloat(key, defaultValue)
            return currentValue
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/destinations/AppDrawerPreferences.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

fun drawer() {
    adapter = prefs.drawerOpacity.getAdapter()
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/util/LawnchairUtils.kt" <<'EOF'
package app.lawnchair.util

fun overrideAllAppsTextColor() {
    val opacity = prefs.drawerOpacity.get()
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/views/LawnchairScrimView.kt" <<'EOF'
package app.lawnchair.views

class LawnchairScrimView {
    init {
        pm.drawerOpacity.subscribeValues(this) { }
    }
}
EOF

    write_file "$root/src/com/android/launcher3/allapps/ActivityAllAppsContainerView.java" <<'EOF'
package com.android.launcher3.allapps;

class ActivityAllAppsContainerView {
    float opacity() {
        return pref.getDrawerOpacity().get();
    }
}
EOF

    write_file "$root/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity
            android:name="app.lawnchair.LawnchairLauncher"
            android:configChanges="keyboard|keyboardHidden|mcc|mnc|navigation|orientation|screenSize|screenLayout|smallestScreenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.HOME" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    write_file "$root/play/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application>
        <activity
            android:name="app.lawnchair.LawnchairLauncher"
            android:configChanges="keyboard|keyboardHidden|mcc|mnc|navigation|orientation|screenSize|screenLayout|smallestScreenSize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.HOME" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name="app.lawnchair.ui.preferences.PreferenceActivity"
            android:label="@string/play_settings_label"
            tools:replace="android:label">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    write_file "$root/lawnchair/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity android:name="app.lawnchair.ui.preferences.PreferenceActivity">
            <intent-filter>
                <action android:name="android.intent.action.APPLICATION_PREFERENCES" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <data android:scheme="lawnchair" android:host="settings" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    write_file "$root/play/res/values/strings.xml" <<'EOF'
<resources>
    <string name="play_settings_label">DotWel Settings</string>
</resources>
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

fun PreferencesDashboard() {
    var defaultLauncher by remember { mutableStateOf(context.isDefaultLauncher()) }
    LifecycleResumeEffect(Unit) {
        defaultLauncher = context.isDefaultLauncher()
        onPauseOrDispose { }
    }
    if (!defaultLauncher) {
        PreferencesSetDefaultLauncherWarning()
    }
}

fun PreferencesSetDefaultLauncherWarning() {
    val roleRequested = isPlayStoreFlavor() && DefaultHomeRoleConsent.requestRole(context)
    if (!roleRequested) {
        runCatching {
            Intent(Settings.ACTION_HOME_SETTINGS)
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/LawnchairApp.kt" <<'EOF'
package app.lawnchair

class LawnchairApp
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
expect_pass 'the Play polish fixture passes' "$clean"

half_default="$TMP_DIR/half-default"
cp -R "$clean" "$half_default"
sed 's/const val PLAY_DEFAULT = 1.0f/const val PLAY_DEFAULT = 0.5f/' \
    "$half_default/lawnchair/src/app/nothingui/drawer/DrawerOpacityDefaults.kt" \
    > "$half_default/drawer.tmp"
mv "$half_default/drawer.tmp" \
    "$half_default/lawnchair/src/app/nothingui/drawer/DrawerOpacityDefaults.kt"
expect_fail_contains 'a half-opaque Play default fails' \
    "$half_default" 'Play drawer-opacity default is not opaque'

hardcoded="$TMP_DIR/hardcoded"
cp -R "$clean" "$hardcoded"
sed 's#DrawerOpacityDefaults.forPlayFlavor(isPlayStoreFlavor())#.5f#' \
    "$hardcoded/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt" \
    > "$hardcoded/pm.tmp"
mv "$hardcoded/pm.tmp" \
    "$hardcoded/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt"
expect_fail_contains 'a hardcoded drawer default fails' \
    "$hardcoded" 'does not use the Play-gated default'

home_settings="$TMP_DIR/home-settings"
cp -R "$clean" "$home_settings"
sed '/android.intent.category.LAUNCHER/a\                <category android:name="android.intent.category.HOME" />' \
    "$home_settings/play/AndroidManifest.xml" > "$home_settings/play.tmp"
mv "$home_settings/play.tmp" "$home_settings/play/AndroidManifest.xml"
expect_fail_contains 'a settings HOME claim fails' \
    "$home_settings" 'must not claim HOME'

play_ui_mode="$TMP_DIR/play-ui-mode"
cp -R "$clean" "$play_ui_mode"
sed 's/smallestScreenSize"/smallestScreenSize|uiMode"/' \
    "$play_ui_mode/play/AndroidManifest.xml" > "$play_ui_mode/play.tmp"
mv "$play_ui_mode/play.tmp" "$play_ui_mode/play/AndroidManifest.xml"
expect_fail_contains 'Play uiMode config handling fails' \
    "$play_ui_mode" 'still handles uiMode manually'

play_missing_flag="$TMP_DIR/play-missing-flag"
cp -R "$clean" "$play_missing_flag"
sed 's/|orientation//' \
    "$play_missing_flag/play/AndroidManifest.xml" > "$play_missing_flag/play.tmp"
mv "$play_missing_flag/play.tmp" "$play_missing_flag/play/AndroidManifest.xml"
expect_fail_contains 'a missing inherited geometry flag fails' \
    "$play_missing_flag" 'missing inherited flag orientation'

base_ui_mode="$TMP_DIR/base-ui-mode"
cp -R "$clean" "$base_ui_mode"
sed 's/smallestScreenSize"/smallestScreenSize|uiMode"/' \
    "$base_ui_mode/AndroidManifest.xml" > "$base_ui_mode/base.tmp"
mv "$base_ui_mode/base.tmp" "$base_ui_mode/AndroidManifest.xml"
expect_fail_contains 'non-Play uiMode config handling fails' \
    "$base_ui_mode" 'non-Play HOME activity still handles uiMode manually'

no_launcher="$TMP_DIR/no-launcher"
cp -R "$clean" "$no_launcher"
sed '/android.intent.category.LAUNCHER/d' \
    "$no_launcher/play/AndroidManifest.xml" > "$no_launcher/play.tmp"
mv "$no_launcher/play.tmp" "$no_launcher/play/AndroidManifest.xml"
expect_fail_contains 'a missing settings LAUNCHER category fails' \
    "$no_launcher" 'missing the LAUNCHER category'

duplicate="$TMP_DIR/duplicate"
cp -R "$clean" "$duplicate"
sed '/<\/application>/i\        <activity android:name="app.lawnchair.ui.preferences.PreferenceActivity" />' \
    "$duplicate/play/AndroidManifest.xml" > "$duplicate/play.tmp"
mv "$duplicate/play.tmp" "$duplicate/play/AndroidManifest.xml"
expect_fail_contains 'a duplicate settings activity fails' \
    "$duplicate" 'expected exactly one PreferenceActivity'

no_resume="$TMP_DIR/no-resume"
cp -R "$clean" "$no_resume"
sed '/LifecycleResumeEffect(Unit)/d' \
    "$no_resume/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" \
    > "$no_resume/dash.tmp"
mv "$no_resume/dash.tmp" \
    "$no_resume/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"
expect_fail_contains 'a stale default status fails' \
    "$no_resume" 'refresh the default status on resume'

unguarded="$TMP_DIR/unguarded"
cp -R "$clean" "$unguarded"
sed '/runCatching/d' \
    "$unguarded/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" \
    > "$unguarded/dash.tmp"
mv "$unguarded/dash.tmp" \
    "$unguarded/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"
expect_fail_contains 'an unguarded Home settings fallback fails' \
    "$unguarded" 'fallback is not guarded'

startup="$TMP_DIR/startup"
cp -R "$clean" "$startup"
printf '\nfun boot() { DefaultHomeRoleConsent.requestRole(context) }\n' \
    >> "$startup/lawnchair/src/app/lawnchair/LawnchairApp.kt"
expect_fail_contains 'a startup role request fails' \
    "$startup" 'must not be requested automatically'

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'nothingui-polish-guard-test: all tests passed\n'
