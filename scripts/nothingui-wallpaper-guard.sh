#!/bin/sh
# Static guard for the offline AMOLED wallpaper gallery:
# - exactly the two committed catalogue choices with distinct offline resources;
# - the original Tecdrop PNG keeps its published SHA-256 and rename-only notice;
# - the Torus source/recolored SVG hashes and colour mapping are documented;
# - the vector keeps the 1080x2340 viewport, literal stroke widths and no fill;
# - applying explicitly targets FLAG_SYSTEM only, checks policy and confirms
#   the returned Home ID, with no provider or storage permission;
# - the gallery entry is Play-gated on the settings dashboard.
#
# Usage: scripts/nothingui-wallpaper-guard.sh [repo-root]
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=${1:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}

fail() {
    printf 'nothingui-wallpaper-guard: %s\n' "$*" >&2
    exit 1
}

CATALOG="$ROOT/lawnchair/src/app/nothingui/wallpaper/AmoledWallpaper.kt"
TARGET="$ROOT/lawnchair/src/app/nothingui/wallpaper/AmoledWallpaperTarget.kt"
APPLIER="$ROOT/lawnchair/src/app/nothingui/wallpaper/AmoledWallpaperApplier.kt"
UI="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/AmoledWallpaperPreferences.kt"
DASHBOARD="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/PreferencesDashboard.kt"
HOME_PREFS="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/destinations/HomeScreenPreferences.kt"
ROUTES="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/navigation/PreferenceRoutes.kt"
NAV="$ROOT/lawnchair/src/app/lawnchair/ui/preferences/navigation/PreferenceNavigation.kt"
PNG="$ROOT/lawnchair/res/drawable-nodpi/dotwel_wallpaper_pitch_black.png"
VECTOR="$ROOT/lawnchair/res/drawable-nodpi/dotwel_wallpaper_wireframe_torus.xml"
SOURCE_SVG="$ROOT/docs/wallpapers/wireframe-torus-source.svg"
RECOLORED_SVG="$ROOT/docs/wallpapers/wireframe-torus-recolored.svg"
PROVENANCE="$ROOT/docs/wallpapers/README.md"
BY_LICENSE="$ROOT/licenses/wallpapers/CC-BY-4.0.txt"
ZERO_LICENSE="$ROOT/licenses/wallpapers/CC0-1.0.txt"
SMOKE="$ROOT/scripts/emulator-smoke.sh"
SMOKE_LIB="$ROOT/scripts/emulator-smoke-lib.sh"
LIVE_SERVICE="$ROOT/lawnchair/src/app/nothingui/wallpaper/DotFieldWallpaperService.kt"
LIVE_POLICY="$ROOT/lawnchair/src/app/nothingui/wallpaper/DotFieldWallpaperPolicy.kt"
LIVE_META="$ROOT/play/res/xml/dotwel_dot_field_wallpaper.xml"
LIVE_THUMB="$ROOT/play/res/drawable/dotwel_live_wallpaper_thumbnail.xml"
PLAY_MANIFEST="$ROOT/play/AndroidManifest.xml"
LIVE_TEST="$ROOT/tests/unit/java/app/nothingui/wallpaper/DotFieldWallpaperPolicyTest.kt"

for file in "$CATALOG" "$TARGET" "$APPLIER" "$UI" "$DASHBOARD" "$HOME_PREFS" \
    "$ROUTES" "$NAV" "$PNG" "$VECTOR" "$SOURCE_SVG" "$RECOLORED_SVG" \
    "$PROVENANCE" "$BY_LICENSE" "$ZERO_LICENSE" "$SMOKE" "$SMOKE_LIB" \
    "$LIVE_SERVICE" "$LIVE_POLICY" "$LIVE_META" "$LIVE_THUMB" "$PLAY_MANIFEST" \
    "$LIVE_TEST"; do
    [ -f "$file" ] || fail "missing $file"
done

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# --- asset integrity ------------------------------------------------------

[ "$(sha256 "$PNG")" = 'd0e03819a6d71672180c5c15d2e3d09c7982ebee448f9599acb6a2ee0585181d' ] ||
    fail "the Tecdrop PNG does not keep its published SHA-256"
[ "$(sha256 "$SOURCE_SVG")" = 'db0311a07de8087eba6bfc7afc18d29fc5f239b265fb8f125a7b53058fd074f0' ] ||
    fail "the Torus source SVG does not keep its published SHA-256"
[ "$(sha256 "$RECOLORED_SVG")" = 'cd1c1671c5ad0b7923f70dbae020fb84697a7f2f469e2196576c69545f5612d1' ] ||
    fail "the recolored Torus SVG hash changed"

grep -Fq '1080 2340' "$SOURCE_SVG" || fail "the Torus source viewport is missing"
grep -Fq 'android:viewportWidth="1080"' "$VECTOR" ||
    fail "the vector viewport width is not 1080"
grep -Fq 'android:viewportHeight="2340"' "$VECTOR" ||
    fail "the vector viewport height is not 2340"
grep -Fq 'android:strokeWidth="1.2"' "$VECTOR" ||
    fail "the vector lost the 1.2 stroke width"
grep -Fq 'android:strokeWidth="1.6"' "$VECTOR" ||
    fail "the vector lost the 1.6 stroke width"
grep -Fq 'android:strokeWidth="3"' "$VECTOR" ||
    fail "the vector lost the 3 stroke width"
grep -Fq '#FFD7261E' "$VECTOR" || fail "the accent red recolour is missing"
grep -Fq '#FF171717' "$VECTOR" || fail "the dark grey recolour is missing"
grep -Fq '#FF222222' "$VECTOR" || fail "the mid grey recolour is missing"
if grep -Eq 'gradient|bitmap|aapt:attr|xlink|href=' "$VECTOR"; then
    fail "the vector gained an external or gradient reference"
fi
# --- vector pathData packaging bounds -------------------------------------
#
# AAPT replaces a compiled string longer than its string-pool limit with the
# ASCII sentinel STRING_TOO_LARGE. Keep every source pathData well below that
# limit and prove the split pieces still concatenate to the original geometry.
PYTHON=${PYTHON:-python3}
command -v "$PYTHON" >/dev/null 2>&1 || fail "python3 is required for the vector path checks"
"$PYTHON" - "$VECTOR" <<'PY' || fail "the Torus vector pathData is not safely splittable"
import hashlib
import re
import sys

PATH_LIMIT = 16000
EXPECTED_BYTES = 46572
EXPECTED_SUBPATHS = 69
EXPECTED_SHA256 = '19ee5302492cf69ffae43392267f1fc1b9a386c4ab09634dc266848f528f7bcd'

with open(sys.argv[1], encoding='utf-8') as vector:
    source = vector.read()
path_data = re.findall(r'android:pathData="([^"]*)"', source)
if not path_data:
    sys.exit('the Torus vector has no pathData')
for index, value in enumerate(path_data, 1):
    size = len(value.encode('utf-8'))
    if size >= PATH_LIMIT:
        sys.exit(
            f'pathData #{index} is {size} bytes; split at absolute-M '
            f'subpath boundaries below {PATH_LIMIT} bytes'
        )
joined = ''.join(path_data).encode('utf-8')
if len(joined) != EXPECTED_BYTES:
    sys.exit(f'pathData byte count changed: {len(joined)} != {EXPECTED_BYTES}')
if hashlib.sha256(joined).hexdigest() != EXPECTED_SHA256:
    sys.exit('pathData geometry changed from the original source path')
subpaths = sum(len(re.findall(r'M[^M]*', value)) for value in path_data)
if subpaths != EXPECTED_SUBPATHS:
    sys.exit(f'pathData subpath count changed: {subpaths} != {EXPECTED_SUBPATHS}')
PY

# --- compiled APK sentinel -------------------------------------------------
#
# verify-play-build.sh runs this guard after assembly and before the emulator.
# When the real Play debug APK is present, inspect the packaged Torus resource
# for AAPT's STRING_TOO_LARGE sentinel in ASCII or UTF-16. Source-only and
# minimal-fixture checkouts without build output keep working.
APK_DIR="$ROOT/build/outputs/apk/lawnWithQuickstepPlay/debug"
if [ -d "$APK_DIR" ]; then
    "$PYTHON" - "$APK_DIR" <<'PY' || fail "the compiled Torus XML contains STRING_TOO_LARGE"
import os
import sys
import zipfile

root = sys.argv[1]
apks = []
for base, _, files in os.walk(root):
    for name in files:
        if name.endswith('.apk'):
            apks.append(os.path.join(base, name))
if not apks:
    print('nothingui-wallpaper-guard: no Play debug APK yet; skipping compiled sentinel check')
    sys.exit(0)
needles = [
    b'STRING_TOO_LARGE',
    'STRING_TOO_LARGE'.encode('utf-16-le'),
    'STRING_TOO_LARGE'.encode('utf-16-be'),
]
found = False
for apk in sorted(apks):
    try:
        with zipfile.ZipFile(apk) as archive:
            members = [
                item for item in archive.namelist()
                if os.path.basename(item) == 'dotwel_wallpaper_wireframe_torus.xml'
            ]
            for member in members:
                found = True
                data = archive.read(member)
                for needle in needles:
                    if needle in data:
                        print(
                            f'{os.path.basename(apk)}:{member} contains '
                            'the STRING_TOO_LARGE sentinel',
                            file=sys.stderr,
                        )
                        sys.exit(1)
    except zipfile.BadZipFile:
        print(f'{apk} is not a readable APK', file=sys.stderr)
        sys.exit(1)
if not found:
    print(
        f'{len(apks)} APK(s) found but none packages '
        'dotwel_wallpaper_wireframe_torus.xml',
        file=sys.stderr,
    )
    sys.exit(1)
print(f'nothingui-wallpaper-guard: compiled Torus XML sentinel-free in {len(apks)} APK(s)')
PY
else
    printf 'nothingui-wallpaper-guard: no %s; skipping compiled sentinel check\n' "$APK_DIR"
fi

grep -Fq 'CC BY 4.0' "$PROVENANCE" || fail "the Tecdrop licence is not documented"
grep -Fq 'CC0 1.0' "$PROVENANCE" || fail "the Walldye licence is not documented"
grep -Fq 'renamed' "$PROVENANCE" || fail "the rename-only change notice is not documented"

# --- catalogue ------------------------------------------------------------

grep -Fq 'PITCH_BLACK_ID = "pitch_black"' "$CATALOG" || fail "Pitch Black id changed"
grep -Fq 'WIREFRAME_TORUS_ID = "wireframe_torus"' "$CATALOG" || fail "Torus id changed"
grep -Fq 'R.drawable.dotwel_wallpaper_pitch_black' "$CATALOG" ||
    fail "Pitch Black does not use the bundled drawable"
grep -Fq 'R.drawable.dotwel_wallpaper_wireframe_torus' "$CATALOG" ||
    fail "Torus does not use the bundled vector"
[ "$(grep -c 'AmoledWallpaperKind\.' "$CATALOG")" -ge 2 ] ||
    fail "the two wallpaper kinds are not declared"
grep -Fq 'listOf(pitchBlack, wireframeTorus)' "$CATALOG" ||
    fail "the catalogue is not exactly the two offline choices"
grep -Fq 'CC_BY_4_0_LICENSE = "https://creativecommons.org/licenses/by/4.0/"' "$CATALOG" ||
    fail "the CC BY 4.0 licence URL is missing"
grep -Fq 'CC0_1_0_LICENSE = "https://creativecommons.org/publicdomain/zero/1.0/"' "$CATALOG" ||
    fail "the CC0 1.0 licence URL is missing"
grep -Fq 'licenseUrl = CC_BY_4_0_LICENSE' "$CATALOG" ||
    fail "Pitch Black does not link its CC BY 4.0 licence"
grep -Fq 'licenseUrl = CC0_1_0_LICENSE' "$CATALOG" ||
    fail "Torus does not link its CC0 1.0 licence"

# --- explicit apply, Home only -------------------------------------------

grep -Fq 'WallpaperManager.FLAG_SYSTEM' "$TARGET" || fail "the target flag is not FLAG_SYSTEM"
if grep -Fq 'FLAG_LOCK' "$TARGET" "$APPLIER" "$UI"; then
    fail "the gallery must never target the lock screen"
fi
grep -Fq 'returnedId > 0 && returnedId == currentHomeId' "$TARGET" ||
    fail "success does not require the confirmed Home wallpaper id"
grep -Fq 'manager.isWallpaperSupported' "$APPLIER" ||
    fail "the applier does not check wallpaper support"
grep -Fq 'manager.isSetWallpaperAllowed' "$APPLIER" ||
    fail "the applier does not check device policy"
grep -Fq 'manager.setStream(stream, null, true, AmoledWallpaperTarget.FLAGS)' "$APPLIER" ||
    fail "the PNG is not applied as an existing-resource stream to Home only"
grep -Fq 'manager.setBitmap(bitmap, null, true, AmoledWallpaperTarget.FLAGS)' "$APPLIER" ||
    fail "the vector is not rendered to a bounded bitmap for Home only"
grep -Fq 'manager.getWallpaperId(AmoledWallpaperTarget.FLAGS)' "$APPLIER" ||
    fail "the applier does not confirm the returned Home id"
grep -Fq 'bitmap.recycle()' "$APPLIER" || fail "the temporary bitmap is not released"
if grep -Eq 'FileProvider|content://|READ_MEDIA|MANAGE_EXTERNAL_STORAGE|setWallpaper\(' \
    "$APPLIER" "$CATALOG" "$TARGET"; then
    fail "the gallery introduced a provider, storage permission or legacy setWallpaper call"
fi
grep -Fq 'apply(context, wallpaper)' "$UI" || fail "the UI does not call the applier"
grep -Fq 'enabled = !applying' "$UI" || fail "repeated apply taps are not guarded"
grep -Fq 'TextButton' "$UI" || fail "the source link is not exposed"
grep -Fq 'stringResource(wallpaper.creditRes)' "$UI" ||
    fail "the in-app credit is not shown"
grep -Fq 'changeNoticeRes' "$UI" ||
    fail "the rename-only change notice is not shown"
grep -Fq 'dotwel_wallpaper_preview_hint' "$UI" ||
    fail "the preview-only hint is not shown"
grep -Fq 'wallpaper.licenseUrl' "$UI" ||
    fail "the licence URL is not exposed in the preview"
grep -Fq 'runCatching { uriHandler.openUri(wallpaper.sourceUrl) }' "$UI" ||
    fail "opening the source link is not guarded"
grep -Fq 'runCatching { uriHandler.openUri(wallpaper.licenseUrl) }' "$UI" ||
    fail "opening the licence link is not guarded"
grep -Fq 'dotwel_wallpaper_cancel_preview' "$UI" ||
    fail "the explicit Cancel preview control is missing"
grep -Fq 'enabled = !applying' "$UI" ||
    fail "the Cancel preview control is not disabled during apply"
grep -Fq 'enabled = enabled' "$UI" ||
    fail "the wallpaper tile does not disable selection while applying"
grep -Fq 'if (!applying) {' "$UI" ||
    fail "the tile select handler is not guarded while applying"

# --- Play-only entry, normal navigation ----------------------------------

grep -Fq 'data object AmoledWallpapers : PreferenceRootRoute' "$ROUTES" ||
    fail "the gallery route is missing"
grep -Fq 'composable<AmoledWallpapers>' "$NAV" ||
    fail "the gallery route is not wired into navigation"
grep -Fq 'import app.lawnchair.ui.util.isPlayStoreFlavor' "$NAV" ||
    fail "the navigation route does not use the Play gate"
grep -Fq 'if (isPlayStoreFlavor()) {' "$NAV" ||
    fail "the gallery deep-link route is not Play gated"
grep -Fq 'onNavigate(AmoledWallpapers)' "$DASHBOARD" ||
    fail "the dashboard does not open the gallery"
grep -Fq 'if (isPlayStoreFlavor()) {' "$DASHBOARD" ||
    fail "the dashboard gallery entry is not Play gated"
grep -Fq 'destination = AmoledWallpapers' "$HOME_PREFS" ||
    fail "the Home Screen wallpaper group has no gallery entry"

# --- measured Apply/Cancel scrolling --------------------------------------

grep -Fq 'ui_clickable_label_within' "$SMOKE" ||
    fail "the smoke does not require a fully visible Apply/Cancel control"
grep -Fq 'settings_scroll_target' "$SMOKE" ||
    fail "the smoke does not scroll inside the measured settings container"
grep -Fq '_cwg_measure_control' "$SMOKE" ||
    fail "the smoke has no bounded scroll-to-visible helper"
grep -Fq 'ui_known_scroll_container_bounds' "$SMOKE" ||
    fail "the smoke has no measured at-limit ScrollView fallback"
grep -Fq 'android.widget.ScrollView' "$SMOKE_LIB" ||
    fail "the at-limit viewport fallback does not recognise the real ScrollView class"
grep -Fq 'attr($0, "package") != want_pkg' "$SMOKE_LIB" ||
    fail "the at-limit viewport fallback is not scoped to the app package"
grep -Fq 'if (w <= 0 || h <= 0) return -1' "$SMOKE_LIB" ||
    fail "the at-limit viewport fallback accepts non-positive bounds"
grep -Fq 'Cancel preview' "$SMOKE" ||
    fail "the smoke does not exercise the explicit Cancel preview control"
grep -Fq 'wallpaper_lock_preserved' "$SMOKE" ||
    fail "the smoke does not prove the lock wallpaper survived"
grep -Fq 'wallpaper-home-after-' "$SMOKE" ||
    fail "the smoke does not capture HOME pixels after each explicit apply"

# --- original live wallpaper: Play-only, BIND_WALLPAPER protected -----------
#
# The service is declared only in the Play overlay and is protected by the
# platform BIND_WALLPAPER service permission. This must never become a
# uses-permission and must not add any other manifest permission.

grep -Fq 'android:name="app.nothingui.wallpaper.DotFieldWallpaperService"' "$PLAY_MANIFEST" ||
    fail "the Play manifest does not declare the dot-field live wallpaper"
grep -Fq 'android:permission="android.permission.BIND_WALLPAPER"' "$PLAY_MANIFEST" ||
    fail "the live wallpaper service is not protected by BIND_WALLPAPER"
grep -Fq 'android:name="android.service.wallpaper.WallpaperService"' "$PLAY_MANIFEST" ||
    fail "the live wallpaper service has no WallpaperService action"
grep -Fq 'android:name="android.service.wallpaper"' "$PLAY_MANIFEST" ||
    fail "the live wallpaper service has no wallpaper metadata"
grep -Fq 'android:resource="@xml/dotwel_dot_field_wallpaper"' "$PLAY_MANIFEST" ||
    fail "the live wallpaper metadata resource is not linked"
if grep -Eq 'uses-permission[^>]*BIND_WALLPAPER' "$PLAY_MANIFEST"; then
    fail "BIND_WALLPAPER must stay a service protection, not a uses-permission"
fi
for denied in INTERNET ACCESS_NETWORK_STATE WAKE_LOCK SCHEDULE_EXACT_ALARM \
    FOREGROUND_SERVICE RECORD_AUDIO CAMERA ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION; do
    if grep -Eq "uses-permission[^>]*$denied" "$PLAY_MANIFEST"; then
        fail "the live wallpaper added a forbidden uses-permission: $denied"
    fi
done

grep -Fq 'android:thumbnail="@drawable/dotwel_live_wallpaper_thumbnail"' "$LIVE_META" ||
    fail "the wallpaper metadata has no thumbnail"
grep -Fq 'android:description="@string/dotwel_live_wallpaper_description"' "$LIVE_META" ||
    fail "the wallpaper metadata has no description"
if ! grep -Fq '<vector' "$LIVE_THUMB"; then
    fail "the live wallpaper thumbnail is not a bundled vector"
fi

grep -Fq 'DEFAULT_FRAME_INTERVAL_MS: Long = 66L' "$LIVE_POLICY" ||
    fail "the live wallpaper is not gated to ~15 fps"
grep -Fq 'fun canDraw(): Boolean' "$LIVE_POLICY" ||
    fail "the live wallpaper has no pure draw gate"
grep -Fq 'onEngineDestroyed' "$LIVE_POLICY" ||
    fail "the live wallpaper policy cannot become terminal"
grep -Fq 'if (widthPx <= 0 || heightPx <= 0) return null' "$LIVE_POLICY" ||
    fail "the live wallpaper geometry accepts an invalid surface"

grep -Fq 'override fun onVisibilityChanged(visible: Boolean)' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not react to visibility"
grep -Fq 'override fun onSurfaceDestroyed(holder: SurfaceHolder)' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not react to surface destruction"
grep -Fq 'override fun onDestroy()' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not react to engine destruction"
grep -Fq 'removeCallbacksAndMessages(null)' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not remove every queued draw callback"
grep -Fq 'if (!policy.canDraw()) return' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not gate every posted frame"
grep -Fq 'if (framePending || drawing) return' "$LIVE_SERVICE" ||
    fail "the live wallpaper can enqueue a duplicate frame"
grep -Fq 'private fun cancelAndAwaitIdle()' "$LIVE_SERVICE" ||
    fail "the live wallpaper has no cancel-and-await teardown"
grep -Fq 'while (drawing)' "$LIVE_SERVICE" ||
    fail "teardown can return while a frame is still drawing"
grep -Fq 'idle.await()' "$LIVE_SERVICE" ||
    fail "teardown does not release the lock while waiting for the draw"
grep -Fq 'idle.signalAll()' "$LIVE_SERVICE" ||
    fail "the draw does not publish completion to a waiting teardown"
grep -Fq 'posted=$postedFrames drawn=$drawnFrames' "$LIVE_SERVICE" ||
    fail "the transition trace does not expose frame counters"
grep -Fq 'engine=$engineToken' "$LIVE_SERVICE" ||
    fail "the transition trace does not expose a per-engine identity token"
grep -Fq 'holder.surface.isValid' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not check the real surface"
grep -Fq 'holder.surfaceFrame' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not derive its bounds from the SurfaceHolder frame"
grep -Fq 'canvas.drawCircle' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not draw the dot field on canvas"
grep -Fq 'Log.d(TAG, "$transition $counters")' "$LIVE_SERVICE" ||
    fail "the live wallpaper has no DEBUG-only transition trace"
grep -Fq 'import com.android.launcher3.BuildConfig' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not use the real com.android.launcher3.BuildConfig"
if grep -Fq 'app.lawnchair.BuildConfig' "$LIVE_SERVICE"; then
    fail "the live wallpaper imports a non-existent app.lawnchair.BuildConfig"
fi
grep -Fq 'BuildConfig.DEBUG' "$LIVE_SERVICE" ||
    fail "the live wallpaper does not use BuildConfig.DEBUG"

# The preview phase must never clear the shared log buffer; it keeps a
# read-only baseline and isolates only the appended tail.
grep -Fq 'live-wallpaper-logcat-before.txt' "$SMOKE" ||
    fail "the preview phase has no read-only logcat baseline"
grep -Fq 'live_wallpaper_preview_log_after' "$SMOKE" ||
    fail "the preview phase does not isolate the fresh post-baseline log"
if grep -Eq 'setWallpaperComponent|WallpaperManager\.getInstance|bindService|Runtime\.getRuntime|ProcessBuilder' \
    "$LIVE_SERVICE" "$UI"; then
    fail "the live wallpaper or UI binds/overrides the wallpaper directly"
fi
if grep -Eq 'AlarmManager|WakeLock|LocationManager|SensorManager' "$LIVE_SERVICE"; then
    fail "the live wallpaper must not use alarms, wake locks, location or sensors"
fi
if grep -Eq 'INTERNET|HttpURLConnection|OkHttp|java\.net' "$LIVE_SERVICE"; then
    fail "the live wallpaper must not use the network"
fi

grep -Fq 'WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER' "$UI" ||
    fail "the settings screen does not open the system live preview"
grep -Fq 'WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT' "$UI" ||
    fail "the settings screen does not name the live wallpaper component"
grep -Fq 'ComponentName(context, DotFieldWallpaperService::class.java)' "$UI" ||
    fail "the settings screen does not target the original live wallpaper"
grep -Fq 'catch (notFound: ActivityNotFoundException)' "$UI" ||
    fail "the live preview launch has no resolution failure feedback"
grep -Fq 'dotwel_live_wallpaper_unavailable' "$UI" ||
    fail "the live preview has no unavailable message"
grep -Fq 'private fun openLiveWallpaperPreview(context: Context): Int?' "$UI" ||
    fail "the live preview launch logic is not isolated"
grep -Fq 'liveMessageRes' "$UI" ||
    fail "the live preview has no failure feedback state"

# The two static catalogue choices and all existing apply/Cancel guards stay.
[ "$(grep -c 'AmoledWallpaper(' "$CATALOG")" -ge 3 ] ||
    fail "the static catalogue no longer declares both wallpapers"
grep -Fq 'dotwel_wallpaper_cancel_preview' "$UI" ||
    fail "the static Cancel preview guard was removed"

for test_case in \
    'aFreshEngineDrawsNothing' \
    'zeroOrNegativeSurfaceDimensionsStayInvalid' \
    'surfaceDestroyOrEngineDestroyStopsEveryFutureFrame' \
    'theFrameCadenceIsAboutFifteenFpsAndNeverZero'; do
    grep -Fq "fun $test_case" "$LIVE_TEST" ||
        fail "the live wallpaper policy test is missing $test_case"
done

printf 'nothingui-wallpaper-guard: OK\n'
