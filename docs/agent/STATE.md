# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: **P9 — Play settings cleanup (inherited announcement cards)**. PR12 is merged into
  `main` (`5da711d`) after fully green CI102 (`10244953269478`, 11m49); actual HOME/drawer/Settings
  foreground, role-consent Cancel and the APK102 fallback were verified. This tiny slice gates the
  inherited upstream announcement cards off in the Play settings dashboard, keeps them for non-Play,
  adds brand-guard negatives, and makes the real settings smoke assert no inherited announcement
  cards before tapping the default-launcher warning. No other UI/theme change.
- branch: `agent/newtinybranchagent-p9-settings`
- head: `ad05a12` (`fix(play): hide inherited announcement cards in settings`) on base `main`
  `5da711d`.
- pr: **none yet** — main owns PR creation/CI approval for this branch. PR12 (#12) is merged and is
  the fallback.

## done (this run — P9 Play settings announcement cleanup)

- **Root cause, read not guessed:** `PreferencesDashboard` called `AnnouncementPreference()`
  unconditionally. That component renders whatever the inherited live-information endpoint
  (`https://lawnchair.app/live-information.json`) returns, which on the actual Play settings screen
  was the Lawnchair 16 sneak-peek card plus two placeholder "important announcement" cards.
- **Play gate:** the dashboard now calls `AnnouncementPreference()` only inside
  `if (!isPlayStoreFlavor())`. The inherited cards disappear on Play; github/nightly keep the exact
  inherited behavior. Nothing was rebranded and no DotWel news card was added.
- **Preserved:** `SyncLiveInformation()`, the debug-build warning, the default-home warning/dialog
  (`PreferencesSetDefaultLauncherWarning` + `DefaultHomeRoleConsent`), the About screen and the
  upstream `NOTICE.md` attribution. No other live-information function, permission, manifest,
  Gradle, SDK, applicationId, signing, paid-service or workflow change.
- **Guard:** `play-brand-guard.sh` now requires exactly one `AnnouncementPreference()` call in the
  dashboard, requires a `!isPlayStoreFlavor()` gate immediately above it, requires the
  `isPlayStoreFlavor` import, rejects a removed non-Play call, rejects `DotWel` in
  `AnnouncementPreference.kt`, and rejects announcement/news/live-information strings in `play/res`.
  Its fixture suite adds ungated-announcement, removed-announcement, fabricated-DotWel-news and
  Play-announcement-resource negatives.
- **Smoke:** `verify_default_home_consent` now captures `role-consent-settings.xml` + the clean
  `role-consent-settings.png`, then asserts the captured hierarchy has no `Lawnchair`, `sneak peek`,
  `important announcement` or `announcement` text **before** tapping the default-launcher warning.
  The genuine 1500 ms / 4-attempt bounded drawer, search, exact Settings foreground, HOME-return and
  role-Cancel checks are unchanged.
- **Verification actually run (no Gradle, no emulator):** `play-brand-guard.sh "$PWD"` OK; its
  fixture suite all pass (including the four new negatives); `emulator-smoke-test.sh` all pass
  (including the new announcement checks and ordering); `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; the repo-level identity, theme, home, home-role, icon and
  drawer-trace guards OK and their suites pass; `sh -n` clean on every edited script;
  `git diff --check` clean. CI must still build, unit-test and run the API 37 smoke.

## done (previous run — 1500 ms harness pacing and gesture input summary)

- **Evidence read, not guessed:** CI100 (`44951103338`) compiled, styled and unit-tested green;
  the real role-consent cancel passed and the Play hint pixels say `DotWel Launcher`. Geometry was
  correct on all four attempts (`start=540,1616 end=540,96 duration=500`), yet the drawer never
  became ready. The actual traces reported last displacement/progress `-726.84 / .37856`,
  `-194.84 / .10148`, `-188.76 / .09831` and `-264.76 / .13790`, all at velocity 0 and accepted
  Normal->AllApps. The requested 1520 px MOVE travel was not fully observed: attempt 1 DOWN
  `21:32:40.016`, dragStart `.072`, dragEnd `41.781` (>500 ms); the others took 1.54/1.29/.98 s.
  `BaseSwipeDetector` deliberately does not update coordinates on ACTION_UP; only MOVE events drive
  progress.
- **Harness pacing:** `scripts/emulator-smoke.sh` now uses a bounded `swipe_duration=1500` (was 500)
  and still logs the duration with every attempt. The four-attempt bound, the genuine swipe,
  search, exact `com.android.settings` foreground and HOME-return assertions are unchanged.
- **Per-gesture input summary:** `AbstractStateChangeTouchController` counts MOVE events and emits
  exactly one `gestureSummary` at UP/CANCEL with `action`, `downX`, `downY`, `downTime`,
  `moveCount`, `lastMoveY`, `lastMoveTime` (`none` when no MOVE arrived), `upY`, `upTime` and
  `history`. It is gated by `DotwelDrawerTrace.ENABLED` (debug Play only) and a start state of
  `NORMAL`, so unrelated input is not logged. There is deliberately no per-MOVE log line.
- **Explicit non-change:** app gesture thresholds, `BaseSwipeDetector`/UP semantics, success
  assertions and the drawer readiness rules were not changed. The longer duration is harness-only.
- **Guards:** `scripts/nothingui-drawer-trace-guard.sh` now requires the summary fields, the debug
  Play and Normal gates, the MOVE counter, and rejects per-MOVE logging (literal and inside a MOVE
  case). Its fixture suite adds missing-summary, realistic per-MOVE and literal per-MOVE negatives.
  `emulator-smoke-test.sh` and `emulator-smoke-drawer-test.sh` require the logged 1500 ms duration.
- **Verification actually run (no Gradle, no emulator):** `nothingui-drawer-trace-guard.sh "$PWD"`
  OK; its suite all pass; `emulator-smoke-test.sh` all pass; `emulator-smoke-drawer-test.sh` all
  pass; `verify-play-build-test.sh`, home/theme/home-role/icon/brand/identity/manifest suites all
  pass; the repo-level identity, brand, theme, home, home-role and icon guards OK; `sh -n` clean on
  every edited script; `git diff --check` clean.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, paid-service or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — dock-row parser and Play default-launcher hint)

- **Root cause from the CI97 actual XML, not guessed:** the dock icons (Phone, Messaging, Contacts,
  WebView Browser Tester) share y=1375..1568. The bottom QSB is three `content-desc="Search"` nodes
  with no resource-id at y=1626..1794, y=1642..1778 and y=1679..1742. The old `ui_dock_bottom`
  selected the deepest labelled node below 55% height, so it returned 1794; `drawer_swipe_target`
  then started at `1794 + (1794 - 1375) / 4 = 1898` instead of 1616. The old synthetic fixture
  omitted those bottom nodes, so it could not catch this.
- **Parser fix:** `ui_dock_bottom` now finds the same lowest labelled row as `ui_dock_top` and takes
  the maximum bottom only from nodes within a 2%-of-height row tolerance. The bottom `Search` nodes
  are excluded even without resource-ids; the existing `search_container_workspace` and `qsb_top`
  exclusions remain. The dock band is therefore 1375..1568 on the actual HOME.
- **Regression:** `scripts/emulator-smoke-test.sh` now uses the full actual hierarchy including all
  three id-less bottom `Search` nodes and derives the target from the parsed dock top/bottom/QSB
  instead of hardcoded values. It asserts dock bottom 1568, start 1616 in the 1568..1626 gutter,
  no 1183 fallback, no 1898 start, >1500 px travel and 0.7917 fraction. Before the parser fix the
  same test failed with dock bottom 1794 and target 1898, proving the regression is real.
  `scripts/emulator-smoke-drawer-test.sh` now uses the same actual hierarchy and requires every
  attempt to start in 1568..1626 and travel more than 1500 px.
- **No gesture/threshold change:** the swipe duration stays at 500 ms. CI97 sampled progress
  .229/.182/.293/.152 at zero release velocity because the start was on the bottom `Search` nodes,
  not because the MOVE sample count was proven low. App gesture logic, the 0.4 success threshold,
  readiness, the genuine swipe/search/Settings-foreground/HOME assertions and the bounded four
  attempts are unchanged; no blind retry or longer duration was added.
- **Play hint:** `play/res/values/strings.xml` now overrides `set_default_launcher_tip` with
  `DotWel Launcher` (single l). `lawnWithQuickstepPlay` already owns `play/res` and outranks the
  single `lawn` flavor, so the combined-variant resource priority is unchanged. The non-Play
  `lawnchair/res/values/strings.xml` text keeps `Lawnchair`, and `NOTICE.md` attribution is
  untouched. `play-brand-guard.sh` now requires the Play hint, rejects `Lawnchair` in it, requires
  the non-Play base to keep `Lawnchair`, and requires `PreferencesDashboard.kt` to still consume
  `R.string.set_default_launcher_tip`. Its fixture suite adds missing-Play-hint, Lawnchair-Play-hint,
  rebranded-non-Play-base and consumer-drift negatives.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass;
  `emulator-smoke-drawer-test.sh` all pass; `play-brand-guard.sh "$PWD"` OK; its fixture suite all
  pass; `nothingui-home-role-guard-test.sh` all pass; `verify-play-build-test.sh` all pass;
  `sh -n` clean on every edited script; `git diff --check` clean. The Android build, unit tests and
  API 37 emulator run are left to CI.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, paid-service, app gesture or threshold change. The untracked local `w/` scratch directory
  was left uncommitted.

## done (previous run — P8 Play-only HOME role consent)

- **Play-only UI entry:** `PreferencesSetDefaultLauncherWarning` now calls
  `DefaultHomeRoleConsent.requestRole(context)` only when `isPlayStoreFlavor()` is true. If the
  platform dialog cannot be shown (API < 29, role unavailable, role already held, or the intent
  throws), it falls through to the inherited `Settings.ACTION_HOME_SETTINGS` path and finishes the
  settings activity exactly as before. Non-Play is unchanged.
- **Pure policy:** `DefaultHomeRolePolicy.resolve` returns `REQUEST_ROLE` only when
  `sdkInt >= 29 && roleAvailable && !roleHeld`; every other case returns `OPEN_HOME_SETTINGS`.
  `DefaultHomeRolePolicyTest` covers API 26, API 28, API 29, unavailable and already-held roles.
- **Native helper:** `DefaultHomeRoleConsent` uses `RoleManager.ROLE_HOME`, `isRoleAvailable`,
  `isRoleHeld` and `createRequestRoleIntent`; it starts the platform consent with
  `startActivityForResult` from the settings activity (or `FLAG_ACTIVITY_NEW_TASK` from a
  non-Activity context). It never uses `cmd role`, `add-role-holder`, or any privileged bypass. The
  result is not interpreted, so cancelling leaves the current default-home choice unchanged. No
  startup/launcher code calls it.
- **Guards:** added `scripts/nothingui-home-role-guard.sh` (7/7 fixture checks) and wired it plus its
  test into `scripts/verify-play-build.sh`. It rejects a missing API gate, a missing already-held
  check, a non-Play request, a missing Home settings fallback, a privileged bypass, and any
  startup/application reference.
- **Smoke:** `scripts/emulator-smoke.sh` now opens the existing settings warning before granting the
  role, taps the warning, waits for the real platform HOME consent, captures
  `role-consent-settings.xml/.png` and `role-consent.xml/.png`, taps the platform Cancel control,
  and requires the role holder list to be unchanged. It then grants the role for the existing
  HOME/drawer/Settings assertions, which are untouched. `emulator-smoke-test.sh` is 69 checks;
  `emulator-smoke-drawer-test.sh` remains 38. `docs/agent/emulator-verification.md` describes the
  new consent phase.
- **Verification actually run (no Gradle, no emulator):** `DefaultHomeRolePolicy` TDD harness RED
  then GREEN; `nothingui-home-role-guard.sh` OK; its suite 7/7; `emulator-smoke-test.sh` 69; drawer
  suite 38; `verify-play-build-test.sh` 11; brand 14, identity 8, manifest 31, theme 9, home 13,
  icon 15, trace 6; `sh -n` clean; `git diff --check` clean. CI must still run the Android build,
  unit tests and the API 37 emulator consent capture.
- **Scope reminder:** no manifest, permission, SDK, Gradle, workflow, applicationId, signing,
  release, paid-service or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — neutral Play icons and QSB)

- **Root cause, not guessed:** the Play policy only changed *which* renderer ran. `MonoIconThemeController`
  and `MonoThemedBitmap` still defaulted to `ThemedIconDrawable.getColors`, and
  `LawnchairProcessInitializer` sets the process-wide `COLORS_LOADER` to the wallpaper-derived
  `Accent1`/`Accent2` swatches. That is why the actual icons and the themed QSB glyph stayed
  blue/lavender after CI93.
- **Neutral palette:** added `NothingUiIconColors` using the original `NothingUiPalette.Ink`/`White`
  pair in `[background, foreground]` order, with the inherited transparent-background preference
  preserved. No wallpaper color is read on the Play path.
- **Inherited loader:** the Play branch of `LawnchairProcessInitializer` now returns the neutral pair,
  so every `ThemedIconDrawable.getColors` consumer (including themed clock icons) is neutral in
  Play. Non-Play keeps the exact inherited accent loader.
- **Controller and cache:** `NothingUiIconThemeController` passes the neutral provider to the native
  renderer and the generated fallback; `LawnchairThemeManager` uses the neutral pair in the Play
  freshness key while keeping `ThemedIconDrawable.getColors` for non-Play.
- **QSB:** `QsbIconUtil.setThemedIconResource` uses `NothingUiHomeChrome.textColor` for themed
  layers and the single-tint path only behind `NothingUiFeature.homeEnabled`. Non-Play keeps
  `QsbIconTint*`/`ColorAccent`. Search actions, accessibility, workspace, wallpaper and the red
  header accent are unchanged.
- **Style:** `NothingUiIconThemeController.policyFor` now puts `NothingUiIconPolicy.resolve(` on the
  same line as `=` with 8-space arguments, fixing the only CI93 spotless/ktlint violation.
- **Tests/guards:** added `NothingUiIconColorsTest` (black/white pairs, neutral channels, contrast,
  stable order). Extended `nothingui-icon-render-guard.sh` and its fixture suite from 13/13 to
  15/15 with the neutral palette, controller provider, Play/non-Play cache keys, QSB gate and
  Play/non-Play loader checks.
- **Verification actually run (no Gradle, no emulator):** `nothingui-icon-render-guard.sh "$PWD"`
  OK; `nothingui-icon-render-guard-test.sh` 15/15; `nothingui-home-guard.sh` OK and suite passes;
  `nothingui-theme-guard.sh` OK and suite passes; `play-brand-guard-test.sh`,
  `play-identity-guard-test.sh`, `manifest-guard-test.sh` and `verify-play-build-test.sh` all pass;
  `sh -n` clean on both edited scripts; `git diff --check` clean. No Android build or emulator run
  happened here; CI must produce the HOME/drawer pixels for review.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, smoke-harness or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — Play icon renderer wiring)

- **Root cause, not guessed:** the Play defaults lived only in `BoolPref` (`themed_icons` and
  `pref_forceIconMonochrome` default true), while the inherited renderer read the raw preference
  keys with false defaults. `LawnchairThemeManager` therefore built no theme controller on a fresh
  Play install, and `MonoIconThemeController`'s forced branch also read
  `shouldForceMonochrome()` with a false default. The provider's force branch returned early before
  icon-pack/per-app overrides, so changing preferences alone could not make the actual pixels
  monochrome and would have ignored explicit choices.
- **Provider wiring:** `LawnchairIconProvider.getIcon` resolves `NothingUiIconPolicy` from the Play
  gate, the themed-icons preference, the force preference and a per-component custom-selection
  decision. The forced native fallback skips the icon pack only when the policy says so; an
  explicit icon-pack or per-app override returns its own drawable and is not replaced.
- **Renderer wiring:** added `NothingUiIconThemeController`, installed only when
  `NothingUiFeature.homeEnabled`. It applies the policy per icon using `SourceHint.key`, delegates
  monochrome-layer apps to the inherited `MonoIconThemeController`, and generates the missing-layer
  fallback with the inherited `MonochromeIconFactory` + `MonoThemedBitmap`. File drawables are not
  forced. Custom selections return no themed bitmap and cached custom entries return
  `ThemedBitmap.NOT_SUPPORTED`.
- **Cache isolation:** the Play `getStateForApp` freshness string now appends the policy cache key
  (`ni=native|fallback|off`), in addition to the existing icon-pack, themed-source, themed, drawer,
  force and override state.
- **Non-Play:** `LawnchairThemeManager` still uses
  `iconControllerFactory.createThemeController()` and the original force-preference branch, and
  the provider keeps the original force/native decision. No non-Play cache string change.
- **Regression actually run (no Gradle, no emulator):** new
  `nothingui-icon-render-guard.sh` OK and its fixture suite 8/8; `nothingui-home-guard.sh` OK and
  13/13; `nothingui-theme-guard.sh` OK and 9/9; drawer-trace guard OK and 6/6;
  `emulator-smoke-test.sh` and `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean.
- **Next:** let CI89+/PR #11 build and confirm the real HOME/drawer pixels are neutral monochrome.
  Then move to the search/QSB slice; do not treat this as visual sign-off until CI pixels are read.
- **Scope reminder:** no Gradle, workflow, SDK, manifest, permission, applicationId, signing,
  release or asset change. Drawer smoke is untouched. No Nothing assets were used. The untracked
  local `w/` scratch directory was left uncommitted.

## done (previous run — actual-home fixture and header rejection)

- **Root cause from CI87, not guessed:** the old fixture invented a bottom QSB node with the
  `search_container_workspace` id at `[0,1640][1080,1775]`, so `ui_qsb_top` returned 1640 and the
  geometry looked correct in tests. The actual UIAutomator dump instead puts that id on the HEADER
  at `[22,91][1058,294]`; the bottom QSB is only visible in the PNG at 1640..1775. The header
  therefore made `qsb_top=91`, failed the `qsb_top > dock_bottom` gutter condition, and fell back
  to `hotseat_top - margin` = 1183. The runtime trace confirmed the same `0.366` progress.
- **Geometry fix:** `ui_qsb_top` now requires a numeric dock bottom and accepts only a
  `search_container_workspace` whose top is strictly below it, so the y=91 header is rejected.
  `ui_dock_bottom` excludes search containers by resource-id, so the dock band is the hotseat
  icons (1375..1568), not the header or QSB. `drawer_target_for_dump` computes `dock_bottom` first
  and passes it to `ui_qsb_top`.
- **No-QSB start:** when the bottom QSB is absent (the actual HOME), `drawer_swipe_target` starts
  at `dock_bottom + (dock_bottom - hotseat_top) / 4`: 1568 + 48 = 1616, ending at 96. Travel is
  1520 px (>1500), start is inside the measured 1568..1640 gutter. A real bottom QSB still uses the
  midpoint start (1604).
- **Duration:** the swipe is now 500 ms instead of 300 ms and the duration is logged with every
  attempt, so adb delivers more MOVE samples for the zero-velocity gesture.
- **Fixtures:** replaced the synthetic bottom-QSB "actual" fixture with the real CI87 HOME shape
  (header at `[22,91][1058,294]`, hotseat node `[0,1375][1080,1920]`, four icons ending at 1568,
  no bottom QSB) and kept a separate real-bottom-QSB fixture. Assertions require start >1568,
  start <1640, travel >1500 and no 1183 fallback. The mock-adb drawer test uses the same actual
  HOME and requires >1500 px travel, a 1568..1640 start and a logged 500 ms duration.
- **Regressions actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 61 checks pass;
  `emulator-smoke-drawer-test.sh` 38 checks pass; `nothingui-drawer-trace-guard-test.sh` 6/6;
  `nothingui-home-guard-test.sh` 13/13; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean.
- **Scope reminder:** no app gesture logic, threshold, animation, manifest, permission, SDK,
  applicationId, signing, release or workflow change. The debug Play `DotwelDrawerTrace` stays
  until the longer gesture is verified in CI. Colored icons and the blue QSB remain pending.

## done (previous run — smoke gesture length only)

- **Root cause read from the actual CI84 trace, not guessed:** the old measured target started at
  y 1183 and ended at y 384 (799 px on a 1920 shift range). The runtime trace showed only
  `-722.0703` displacement and `0.3760783` progress at zero velocity, below the 0.4 phone
  NORMAL→ALL_APPS success threshold, so the launcher snapped back to Normal exactly as designed.
- **Fix in the harness only:** `drawer_swipe_target` now accepts the measured dock icon bottom and
  QSB top. When both are present it starts in the empty gutter between them (actual HOME: dock
  bottom 1568, QSB top 1640 → start 1604) and ends at 5 percent of the display (96 on 1920), a
  1508 px / 78.5 percent travel. Without those measurements it keeps the safe above-dock start.
  The x stays at the horizontal centre because the start row is below every dock icon.
- **New pure helpers:** `ui_dock_bottom` (excludes the QSB and anything at/below its top),
  `ui_qsb_top` (matches the `search_container_workspace` id suffix), `drawer_swipe_is_long_enough`
  (strictly more than half the display height), and `drawer_swipe_travel_fraction`.
- **Orchestration:** `drawer_target_for_dump` measures `ui_dock_top`, `ui_qsb_top` and
  `ui_dock_bottom` from the same pre-swipe HOME XML and passes all three to the geometry. The
  four bounded attempts, before/after XML+PNG, swipe log and per-attempt debug trace are unchanged.
- **Regressions actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` passes with new
  actual-1080x1920 geometry (`540 1604 540 96`, 0.7854), old-799-px reject (0.4161) and CI84
  trace reject (0.3760); `emulator-smoke-drawer-test.sh` passes and now also requires every mock
  attempt to swipe more than half the 1920 px display. Drawer-trace guard 6/6, home guard 13/13,
  theme guard 9/9, brand/identity/manifest suites pass, repo-level identity/brand/theme/home/trace
  guards OK, `sh -n` clean, `git diff --check` clean.
- **Scope reminder:** no app gesture logic, threshold, animation, manifest, permission, SDK,
  applicationId, signing, release or workflow change. The debug Play `DotwelDrawerTrace` stays
  until the longer gesture is verified in CI. Colored icons and the blue QSB remain pending.

## done (previous run — micro compile fix only)

- `Launcher.java` now logs `DisplayController.getNavigationMode(this).name()` (NavigationMode is a
  Java enum), not the invalid `.name` field.
- `AbstractStateChangeTouchController` now routes all four DOWN/UP diagnostics through the existing
  `stateName(...)` helper, and that helper uses `LauncherState.toString()` (the verified
  `TestProtocol.stateOrdinalToString` identifier), not the nonexistent `state.name` field.
- `nothingui-drawer-trace-guard.sh` fails if either file contains a `.name` field access without a
  call (`.name` not followed by `(`); its fixture suite adds navigation-mode and LauncherState
  negatives (now 6/6). The existing debug Play gate, per-attempt `logcat -s DotwelDrawerTrace`
  capture and swipe evidence checks are unchanged.
- Verification actually run (no Gradle, no emulator): drawer-trace guard OK and 6/6;
  `verify-play-build-test.sh`; home guard 13/13; theme guard 9/9; brand guard 14/14; identity
  guard 8/8; manifest guard all pass; emulator-smoke and drawer suites all pass; the repo-level
  identity/home/theme/brand guards OK; `sh -n` clean; `git diff --check` clean.

## done (previous run — P3b runtime drawer diagnostic)

- **Micro diagnostic only:** added `src/com/android/launcher3/touch/DotwelDrawerTrace.java`, a
  temporary log helper gated by `BuildConfig.DEBUG && "play".equals(BuildConfig.FLAVOR_channel)`.
  Release and github/nightly builds never emit the tag.
- **Selected factory:** `Launcher.createTouchControllers()` logs the selected controller class
  names and `DisplayController.getNavigationMode(...).name` when the trace is enabled.
- **Central controller:** `AbstractStateChangeTouchController` logs ACTION_DOWN accept/skip with
  state, ACTION_UP with no-intercept/dragging/state, `onDragStart` with start displacement and
  from/to state, and `onDragEnd` with velocity, fling, last displacement, progress and target
  state. There is deliberately no per-MOVE logging.
- **Smoke evidence:** `scripts/emulator-smoke.sh` runs a bounded
  `adb logcat -d -s DotwelDrawerTrace` into `appdrawer-trace-N.txt` after every swipe attempt,
  before the readiness check, so a no-op swipe still leaves a trace artifact.
- **Regression:** added `scripts/nothingui-drawer-trace-guard.sh` and its fixture test (debug gate,
  factory/controller trace points, no MOVE logging, per-attempt smoke capture); wired into
  `scripts/verify-play-build.sh`. The mock-adb drawer test now also requires
  `appdrawer-trace-N.txt` for all four attempts.
- **Verification actually run (no Gradle, no emulator):** trace guard OK and its test 4/4;
  `emulator-smoke-drawer-test.sh` all pass (now 42 checks); `emulator-smoke-test.sh` 34/34;
  `nothingui-home-guard-test.sh` 13/13; `verify-play-build-test.sh` 11/11; `sh -n` clean on edited
  scripts; `git diff --check` clean.
- **Scope reminder:** no gesture routing, animation, workflow, SDK, manifest, permission,
  applicationId, signing, Gradle or app-visual change. No guessed fix was applied. The untracked
  local `w/` scratch directory was left uncommitted.

## done (this run — P3b smoke harness retry-state repair)

- **CI70 hang read correctly:** run `44924192206` on PR #11 was canceled after 22m. The real
  `open_app_drawer` loop never advanced because every helper was a plain POSIX function writing
  globals. `capture_ui_xml` set `attempt=1` on each capture, and `wait_for_launcher_idle` /
  `wait_for_foreground` did the same, so the outer `attempt` was reset before it could reach
  `max_attempts=4`. The helper variables `name`, `label`, `target`, `xml`, `root`, `width` and
  `height` were also shared with callers. No assertion was weakened.
- **Helper isolation:** all pure/parsing helpers in `scripts/emulator-smoke-lib.sh` and the smoke
  script are now POSIX subshell functions `foo() ( ... )`, so their variables cannot leak. Helpers
  that must call `fail`/`exit` stay in the current shell but use unique names (`_rh_*`, `_cai_*`,
  `_cab_*`, `_cts_*`, `_vnh_*`, `_ead_*`). The `open_app_drawer` loop now keeps its `attempt` and
  `poll` state, while the exact Settings foreground proof and the real drawer UI path are unchanged.
- **Bounded operations:** added `run_with_timeout` (GNU `timeout`, or a background/kill fallback)
  and bounded every `adb_cmd` call: 60s default, 20s for uiautomator dump/pull and screencap, 30s
  for logcat, 300s for install, 180s for the base-APK pull, 60s for uninstall. Timeouts print the
  operation to stderr.
- **Evidence on failure:** `fail` marks the evidence as captured, and an `EXIT` trap in the live
  flow captures logcat + screenshot and prints the artifact directory for any other nonzero exit.
  This keeps evidence for `set -e` failures that do not go through `fail`.
- **Mock-adb regression:** added executable `scripts/emulator-smoke-drawer-test.sh`. A mock `adb`
  returns an unchanged HOME hierarchy, the test sources the real smoke script in a source-only mode
  (no device), runs the real `open_app_drawer`, and requires exit 1 (not a timeout), exactly four
  swipes, before/after XML+PNG and swipe command/log per attempt, retained logcat+screenshot, and
  the terminal failure/evidence message, all inside a 30s host timeout. It is wired into
  `scripts/verify-play-build.sh`. Temporarily reverting the `capture_ui_xml` subshell reproduces
  the old behavior (timeout 124 and more than four swipes), so the regression is real.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-drawer-test.sh` passes
  (31 checks); `emulator-smoke-test.sh` 34/34; `verify-play-build-test.sh` all pass;
  `nothingui-home-guard-test.sh` 13/13; `nothingui-theme-guard-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. The regression was also proven to fail against a
  temporary reverted copy of the smoke script.
- **Scope reminder:** this run changed only the smoke harness and its tests. No app visual change;
  the actual HOME grid/drawer visuals, colored icons and blue QSB are still pending and must not be
  claimed as visually ready. User workspace/wallpaper choices were not touched. No workflow, SDK,
  manifest, permission, applicationId, signing or Gradle change was made. The untracked local `w/`
  scratch directory was left uncommitted.

## done (prior run — P3b drawer-readiness smoke repair)

- **CI68 failure read correctly:** run `44921875638` on PR #11 was green for compile/style/unit but
  the API 37 smoke failed at `appdrawer` with no search label. The coordinator downloaded the actual
  `home.xml` and `appdrawer.xml`; both were identical HOME (clock `4:10`, dock Phone/Messaging/
  Contacts/WebView/Browser/Tester), so the swipe did not transition and the Settings launch phase
  was never reached. The emulator's `ColorBuffer74` log noise was not assumed to be infra, and no
  assertion was lowered.
- **Root cause:** `open_app_drawer` swiped from `height * 3 / 4` (~1440 on 1920) to `height / 4`.
  The dock occupies roughly 1375–1568, so the gesture started on the Phone icon instead of the
  workspace and was consumed by the dock.
- **Fix:** `open_app_drawer` now runs up to 4 bounded, state-based attempts. Each attempt waits for
  the launcher to be the idle resumed foreground, captures `appdrawer-attempt-N-before.xml` +
  `.png`, computes the target from the live HOME hierarchy, swipes, then polls for the real drawer
  search input or app-list container. Every attempt also writes `appdrawer-attempt-N.xml` + `.png`
  and an `appdrawer-swipe-log.txt` line plus `appdrawer-swipe-N.txt`.
- **Geometry:** the swipe target uses the UIAutomator root bounds (so current insets/root bounds
  apply), finds the dock top from the lowest labelled row, and starts in the empty workspace above
  it (e.g. 1920 px display / 1400 px dock top -> start y 1208, end y 384). `wm size` is only a
  measured fallback when the hierarchy is unavailable. The old 75% dock hit point is gone.
- **Readiness:** `drawer_is_ready` accepts an actual search input (`/input`, `EditText`,
  `AllAppsSearchInput`, `search_container_all_apps`) or app-list container (`apps_list_view`,
  `SearchContainerView`); a closed HOME is not ready. The dump must also differ from the pre-swipe
  HOME, so a swipe that did nothing cannot be mistaken for an opened drawer. The pre-search
  `Settings` label assertion was removed because Settings may be off the first screen; the real
  search-result assertion remains.
- **Mandatory flow preserved:** the drawer is still opened by a real swipe, search is still typed
  into the real input, the clickable Settings result is still tapped, and the exact
  `com.android.settings/` foreground poll is still required (bounded 15 s). There is still no
  `am start` shortcut to Settings. Clock/date, app-info, About, theme-sample, and crash checks are
  unchanged.
- **Regression:** `scripts/emulator-smoke-test.sh` is now 34/34, adding pure fixtures for root
  bounds, dock-top detection, the measured swipe target (including the old 75% case and fallback),
  drawer readiness (including an unchanged reference HOME), and static
  assertions that each attempt is bounded, captures evidence, and no longer uses the 75% start.
- Pending visuals are untouched: **colored icons and the blue QSB still need pixel repair; the
  header fits the pinned row but is not visually ready.** Private-space runtime UI, the in-app
  `RoleManager.ROLE_HOME` prompt and the non-Play runtime control remain pending. No Gradle,
  workflow, SDK, manifest, permission, applicationId, signing, release, paid-service or YouTube
  change was made. The untracked local `w/` scratch directory was left uncommitted.

## done (prior run — P3b bounded finish)

- Reviewed the existing branch diff against `main` and kept the saved work rather than restarting.
  The branch already contained: the Play-only `NOTHINGUI_HOME_ENABLED` flag, the original
  `NothingUiHomeHeaderView` (live Doto clock/date, red accent, dot strip), `NothingUiHomeClock`,
  the smartspace-slot hook, monochrome icon defaults, QSB and page-dot hooks, a static home guard,
  a JUnit clock test and the extended emulator smoke.
- **Fixed the specific review concern (chrome contrast).** `NothingUiHomeChrome` no longer pairs
  `Themes.getColorBackgroundFloating` (pale) with `Themes.getAttrColor(workspaceTextColor)` (often
  wallpaper-derived white). It now selects an explicit original pair from `NothingUiPalette`:
  light theme -> `Paper` surface + `Ink` text; dark theme -> `Gray900` surface + `Paper` text.
  The choice follows the inherited user light/dark theme (`R.attr.isMainColorDark`), matching the
  inherited day/night QSB icon and page-dot tints. The header, QSB pill and page dots all share
  this pair.
- **Header row fit.** Reduced the header clock to 30 sp, date to 10 sp, outer padding to 10/2 dp,
  card padding to 14/6 dp, corner radius to 22 dp and the dot strip to 48×5 dp so the card fits the
  existing single-row pinned smartspace cell without clipping. The header still uses the live clock,
  date, red accent and monochrome dot motif; it is not a sample-only screen.
- **Guard coverage added.** `scripts/nothingui-home-guard.sh` now asserts the original palette pair,
  the `isMainColorDark` theme choice, that the header shares the pair, and that the chrome never
  falls back to `getColorBackgroundFloating` / `workspaceTextColor`. It also locks the fitted
  clock/date text sizes. The fixture suite adds an inherited-floating/wallpaper negative case.
- **Smoke evidence.** `scripts/emulator-smoke.sh` captures the actual HOME (`home.xml` + `home.png`)
  and requires live clock/date text with no inherited `Lawnchair` text. It opens the inherited app
  drawer (`appdrawer.xml` + `.png`), searches for Settings, taps the real result, verifies
  `com.android.settings` is foreground, then returns HOME. The app-info, About, theme-sample and
  crash checks are retained.
- Pending items are untouched: private-space runtime UI, the in-app `RoleManager.ROLE_HOME` prompt
  and the non-Play runtime control. No manifest, permission, SDK, applicationId, signing, release,
  paid-service, workflow or YouTube change was made. The untracked local `w/` scratch directory was
  left uncommitted.

## verification actually run (no Gradle, no emulator, no CI)

- This run: `sh scripts/play-brand-guard.sh "$PWD"` -> OK; `play-brand-guard-test.sh` all pass,
  including the new ungated-announcement, removed-announcement, fabricated-DotWel-news and
  Play-announcement-resource negatives.
- This run: `sh scripts/emulator-smoke-test.sh` -> all pass, including the announcement helper,
  markers, case-insensitivity and the clean-screenshot/assert-before-tap ordering.
- This run: `sh scripts/emulator-smoke-drawer-test.sh` -> all pass; the genuine 1500 ms / 4-attempt
  drawer assertions are unchanged.
- This run: `verify-play-build-test.sh` -> all pass. The repo-level identity, theme, home, home-role,
  icon and drawer-trace guards all print OK, and their fixture suites all pass.
- This run: `sh -n` clean on every edited script; `git diff --check` clean.
- Prior run: the drawer-trace guard and both smoke suites passed the 1500 ms pacing and input
  summary; `DefaultHomeRolePolicy` TDD harness passed after the pure policy was added.
- Not run here: `spotlessCheck`, any Gradle build/test, the API 37 emulator smoke, or PR CI. The
  branch is statically verified only; the Play announcement gate and clean settings pixels are
  scripted but unverified on device.

## next

- Main owns PR creation/CI approval for `agent/newtinybranchagent-p9-settings` at head `ad05a12`.
  PR12 (#12) is merged into `main` (`5da711d`) and remains the fallback.
- CI must be green on this head: `spotlessCheck`, `assembleLawnWithQuickstepPlayDebug`, the Play
  unit tests, `verify-play-build.sh` (the brand guard now includes the Play announcement gate), both
  smoke suites and the API 37 emulator smoke.
- Inspect the runtime artifacts after the run:
  - `role-consent-settings.xml` / `.png`: the settings warning is visible and the screenshot is
    clean. There must be no `Lawnchair`, `sneak peek`, `important announcement` or `announcement`
    text from the inherited cards. If the upstream card wording changes, update the smoke markers
    from the captured XML rather than weakening the assertion.
  - `role-consent.xml` / `.png`: the real platform HOME role consent, with a Cancel control.
  - `role-consent-before.txt` / `role-consent-after.txt`: our package is not a holder and the lists
    are unchanged after cancel.
  - `activities-role-consent-cancel.txt`: the settings activity (or launcher) is foreground after
    cancel, not a granted role.
  - `appdrawer-swipe-log.txt` / `appdrawer-swipe-N.txt`: start `540 1616` and duration 1500.
  - `appdrawer-attempt-N.xml` / `.png`: the first ready drawer differs from HOME and exposes the
    search input or app-list container.
- If the API 37 system image uses a different cancel label, change `ui_cancel_bounds` from the
  captured XML. Do not guess a new coordinate or lower the assertion.
- **Next separate slice (do not start in this run): verify the real grid and widgets.** No other UI
  or theme feature change belongs to this cleanup.
- P8 remains open beyond these slices: appearance controls, backup/restore wiring and any broader
  onboarding. Pending gates: private-space runtime UI and a non-Play runtime control build.

## blockers

- No local Gradle build or emulator run is allowed here, so the Android compile, unit test and the
  API 37 emulator run are unverified until CI runs on `ad05a12`.
- No PR exists yet for `agent/newtinybranchagent-p9-settings`; a maintainer must create/approve it.
- The smoke's consent phase assumes the platform HOME role dialog exposes a Cancel control. The
  script fails closed if it does not; the captured XML will name the exact label to add.
- The announcement assertion is worded for the current inherited cards. If the live-information
  endpoint changes that wording, the smoke fails closed and the captured XML must drive the marker
  update; do not replace the assertion with a weaker check.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings (this run and prior P3a)

- P3b actual-home fix: the bottom QSB is only accepted when its top is strictly below the measured
  dock icon bottom; the same `search_container_workspace` id on the header is rejected. Cost if
  wrong: a device whose QSB sits above the dock icons would fall back to the icon-band gutter
  instead of the dock/QSB midpoint, which is still a >1500 px swipe.
- P3b actual-home fix: when the bottom QSB is absent, start a quarter of the measured icon band
  below the icon bottom (1568 + 48 = 1616). Cost if wrong: a shorter icon band starts closer to
  the icons, but the start remains below every icon and above the PNG-visible QSB top.
- P8 drawer diagnostic: the harness swipe duration is now 1500 ms instead of 500 ms. Cost if wrong:
  the gesture takes longer on a slow emulator, but it is still a bounded `input swipe` and gives adb
  more MOVE samples at zero release velocity. This is a harness/fixture change only; the app's
  gesture logic, threshold and ACTION_UP semantics are untouched.
- P8 drawer diagnostic: the per-gesture `gestureSummary` is emitted once at UP/CANCEL and only for a
  debug Play gesture that started in `NORMAL`. Cost if wrong: a gesture that never reaches this
  controller leaves no summary, but that is exactly the lost-input case the existing DOWN/UP
  interception lines already show; no unrelated input is logged and there is no per-MOVE flood.
- P3b drawer-readiness repair: derive the swipe target from the live HOME hierarchy (root bounds +
  lowest labelled row) rather than a fixed display fraction. Cost if wrong: the hierarchy adds one
  uiautomator dump per attempt, but the gesture can no longer land on the dock; if no labelled row
  is found the measured `wm size` fallback uses 55% height, still above a 71%-height dock.
- P3b drawer-readiness repair: require an actual drawer search input or app-list container before
  proceeding. Cost if wrong: a future drawer that exposes neither id will fail rather than silently
  testing HOME, which is the intended fail-closed behavior.
- P3b drawer-readiness repair: require the post-swipe dump to differ from the pre-swipe HOME. Cost
  if wrong: a drawer that opens and produces a byte-identical hierarchy would be rejected, but the
  inherited drawer changes the visible tree, and this directly rejects the CI68 closed-HOME case.
- P3b drawer-readiness repair: drop the pre-search `Settings` label assertion but keep the real
  search-result assertion and the exact foreground poll. Cost if wrong: a drawer that opens without
  Settings on the first screen still proceeds to search, which is the behavior the task needs.
- P3b smoke repair: the app-launch assertion reads only the live
  `topResumedActivity`/`mResumedActivity` fields and matches the exact package boundary; task
  history is never treated as foreground. Cost if wrong: a dump that omits both fields fails the
  smoke instead of passing on a historical record.
- P3b smoke repair: the drawer taps the clickable Settings result node (or its nearest clickable
  ancestor), never an earlier bare `text="Settings"` label. Cost if wrong: if the result container
  is not clickable the nearest ancestor is used, and if no clickable node exists the label bounds
  are the last-resort fallback.
- P3b chrome pair: use the original `Paper`/`Ink` (light) and `Gray900`/`Paper` (dark) pair selected
  by `R.attr.isMainColorDark`, not the inherited wallpaper text plus floating surface. Cost if
  wrong: with a light theme on a dark wallpaper the card is light rather than wallpaper-matched,
  but it keeps high contrast and follows the user's light/dark choice, matching QSB/day-night tints.
- P3b header: keep the original header in the inherited pinned smartspace slot, sized to one row,
  rather than hard-wiring it into `Workspace` or adding a second launcher surface. Cost if wrong:
  the header is less tall than a multi-row Nothing-style clock widget, but it cannot clip the grid.
- P3a repair: the forbidden-font check inspects lowercased basenames only. Cost if wrong: a
  forbidden font hidden inside a directory name would not be caught, but fonts live flat in
  `lawnchair/res/font` and the guard still checks the whole file list there.
- P3a repair: the diagnostic route reuses the existing exported `PreferenceActivity` and an
  explicit extra instead of adding a component. Cost if wrong: the extra is discoverable in debug
  Play builds, but it is inert outside `BuildConfig.DEBUG` + Play and has no release exposure.
- P3a repair: the smoke starts the sample with
  `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_MULTIPLE_TASK` (`0x18000000`) so the extra is delivered
  to a fresh instance. Cost if wrong: the sample task is separate from the HOME task and is
  auto-removed from recents; if `am` ignores the flag on a future API the smoke fails rather than
  silently reusing About.
- P3a: the Play-only gate is a `BuildConfig` boolean (default false, true in the `play` flavor)
  rather than a resource or a source-set split. Cost if wrong: the shared theme code still compiles
  for github/nightly and the guard must keep asserting the flag; the font bytes add ~281 KB to
  those APKs even though they are unused.
- P3a: Doto is bundled as static 400/700 instances generated from the official variable font, not
  as the variable font itself. Cost if wrong: a future display weight outside 400/700 needs another
  static instance and an attribution hash update.
- P3a: body/title/label text uses `FontFamily.SansSerif`, not a bundled font. Cost if wrong: the
  launcher follows the platform sans rather than a fixed brand sans, which is intentional for
  legibility and avoids another font license.
- P3a: the safe gate requires a `fallback` slot, so a caller cannot silently render a blank
  non-Play surface. Cost if wrong: future callers must supply the inherited theme explicitly.
- P3a: the new theme guard is called from `verify-play-build.sh` rather than a workflow edit,
  because `.github/workflows/` is off-limits. Cost if wrong: a future CI refactor that stops
  calling `verify-play-build.sh` also drops the theme guard.
- P3a system-bar repair: the diagnostic sample passes its own dark flag into `EdgeToEdge` and skips
  the inherited early `enableEdgeToEdge()` call, so bar contrast follows the requested sample mode
  and never the inherited system/preference theme. Normal settings keep the inherited path. Cost if
  wrong: the sample's window setup is not byte-for-byte the settings sequence, so a settings-only
  regression must still be caught by the normal-path guard and the smoke's `return_home
  theme-sample` resume check.

## prior rulings still binding (P2c)

- Play resources live in the `lawnWithQuickstepPlay` multi-flavor source set, not the single
  `play` flavor. `flavorDimensions` puts `app` (lawn) before `channel` (play), so a single-flavor
  Play resource loses same-name lawn resources at merge time. The brand guard asserts the source
  set ownership.
- The Play manifest lists both `android:label` and `android:icon` in `tools:replace`; the overlay
  owns both values and the base values are discarded at merge.
- All Play icon artwork lives in `play/res`; github/nightly keep the inherited Lawnchair icon.
  The Play icon is an original near-black/white/red dot grid, not a Nothing asset.
- Play locale overrides replace only the `Lawnchair` brand token in `onboarding_welcome`.
  `derived_app_name` is a Play-gated variant-level `resValue` because the build-type value outranks
  flavor resources.
- The brand guard is called from `verify-play-build.sh`, not a workflow file, so CI keeps it
  without editing `.github/workflows/`.

## log

- 2026-11-21: P9 Play settings announcement cleanup on `agent/newtinybranchagent-p9-settings`
  (`ad05a12`), from `main` `5da711d` (PR12 merged after green CI102 `10244953269478`, 11m49).
  `PreferencesDashboard` now renders `AnnouncementPreference()` only inside
  `if (!isPlayStoreFlavor())`, so the inherited Lawnchair 16 sneak-peek and placeholder
  "important announcement" cards no longer appear in Play settings; non-Play keeps them and nothing
  was rebranded or fabricated. The debug warning, default-home warning/role consent, About and
  NOTICE attribution are untouched. `play-brand-guard.sh` now requires the gate and import, rejects
  a removed non-Play call, DotWel text in the announcement component and announcement resources in
  `play/res`; its suite adds four negatives. The real settings smoke asserts no inherited
  announcement markers and captures the clean `role-consent-settings.png` before tapping the
  default-launcher warning; the 1500 ms / 4-attempt drawer, search, exact Settings foreground,
  HOME-return and role-Cancel checks are unchanged. All local guard/smoke/verify suites pass;
  `sh -n` and `git diff --check` clean. CI/device evidence and PR creation are still pending.
- 2026-11-21: Drawer input pacing and per-gesture summary on `agent/p8-home-role-consent`
  (`d341e51`). CI100 (`44951103338`) was compile/style/unit green, the role consent cancel passed
  and the Play hint pixels say `DotWel Launcher`. Geometry was correct on all four attempts
  (`540 1616 540 96`, 500 ms), but the traces showed last displacement/progress `-726.84 / .37856`,
  `-194.84 / .10148`, `-188.76 / .09831`, `-264.76 / .13790`, all velocity 0 and accepted
  Normal->AllApps; the requested 1520 px MOVE travel was not fully observed. The harness now uses a
  bounded 1500 ms swipe (still logged per attempt) and the debug Play controller emits one
  `gestureSummary` at UP/CANCEL with DOWN x/y/time, MOVE count, last MOVE y/time, UP y/time and
  history size. No per-MOVE log, no app threshold/UP/success change. The drawer-trace guard now
  requires the summary fields/gates and rejects per-MOVE logging; smoke fixtures assert 1500 ms.
  Local trace, smoke, drawer and all guard suites pass; `sh -n` and `git diff --check` clean. CI and
  device evidence are still required.
- 2026-11-21: Dock-row parser and Play hint repair on `agent/p8-home-role-consent` (`e40fc3b`,
  `f83603d`). CI97 (`44949228055`) passed compile/style/unit and captured/cancelled the real native
  `ROLE_HOME` dialog with an unchanged role holder list, but the drawer phase failed four attempts.
  The actual HOME XML has three id-less bottom `Search` nodes at y=1626..1794; the old
  `ui_dock_bottom` returned 1794 and `drawer_swipe_target` started at 1898 instead of 1616.
  `ui_dock_bottom` now takes the bottom only from the same icon row as `ui_dock_top`, so id-less
  bottom Search nodes are excluded. The actual-hierarchy regression now includes all three nodes,
  derives the target from parsed values and asserts dock bottom 1568, start 1616 in the 1568..1626
  gutter, no 1898 and >1500 px travel; the old parser fails it with 1794/1898. The mock-adb drawer
  test uses the same hierarchy. Duration stays 500 ms because CI97's low progress came from the
  1898 start, not proven sampling loss; no gesture/threshold change. Also added the Play-only
  `set_default_launcher_tip` "DotWel Launcher" override in `play/res` (non-Play keeps Lawnchair),
  with brand-guard checks for the Play text, non-Play inherited text and the dashboard consumer.
  Local smoke, drawer, brand, role and verify suites pass; `sh -n` and `git diff --check` clean.
  No workflow, Gradle, SDK, manifest, permission, applicationId, signing or paid-service change.
- 2026-11-21: P8 Play-only HOME role consent slice on `agent/p8-home-role-consent` (`7f5a6c9`,
  `567203f`, `38348e7`). The existing settings warning now requests `RoleManager.ROLE_HOME` only on
  Play, through a pure API/role-state policy and a native consent helper; non-Play keeps the inherited
  `ACTION_HOME_SETTINGS` path. Cancelling leaves the role unchanged; API < 29, unavailable and
  already-held roles fall back to Home settings. Added `DefaultHomeRolePolicyTest`, a 7/7 static
  guard, and a smoke phase that taps the warning, captures and cancels the real platform consent,
  and proves the holder list is unchanged before granting the role for the existing HOME/drawer
  assertions. Local shell suites pass; CI/PR12 and runtime consent are pending. Corrected CI93
  (style failure, not fully green) and recorded CI95 as fully green with verified pixels.
- 2026-11-21: Neutral Play icon/QSB fix on `agent/p3b-actual-home-visual-slice-n` (`9fc5a33`).
  CI93 (`44944409947`) on `9076be5` had assembly, unit tests and emulator pass but a style failure;
  it was not fully green. CI95 (`44946373901`) was fully green in 11m40 and its actual pixels were
  verified black/white icons and black HOME/drawer QSB. Before CI95, the inspected HOME/drawer pixels
  kept the wallpaper-derived blue/lavender tint on the icon fallback and the QSB glyph. Root cause was the
  inherited process-wide `ThemedIconDrawable.COLORS_LOADER`, not the policy. Added
  `NothingUiIconColors`, gated the loader to the neutral black/white pair in Play (non-Play
  unchanged), passed the provider through the controller and fallback, kept the Play freshness key
  neutral, neutralized themed QSB layers behind the Play gate, and fixed the CI93 `policyFor`
  style. Icon-render guard now 15/15 with `NothingUiIconColorsTest`. CI95 then verified the
  black/white icons and black HOME/drawer QSB pixels.
- 2026-11-21: Actual-home fixture fix on `agent/p3b-actual-home-visual-slice-n` (`039a41d`).
  CI87 (`44935461427`, artifact `14719887963`) still traced `0.366` progress target Normal. The
  actual HOME XML puts `search_container_workspace` on the y=91 HEADER, not the bottom QSB, so
  `ui_qsb_top` returned 91 and the gutter branch fell back to start 1183. The fixture had invented
  a bottom-QSB id at 1640. `ui_qsb_top` now requires a dock bottom and rejects candidates at or
  above it; `ui_dock_bottom` excludes search containers; `drawer_target_for_dump` derives the dock
  bottom first. With no bottom QSB, the start is dock_bottom + icon_band/4 = 1568 + 48 = 1616,
  ending at 96 (1520 px, 79.2 percent). The swipe duration is 500 ms and is logged. The real CI87
  HOME is now the fixture; a separate bottom-QSB fixture still proves the 1604 midpoint. Local
  shell suites: smoke 61 checks, drawer 38 checks, trace 6/6, home 13/13, verify suite all pass;
  `sh -n` and `git diff --check` clean. No app logic, thresholds, manifest, permissions, SDK,
  applicationId, signing or workflow change. New API 37 evidence is still required.
- 2026-11-21: Smoke gesture length fix only on `agent/p3b-actual-home-visual-slice-n`
  (`96e2f7b`, `4ebc2b5`). CI84 (`44933644538`, artifact `14719700048`) showed the route works
  (DOWN accepted, Normal→AllApps) but the old test swipe covered only 799 px of the 1920 shift
  range, so `dragEnd` at velocity 0 recorded progress `0.3760783` and correctly returned Normal.
  The harness now measures the dock icon bottom and QSB top from the same HOME XML and starts in
  the empty gutter between them, ending at 5 percent of the display (actual 1080x1920:
  `540 1604 540 96`, 1508 px / 0.7854). Added pure `ui_dock_bottom`, `ui_qsb_top`,
  `drawer_swipe_is_long_enough` and `drawer_swipe_travel_fraction`, plus regressions that reject
  the old 0.4161 geometry and the CI84 0.3760 trace. The mock-adb drawer test now requires every
  attempt to exceed half the display. App gesture logic, thresholds, visuals, manifest,
  permissions, SDK, applicationId, signing and workflows are unchanged. Local shell suites pass;
  the longer gesture still needs a new API 37 smoke run to produce the AllApps `dragEnd` trace.
- 2026-11-21: Micro compile fix only on `agent/p3b-actual-home-visual-slice-n`. CI81
  (`44932685973`) on `f2377c5` failed javac on the new diagnostics: `NavigationMode` is a Java
  enum, so `getNavigationMode(this).name` became `.name()`, and `LauncherState` has no `name`
  field, so all four state logs use `stateName(...)` backed by the verified `toString()`. The
  drawer-trace guard now rejects `.name` field access and its fixture suite is 6/6. Debug Play
  gating and per-attempt trace artifacts unchanged; no app behavior change.
- 2026-11-21: P3b smoke harness retry-state repair on `agent/p3b-actual-home-visual-slice-n`
  (`d5122ad`, `50176d8`). CI70 (`44924192206`) was canceled after 22m because plain POSIX helper
  functions shared globals: `capture_ui_xml` reset the outer `open_app_drawer` `attempt`, so the
  4-attempt loop could repeat forever; `name`/`label`/`target`/`xml` also leaked between helpers and
  callers. Pure helpers are now subshell functions, effectful helpers use unique `_*` names, every
  adb/uiautomator call is bounded by `run_with_timeout`, and an `EXIT` trap retains evidence on
  failure. Added executable `emulator-smoke-drawer-test.sh` (mock adb, real `open_app_drawer`,
  unchanged HOME, exactly four swipes, per-attempt evidence, exit 1 inside 30s) and wired it into
  `verify-play-build.sh`; a temporary revert reproduces the old timeout/5+ swipes. Local shell
  suites pass; no Gradle/emulator run here. Colored icons + blue QSB still need pixel repair; header
  fits but is not visually ready.
- 2026-11-21: P3b drawer-readiness repair on `agent/p3b-actual-home-visual-slice-n` (`522516b`,
  `fb5aa61`, `83c3ad8`). CI68 (`44921875638`) was compile/style/unit green but the API 37 smoke failed because
  `appdrawer.xml` was identical to `home.xml`; the 75%-height swipe started inside the dock/Phone
  hit region. `open_app_drawer` now uses up to 4 bounded state-based attempts, waits for launcher
  idle, derives the target from live root bounds + dock top, captures before/after XML+PNG and a
  swipe log per attempt, and requires a real drawer input/container that differs from the pre-swipe
  HOME. The real swipe -> search -> Settings tap -> exact
  foreground flow is unchanged. `emulator-smoke-test.sh` is 34/34. Static checks only; CI and pixels
  pending. Colored icons + blue QSB still need pixel repair; header fits but is not visually ready.
- 2026-11-21: P3b smoke repair on `agent/p3b-actual-home-visual-slice-n` (`84a0493`). The app-launch
  false positive came from grepping the whole dumpsys dump; only the live resumed fields now count,
  polled with a bounded wait. The drawer taps the clickable Settings result instead of the first
  text match, captures `settings-launched` and `home-after-app-launch` XML/PNG, and fails if either
  foreground assertion is wrong. Added `emulator-smoke-lib.sh` and a 14-case regression wired into
  `verify-play-build.sh`; existing guard suites and 16 unit tests unchanged. Colored icons + blue
  QSB still need pixel repair; the header fits but is not visually ready. No visual edits this run.
- 2026-11-21: P3b bounded finish on `agent/p3b-actual-home-visual-slice-n` (`ac31c4e`). Fixed the
  chrome white-on-white risk with an explicit neutral surface/ink pair selected by the inherited
  light/dark theme, shared it across the header/QSB/page dots, sized the header to the single pinned
  row, extended the home guard (13/13) and kept the actual-HOME + drawer/search/launch smoke. Static
  checks only; CI and pixel review pending. Pending private UI / RoleManager / non-Play runtime
  unchanged.
- 2026-11-21: P3b saved work checkpointed on the branch: Play-gated clock header, pure clock
  formatter, monochrome icon defaults, QSB/page-dot chrome hooks, home guard + tests, and the
  actual-HOME/drawer smoke. Run was cancelled before closeout; resumed and finished above.
- 2026-11-21: P3a system-bar repair: CI62 (`44909523145`) on `e359a9a` was green (7 token + 4
  predicate JUnit tests, 0 skipped) but the real dark sample kept dark status/nav icons. Root
  cause: the sample branch used the inherited `EdgeToEdge()`/`enableEdgeToEdge()` theme preference
  instead of the requested sample mode. Added an explicit `darkTheme` parameter, passed
  `themeSampleDark` from the diagnostic branch, skipped the inherited early call there, and added
  guard fixtures (9/9). P3a is merged; HOME styling moved to P3b.
- 2026-11-21: P3a repair/visual-evidence slice: reproduced and fixed the CI53 guard false positive
  (full-path vs basename scan), added the `NothingOS-Launcher`/ndot regression suite, added the
  DEBUG+Play diagnostic sample route, and extended the API 37 smoke to capture dark/light sample
  XML+PNG and return HOME.
- 2026-11-21: P3a foundation implemented: palette/spacing/motion/typography, Doto OFL assets,
  Play-only `BuildConfig` gate, sample screen and previews, pure token tests, and a static theme
  guard wired into `verify-play-build.sh`.
- 2026-11-21: P2c verified by the coordinator: CI51 (`44903885094`) on `e6ea08b` green with 4
  Gradle tests and API 37 install/HOME/role/crash checks; HOME says `Welcome to DotWel Launcher`
  and About/app-info show the dot-grid icon and name.
- 2026-11-21: PR9 merged to `main` at `02ac058`; the P3a branch was cut from that merge.
- 2026-11-21: CI42 (`44901579949`) on `293f96e` was fully green; the earlier About icon and HOME
  welcome defects were repaired by moving `play/res` to the `lawnWithQuickstepPlay` multi-flavor
  source set.
- 2026-11-21: CI37 (`44900708538`) failed the Play manifest merge; the `android:icon`
  `tools:replace` repair and its guard regression landed before PR9.
- 2026-11-21: PR8 merged at `4bd5c39`; PR7 merged the Play label and guard suites.
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + identity/authority
  guard + docs).
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal).
