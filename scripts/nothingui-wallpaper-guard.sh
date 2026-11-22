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

for file in "$CATALOG" "$TARGET" "$APPLIER" "$UI" "$DASHBOARD" "$HOME_PREFS" \
    "$ROUTES" "$NAV" "$PNG" "$VECTOR" "$SOURCE_SVG" "$RECOLORED_SVG" \
    "$PROVENANCE" "$BY_LICENSE" "$ZERO_LICENSE" "$SMOKE"; do
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
grep -Fq 'Cancel preview' "$SMOKE" ||
    fail "the smoke does not exercise the explicit Cancel preview control"
grep -Fq 'wallpaper_lock_preserved' "$SMOKE" ||
    fail "the smoke does not prove the lock wallpaper survived"

printf 'nothingui-wallpaper-guard: OK\n'
