#!/bin/sh
# Tests for scripts/nothingui-theme-guard.sh.
# Run with: sh scripts/nothingui-theme-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-theme-guard.sh"
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
    fail 'nothingui-theme-guard.sh exists'
    exit 1
fi

write_file() {
    target=$1
    mkdir -p "$(dirname "$target")"
    cat > "$target"
}

write_font() {
    target=$1
    mkdir -p "$(dirname "$target")"
    printf '\000\001\000\000\000\001\000\000fixture-font-data\n' > "$target"
}

write_fixture() {
    root=$1

    write_font "$root/lawnchair/res/font/doto_regular.ttf"
    write_font "$root/lawnchair/res/font/doto_bold.ttf"
    write_font "$root/lawnchair/res/font/googlesansflex_variable.ttf"

    regular_hash=$(sha256sum "$root/lawnchair/res/font/doto_regular.ttf" | awk '{print $1}')
    bold_hash=$(sha256sum "$root/lawnchair/res/font/doto_bold.ttf" | awk '{print $1}')

    write_file "$root/licenses/fonts/OFL-Doto.txt" <<'EOF'
SIL OPEN FONT LICENSE Version 1.1
Copyright 2024 The Doto Project Authors
EOF

    write_file "$root/licenses/fonts/doto.md" <<EOF
Doto source: https://github.com/google/fonts/tree/7380f7cebbf2250460c23fd301b51bcbab162edf/ofl/doto
Variable source file: Doto[ROND,wght].ttf
sha256 doto_regular.ttf $regular_hash
sha256 doto_bold.ttf $bold_hash
EOF

    write_file "$root/build.gradle" <<'EOF'
android {
    defaultConfig {
        buildConfigField "boolean", "NOTHINGUI_THEME_ENABLED", "false"
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
            buildConfigField "boolean", "NOTHINGUI_THEME_ENABLED", "true"
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiFeature.kt" <<'EOF'
package app.nothingui.theme

import com.android.launcher3.BuildConfig

object NothingUiFeature {
    val themeEnabled: Boolean = BuildConfig.NOTHINGUI_THEME_ENABLED
}

fun NothingUiThemeIfEnabled() = Unit
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiTypography.kt" <<'EOF'
package app.nothingui.theme

private val BodyFontFamily = FontFamily.SansSerif

val NothingUiTypography = base.copy(
    displayLarge = base.displayLarge.copy(fontFamily = DotoFontFamily),
    bodyLarge = base.bodyLarge.copy(fontFamily = BodyFontFamily),
)
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiThemeSample.kt" <<'EOF'
package app.nothingui.theme

@Preview
fun NothingUiThemeSampleScreen() = Unit
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

# Regression for CI53: the checkout parent is named NothingOS-Launcher-, and the
# old scan matched that path segment instead of the font basename.
clean="$TMP_DIR/NothingOS-Launcher/clean"
write_fixture "$clean"
expect_pass 'repo parent named NothingOS-Launcher does not trip the font scan' "$clean"

ndot="$TMP_DIR/NothingOS-Launcher/ndot"
cp -R "$clean" "$ndot"
write_font "$ndot/lawnchair/res/font/ndot_regular.ttf"
expect_fail_contains 'real forbidden ndot basename fails' "$ndot" 'ndot_regular.ttf'

nothing_font="$TMP_DIR/NothingOS-Launcher/nothing-font"
cp -R "$clean" "$nothing_font"
write_font "$nothing_font/lawnchair/res/font/NothingSans.ttf"
expect_fail_contains 'case-insensitive Nothing basename fails' \
    "$nothing_font" 'NothingSans.ttf'

nfont="$TMP_DIR/NothingOS-Launcher/nfont"
cp -R "$clean" "$nfont"
write_font "$nfont/lawnchair/res/font/nfont_display.ttf"
expect_fail_contains 'forbidden nfont basename fails' "$nfont" 'nfont_display.ttf'

provenance="$TMP_DIR/NothingOS-Launcher/provenance"
cp -R "$clean" "$provenance"
printf '\000\001\000\000\000\001\000\000changed-font-data\n' \
    > "$provenance/lawnchair/res/font/doto_bold.ttf"
expect_fail_contains 'changed font without an updated attribution hash fails' \
    "$provenance" 'does not record the doto_bold.ttf hash'

missing_license="$TMP_DIR/NothingOS-Launcher/missing-license"
cp -R "$clean" "$missing_license"
rm "$missing_license/licenses/fonts/OFL-Doto.txt"
expect_fail_contains 'missing OFL license still fails' \
    "$missing_license" 'missing'

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-theme-guard tests passed\n'
