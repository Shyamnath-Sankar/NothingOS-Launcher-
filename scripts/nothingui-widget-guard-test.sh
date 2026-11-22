#!/bin/sh
# Tests for scripts/nothingui-widget-guard.sh.
# Run with: sh scripts/nothingui-widget-guard-test.sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUARD="$SCRIPT_DIR/nothingui-widget-guard.sh"
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

write_file() {
    file=$1
    mkdir -p "$(dirname "$file")"
    cat > "$file"
}

build_fixture() {
    root=$1
    write_file "$root/play/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <receiver
            android:name="app.dotwel.widgets.DotWelClockWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/nothingui_clock_widget_info" />
        </receiver>
        <receiver
            android:name="app.dotwel.widgets.DotWelBatteryWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/nothingui_battery_widget_info" />
        </receiver>
        <receiver
            android:name="app.dotwel.widgets.DotWelDeviceWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
                <action android:name="android.appwidget.action.APPWIDGET_OPTIONS_CHANGED" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/nothingui_device_widget_info" />
        </receiver>
    </application>
</manifest>
EOF

    write_file "$root/lawnchair/src/app/dotwel/widgets/DotWelClockWidgetProvider.kt" <<'EOF'
package app.dotwel.widgets

import android.provider.AlarmClock
import app.nothingui.widgets.NothingUiWidgetColors

class DotWelClockWidgetProvider : AppWidgetProvider() {
    companion object {
        fun refreshAll(context: Context) {
            val action = AlarmClock.ACTION_SHOW_ALARMS
            val content = NothingUiWidgetColors.contentColor(context)
            views.setInt(id, "setBackgroundResource", NothingUiWidgetColors.tileDrawable(false))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/NothingUiWidgetColors.kt" <<'EOF'
package app.nothingui.widgets

object NothingUiWidgetColors {
    fun isLightSurface(context: Context): Boolean = !Utilities.isDarkTheme(context)

    fun surfaceColor(lightSurface: Boolean): Int =
        if (lightSurface) NothingUiPalette.Paper else NothingUiPalette.Gray900

    fun contentColor(lightSurface: Boolean): Int =
        if (lightSurface) NothingUiPalette.Ink else NothingUiPalette.White
}
EOF

    write_file "$root/lawnchair/src/app/dotwel/widgets/DotWelBatteryWidgetProvider.kt" <<'EOF'
package app.dotwel.widgets

import app.nothingui.widgets.NothingUiBatteryArt
import app.nothingui.widgets.NothingUiWidgetBudget
import app.nothingui.widgets.NothingUiWidgetColors
import app.nothingui.widgets.NothingUiWidgetMonitor

class DotWelBatteryWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged() {
        val level = BatteryManager.EXTRA_LEVEL
        val scale = BatteryManager.EXTRA_SCALE
        val action = Intent.ACTION_BATTERY_CHANGED
        val fallback = UNKNOWN_PERCENT
        val tap = Intent(Intent.ACTION_POWER_USAGE_SUMMARY)
        val content = NothingUiWidgetColors.contentColor(context)
        appWidgetManager.updateAppWidget(id, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BATTERY_CHANGED -> refreshAll(context, intent)
            Intent.ACTION_POWER_CONNECTED,
            Intent.ACTION_POWER_DISCONNECTED,
            -> refreshAll(context)
        }
    }

    companion object {
        fun refreshAll(context: Context, batteryIntent: Intent? = null) {
            val content = NothingUiWidgetColors.contentColor(context)
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/NothingUiWidgetMonitor.kt" <<'EOF'
package app.nothingui.widgets

import app.dotwel.widgets.DotWelBatteryWidgetProvider
import app.dotwel.widgets.DotWelClockWidgetProvider
import app.dotwel.widgets.DotWelDeviceWidgetProvider

object NothingUiWidgetMonitor {
    fun start(context: Context) {
        val appContext = context.applicationContext
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_BATTERY_CHANGED ->
                        DotWelBatteryWidgetProvider.refreshAll(appContext, intent)
                    Intent.ACTION_POWER_CONNECTED,
                    Intent.ACTION_POWER_DISCONNECTED,
                    -> DotWelBatteryWidgetProvider.refreshAll(appContext)
                    Intent.ACTION_CONFIGURATION_CHANGED -> refreshAll(appContext)
                }
            }
        }
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        refreshAll(appContext)
    }

    private fun refreshAll(context: Context) {
        DotWelClockWidgetProvider.refreshAll(context)
        DotWelBatteryWidgetProvider.refreshAll(context)
        DotWelDeviceWidgetProvider.refreshAll(context)
    }
}
EOF

    write_file "$root/lawnchair/src/app/dotwel/widgets/DotWelDeviceWidgetProvider.kt" <<'EOF'
package app.dotwel.widgets

import android.provider.Settings
import android.os.StatFs
import app.nothingui.widgets.NothingUiDeviceStorage
import app.nothingui.widgets.NothingUiWidgetColors

class DotWelDeviceWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged() {
        val storage = StatFs(context.dataDir.path)
        val total = storage.totalBytes
        val available = storage.availableBytes
        val known = NothingUiDeviceStorage.isKnown(total, available)
        val wifi = Intent(Settings.ACTION_WIFI_SETTINGS)
        val sound = Intent(Settings.ACTION_SOUND_SETTINGS)
        val display = Intent(Settings.ACTION_DISPLAY_SETTINGS)
        val fallback = Intent(Settings.ACTION_SETTINGS)
        val resolved = context.packageManager.resolveActivity(wifi, 0)
        val content = NothingUiWidgetColors.contentColor(context)
        views.setProgressBar(id, 100, NothingUiDeviceStorage.progress(total, available), false)
        appWidgetManager.updateAppWidget(id, views)
    }

    companion object {
        fun refreshAll(context: Context) {
            val content = NothingUiWidgetColors.contentColor(context)
        }
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/NothingUiDeviceStorage.kt" <<'EOF'
package app.nothingui.widgets

object NothingUiDeviceStorage {
    const val UNKNOWN_PERCENT = -1

    fun isKnown(total: Long, available: Long): Boolean =
        total > 0L && available >= 0L && available <= total

    fun usedPercent(total: Long, available: Long): Int {
        if (!isKnown(total, available)) return UNKNOWN_PERCENT
        return ((total - available) * 100 / total).toInt().coerceIn(0, 100)
    }

    fun progress(total: Long, available: Long): Int {
        val percent = usedPercent(total, available)
        return if (percent == UNKNOWN_PERCENT) 0 else percent
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/NothingUiBatteryArt.kt" <<'EOF'
package app.nothingui.widgets

object NothingUiBatteryArt {
    fun render(percent: Int, surfaceColor: Int, contentColor: Int) {
        val config = Bitmap.Config.ARGB_8888
        val label = "$percent%"
        canvas.drawCircle(0f, 0f, 1f, paint)
    }
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/NothingUiWidgetBudget.kt" <<'EOF'
package app.nothingui.widgets

object NothingUiWidgetBudget {
    private const val MAX_DIMENSION_PX = 512
    private const val CAP_FACTOR = 6L
    fun cap(context: Context) = context.getSystemService(WindowManager::class.java)
        .currentWindowMetrics.bounds
}
EOF

    write_file "$root/lawnchair/src/app/nothingui/widgets/DotText.kt" <<'EOF'
package app.nothingui.widgets

object DotText {
    private const val MAX_BYTES = 340_000
}
EOF

    write_file "$root/lawnchair/res/layout/nothingui_widget_clock.xml" <<'EOF'
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android">
    <ImageView
        android:id="@+id/nothingui_clock_surface"
        android:background="@drawable/nothingui_widget_tile_dark"
        android:importantForAccessibility="no" />
    <TextClock
        android:fontFamily="@font/doto_bold"
        android:format12Hour="h:mm"
        android:format24Hour="HH:mm"
        android:autoSizeTextType="uniform"
        android:autoSizeMaxTextSize="64sp"
        android:paddingHorizontal="14dp" />
</FrameLayout>
EOF

    write_file "$root/lawnchair/res/drawable/nothingui_widget_tile_dark.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/nothingui_widget_surface_dark" />
    <corners android:radius="20dp" />
</shape>
EOF

    write_file "$root/lawnchair/res/drawable/nothingui_widget_tile_light.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/nothingui_widget_surface_light" />
    <corners android:radius="20dp" />
</shape>
EOF

    write_file "$root/lawnchair/res/values/colors.xml" <<'EOF'
<resources>
    <color name="nothingui_widget_surface_dark">#FF1A1A1A</color>
    <color name="nothingui_widget_surface_light">#FFF2F2F2</color>
    <color name="nothingui_widget_accent">#FFD7261E</color>
</resources>
EOF

    write_file "$root/lawnchair/res/layout/nothingui_widget_battery.xml" <<'EOF'
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android">
    <ImageView android:id="@+id/nothingui_battery_art" />
</FrameLayout>
EOF

    write_file "$root/lawnchair/res/layout/nothingui_widget_device.xml" <<'EOF'
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android">
    <ImageView android:id="@+id/nothingui_device_surface" />
    <ProgressBar android:id="@+id/nothingui_device_storage_progress" />
    <TextView android:id="@+id/nothingui_device_storage_value" />
    <TextView android:id="@+id/nothingui_device_wifi" />
    <TextView android:id="@+id/nothingui_device_sound" />
    <TextView android:id="@+id/nothingui_device_display" />
</FrameLayout>
EOF

    write_file "$root/lawnchair/res/drawable/nothingui_device_pill_dark.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <corners android:radius="14dp" />
</shape>
EOF

    write_file "$root/lawnchair/res/drawable/nothingui_device_pill_light.xml" <<'EOF'
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <corners android:radius="14dp" />
</shape>
EOF

    write_file "$root/lawnchair/res/xml/nothingui_clock_widget_info.xml" <<'EOF'
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:updatePeriodMillis="0"
    android:targetCellWidth="2"
    android:targetCellHeight="2" />
EOF

    write_file "$root/lawnchair/res/xml/nothingui_battery_widget_info.xml" <<'EOF'
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:targetCellWidth="2"
    android:targetCellHeight="2" />
EOF

    write_file "$root/lawnchair/res/xml/nothingui_device_widget_info.xml" <<'EOF'
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:updatePeriodMillis="0"
    android:targetCellWidth="4"
    android:targetCellHeight="2" />
EOF

    write_file "$root/play/res/xml/default_workspace_4x5.xml" <<'EOF'
<favorites>
    <appwidget
        launcher:className="app.dotwel.widgets.DotWelClockWidgetProvider"
        launcher:packageName="@string/launcher_component"
        launcher:x="0"
        launcher:y="1" />
    <appwidget
        launcher:className="app.dotwel.widgets.DotWelBatteryWidgetProvider"
        launcher:packageName="@string/launcher_component"
        launcher:x="2"
        launcher:y="1" />
    <appwidget
        launcher:className="app.dotwel.widgets.DotWelDeviceWidgetProvider"
        launcher:packageName="@string/launcher_component"
        launcher:spanX="4"
        launcher:x="0"
        launcher:y="3" />
</favorites>
EOF

    write_file "$root/play/res/values/config.xml" <<'EOF'
<resources>
    <item name="config_default_home_icon_size_factor" type="dimen" format="float">0.76</item>
</resources>
EOF

    write_file "$root/play/res/values/dimens.xml" <<'EOF'
<resources>
    <dimen name="qsb_widget_height">48dp</dimen>
</resources>
EOF

    write_file "$root/lawnchair/src/app/lawnchair/LawnchairLauncher.kt" <<'EOF'
package app.lawnchair

class LawnchairLauncher {
    fun onResume() {
        if (NothingUiFeature.homeEnabled) {
            NothingUiWidgetMonitor.start(this)
        }
    }
    fun onPause() {
        NothingUiWidgetMonitor.stop(this)
    }
}
EOF

    write_file "$root/src/com/android/launcher3/AutoInstallsLayout.java" <<'EOF'
class AutoInstallsLayout {
    private String resolveComponentPackage(XmlPullParser parser) {
        final String packageName = getAttributeValue(parser, ATTR_PACKAGE_NAME);
        final int resourceId = getAttributeResourceValue(parser, ATTR_PACKAGE_NAME, 0);
        final int launcherComponentId = mContext.getResources().getIdentifier(
                "launcher_component", "string", mContext.getPackageName());
        final String resourceValue = resourceId != 0 && resourceId != launcherComponentId
                ? mSourceRes.getString(resourceId) : null;
        return WidgetPackageResolver.resolve(
                packageName, resourceId, launcherComponentId,
                mContext.getPackageName(), resourceValue);
    }
}
EOF

    write_file "$root/src/com/android/launcher3/WidgetPackageResolver.java" <<'EOF'
class WidgetPackageResolver {
    static String resolve(String attributeValue, int resourceId,
            int launcherComponentResourceId, String contextPackage, String resourceValue) {
        if (resourceId != 0) {
            if (resourceId == launcherComponentResourceId) return contextPackage;
            return packagePart(resourceValue);
        }
        if (attributeValue != null && attributeValue.startsWith("@string/")) {
            if ("launcher_component".equals(attributeValue.substring("@string/".length()))) {
                return contextPackage;
            }
            if (resourceValue != null) return packagePart(resourceValue);
        }
        return attributeValue;
    }

    static String packagePart(String value) {
        int separator = value.indexOf('/');
        return separator > 0 ? value.substring(0, separator) : value;
    }
}
EOF

    write_file "$root/src/com/android/launcher3/DefaultLayoutParser.java" <<'EOF'
class DefaultLayoutParser {
    protected int verifyAndInsert(ComponentName cn, Bundle extras) {
        if (!bind(cn)) {
            delete(id);
            if (DotWelWidgetProviderPolicy.isOwnDotWelProvider(
                    mContext.getPackageName(), cn.getPackageName(), cn.getClassName())) {
                return super.verifyAndInsert(cn, extras);
            }
            return -1;
        }
        return insert(cn);
    }
}
EOF

    write_file "$root/src/com/android/launcher3/DotWelWidgetProviderPolicy.java" <<'EOF'
final class DotWelWidgetProviderPolicy {
    static final String CLOCK_PROVIDER_CLASS =
            "app.dotwel.widgets.DotWelClockWidgetProvider";
    static final String BATTERY_PROVIDER_CLASS =
            "app.dotwel.widgets.DotWelBatteryWidgetProvider";
    static final String DEVICE_PROVIDER_CLASS =
            "app.dotwel.widgets.DotWelDeviceWidgetProvider";

    static boolean isOwnDotWelProvider(
            String ownPackage, String componentPackage, String componentClass) {
        if (ownPackage == null || componentPackage == null || componentClass == null) {
            return false;
        }
        if (!ownPackage.equals(componentPackage)) {
            return false;
        }
        return CLOCK_PROVIDER_CLASS.equals(componentClass)
                || BATTERY_PROVIDER_CLASS.equals(componentClass)
                || DEVICE_PROVIDER_CLASS.equals(componentClass);
    }
}
EOF

    write_file "$root/scripts/emulator-smoke.sh" <<'EOF'
#!/bin/sh
# Minimal fixture for the widget guard's no-bypass checks.
EOF

    write_file "$root/NOTICE.md" <<'EOF'
## Third-party widget renderer

Adapted from dotline-widgets under the MIT License.
EOF

    write_file "$root/licenses/third-party/dotline-widgets-MIT.txt" <<'EOF'
MIT License

Copyright (c) 2026 oceansde012

Source commit: b53a12aaf09f3572582dbd2c4278ea65f6a83306
EOF
}

expect_pass() {
    name=$1
    root=$2
    if sh "$GUARD" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
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
    if sh "$GUARD" "$root" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        fail "$name (expected failure)"
        return
    fi
    if grep -Fq "$needle" "$TMP_DIR/out" "$TMP_DIR/err"; then
        pass "$name"
    else
        fail "$name (failure did not mention '$needle')"
        cat "$TMP_DIR/out" "$TMP_DIR/err" >&2
    fi
}

clean="$TMP_DIR/clean"
build_fixture "$clean"
expect_pass 'clean Play widget fixture passes' "$clean"

exported="$TMP_DIR/exported"
cp -R "$clean" "$exported"
sed -i '0,/android:exported="false"/s//android:exported="true"/' \
    "$exported/play/AndroidManifest.xml"
expect_fail_contains 'exported widget receiver fails' "$exported" 'is exported'

manifest_battery="$TMP_DIR/manifest-battery"
cp -R "$clean" "$manifest_battery"
printf '%s\n' '<action android:name="android.intent.action.BATTERY_CHANGED" />' \
    >> "$manifest_battery/play/AndroidManifest.xml"
expect_fail_contains 'manifest BATTERY_CHANGED receiver fails' \
    "$manifest_battery" 'tries to receive sticky BATTERY_CHANGED'

not_text_clock="$TMP_DIR/not-text-clock"
cp -R "$clean" "$not_text_clock"
sed -i 's/<TextClock/<AnalogClock/' \
    "$not_text_clock/lawnchair/res/layout/nothingui_widget_clock.xml"
expect_fail_contains 'non-TextClock clock fails' "$not_text_clock" 'not a native TextClock'

wrong_24h="$TMP_DIR/wrong-24h"
cp -R "$clean" "$wrong_24h"
sed -i 's/HH:mm/hh:mm/' \
    "$wrong_24h/lawnchair/res/layout/nothingui_widget_clock.xml"
expect_fail_contains 'wrong 24-hour clock format fails' "$wrong_24h" '24-hour HH:mm format'

partial_update="$TMP_DIR/partial-update"
cp -R "$clean" "$partial_update"
printf '%s\n' 'appWidgetManager.partiallyUpdateAppWidget(id, views)' \
    >> "$partial_update/lawnchair/src/app/dotwel/widgets/DotWelBatteryWidgetProvider.kt"
expect_fail_contains 'partial RemoteViews update fails' "$partial_update" 'partial RemoteViews'

display_metrics="$TMP_DIR/display-metrics"
cp -R "$clean" "$display_metrics"
printf '%s\n' 'val d = context.resources.displayMetrics' \
    >> "$display_metrics/lawnchair/src/app/nothingui/widgets/NothingUiWidgetBudget.kt"
expect_fail_contains 'displayMetrics budget fails' "$display_metrics" 'still reads displayMetrics'

missing_battery="$TMP_DIR/missing-battery"
cp -R "$clean" "$missing_battery"
write_file "$missing_battery/play/res/xml/default_workspace_4x5.xml" <<'EOF'
<favorites>
    <appwidget
        launcher:className="app.dotwel.widgets.DotWelClockWidgetProvider"
        launcher:packageName="@string/launcher_component"
        launcher:x="0"
        launcher:y="1" />
</favorites>
EOF
expect_fail_contains 'fresh layout without the battery fails' \
    "$missing_battery" 'does not seed the battery widget'

google_clock="$TMP_DIR/google-clock"
cp -R "$clean" "$google_clock"
printf '%s\n' 'com.google.android.deskclock' \
    >> "$google_clock/play/res/xml/default_workspace_4x5.xml"
expect_fail_contains 'fresh layout with the Google clock fails' \
    "$google_clock" 'still seeds the Google desk clock'

big_icons="$TMP_DIR/big-icons"
cp -R "$clean" "$big_icons"
sed -i 's/0.76/1.0/' "$big_icons/play/res/values/config.xml"
expect_fail_contains 'unshrunk home icons fail' "$big_icons" 'not 0.76'

no_license="$TMP_DIR/no-license"
cp -R "$clean" "$no_license"
sed -i 's/MIT License/Proprietary/' "$no_license/licenses/third-party/dotline-widgets-MIT.txt"
expect_fail_contains 'missing MIT text fails' "$no_license" 'MIT license text is missing'

no_stop="$TMP_DIR/no-stop"
cp -R "$clean" "$no_stop"
write_file "$no_stop/lawnchair/src/app/lawnchair/LawnchairLauncher.kt" <<'EOF'
class LawnchairLauncher {
    fun onResume() {
        if (NothingUiFeature.homeEnabled) {
            NothingUiWidgetMonitor.start(this)
        }
    }
}
EOF
expect_fail_contains 'unsymmetrical battery lifecycle fails' "$no_stop" 'never stops'

fake_data="$TMP_DIR/fake-data"
cp -R "$clean" "$fake_data"
printf '%s\n' 'val fake = Random.nextInt(100)' \
    >> "$fake_data/lawnchair/src/app/dotwel/widgets/DotWelBatteryWidgetProvider.kt"
expect_fail_contains 'random/fake battery data fails' "$fake_data" 'fake/random data'

no_resolver="$TMP_DIR/no-resolver"
cp -R "$clean" "$no_resolver"
write_file "$no_resolver/src/com/android/launcher3/AutoInstallsLayout.java" <<'EOF'
class AutoInstallsLayout {
    private String getPackageName(String packageName) { return packageName; }
}
EOF
expect_fail_contains 'parser without resource package resolution fails' \
    "$no_resolver" 'cannot resolve a resource package name'

no_resource_id="$TMP_DIR/no-resource-id"
cp -R "$clean" "$no_resource_id"
write_file "$no_resource_id/src/com/android/launcher3/AutoInstallsLayout.java" <<'EOF'
class AutoInstallsLayout {
    private String resolveComponentPackage(String packageName) {
        if (packageName.startsWith("@string/")) return mContext.getPackageName();
        return packageName;
    }
}
EOF
expect_fail_contains 'parser that only matches the @string text prefix fails' \
    "$no_resource_id" 'does not read the compiled package resource id'

hardcoded_package="$TMP_DIR/hardcoded-package"
cp -R "$clean" "$hardcoded_package"
printf '%s\n' '// com.launchernos.dotwellabs' \
    >> "$hardcoded_package/src/com/android/launcher3/AutoInstallsLayout.java"
expect_fail_contains 'parser with a hardcoded applicationId fails' \
    "$hardcoded_package" 'hardcodes the applicationId'

bare_view="$TMP_DIR/bare-view"
cp -R "$clean" "$bare_view"
sed -i 's/<ImageView/<View/' \
    "$bare_view/lawnchair/res/layout/nothingui_widget_clock.xml"
expect_fail_contains 'clock tile using an unsupported bare View fails' \
    "$bare_view" 'unsupported bare View'

wrong_alarm="$TMP_DIR/wrong-alarm"
cp -R "$clean" "$wrong_alarm"
sed -i 's/import android.provider.AlarmClock/import android.app.AlarmClock/' \
    "$wrong_alarm/lawnchair/src/app/dotwel/widgets/DotWelClockWidgetProvider.kt"
expect_fail_contains 'wrong AlarmClock namespace fails' \
    "$wrong_alarm" 'wrong AlarmClock namespace'

provider_theme_attr="$TMP_DIR/provider-theme-attr"
cp -R "$clean" "$provider_theme_attr"
printf '%s\n' 'val ink = NothingUiHomeChrome.textColor(context)' \
    >> "$provider_theme_attr/lawnchair/src/app/dotwel/widgets/DotWelClockWidgetProvider.kt"
expect_fail_contains 'provider theme-attribute lookup fails' \
    "$provider_theme_attr" 'still reads the launcher theme attributes'

colors_theme_attr="$TMP_DIR/colors-theme-attr"
cp -R "$clean" "$colors_theme_attr"
printf '%s\n' 'val dark = Themes.getAttrBoolean(context, R.attr.isMainColorDark)' \
    >> "$colors_theme_attr/lawnchair/src/app/nothingui/widgets/NothingUiWidgetColors.kt"
expect_fail_contains 'widget colour theme-attribute lookup fails' \
    "$colors_theme_attr" 'still read launcher theme attributes'

no_clock_refresh="$TMP_DIR/no-clock-refresh"
cp -R "$clean" "$no_clock_refresh"
sed -i '/DotWelClockWidgetProvider.refreshAll/d' \
    "$no_clock_refresh/lawnchair/src/app/nothingui/widgets/NothingUiWidgetMonitor.kt"
expect_fail_contains 'monitor without clock refresh fails' \
    "$no_clock_refresh" 'does not refresh the clock widget'

power_intent="$TMP_DIR/power-intent"
cp -R "$clean" "$power_intent"
sed -i 's/-> refreshAll(context)$/-> refreshAll(context, intent)/' \
    "$power_intent/lawnchair/src/app/dotwel/widgets/DotWelBatteryWidgetProvider.kt"
expect_fail_contains 'battery power event reusing the power intent fails' \
    "$power_intent" 'passes the power intent into BatteryState.from'

monitor_power_intent="$TMP_DIR/monitor-power-intent"
cp -R "$clean" "$monitor_power_intent"
sed -i 's/-> DotWelBatteryWidgetProvider.refreshAll(appContext)$/-> DotWelBatteryWidgetProvider.refreshAll(appContext, intent)/' \
    "$monitor_power_intent/lawnchair/src/app/nothingui/widgets/NothingUiWidgetMonitor.kt"
expect_fail_contains 'monitor power event reusing the power intent fails' \
    "$monitor_power_intent" 'passes the power intent into BatteryState.from'

no_surface="$TMP_DIR/no-surface"
cp -R "$clean" "$no_surface"
sed -i '/nothingui_clock_surface/d' \
    "$no_surface/lawnchair/res/layout/nothingui_widget_clock.xml"
expect_fail_contains 'clock without a tile surface fails' \
    "$no_surface" 'has no tile surface view'

no_face="$TMP_DIR/no-face"
cp -R "$clean" "$no_face"
sed -i '/surfaceColor/d' \
    "$no_face/lawnchair/src/app/nothingui/widgets/NothingUiBatteryArt.kt"
expect_fail_contains 'battery without a circular face fails' \
    "$no_face" 'does not draw the circular face from the surface token'

no_config_refresh="$TMP_DIR/no-config-refresh"
cp -R "$clean" "$no_config_refresh"
sed -i '/ACTION_CONFIGURATION_CHANGED/d' \
    "$no_config_refresh/lawnchair/src/app/nothingui/widgets/NothingUiWidgetMonitor.kt"
expect_fail_contains 'monitor without configuration refresh fails' \
    "$no_config_refresh" 'does not refresh on configuration changes'

no_pending_fallback="$TMP_DIR/no-pending-fallback"
cp -R "$clean" "$no_pending_fallback"
sed -i '/super.verifyAndInsert(cn, extras)/d' \
    "$no_pending_fallback/src/com/android/launcher3/DefaultLayoutParser.java"
expect_fail_contains 'own provider without the pending fallback fails' \
    "$no_pending_fallback" 'does not preserve an own provider'

loose_policy="$TMP_DIR/loose-policy"
cp -R "$clean" "$loose_policy"
sed -i 's/ownPackage.equals(componentPackage)/true/' \
    "$loose_policy/src/com/android/launcher3/DotWelWidgetProviderPolicy.java"
expect_fail_contains 'own-provider policy without the exact package check fails' \
    "$loose_policy" 'does not require the exact own package'

bind_permission="$TMP_DIR/bind-permission"
cp -R "$clean" "$bind_permission"
printf '%s\n' '<uses-permission android:name="android.permission.BIND_APPWIDGET" />' \
    >> "$bind_permission/play/AndroidManifest.xml"
expect_fail_contains 'Play manifest requesting widget bind fails' \
    "$bind_permission" 'requests the widget-bind permission'

adb_bind="$TMP_DIR/adb-bind"
cp -R "$clean" "$adb_bind"
printf '%s\n' 'adb shell appwidget bind 1' \
    >> "$adb_bind/scripts/emulator-smoke.sh"
expect_fail_contains 'smoke binding widgets through adb fails' \
    "$adb_bind" 'bind widgets through adb'

runtime_grant="$TMP_DIR/runtime-grant"
cp -R "$clean" "$runtime_grant"
printf '%s\n' 'grantRuntimePermission' \
    >> "$runtime_grant/src/com/android/launcher3/DefaultLayoutParser.java"
expect_fail_contains 'parser granting the widget bind at runtime fails' \
    "$runtime_grant" 'tries to grant the widget-bind permission'

if [ "$failures" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nall nothingui-widget-guard tests passed\n'
