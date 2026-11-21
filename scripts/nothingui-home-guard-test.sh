#!/bin/sh
# Tests for scripts/nothingui-home-guard.sh.
# Run with: sh scripts/nothingui-home-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-home-guard.sh"
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
    fail 'nothingui-home-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_fixture() {
    root=$1

    write_file "$root/build.gradle" <<'EOF'
android {
    defaultConfig {
        buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "false"
    }
    productFlavors {
        github {
            dimension "channel"
        }
        nightly {
            dimension "channel"
        }
        play {
            dimension "channel"
            buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "true"
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiFeature.kt" <<'EOF'
package app.nothingui.theme

import com.android.launcher3.BuildConfig

object NothingUiFeature {
    val themeEnabled: Boolean = BuildConfig.NOTHINGUI_THEME_ENABLED
    val homeEnabled: Boolean = BuildConfig.NOTHINGUI_HOME_ENABLED
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/home/NothingUiHomeHeaderView.kt" <<'EOF'
package app.nothingui.home

import app.nothingui.theme.NothingUiPalette
import com.android.launcher3.R

class NothingUiHomeHeaderView {
    val regular = R.font.doto_regular
    val bold = R.font.doto_bold
    val accent = NothingUiPalette.AccentRed
    val tick = "android.intent.action.TIME_TICK"
    val tickAction = "ACTION_TIME_TICK"
    val label = "contentDescription"
    val clock = "DateFormat.is24HourFormat"
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/home/NothingUiHomeClock.kt" <<'EOF'
package app.nothingui.home

object NothingUiHomeClock {
    fun formatClock(): String = "09:41"
    fun formatDate(): String = "SAT 21 NOV"
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/home/NothingUiHomeChrome.kt" <<'EOF'
package app.nothingui.home

object NothingUiHomeChrome {
    fun surfaceColor() = 0
    fun pageIndicatorColor() = 0
}
EOF

    write_file "$root/lawnchair/res/layout/nothingui_home_header.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<app.nothingui.home.NothingUiHomeHeaderView
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
EOF

    write_file "$root/lawnchair/src/app/lawnchair/smartspace/model/SmartspaceMode.kt" <<'EOF'
package app.lawnchair.smartspace.model

import app.nothingui.theme.NothingUiFeature
import com.android.launcher3.R

object LawnchairSmartspace {
    val layout = if (NothingUiFeature.homeEnabled) {
        R.layout.nothingui_home_header
    } else {
        R.layout.smartspace_container
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt" <<'EOF'
package app.lawnchair.preferences

import app.nothingui.theme.NothingUiFeature

class PreferenceManager {
    val themedIcons = BoolPref("themed_icons", NothingUiFeature.homeEnabled, reloadIcons)
    val drawerThemedIcons = BoolPref("drawer_themed_icons", NothingUiFeature.homeEnabled, reloadIcons)
    val forceIconMonochrome = BoolPref("pref_forceIconMonochrome", NothingUiFeature.homeEnabled)
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/LawnchairLauncher.kt" <<'EOF'
package app.lawnchair

import app.nothingui.theme.NothingUiFeature

class LawnchairLauncher {
    fun migrate() {
        if (
            !NothingUiFeature.homeEnabled &&
            prefs.themedIcons.get()
        ) {
            prefs.themedIcons.set(newValue = false)
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/qsb/LawnQsbLayout.kt" <<'EOF'
package app.lawnchair.qsb

import app.nothingui.home.NothingUiHomeChrome
import app.nothingui.theme.NothingUiFeature

class LawnQsbLayout {
    fun style() = if (NothingUiFeature.homeEnabled) {
        NothingUiHomeChrome.surfaceColor()
    } else {
        0
    }
}
EOF

    write_file "$root/src/com/android/launcher3/pageindicators/PageIndicatorDots.java" <<'EOF'
package com.android.launcher3.pageindicators;

import app.nothingui.home.NothingUiHomeChrome;
import app.nothingui.theme.NothingUiFeature;

class PageIndicatorDots {
    int color() {
        return NothingUiFeature.INSTANCE.getHomeEnabled()
                ? NothingUiHomeChrome.INSTANCE.pageIndicatorColor(context)
                : 0;
    }
}
EOF

    write_file "$root/src/com/android/launcher3/Workspace.java" <<'EOF'
package com.android.launcher3;

class Workspace {
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/smartspace/SmartspaceViewContainer.kt" <<'EOF'
package app.lawnchair.smartspace

class SmartspaceViewContainer
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
expect_pass 'clean Play-gated home fixture passes' "$clean"

default_true="$TMP_DIR/default-true"
cp -R "$clean" "$default_true"
write_file "$default_true/build.gradle" <<'EOF'
android {
    defaultConfig {
        buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "true"
    }
    productFlavors {
        play {
            buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "true"
        }
    }
}
EOF
expect_fail_contains 'defaultConfig enabling the home surface fails' \
    "$default_true" 'defaultConfig must disable NOTHINGUI_HOME_ENABLED'

play_off="$TMP_DIR/play-off"
cp -R "$clean" "$play_off"
write_file "$play_off/build.gradle" <<'EOF'
android {
    defaultConfig {
        buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "false"
    }
    productFlavors {
        play {
            buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "false"
        }
    }
}
EOF
expect_fail_contains 'play flavor without the home flag fails' \
    "$play_off" 'the play flavor must enable NOTHINGUI_HOME_ENABLED'

github_on="$TMP_DIR/github-on"
cp -R "$clean" "$github_on"
write_file "$github_on/build.gradle" <<'EOF'
android {
    defaultConfig {
        buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "false"
    }
    productFlavors {
        github {
            buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "true"
        }
        play {
            buildConfigField "boolean", "NOTHINGUI_HOME_ENABLED", "true"
        }
    }
}
EOF
expect_fail_contains 'github enabling the home surface fails' \
    "$github_on" 'the github flavor must not enable the NothingUI home surface'

missing_header="$TMP_DIR/missing-header"
cp -R "$clean" "$missing_header"
write_file "$missing_header/lawnchair/src/app/lawnchair/smartspace/model/SmartspaceMode.kt" <<'EOF'
package app.lawnchair.smartspace.model

import app.nothingui.theme.NothingUiFeature
import com.android.launcher3.R

object LawnchairSmartspace {
    val layout = if (NothingUiFeature.homeEnabled) {
        R.layout.smartspace_container
    } else {
        R.layout.smartspace_container
    }
}
EOF
expect_fail_contains 'smartspace without the NothingUI header fails' \
    "$missing_header" 'does not use the NothingUI header layout'

missing_fallback="$TMP_DIR/missing-fallback"
cp -R "$clean" "$missing_fallback"
write_file "$missing_fallback/lawnchair/src/app/lawnchair/smartspace/model/SmartspaceMode.kt" <<'EOF'
package app.lawnchair.smartspace.model

import app.nothingui.theme.NothingUiFeature
import com.android.launcher3.R

object LawnchairSmartspace {
    val layout = if (NothingUiFeature.homeEnabled) {
        R.layout.nothingui_home_header
    } else {
        R.layout.nothingui_home_header
    }
}
EOF
expect_fail_contains 'smartspace without the inherited fallback fails' \
    "$missing_fallback" 'no longer keeps the inherited smartspace fallback'

missing_doto="$TMP_DIR/missing-doto"
cp -R "$clean" "$missing_doto"
write_file "$missing_doto/lawnchair/src/app/nothingui/home/NothingUiHomeHeaderView.kt" <<'EOF'
package app.nothingui.home

class NothingUiHomeHeaderView {
    val accent = "NothingUiPalette.AccentRed"
    val tickAction = "ACTION_TIME_TICK"
    val label = "contentDescription"
    val clock = "DateFormat.is24HourFormat"
}
EOF
expect_fail_contains 'header without the Doto font fails' \
    "$missing_doto" 'does not use the bundled Doto font'

missing_force="$TMP_DIR/missing-force"
cp -R "$clean" "$missing_force"
write_file "$missing_force/lawnchair/src/app/lawnchair/preferences/PreferenceManager.kt" <<'EOF'
package app.lawnchair.preferences

class PreferenceManager {
    val themedIcons = BoolPref("themed_icons", NothingUiFeature.homeEnabled)
    val forceIconMonochrome = BoolPref("pref_forceIconMonochrome", false)
}
EOF
expect_fail_contains 'monochrome fallback without the Play gate fails' \
    "$missing_force" 'monochrome icon fallback is not defaulted through the Play home gate'

migration_ungated="$TMP_DIR/migration-ungated"
cp -R "$clean" "$migration_ungated"
write_file "$migration_ungated/lawnchair/src/app/lawnchair/LawnchairLauncher.kt" <<'EOF'
package app.lawnchair

class LawnchairLauncher {
    fun migrate() {
        if (prefs.themedIcons.get()) {
            prefs.themedIcons.set(newValue = false)
        }
    }
}
EOF
expect_fail_contains 'ungated legacy icon migration fails' \
    "$migration_ungated" 'legacy themed-icon migration is not gated off'

qsb_ungated="$TMP_DIR/qsb-ungated"
cp -R "$clean" "$qsb_ungated"
write_file "$qsb_ungated/lawnchair/src/app/lawnchair/qsb/LawnQsbLayout.kt" <<'EOF'
package app.lawnchair.qsb

class LawnQsbLayout {
    fun style() = 0
}
EOF
expect_fail_contains 'search chrome without the Play gate fails' \
    "$qsb_ungated" 'search bar chrome is not Play-gated'

dots_ungated="$TMP_DIR/dots-ungated"
cp -R "$clean" "$dots_ungated"
write_file "$dots_ungated/src/com/android/launcher3/pageindicators/PageIndicatorDots.java" <<'EOF'
package com.android.launcher3.pageindicators;

class PageIndicatorDots {
    int color() {
        return 0;
    }
}
EOF
expect_fail_contains 'page indicator without the Play gate fails' \
    "$dots_ungated" 'page indicator recolor is not Play-gated'

workspace_hardwired="$TMP_DIR/workspace-hardwired"
cp -R "$clean" "$workspace_hardwired"
write_file "$workspace_hardwired/src/com/android/launcher3/Workspace.java" <<'EOF'
package com.android.launcher3;

import app.nothingui.home.NothingUiHomeHeaderView;

class Workspace {
    NothingUiHomeHeaderView header;
}
EOF
expect_fail_contains 'hard-wiring the header into Workspace fails' \
    "$workspace_hardwired" 'Workspace.java directly references the NothingUI header'

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-home-guard tests passed\n'
