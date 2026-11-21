#!/bin/sh
# Tests for scripts/play-brand-guard.sh.
# Run with: sh scripts/play-brand-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/play-brand-guard.sh"
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
    fail 'play-brand-guard.sh exists'
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
    flavorDimensions += ["app", "recents", "channel"]
    productFlavors {
        lawn {
            dimension "app"
        }
        withQuickstep {
            dimension "recents"
        }
        nightly {
            dimension "channel"
        }
        play {
            dimension "channel"
            manifest.srcFile "play/AndroidManifest.xml"
        }
    }
    sourceSets {
        lawn {
            res.srcDirs = ["lawnchair/res"]
        }
        nightly {
            res.srcDirs = ["nightly/res"]
        }
        lawnWithQuickstepPlay {
            manifest.srcFile "play/AndroidManifest.xml"
            res.srcDirs = ["play/res"]
        }
    }
}
androidComponents {
    onVariants(selector().all()) { variant ->
        def channel = variant.productFlavors.last().second
        if (channel == "play") {
            variant.resValues.put(
                variant.makeResValueKey("string", "derived_app_name"),
                new com.android.build.api.variant.ResValue("DotWel Launcher", "Play display label")
            )
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/about/About.kt" <<'EOF'
package app.lawnchair.ui.preferences.about

val aboutIcon = R.drawable.ic_launcher_home_comp
EOF

    write_file "$root/lawnchair/src/app/lawnchair/smartspace/provider/OnboardingProvider.kt" <<'EOF'
package app.lawnchair.smartspace.provider

val welcome = R.string.onboarding_welcome
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

import app.lawnchair.ui.preferences.components.AnnouncementPreference
import app.lawnchair.ui.util.isPlayStoreFlavor

fun dashboard() {
    if (!isPlayStoreFlavor()) {
        AnnouncementPreference()
    }
}

val tip = R.string.set_default_launcher_tip
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/components/AnnouncementPreference.kt" <<'EOF'
package app.lawnchair.ui.preferences.components

fun AnnouncementPreference() {}
EOF

    write_file "$root/play/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:icon="@mipmap/ic_launcher_home"
        android:roundIcon="@mipmap/ic_launcher_home_round"
        android:label="@string/play_app_name"
        tools:replace="android:label,android:icon" />
</manifest>
EOF

    write_file "$root/NOTICE.md" <<'EOF'
# NOTICE

Derived from Lawnchair, licensed under the Apache License, Version 2.0.
Play display label: DotWel Launcher.
EOF

    write_file "$root/lawnchair/res/values/strings.xml" <<'EOF'
<resources>
    <string name="onboarding_welcome">Welcome to Lawnchair!</string>
    <string name="set_default_launcher_tip">To access shortcuts and additional features, set Lawnchair as your default launcher</string>
</resources>
EOF

    write_file "$root/lawnchair/res/values-de-rDE/strings.xml" <<'EOF'
<resources>
    <string name="onboarding_welcome">Willkommen bei Lawnchair!</string>
</resources>
EOF

    write_file "$root/play/res/values/strings.xml" <<'EOF'
<resources>
    <string name="play_app_name" translatable="false">DotWel Launcher</string>
    <string name="onboarding_welcome">Welcome to DotWel Launcher!</string>
    <string name="set_default_launcher_tip">To access shortcuts and additional features, set DotWel Launcher as your default launcher</string>
</resources>
EOF

    write_file "$root/play/res/values-de-rDE/strings.xml" <<'EOF'
<resources>
    <string name="onboarding_welcome">Willkommen bei DotWel Launcher!</string>
</resources>
EOF

    write_file "$root/play/res/drawable/ic_launcher_home_background.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#0B0B0B" android:pathData="M0,0h108v108h-108z" />
</vector>
EOF

    write_file "$root/play/res/drawable/ic_launcher_home_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFFFFF" android:pathData="M54,54m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
    <path android:fillColor="#D7261E" android:pathData="M72,36m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
</vector>
EOF

    write_file "$root/play/res/drawable/ic_launcher_home_monochrome.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFFFFF" android:pathData="M54,54m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
</vector>
EOF

    write_file "$root/play/res/drawable/ic_launcher_home.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#0B0B0B" android:pathData="M0,0h108v108h-108z" />
    <path android:fillColor="#FFFFFF" android:pathData="M54,54m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
    <path android:fillColor="#D7261E" android:pathData="M72,36m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
</vector>
EOF

    cp "$root/play/res/drawable/ic_launcher_home.xml" \
        "$root/play/res/drawable/ic_launcher_home_comp.xml"

    write_file "$root/play/res/mipmap-anydpi-v26/ic_launcher_home.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_home_background" />
    <foreground android:drawable="@drawable/ic_launcher_home_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_home_monochrome" />
</adaptive-icon>
EOF

    write_file "$root/play/res/mipmap-anydpi-v26/ic_launcher_home_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_home_background" />
    <foreground android:drawable="@drawable/ic_launcher_home_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_home_monochrome" />
</adaptive-icon>
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
expect_pass 'clean fixture passes' "$clean"

missing_round="$TMP_DIR/missing-round"
cp -R "$clean" "$missing_round"
rm "$missing_round/play/res/mipmap-anydpi-v26/ic_launcher_home_round.xml"
expect_fail_contains 'missing round adaptive icon fails' "$missing_round" 'ic_launcher_home_round'

lawnchair_welcome="$TMP_DIR/lawnchair-welcome"
cp -R "$clean" "$lawnchair_welcome"
write_file "$lawnchair_welcome/play/res/values/strings.xml" <<'EOF'
<resources>
    <string name="play_app_name" translatable="false">DotWel Launcher</string>
    <string name="onboarding_welcome">Welcome to Lawnchair!</string>
    <string name="set_default_launcher_tip">To access shortcuts and additional features, set DotWel Launcher as your default launcher</string>
</resources>
EOF
expect_fail_contains 'inherited welcome text fails' "$lawnchair_welcome" 'Lawnchair'

lawnchair_tip="$TMP_DIR/lawnchair-tip"
cp -R "$clean" "$lawnchair_tip"
write_file "$lawnchair_tip/play/res/values/strings.xml" <<'EOF'
<resources>
    <string name="play_app_name" translatable="false">DotWel Launcher</string>
    <string name="onboarding_welcome">Welcome to DotWel Launcher!</string>
    <string name="set_default_launcher_tip">To access shortcuts and additional features, set Lawnchair as your default launcher</string>
</resources>
EOF
expect_fail_contains 'Play default-launcher hint still saying Lawnchair fails' \
    "$lawnchair_tip" 'default-launcher hint still says Lawnchair'

missing_play_tip="$TMP_DIR/missing-play-tip"
cp -R "$clean" "$missing_play_tip"
write_file "$missing_play_tip/play/res/values/strings.xml" <<'EOF'
<resources>
    <string name="play_app_name" translatable="false">DotWel Launcher</string>
    <string name="onboarding_welcome">Welcome to DotWel Launcher!</string>
</resources>
EOF
expect_fail_contains 'missing Play default-launcher hint fails' \
    "$missing_play_tip" 'default-launcher hint does not name DotWel Launcher'

rebranded_base_tip="$TMP_DIR/rebranded-base-tip"
cp -R "$clean" "$rebranded_base_tip"
write_file "$rebranded_base_tip/lawnchair/res/values/strings.xml" <<'EOF'
<resources>
    <string name="onboarding_welcome">Welcome to Lawnchair!</string>
    <string name="set_default_launcher_tip">To access shortcuts and additional features, set DotWel Launcher as your default launcher</string>
</resources>
EOF
expect_fail_contains 'rebranding the non-Play inherited hint fails' \
    "$rebranded_base_tip" 'non-Play default-launcher hint no longer keeps the inherited Lawnchair text'

unused_tip="$TMP_DIR/unused-tip"
cp -R "$clean" "$unused_tip"
write_file "$unused_tip/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

val tip = R.string.smartspace_onboarding
EOF
expect_fail_contains 'default-launcher hint consumer drift fails' \
    "$unused_tip" 'Play default-launcher hint override is unused'

ungated_announcement="$TMP_DIR/ungated-announcement"
cp -R "$clean" "$ungated_announcement"
write_file "$ungated_announcement/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

import app.lawnchair.ui.preferences.components.AnnouncementPreference
import app.lawnchair.ui.util.isPlayStoreFlavor

fun dashboard() {
    AnnouncementPreference()
}

val tip = R.string.set_default_launcher_tip
EOF
expect_fail_contains 'an ungated Play announcement card fails' \
    "$ungated_announcement" 'without a !isPlayStoreFlavor() gate'

removed_announcement="$TMP_DIR/removed-announcement"
cp -R "$clean" "$removed_announcement"
write_file "$removed_announcement/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt" <<'EOF'
package app.lawnchair.ui.preferences.destinations

import app.lawnchair.ui.util.isPlayStoreFlavor

val tip = R.string.set_default_launcher_tip
EOF
expect_fail_contains 'removing the non-Play announcement cards fails' \
    "$removed_announcement" 'the non-Play announcements were removed'

dotwel_announcement="$TMP_DIR/dotwel-announcement"
cp -R "$clean" "$dotwel_announcement"
write_file "$dotwel_announcement/lawnchair/src/app/lawnchair/ui/preferences/components/AnnouncementPreference.kt" <<'EOF'
package app.lawnchair.ui.preferences.components

val fakeNews = "DotWel Launcher news"
EOF
expect_fail_contains 'fabricating DotWel news fails' \
    "$dotwel_announcement" 'do not fabricate DotWel news'

play_announcement="$TMP_DIR/play-announcement"
cp -R "$clean" "$play_announcement"
write_file "$play_announcement/play/res/values/announcements.xml" <<'EOF'
<resources>
    <string name="play_announcement">DotWel Launcher news</string>
</resources>
EOF
expect_fail_contains 'Play-only announcement resources fail' \
    "$play_announcement" 'Play resources define announcement/news content'

missing_locale="$TMP_DIR/missing-locale"
cp -R "$clean" "$missing_locale"
rm -r "$missing_locale/play/res/values-de-rDE"
expect_fail_contains 'missing locale override fails' "$missing_locale" 'values-de-rDE'

missing_resvalue="$TMP_DIR/missing-resvalue"
cp -R "$clean" "$missing_resvalue"
write_file "$missing_resvalue/build.gradle" <<'EOF'
android {
    defaultConfig { }
}
EOF
expect_fail_contains 'missing Play derived_app_name override fails' "$missing_resvalue" 'derived_app_name'

wrong_manifest_icon="$TMP_DIR/wrong-manifest-icon"
cp -R "$clean" "$wrong_manifest_icon"
write_file "$wrong_manifest_icon/play/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:icon="@drawable/ic_launcher_home"
        android:roundIcon="@mipmap/ic_launcher_home_round"
        android:label="@string/play_app_name" />
</manifest>
EOF
expect_fail_contains 'non-adaptive manifest icon fails' "$wrong_manifest_icon" '@mipmap/ic_launcher_home'

missing_icon_replace="$TMP_DIR/missing-icon-replace"
cp -R "$clean" "$missing_icon_replace"
write_file "$missing_icon_replace/play/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:icon="@mipmap/ic_launcher_home"
        android:roundIcon="@mipmap/ic_launcher_home_round"
        android:label="@string/play_app_name"
        tools:replace="android:label" />
</manifest>
EOF
expect_fail_contains 'missing android:icon tools:replace directive fails' \
    "$missing_icon_replace" 'tools:replace does not include android:icon'

red_monochrome="$TMP_DIR/red-monochrome"
cp -R "$clean" "$red_monochrome"
write_file "$red_monochrome/play/res/drawable/ic_launcher_home_monochrome.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#D7261E" android:pathData="M54,54m-5.5,0a5.5,5.5 0,1 0,11 0a5.5,5.5 0,1 0,-11 0" />
</vector>
EOF
expect_fail_contains 'red monochrome layer fails' "$red_monochrome" 'monochrome'

missing_notice="$TMP_DIR/missing-notice"
cp -R "$clean" "$missing_notice"
rm "$missing_notice/NOTICE.md"
expect_fail_contains 'missing NOTICE fails' "$missing_notice" 'NOTICE.md'

play_res_loses="$TMP_DIR/play-res-loses"
cp -R "$clean" "$play_res_loses"
write_file "$play_res_loses/build.gradle" <<'EOF'
android {
    flavorDimensions += ["app", "recents", "channel"]
    productFlavors {
        lawn {
            dimension "app"
        }
        withQuickstep {
            dimension "recents"
        }
        nightly {
            dimension "channel"
        }
        play {
            dimension "channel"
            manifest.srcFile "play/AndroidManifest.xml"
            res.srcDirs = ["play/res"]
        }
    }
    sourceSets {
        lawn {
            res.srcDirs = ["lawnchair/res"]
        }
        nightly {
            res.srcDirs = ["nightly/res"]
        }
        lawnWithQuickstepPlay {
            manifest.srcFile "play/AndroidManifest.xml"
        }
    }
}
androidComponents {
    onVariants(selector().all()) { variant ->
        def channel = variant.productFlavors.last().second
        if (channel == "play") {
            variant.resValues.put(
                variant.makeResValueKey("string", "derived_app_name"),
                new com.android.build.api.variant.ResValue("DotWel Launcher", "Play display label")
            )
        }
    }
}
EOF
expect_fail_contains 'play res in the single flavor fails precedence' \
    "$play_res_loses" 'does not own play/res'

lawn_res_lost="$TMP_DIR/lawn-res-lost"
cp -R "$clean" "$lawn_res_lost"
write_file "$lawn_res_lost/build.gradle" <<'EOF'
android {
    flavorDimensions += ["app", "recents", "channel"]
    productFlavors {
        lawn {
            dimension "app"
        }
        withQuickstep {
            dimension "recents"
        }
        nightly {
            dimension "channel"
        }
        play {
            dimension "channel"
            manifest.srcFile "play/AndroidManifest.xml"
        }
    }
    sourceSets {
        nightly {
            res.srcDirs = ["nightly/res"]
        }
        lawnWithQuickstepPlay {
            manifest.srcFile "play/AndroidManifest.xml"
            res.srcDirs = ["play/res"]
        }
    }
}
androidComponents {
    onVariants(selector().all()) { variant ->
        def channel = variant.productFlavors.last().second
        if (channel == "play") {
            variant.resValues.put(
                variant.makeResValueKey("string", "derived_app_name"),
                new com.android.build.api.variant.ResValue("DotWel Launcher", "Play display label")
            )
        }
    }
}
EOF
expect_fail_contains 'lawn resources stripped from github/nightly fails' \
    "$lawn_res_lost" 'lawnchair/res'

unused_about_icon="$TMP_DIR/unused-about-icon"
cp -R "$clean" "$unused_about_icon"
write_file "$unused_about_icon/lawnchair/src/app/lawnchair/ui/preferences/about/About.kt" <<'EOF'
package app.lawnchair.ui.preferences.about

val aboutIcon = R.drawable.ic_launcher
EOF
expect_fail_contains 'About icon consumer drift fails' \
    "$unused_about_icon" 'ic_launcher_home_comp'

unused_welcome="$TMP_DIR/unused-welcome"
cp -R "$clean" "$unused_welcome"
write_file "$unused_welcome/lawnchair/src/app/lawnchair/smartspace/provider/OnboardingProvider.kt" <<'EOF'
package app.lawnchair.smartspace.provider

val welcome = R.string.smartspace_onboarding
EOF
expect_fail_contains 'HOME welcome consumer drift fails' \
    "$unused_welcome" 'onboarding_welcome'

if command -v python3 >/dev/null 2>&1; then
    malformed="$TMP_DIR/malformed"
    cp -R "$clean" "$malformed"
    write_file "$malformed/play/res/drawable/ic_launcher_home_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android">
    <path android:fillColor="#FFFFFF"
</vector>
EOF
    expect_fail_contains 'malformed play XML fails' "$malformed" 'not well-formed'
fi

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all play-brand-guard tests passed\n'
