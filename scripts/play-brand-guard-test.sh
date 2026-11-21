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

    write_file "$root/play/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:icon="@mipmap/ic_launcher_home"
        android:roundIcon="@mipmap/ic_launcher_home_round"
        android:label="@string/play_app_name" />
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
</resources>
EOF
expect_fail_contains 'inherited welcome text fails' "$lawnchair_welcome" 'Lawnchair'

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
