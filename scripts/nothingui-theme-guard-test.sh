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
    headlineLarge = base.headlineLarge.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineMedium = base.headlineMedium.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineSmall = base.headlineSmall.copy(
        fontFamily = DotoFontFamily,
    ),
    titleLarge = base.titleLarge.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineLargeEmphasized = base.headlineLargeEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineMediumEmphasized = base.headlineMediumEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineSmallEmphasized = base.headlineSmallEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    titleLargeEmphasized = base.titleLargeEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    bodyLarge = base.bodyLarge.copy(fontFamily = BodyFontFamily),
    bodyMedium = base.bodyMedium.copy(fontFamily = BodyFontFamily),
    labelSmall = base.labelSmall.copy(fontFamily = BodyFontFamily),
)
EOF

    write_file "$root/lawnchair/src/app/nothingui/theme/NothingUiThemeSample.kt" <<'EOF'
package app.nothingui.theme

@Preview
fun NothingUiThemeSampleScreen() = Unit
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/theme/Theme.kt" <<'EOF'
package app.lawnchair.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiTheme

@Composable
fun LawnchairTheme(
    darkTheme: Boolean = isSelectedThemeDark,
    content: @Composable () -> Unit,
) {
    if (NothingUiFeature.themeEnabled) {
        NothingUiTheme(darkTheme = darkTheme, content = content)
        return
    }

    val colorScheme = getColorScheme(darkTheme = darkTheme)
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        content = content,
    )
}

@Composable
fun ComponentActivity.EdgeToEdge(darkTheme: Boolean = isSelectedThemeDark) {
    LaunchedEffect(darkTheme) {
        Unit
    }
}
EOF

    write_file "$root/src/com/android/launcher3/util/WallpaperThemeManager.kt" <<'EOF'
package com.android.launcher3.util

import android.app.Activity
import android.content.ComponentCallbacks
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import app.lawnchair.theme.UiColorMode
import com.android.launcher3.BuildConfig
import com.android.launcher3.R
import com.android.launcher3.Utilities

class WallpaperThemeManager(private val activity: Activity) :
    ActivityLifecycleCallbacksAdapter, ComponentCallbacks {

    private var themeRes: Int = R.style.AppTheme

    private var recreateToUpdateTheme = false

    init {
        val expectedTheme = Themes.getActivityThemeRes(activity)
        if (expectedTheme != themeRes) {
            themeRes = expectedTheme
            activity.setTheme(expectedTheme)
        }
        logThemeState(expectedTheme, "init")
        if (Utilities.ATLEAST_Q) {
            activity.registerActivityLifecycleCallbacks(this)
        } else {
            activity.application.registerActivityLifecycleCallbacks(this)
        }
        activity.registerComponentCallbacks(this)
    }

    override fun onActivitySaveInstanceState(activity: Activity, bundle: Bundle) =
        bundle.putBoolean("recreate", recreateToUpdateTheme)

    override fun onActivityResumed(resumedActivity: Activity) {
        if (resumedActivity === activity) {
            updateTheme("resume")
        }
    }

    override fun onActivityDestroyed(destroyedActivity: Activity) {
        if (destroyedActivity !== activity) return
        activity.unregisterComponentCallbacks(this)
        if (Utilities.ATLEAST_Q) {
            activity.unregisterActivityLifecycleCallbacks(this)
        } else {
            activity.application.unregisterActivityLifecycleCallbacks(this)
        }
    }

    override fun onConfigurationChanged(config: Configuration) {
        updateTheme("config", config)
        logDeferredConfigurationIfStale(config)
    }

    override fun onLowMemory() {}

    fun updateTheme() = updateTheme("manual")

    private fun updateTheme(source: String, suppliedConfig: Configuration? = null) {
        val expectedTheme = Themes.getActivityThemeRes(activity)
        logThemeState(expectedTheme, source, suppliedConfig)
        if (themeRes == expectedTheme) return
        themeRes = expectedTheme
        activity.setTheme(expectedTheme)
        recreateToUpdateTheme = true
        activity.recreate()
    }

    private fun logDeferredConfigurationIfStale(suppliedConfig: Configuration) {
        if (!BuildConfig.DEBUG) return
        val suppliedNight = isNight(suppliedConfig)
        val activityNight = isNight(activity.resources.configuration)
        if (suppliedNight == activityNight) return
        activity.window?.decorView?.post {
            if (!activity.isDestroyed) {
                logThemeState(Themes.getActivityThemeRes(activity), "config-post", suppliedConfig)
            }
        }
    }

    private fun logThemeState(
        expectedTheme: Int,
        source: String,
        suppliedConfig: Configuration? = null,
    ) {
        if (!BuildConfig.DEBUG) return
        val night = isNight(activity.resources.configuration)
        val appNight = "n/a"
        val suppliedNight = suppliedConfig?.let(::isNight)?.toString() ?: "n/a"
        val resolvedDark = UiColorMode(
            Themes.getAttrInteger(activity, R.attr.uiColorMode),
        ).isDarkTheme
        Log.d(
            TAG,
            "theme-refresh night=$night resolvedDark=$resolvedDark expected=$expectedTheme" +
                " source=$source activity=${activity.javaClass.name}" +
                " suppliedNight=$suppliedNight appNight=$appNight",
        )
    }

    private fun isNight(configuration: Configuration): Boolean =
        configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES

    companion object {
        private const val TAG = "DotWelTheme"
    }
}
EOF

    write_file "$root/lawnchair/src/app/lawnchair/ui/preferences/PreferenceActivity.kt" <<'EOF'
package app.lawnchair.ui.preferences

import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiThemeSampleScreen
import com.android.launcher3.BuildConfig

private const val EXTRA_THEME_SAMPLE = "app.lawnchair.ui.preferences.THEME_SAMPLE"
private const val THEME_SAMPLE_DARK = "dark"

private fun resolveThemeSampleMode(): String? {
    if (!BuildConfig.DEBUG || !NothingUiFeature.themeEnabled) return null
    return EXTRA_THEME_SAMPLE
}

private fun render(mode: String?) {
    val themeSampleMode = mode
    val themeSampleDark = themeSampleMode == THEME_SAMPLE_DARK
    if (themeSampleMode == null) {
        EdgeToEdge()
        NothingUiThemeSampleScreen()
    } else {
        NothingUiThemeSampleScreen()
        EdgeToEdge(darkTheme = themeSampleDark)
    }
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

missing_debug_gate="$TMP_DIR/NothingOS-Launcher/missing-debug-gate"
cp -R "$clean" "$missing_debug_gate"
write_file "$missing_debug_gate/lawnchair/src/app/lawnchair/ui/preferences/PreferenceActivity.kt" <<'EOF'
package app.lawnchair.ui.preferences

import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiThemeSampleScreen

private const val EXTRA_THEME_SAMPLE = "app.lawnchair.ui.preferences.THEME_SAMPLE"

private fun resolveThemeSampleMode(): String? {
    if (!NothingUiFeature.themeEnabled) return null
    NothingUiThemeSampleScreen()
    return EXTRA_THEME_SAMPLE
}
EOF
expect_fail_contains 'theme sample without the debug gate fails' \
    "$missing_debug_gate" 'debug-gated'

missing_sample_mode="$TMP_DIR/NothingOS-Launcher/missing-sample-mode"
cp -R "$clean" "$missing_sample_mode"
write_file "$missing_sample_mode/lawnchair/src/app/lawnchair/ui/preferences/PreferenceActivity.kt" <<'EOF'
package app.lawnchair.ui.preferences

import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiThemeSampleScreen
import com.android.launcher3.BuildConfig

private const val EXTRA_THEME_SAMPLE = "app.lawnchair.ui.preferences.THEME_SAMPLE"
private const val THEME_SAMPLE_DARK = "dark"

private fun resolveThemeSampleMode(): String? {
    if (!BuildConfig.DEBUG || !NothingUiFeature.themeEnabled) return null
    return EXTRA_THEME_SAMPLE
}

private fun render(mode: String?) {
    val themeSampleMode = mode
    val themeSampleDark = themeSampleMode == THEME_SAMPLE_DARK
    if (themeSampleMode == null) {
        EdgeToEdge()
        NothingUiThemeSampleScreen()
    } else {
        NothingUiThemeSampleScreen()
        EdgeToEdge()
    }
}
EOF
expect_fail_contains 'theme sample without explicit sample-mode system bars fails' \
    "$missing_sample_mode" 'sample mode'

missing_explicit_edge="$TMP_DIR/NothingOS-Launcher/missing-explicit-edge"
cp -R "$clean" "$missing_explicit_edge"
write_file "$missing_explicit_edge/lawnchair/src/app/lawnchair/ui/theme/Theme.kt" <<'EOF'
package app.lawnchair.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiTheme

@Composable
fun LawnchairTheme(
    darkTheme: Boolean = isSelectedThemeDark,
    content: @Composable () -> Unit,
) {
    if (NothingUiFeature.themeEnabled) {
        NothingUiTheme(darkTheme = darkTheme, content = content)
        return
    }

    val colorScheme = getColorScheme(darkTheme = darkTheme)
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        content = content,
    )
}

@Composable
fun ComponentActivity.EdgeToEdge() {
    val darkTheme = isSelectedThemeDark
    LaunchedEffect(darkTheme) {
        Unit
    }
}
EOF
expect_fail_contains 'EdgeToEdge without an explicit override fails' \
    "$missing_explicit_edge" 'explicit dark-theme override'

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

missing_theme_gate="$TMP_DIR/NothingOS-Launcher/missing-theme-gate"
cp -R "$clean" "$missing_theme_gate"
write_file "$missing_theme_gate/lawnchair/src/app/lawnchair/ui/theme/Theme.kt" <<'EOF'
package app.lawnchair.ui.theme

import androidx.compose.runtime.Composable
import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiTheme

@Composable
fun LawnchairTheme(
    darkTheme: Boolean = isSelectedThemeDark,
    content: @Composable () -> Unit,
) {
    NothingUiTheme(darkTheme = darkTheme, content = content)
}
EOF
expect_fail_contains 'settings palette without the Play gate fails' \
    "$missing_theme_gate" 'does not gate the NothingUI palette to Play'

hardcoded_theme_dark="$TMP_DIR/NothingOS-Launcher/hardcoded-theme-dark"
cp -R "$clean" "$hardcoded_theme_dark"
write_file "$hardcoded_theme_dark/lawnchair/src/app/lawnchair/ui/theme/Theme.kt" <<'EOF'
package app.lawnchair.ui.theme

import androidx.compose.runtime.Composable
import app.nothingui.theme.NothingUiFeature
import app.nothingui.theme.NothingUiTheme

@Composable
fun LawnchairTheme(
    darkTheme: Boolean = isSelectedThemeDark,
    content: @Composable () -> Unit,
) {
    if (NothingUiFeature.themeEnabled) {
        NothingUiTheme(darkTheme = true, content = content)
        return
    }

    val colorScheme = getColorScheme(darkTheme = darkTheme)
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        content = content,
    )
}
EOF
expect_fail_contains 'settings palette that ignores the resolved darkTheme fails' \
    "$hardcoded_theme_dark" 'does not pass the resolved darkTheme'

missing_heading_doto="$TMP_DIR/NothingOS-Launcher/missing-heading-doto"
cp -R "$clean" "$missing_heading_doto"
write_file "$missing_heading_doto/lawnchair/src/app/nothingui/theme/NothingUiTypography.kt" <<'EOF'
package app.nothingui.theme

private val BodyFontFamily = FontFamily.SansSerif

val NothingUiTypography = base.copy(
    displayLarge = base.displayLarge.copy(fontFamily = DotoFontFamily),
    headlineLarge = base.headlineLarge.copy(fontFamily = BodyFontFamily),
    headlineMedium = base.headlineMedium.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineSmall = base.headlineSmall.copy(
        fontFamily = DotoFontFamily,
    ),
    titleLarge = base.titleLarge.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineLargeEmphasized = base.headlineLargeEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineMediumEmphasized = base.headlineMediumEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    headlineSmallEmphasized = base.headlineSmallEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    titleLargeEmphasized = base.titleLargeEmphasized.copy(
        fontFamily = DotoFontFamily,
    ),
    bodyLarge = base.bodyLarge.copy(fontFamily = BodyFontFamily),
    bodyMedium = base.bodyMedium.copy(fontFamily = BodyFontFamily),
    labelSmall = base.labelSmall.copy(fontFamily = BodyFontFamily),
)
EOF
expect_fail_contains 'a sans-serif headline instead of the dot heading fails' \
    "$missing_heading_doto" 'headlineLarge is not wired to the Doto heading typography'

missing_resume_check="$TMP_DIR/NothingOS-Launcher/missing-resume-check"
cp -R "$clean" "$missing_resume_check"
sed -i.bak '/override fun onActivityResumed/,/^    }$/d' \
    "$missing_resume_check/src/com/android/launcher3/util/WallpaperThemeManager.kt"
rm -f "$missing_resume_check/src/com/android/launcher3/util/WallpaperThemeManager.kt.bak"
expect_fail_contains 'a native theme without the resume check fails' \
    "$missing_resume_check" 'no resume theme check'

missing_theme_cleanup="$TMP_DIR/NothingOS-Launcher/missing-theme-cleanup"
cp -R "$clean" "$missing_theme_cleanup"
sed -i.bak '/unregisterComponentCallbacks(this)/d; /unregisterActivityLifecycleCallbacks(this)/d' \
    "$missing_theme_cleanup/src/com/android/launcher3/util/WallpaperThemeManager.kt"
rm -f "$missing_theme_cleanup/src/com/android/launcher3/util/WallpaperThemeManager.kt.bak"
expect_fail_contains 'a native theme without callback cleanup fails' \
    "$missing_theme_cleanup" 'unregister its component callbacks'

missing_theme_loop_guard="$TMP_DIR/NothingOS-Launcher/missing-theme-loop-guard"
cp -R "$clean" "$missing_theme_loop_guard"
sed -i.bak '/if (themeRes == expectedTheme) return/d' \
    "$missing_theme_loop_guard/src/com/android/launcher3/util/WallpaperThemeManager.kt"
rm -f "$missing_theme_loop_guard/src/com/android/launcher3/util/WallpaperThemeManager.kt.bak"
expect_fail_contains 'a native theme without the no-change guard fails' \
    "$missing_theme_loop_guard" 'lost the no-change theme guard'

missing_theme_source="$TMP_DIR/NothingOS-Launcher/missing-theme-source"
cp -R "$clean" "$missing_theme_source"
sed -i.bak '/source=\$source activity=/d' \
    "$missing_theme_source/src/com/android/launcher3/util/WallpaperThemeManager.kt"
rm -f "$missing_theme_source/src/com/android/launcher3/util/WallpaperThemeManager.kt.bak"
expect_fail_contains 'a native theme without the callback-source trace fails' \
    "$missing_theme_source" 'callback source and activity'

if [ "$failures" -ne 0 ]; then
    printf '%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all nothingui-theme-guard tests passed\n'
