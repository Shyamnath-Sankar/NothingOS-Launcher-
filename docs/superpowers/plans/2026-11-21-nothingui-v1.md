# NothingUI v1 — implementation plan

Spec: [`docs/superpowers/specs/2026-11-21-nothingui-launcher-design.md`](../specs/2026-11-21-nothingui-launcher-design.md)

Each phase ends with a green gate. Do not start the next phase on a red gate.

---

## P0 — Import the fork and prove it builds

- [ ] `git remote add upstream https://github.com/LawnchairLauncher/lawnchair.git`
- [ ] `git fetch upstream 16-dev`
- [ ] `git merge --allow-unrelated-histories upstream/16-dev`
      - resolve: keep our `README.md` (attributed), union `.gitignore`, keep `AGENTS.md`
- [ ] init submodules: `git submodule update --init --recursive`
- [ ] `git tag upstream-16-dev-base` (anchor for future merges)
- [ ] **Gate:** `./gradlew assembleLawnWithQuickstepPlayDebug` on the untouched fork

Local SDK for `compileSdk 37` / `buildToolsVersion 37.0.0` must be installed, or the build fails with
`Failed to find target with hash string 'android-37'`. That is an SDK-install problem, not an
Android 17 problem.

## P1 — Play-safe build (the compliance gate)

- [ ] `play/AndroidManifest.xml`: `tools:node="remove"` for `READ_CONTACTS`, `READ_MEDIA_*`,
      `READ_HISTORY_BOOKMARKS`, `PACKAGE_USAGE_STATS`, `INTERACT_ACROSS_USERS*`, `MANAGE_USERS`,
      `FORCE_STOP_PACKAGES`, `STATUS_BAR_SERVICE`, `SUSPEND_APPS`, QSB, Smartspacer.
- [ ] remove `LawnchairAccessibilityService` from the Play variant + its settings entry point.
- [ ] remove feed / foreground-sync components from the Play variant.
- [ ] add `ACCESS_HIDDEN_PROFILES` + private-space containers; locked profiles never surface in
      drawer, search or recents.
- [ ] `scripts/manifest-guard.sh`: dump merged manifest, fail on any forbidden permission/component.
- [ ] **Gate:** guard passes on `lawnPlay`; merged manifest reviewed by hand once.

## P2 — Rebrand

- [x] `applicationId com.launchernos.dotwellabs` for the Play channel only.
- [x] Play-only app and launcher-activity label: **DotWel Launcher** (single l). github/nightly keep
      their inherited "Lawnchair" branding; this is not a name-clearance claim.
- [x] icon, `mipmap-*` — original geometric dot-grid adaptive icon, Play-only overlay
      (`play/res`), with round and monochrome layers and API 26+ resolution. Visual review pending.
- [x] Play-only `onboarding_welcome` and in-app `derived_app_name` say **DotWel Launcher**;
      github/nightly keep the inherited strings.
- [x] keep `NOTICE` and Apache headers; add our `NOTICE` entry.
- [ ] **Gate:** `assembleLawnPlayDebug` installs and becomes default home on emulator. The CI35
      emulator run verified install, HOME label and role; the in-app `RoleManager` prompt is still
      pending.

## P3 — Theme and home surface

- [ ] `app/nothingui/theme`: monochrome palette, Doto typography, spacing/motion tokens.
- [ ] bundle OFL fonts under `lawnchair/res/font/` + `licenses/fonts/`.
- [ ] 4×6 `DeviceProfile` override; grid math from `WindowMetrics` (Android 17 large-screen rule).
- [ ] monochrome icon treatment hook; dot-matrix page indicator.
- [ ] **Gate:** Compose UI test for grid + `@Preview`s; no jank in workspace scroll.

## P4 — Drawer

- [ ] restyle inherited all-apps; keep A–Z scroller and search.
- [ ] recents + folder rendering in the new visual language.
- [ ] **Gate:** search finds an app in ≤2 characters; profile filtering correct.

## P5 — Widgets (highest API 37 risk)

- [ ] `NothingUiWidgetHost` base: `calculateWidgetMemoryCapBytes()` from `WindowMetrics`,
      downsample helper (`inSampleSize`, `RGB_565`), full-update helper.
- [ ] clock, date, battery (canvas/`RemoteViews`, minimal bitmaps).
- [ ] weather (Glance; decode once in `provideGlance`, zero-bitmap `onCompositionError` fallback).
- [ ] **Gate:** all four on the Android 17 emulator with `adb shell dumpsys appwidget` inside budget;
      no `IllegalArgumentException` in logcat.

## P6 — Wallpaper

- [ ] static original dot-field pack; Photo Picker / `ACTION_GET_CONTENT`; `SET_WALLPAPER`.
- [ ] one `WallpaperService` live wallpaper, paused when not visible.
- [ ] **Gate:** no wake lock held while paused; no jank on home scroll.

## P7 — Icons

- [ ] monochrome processor: `AdaptiveIconDrawable` monochrome layer (33+), grayscale/threshold
      fallback (26–32).
- [ ] cache keyed by package + user + version; invalidate on package change, debounced.
- [ ] **Gate:** unit tests for the threshold path; no main-thread bitmap work.

## P8 — Settings and onboarding

- [ ] Appearance section in existing Compose preferences: grid size, labels, dock slots, theme.
- [ ] backup/restore wired to the inherited implementation.
- [ ] `RoleManager.ROLE_HOME` onboarding, user-initiated, reversible.
- [ ] **Gate:** Compose UI tests; role request works and can be undone.

## P9 — CI and release

- [ ] adapt `.github/workflows/ci.yml`: `checkout@v7` + `submodules: true`, JDK 21 Zulu,
      `gradle/actions/setup-gradle@v6`, `sdkmanager` install of API 37 + build-tools 37.0.0,
      `spotlessCheck`, `assembleLawnWithQuickstepPlayDebug`, unit tests, manifest guard, APK artifact.
- [ ] add `android-17` emulator job (API 37 system image) for `connectedLawnWithQuickstepPlayDebugAndroidTest`
      and the widget memory check.
- [ ] `release.yml` on `v*`: keystore decode, `bundleLawnWithQuickstepPlayRelease`, upload `.aab` + `mapping.txt`.
- [ ] **Gate:** CI green on `main`; release workflow dry-run on a `v0.0.1-test` tag.

---

## Cross-cutting rules

- Conventional Commits; branch `feat/<slug>`.
- Never commit secrets, keystores, `local.properties` or build output.
- Any permission or manifest change needs human approval and a §7 update in the same PR.
- Report actual command output; never claim a green build that was not run.
