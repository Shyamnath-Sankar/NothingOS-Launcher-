# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: **P3b — actual HOME visual slice (drawer-readiness smoke repair only)**. CI68
  (`44921875638`) was compile/style/unit green but the API 37 smoke failed at the drawer step
  (`appdrawer` did not expose a search label): the coordinator's `appdrawer.xml` was identical to
  `home.xml`. Root cause was the swipe start at 75% height, inside the dock/Phone hit region, so the
  all-apps transition never began. This run makes `open_app_drawer` bounded and state-based. No app
  visual change was made. Colored icons and the blue QSB are still pending pixel repair, and the
  header fits the pinned row but is **not visually ready**. P3b is not visually done.
- branch: `agent/p3b-actual-home-visual-slice-n`
- head: `522516b` (base `main` at `0df97ff`)
- pr: #11 (existing PR for this branch; resume it, do not open a duplicate):
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/11

## done (this run — P3b drawer-readiness smoke repair)

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
  `SearchContainerView`); a closed HOME is not ready. The pre-search `Settings` label assertion was
  removed because Settings may be off the first screen; the real search-result assertion remains.
- **Mandatory flow preserved:** the drawer is still opened by a real swipe, search is still typed
  into the real input, the clickable Settings result is still tapped, and the exact
  `com.android.settings/` foreground poll is still required (bounded 15 s). There is still no
  `am start` shortcut to Settings. Clock/date, app-info, About, theme-sample, and crash checks are
  unchanged.
- **Regression:** `scripts/emulator-smoke-test.sh` is now 31/31, adding pure fixtures for root
  bounds, dock-top detection, the measured swipe target (including the old 75% case and fallback),
  drawer readiness, and static assertions that each attempt is bounded, captures evidence, and no
  longer uses the 75% start.
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

- This run: `sh scripts/emulator-smoke-test.sh` -> 31/31 passed (14 existing + 17 new
  geometry/readiness/static cases).
- This run: `sh scripts/nothingui-home-guard-test.sh` -> 13/13 passed;
  `nothingui-theme-guard-test.sh` -> 9/9; `play-brand-guard-test.sh`,
  `play-identity-guard-test.sh`, `manifest-guard-test.sh` -> all pass.
- This run: `sh -n` clean on `emulator-smoke.sh`, `emulator-smoke-lib.sh`,
  `emulator-smoke-test.sh`; `git diff --check` clean.
- Prior run: `sh scripts/emulator-smoke-test.sh` -> 14/14 passed.
- Prior run: `sh scripts/nothingui-home-guard-test.sh` -> 13/13; `nothingui-theme-guard-test.sh` ->
  9/9; `play-brand-guard-test.sh`, `play-identity-guard-test.sh`, `manifest-guard-test.sh`,
  `verify-play-build-test.sh` -> all pass.
- Prior run: `sh scripts/nothingui-home-guard.sh "$PWD"` -> `nothingui-home-guard: OK`.
- Prior run: `kotlinc` compiled the pure `NothingUiHomeClock.kt` (exit 0). Parsing the
  Android-dependent header/chrome/QSB files produced only expected unresolved-Android-reference
  cascades, no syntax errors.
- Not run here: `spotlessCheck`, any Gradle build/test, the API 37 emulator smoke, or PR CI. The
  branch is statically verified only.

## next

- Coordinator reviews the `522516b` diff and approves CI on PR #11. Do not open a duplicate PR.
- CI must show: `spotlessCheck`; `assembleLawnWithQuickstepPlayDebug`; the existing 16 Play unit
  tests unchanged (`NothingUiHomeClockTest` 5 + `LockedProfilePredicateTest` 4 + the rest);
  `verify-play-build.sh` including `emulator-smoke-test.sh` (31/31) and the home guard (13/13);
  and the API 37 emulator smoke.
- Review the new drawer artifacts before claiming the repair:
  - `appdrawer-swipe-log.txt` and `appdrawer-swipe-N.txt`: the start y must be above the measured
    dock top, not the old 75% point;
  - `appdrawer-attempt-N-before.xml` / `.png`: HOME before each swipe;
  - `appdrawer-attempt-N.xml` / `.png`: the state after each bounded wait;
  - `appdrawer.xml` / `appdrawer.png`: the first ready drawer, which must differ from HOME and
    expose the search input or app-list container;
  - `activities-app-launch.txt`: only `topResumedActivity`/`mResumedActivity` lines are used; the
    resumed package must be exactly `com.android.settings/`;
  - `settings-launched.xml` / `.png` and `home-after-app-launch.xml` / `.png`.
- Visual review is still outstanding: **colored icons and the blue QSB need pixel repair; the
  header fits the pinned row but is not visually ready.** Do not claim finished visuals from source
  guards alone.
- P4 (drawer restyle) follows P3b; the inherited drawer/search/drag/widgets engine must stay.
- Pending gates: private-space runtime UI, the in-app `RoleManager` prompt, and a non-Play runtime
  control build remain unverified.

## blockers

- No local Gradle build or emulator run is allowed here, so CI and pixels are unverified.
- The agent cannot open/approve PRs (`gh` is unauthenticated); a maintainer must run the PR workflow.
- P3b visuals: colored icons and the blue QSB are still pending pixel repair; the header fits but
  is not visually ready.
- P3b drawer smoke: the new geometry is statically verified only. CI68's `ColorBuffer74` log noise
  is not accepted as an infra excuse; the next API 37 run must show a real drawer transition or
  fail with the new per-attempt evidence.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings (this run and prior P3a)

- P3b drawer-readiness repair: derive the swipe target from the live HOME hierarchy (root bounds +
  lowest labelled row) rather than a fixed display fraction. Cost if wrong: the hierarchy adds one
  uiautomator dump per attempt, but the gesture can no longer land on the dock; if no labelled row
  is found the measured `wm size` fallback uses 55% height, still above a 71%-height dock.
- P3b drawer-readiness repair: require an actual drawer search input or app-list container before
  proceeding. Cost if wrong: a future drawer that exposes neither id will fail rather than silently
  testing HOME, which is the intended fail-closed behavior.
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

- 2026-11-21: P3b drawer-readiness repair on `agent/p3b-actual-home-visual-slice-n` (`522516b`).
  CI68 (`44921875638`) was compile/style/unit green but the API 37 smoke failed because
  `appdrawer.xml` was identical to `home.xml`; the 75%-height swipe started inside the dock/Phone
  hit region. `open_app_drawer` now uses up to 4 bounded state-based attempts, waits for launcher
  idle, derives the target from live root bounds + dock top, captures before/after XML+PNG and a
  swipe log per attempt, and requires a real drawer input/container. The real swipe -> search ->
  Settings tap -> exact foreground flow is unchanged. `emulator-smoke-test.sh` is 31/31. Static
  checks only; CI and pixels pending. Colored icons + blue QSB still need pixel repair; header fits
  but is not visually ready.
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
