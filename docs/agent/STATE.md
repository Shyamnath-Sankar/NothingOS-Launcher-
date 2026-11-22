# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: **P5 home-widget-composition-v1 — Play polish checkpoint: opaque unset drawer,
  discoverable settings entry and default-home status**.
- branch: `agent/home-widget-composition-v1-new`
- head: `2120284` (`test(drawer): avoid ambiguous float assert overload`); this STATE commit
  follows. This run's code commits: `79e8080`, `5e5f071`, `2120284`. Start `ca472427`.
- pr: **#19** — https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/19
- ci: **CI174** (coordinator-reported, not reproduced locally): assembly, style and **70 unit
  tests** passed, but the API 37 **native dark readiness check failed**. Native theme switching is
  therefore still NOT fixed. `ca472427` is the Run66 checkpoint that saved diagnostics only; its
  earlier stale-theme refresh hypothesis is unproven. This run makes no runtime/APK/pixel claim and
  needs a fresh CI at `2120284`.
- next: let PR19 CI rerun the Play debug build, `spotlessKotlinCheck`, `spotlessJavaCheck`, the
  expanded unit tests (72+ with the new drawer-default JUnit), Verify Play manifest and identity
  including the new polish guard, and the API 37 smoke. Confirm the merged manifest has exactly one
  `PreferenceActivity` MAIN/LAUNCHER entry labelled **DotWel Settings**, no HOME on that activity,
  HOME still on `LawnchairLauncher`, and that the dashboard shows the refreshed default/not-default
  state after role consent or cancel. Confirm unset Play drawer opacity is 1.0 and github/nightly
  0.5 while saved values are untouched. Native dark/light pixels still have to be observed; do not
  merge until the API 37 smoke is green. Release and hosting stay paused.

## done (this run — Play polish: opaque drawer default, settings entry, default-home status)

- **Drawer opacity (unset only):** `PreferenceManager` keeps the same `pref_drawerOpacity` key and
  now passes `DrawerOpacityDefaults.forPlayFlavor(isPlayStoreFlavor())`. The pure helper returns
  `1.0f` on Play and `0.5f` on github/nightly. `FloatPref.get()` still reads
  `sp.getFloat(key, defaultValue)`, so every explicitly saved value (including `0.5`, `0`, or a
  custom one) wins and nothing migrates or resets the preference. Slider, text/background colour,
  scrim and all-apps header consumers all keep reading the same `drawerOpacity` preference.
- **Play settings entry:** `play/AndroidManifest.xml` adds only a MAIN/LAUNCHER intent-filter (and a
  clear `DotWel Settings` label via `play_settings_label`) to the existing
  `app.lawnchair.ui.preferences.PreferenceActivity`. It does not add HOME, does not add an
  activity-alias or a second app/package, and leaves `APPLICATION_PREFERENCES` and the
  `lawnchair://settings` deep link in `lawnchair/AndroidManifest.xml`. `LawnchairLauncher` keeps HOME
  and remains the launcher activity.
- **Default-home status:** the dashboard now remembers `isDefaultLauncher()` and re-checks it in
  `LifecycleResumeEffect`, so the card is correct after returning from the platform role dialog or
  cancelling. The not-default card still uses `DefaultHomeRoleConsent` only on the user tap, is
  Play-gated, and has a `runCatching`-guarded `Settings.ACTION_HOME_SETTINGS` fallback. When the
  app is default, Play shows a small matching `X is your default home` status card. No automatic
  role request, no silent default change.
- **Insets:** inspected `BottomSpacer`/`PreferenceLayout`; the Box takes the max of the nav-bar and
  IME spacer rather than summing them, so there is no clear duplicate-padding defect. Nothing was
  changed.
- **Regression checks:** new `DrawerOpacityDefaultsTest` (Play 1.0, inherited 0.5, distinct
  constants) and new `scripts/nothingui-polish-guard.sh`/`-test.sh` (unset-vs-saved fallback,
  Play gating, one MAIN/LAUNCHER settings entry with no HOME, preserved base filters, resume
  refresh, guarded fallback, no startup role request, duplicate-entry and negatives). The suite is
  wired into `verify-play-build.sh`; no workflow was edited.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-polish-guard.sh` OK and its suite **9/9**; `nothingui-home-role-guard.sh` OK and suite
  **7/7**; `play-brand-guard.sh` OK and suite **22/22**; `verify-play-build-test.sh` **11/11**;
  `sh -n` clean on all three edited/new shell scripts; `git diff --check` clean.
- **Blocked/unknown:** no local JUnit, APK, merged-manifest or pixel result. CI174's native dark
  readiness failure is not addressed here; this run deliberately does not claim a native theme fix.
  PR19 is not merged.

## previous run — stale native theme refresh and AMOLED foundation (runtime unverified)

> Correction: CI174 later failed the API 37 native dark readiness check. Treat the native-refresh
> claims below as unproven, not as a fixed theme. `ca472427` only preserved diagnostics.

- **Diagnosed from the reported screenshots, not guessed:** the Compose settings screen changed with
  system night mode, but the native HOME long-press popup and app drawer, including the own widgets,
  stayed light while `pref_launcherTheme=system`. `WallpaperThemeManager` re-read the activity theme
  in `onConfigurationChanged` but did not remember the expected theme or re-check on resume, so a
  launcher stopped while the system theme changed could keep a stale native activity theme.
- **Native refresh fix:** `WallpaperThemeManager.updateTheme()` now returns early when the activity
  already has the expected theme, otherwise records it with `setTheme` and recreates for an actual
  change. A scoped `onActivityResumed` re-runs the check only for the manager's own activity.
  `onActivityDestroyed` now removes the wallpaper listeners, unregisters the component callbacks and
  the lifecycle callbacks, so no recreate loop or leaked callbacks remain. No theme preference,
  workspace or file label is changed.
- **Evidence:** new debug-only `DotWelTheme` trace
  `theme-refresh night=... resolvedDark=... expected=...` is emitted only when
  `BuildConfig.DEBUG`; it reads the resolved native activity theme through
  `UiColorMode(Themes.getAttrInteger(activity, R.attr.uiColorMode)).isDarkTheme`. Release builds
  carry no trace.
- **AMOLED foundation:** the dark settings background and native drawer/header/tab background are
  now `NothingUiPalette.Black` (pure black); popups, cards and elevated surfaces stay charcoal
  (`Gray900`/`Gray700`). `NothingUiPalette.Ink` is unchanged because it is also light-mode
  foreground text. Light colors are unchanged, and non-Play paths keep the inherited tokens. The
  settings top bars and the edge-to-edge navigation-bar scrim switch to the pure-black background
  only on the Play theme gate when the resolved background is black; Back/predictive navigation, nav/IME insets and the
  `BottomSpacer` behavior are untouched.
- **Smoke readiness:** before each native popup/drawer capture the smoke reads back
  `cmd uimode night`, then polls the debug trace from a per-mode logcat baseline until it reports the
  expected night and resolved dark state. It stores `native-theme-<mode>-system-night.txt` and
  `native-theme-<mode>-state.txt` before capturing. A stale pre-switch line cannot satisfy the next
  mode, and the smoke still never writes a theme preference. `docs/agent/emulator-verification.md`
  records the readiness and AMOLED evidence.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **517/517**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-theme-guard.sh` OK and suite 15/15; `nothingui-native-surfaces-guard.sh` OK and suite
  17/17; `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite
  19/19; `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-icon-render-guard-test.sh` 15/15; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; all source guards OK; `sh -n` clean on the edited scripts;
  `git diff --check` clean. `verify-play-build.sh` then stopped only at the expected missing
  `build/intermediates` because Gradle did not run.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the native dark/light popup and drawer
  now match settings and Home, and that the new readiness trace is present before each capture. No
  runtime, APK or pixel claim is made from fixtures. PR19 is not merged.

## done (previous run — CI165 no-header later-page swipe geometry recovery)

- **Root cause from CI165, not guessed:** `workspace_page_swipe` still required the labelled-row
  `ui_dock_top` and a nonempty `ui_header_bottom`. The genuine later page has workspace
  `0 0 1080 1920`, hotseat `0 1481 1080 1920`, the Calendar host at `38 107 524 738`, a
  Gallery/Settings icon row at y=1196 and no `search_container_workspace` header. The labelled row
  reported 1196 and the header was absent, so the helper printed nothing and the return swipe
  failed. The app, design, workflow, SDK, permissions, signing, release and AMOLED files were
  untouched.
- **Page-local swipe:** `workspace_page_swipe` now reads the actual `workspace` (or
  `workspace_right`/`workspace_grid`) and `hotseat` bounds, validates both are numeric and
  nondegenerate, and requires the hotseat top to be below the workspace top. It starts the safe
  band at the real `ui_header_bottom` when one exists, otherwise at the measured workspace top, and
  never inherits a first-page header or invents a fraction. y is the midpoint above the actual
  hotseat; x endpoints are absolute and strictly inside the actual workspace, including nonzero
  origins. Missing/malformed/degenerate workspace or hotseat, an impossible band, or an unknown
  direction fails closed. Generic drawer helpers and `ui_dock_top`/`ui_header_bottom` themselves are
  unchanged.
- **Handoff audit:** the only no-header assumption in the third-party handoff was this swipe helper.
  `search_home_pages_for_widget`, `restore_primary_home`/`primary_home_is_ready`,
  `verify_nothing_home`/`verify_home_widgets`, and the subsequent drawer/Settings/native checks do
  not require a later-page header. The smoke still completes third-party proof first, then restores
  the primary HOME with the normal HOME key and runs the existing `verify_nothing_home`.
- **Fixtures:** CI159 first page (header bottom 312, hotseat 1481) yields next `864 896 216 896` and
  prev `216 896 864 896`; the no-header later page (icon row 1196, hotseat 1481) yields
  `864 740 216 740` and `216 740 864 740`, proving the helper ignores icon row 1196. A nonzero-origin
  workspace `[40,120][1040,1800]` yields absolute `840 810 240 810`. Missing/malformed/degenerate
  workspace and hotseat, a hotseat above the workspace, a header reaching past the hotseat, and an
  unknown direction all fail closed. Existing selected `WidgetCell` caption separation, exact
  provider/bounds/new-ID proof, foreground/no-permanent-binding guards and primary-page assertions
  are unchanged.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **511/511**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; the widget/home/role/theme/icon/native/drawer-trace/brand/
  identity source guards all OK; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** CI has not yet rerun the API 37 runtime smoke at this head. No runtime, APK
  or pixel success is claimed from fixtures; the later-page return/recheck swipe must be observed
  to pass in the next CI. PR19 is not merged. Release and hosting remain paused.

## done (previous run — CI161 selected-preview caption and primary-HOME restore)

- **Root cause from CI161, not guessed:** the picker's Clock provider exposed both `Analog clock`
  and `Digital clock` `WidgetCell`s at the same vertical position. The smoke passed the provider
  header `Clock` to `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds`, so the
  exact platform dialog (`Widget: Analog clock`) was rejected and the run timed out. The app,
  workflow, SDK, permissions, signing and release configuration were untouched.
- **Two separate identities:** the selected provider/app title `Clock` remains only the HOME host
  and page-search identity. The new pure `widget_picker_selected_caption` reads the `widget_name`
  from the same actual `WidgetCell` (nearest ancestor class) that owns the measured
  `widget_preview_container` bounds in the saved pre-Add XML. It never uses the first global
  `widget_name` or the provider header. It prints a caption only when exactly one `WidgetCell` owns
  the selected preview and that cell exposes exactly one non-empty `widget_name`; missing, foreign,
  duplicate or ambiguous captions print nothing and the smoke fails closed.
- **Consent wiring:** both `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds`
  now receive `_cwp_widget_caption`; the provider title still feeds `home_widget_bounds`,
  `placed_widget_page_is_safe` and the bounded page search. The log records both values.
- **Primary HOME restore:** after the exact placed host/new launcher-owned id, Settings/HOME
  survival and bounded page recheck pass, new `restore_primary_home` sends one ordinary HOME key
  (the existing `Launcher.onNewIntent` default-page behavior), then polls `primary_home_is_ready`
  for up to 10 attempts. That readiness requires the date pill, live clock text and the clock,
  battery, device-storage value and device-progress child ids. Only then does `verify_nothing_home`
  run. No workspace item is reset, moved or deleted, and the primary-page assertions are unchanged.
- **Fixtures:** new Clock cells model `Analog clock`/`Digital clock` at the same vertical position
  with left/right preview selection; Calendar with the same provider/widget name; the own DotWel
  group with distinct captions; missing, ambiguous, unrelated and provider-header negatives. The
  CI161 platform consent fixture now expects `Analog clock`; `Clock` and `Digital clock` expectations
  fail to find a Create target, and Always allow stays unchecked. Existing wrong
  widget/launcher/dialog/package/disabled-button/checkbox negatives are retained.
- **Source regression guard:** the smoke test asserts the recheck line precedes the
  `restore_primary_home` call, which precedes `verify_nothing_home`; it also asserts the restore uses
  `KEYCODE_HOME` and never clears/moves/deletes workspace items.
- **Docs:** `docs/agent/emulator-verification.md` records the two identities, the same-`WidgetCell`
  caption rule, fail-closed ambiguity, primary-HOME restore and the new evidence files.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **495/495**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; the widget/home/role/theme/icon/native/drawer-trace/brand/
  identity source guards all OK; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** CI has not yet rerun the API 37 runtime smoke at this head. No runtime, APK
  or pixel success is claimed from fixtures; the Analog clock consent must be observed to pass in
  the next CI, and the primary/default HOME restore must be observed before `verify_nothing_home`.
  PR19 is not merged.

## done (previous run — CI159 placed-widget page-geometry recovery)

- **Diagnosed from the reported evidence, not guessed:** the old check measured
  `_cwp_ref_dock_top` and `_cwp_ref_header_bottom` from the pre-widget first page and applied them to
  the page where the Calendar was actually found. The later page legitimately has no launcher
  `search_container_workspace` header, so its Calendar top `107` is valid; the stale first-page
  header bottom `312` falsely rejected it.
- **Page-local geometry helper:** new pure `home_widget_page_geometry_ok <xml> <bounds>` reads the
  workspace actually present on the placed page (`workspace`/`workspace_right`/`workspace_grid`),
  the actual `hotseat` dock top, and `ui_header_bottom` only when a launcher header really exists on
  that page. It rejects out-of-workspace bounds, real header overlap, real dock overlap and
  missing/malformed workspace or dock geometry. It never inherits the first-page header and never
  invents the old 15 percent band. It deliberately does not use the labelled-row `ui_dock_top`,
  which can report `1196` for ordinary Gallery/Settings icons on a later page.
- **Identity retained:** new `placed_widget_page_is_safe` re-runs `home_widget_bounds` with the
  selected provider label and requires the exact placed bounds before the geometry check, so
  absent, foreign, picker-preview and mismatched hosts still fail closed.
- **Smoke wiring:** `capture_widgets_picker` now calls `placed_widget_page_is_safe` on
  `$_cwp_placed` with the reference, provider title and placed bounds. The stale
  `_cwp_ref_dock_top`/`_cwp_ref_header_bottom` block is gone. Add/Create, new AppWidgetId/host/
  provider ownership, later-page discovery, post-Settings/HOME survival, exact foreground,
  own-widget/header/dock and no-permanent-binding guards are unchanged.
- **Fixtures:** CI159 first page (header bottom `312`, Calendar `38 328 524 738`) and no-header
  later page (Calendar `38 107 524 738`, Gallery/Settings at `1196`) are accepted; first-page header
  overlap, dock overlap, out-of-workspace, missing hotseat, missing workspace, malformed/non-numeric/
  empty bounds, absent host, foreign label, picker preview and mismatched bounds are rejected. The
  later-page `ui_dock_top=1196` hazard is asserted explicitly.
- **Docs:** `docs/agent/emulator-verification.md` records the page-local validation, the no-header
  later-page rule and the fail-closed geometry.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` 469/469; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on all three edited scripts;
  `git diff --check` clean.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the later-page Calendar now passes and
  the strict first-page header/dock/workspace negatives still fail closed. No runtime, APK or pixel
  claim. PR19 is not merged; a fresh CI is required.

## done (previous run — CI155 HOME long-press widget-host recovery)

- **Diagnosed failure fixed in the harness:** CI155's `home_longpress_target` chose `540,896`,
  which is inside the third real widget host (`38,770,1042,1180`, the Device card). The old
  `ui_point_is_free` skipped every node whose `clickable` was not `true`, so a hosted widget exposed
  as a non-clickable `LauncherAppWidgetHostView` was treated as empty.
- **Occupancy:** `ui_point_is_free` now treats any `*AppWidgetHostView` class and any `/appwidget`
  resource-id as occupied regardless of `clickable`, `text` or `content-desc`; pending hosts are
  covered. Labelled clickable icons/folders keep their existing protection, and the header/dock/QSB
  band math is unchanged.
- **Safe candidate search:** widget-host bounds are expanded by the same measured 4% margin, and
  `home_longpress_target` adds bounded 90/95/100 percent candidates so it can reach the genuinely
  empty band below the Device card instead of a narrow gap or a widget edge. If all candidates are
  occupied it still fails closed; no widget is pressed and no UI is bypassed.
- **Fixtures:** new CI155 geometry (root 1080x1920, full-root workspace, hotseat at 1481, three
  non-clickable "DotWel Launcher" hosts) rejects `540,896` and selects `540,1300`, which is asserted
  below the Device card, above the dock and free. Added pending-host, unlabelled-host and
  all-widget-occupied fail-closed fixtures. The legacy empty-layout target remains `540,834`.
- **Docs:** `docs/agent/emulator-verification.md` records host occupancy, clearance and the
  below-Device-card candidates.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` 450/450; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the new target opens the normal HOME
  popup. PR19 is not merged and no runtime/APK claim is made.

## done (previous run — CI155 style-only correction)

- **Formatter-only:** `NothingUiDeviceStorage.isKnown`'s short expression body now has `=` and
  `total > 0L && available >= 0L && available <= total` on one line, as CI155 `check-style`
  requested. One file, 1 insertion / 2 deletions; every token and all behavior preserved.
- **Untouched:** widgets, tests, models, workflows, dependencies, permissions, identity, signing and
  every other file. No Gradle, Android build, merge or CI dispatch was run here.
- **Verification actually run:** `git diff --check` clean; the source diff is the single line above.
- **Blocked/unknown:** CI155's independent Android/emulator lanes and their pixels remain unreviewed;
  a fresh CI run must confirm `spotlessKotlinCheck`/`spotlessJavaCheck`.

## done (previous run — PR19 provider identity, page discovery and device Settings proof)

- **Device storage fallback:** `NothingUiDeviceStorage` now exposes `UNKNOWN_MARKER = "--"` and a
  negative/unknown size renders `--`; the device layout's default storage value and the localized
  `Storage unavailable` detail are the short fallback. The unit expectation for
  `usedPercent(3L, 1L)` was corrected from `100` to `67` (integer rounding is 67%), and
  `formatSize(-1L)` expects `--`. The new `nothingui_device_storage_unknown_value` string is
  `translatable="false"`.
- **Provider identity, not geometry:** `home_widget_bounds` accepts an optional expected provider
  label, matches the real workspace host `content-desc`, ignores reference hosts with a different
  label, and rejects pending hosts, picker/sheet previews and hosts outside the workspace when an
  expected label is supplied. The inherited first-unseen behavior is preserved when no label is
  supplied. The unsafe `home_has_widget_bounds` helper was removed; no bounds-only placement claim
  remains. Fixtures cover new Calendar vs existing own Clock at the same geometry, a wrong provider
  at the same bounds, preview, outside workspace, pending host, and two own hosts before Calendar.
- **Measured page discovery:** after Add and bind consent, the smoke waits for a new
  launcher-owned `AppWidgetId`, then searches at most three measured HOME pages by provider label
  plus a real workspace host. It refuses to swipe unless the launcher is resumed and no bind consent
  is open, and saves per-page XML/PNG, activities/swipe logs and `widgets-page-log.txt`. The
  after-Settings survival search uses the provider label plus the exact placed bounds and rechecks
  that exact host. Static tests assert the three-page cap, foreground/consent safety, per-page
  evidence and no bounds-only helper.
- **Device Settings shortcuts:** `exercise_device_settings_shortcuts` taps the measured child bounds
  of `nothingui_device_wifi`, `nothingui_device_sound` and `nothingui_device_display`. It resolves
  each expected destination from the installed platform with
  `cmd package resolve-activity --brief` for `WIFI_SETTINGS`, `SOUND_SETTINGS` and
  `DISPLAY_SETTINGS`, falling back to `android.settings.SETTINGS` exactly as the widget does, and
  never guesses an alias. It requires the platform-resolved component foreground, captures the
  Settings activity/UI, returns HOME, requires the card and pill visible again, and re-reads
  `dumpsys appwidget` to prove all three own ids are distinct and unchanged. It never writes a
  setting or rebinds a widget.
- **Focused fixtures:** smoke tests now cover `parse_resolved_component` (brief, priority-prefixed,
  alias and no-activity output), device child bounds, device storage short fallback, device provider
  binding in `own_widget_new_binding`, static device provider/storage checks, and the device
  Settings flow/order. `_cows_max_rounds` was corrected to `3` with the label “at most three rounds”.
- **Verification actually run (no Gradle, no Android, no emulator):**
  `emulator-smoke-test.sh` 443/443; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on every edited script; `git diff --check`
  clean. The JUnit test, Android build, style and API 37 runtime captures remain CI gates.
- **Blocked/unknown:** no local JUnit or runtime result. CI147's third-party detector failure is not
  fixed here; the page-discovery change is the intended correction but needs fresh CI evidence.
  PR19 is not merged and no pixel/APK claim is made.

## done (previous run — PR19 pending-widget smoke harness recovery)

- **Reported failure reproduced:** at `740b2cb` the smoke fixture suite had exactly one failure:
  `a pending host outside a present workspace is rejected` returned `40 900 500 1200`.
- **Root cause:** `home_pending_widget_bounds` set `saw_ws` only inside the pending-host branch, so
  a workspace with no pending host was invisible and the no-workspace fallback returned an outside
  host. `saw_ws` is now set for any workspace node, so the fallback applies only when no workspace
  is exposed. Fixtures keep the no-workspace fallback positive and the outside-host negative.
- **Exact own-provider acceptance:** new `own_widget_new_binding` accepts exactly one newly bound
  record with a numeric id, the running `$PKG` as both host and provider package, and exactly
  `app.dotwel.widgets.DotWelClockWidgetProvider` or
  `...DotWelBatteryWidgetProvider`. The old substring `case` is gone. Fixtures cover one clock,
  one battery, unchanged, foreign provider package, class prefix/suffix lookalikes, short class,
  wrong provider, two records, mixed own/foreign multiline, foreign host and non-numeric id.
- **Exact consent activity:** new `foreground_is_component` matches the resumed component exactly.
  The own-widget consent now requires `com.android.settings/.AllowBindAppWidgetActivity` (or its
  fully qualified form), grounded in the CI134 `activities-widget-placed-1.txt` evidence. Fixtures
  cover the CI134 shape, the fully qualified form, another Settings activity, a foreign package, a
  class suffix lookalike and the exact package requirement.
- **Per-round completion:** after Create the flow now requires the real launcher HOME
  (`$PKG/$LAUNCHER_ACTIVITY`) and finishes a round only when exactly one new own provider is bound
  and the pending count decreases by exactly one. A missing decrease, a still-open dialog or a
  wrong provider fails closed. Max two rounds, 12 bounded polls, unexpected-dialog failure, Always
  allow unchecked and ordinary measured taps are unchanged; before/consent/after XML+PNG retained.
- **Unchanged proofs:** `verify_home_widgets` still proves distinct launcher-owned ids, the live
  `TextClock` value and a real battery percentage/`--`; `capture_clean_home_theme` and the
  third-party picker/consent/placement/Settings-survival flow are untouched.
- **Formatting:** the Java policy constants were joined to one line (94/98 columns) to match
  google-java-format AOSP, since every existing split constant in `src/com/android/launcher3` is
  >100 columns. The Kotlin policy test matches the existing `tests/unit` style (header, imports,
  4-space indent, trailing commas); no Gradle was run here.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 389/389;
  `emulator-smoke-drawer-test.sh` 38/38; `nothingui-widget-guard-test.sh` 31/31;
  `nothingui-home-guard-test.sh` 18/18; `play-brand-guard-test.sh` 22/22;
  `play-identity-guard-test.sh` 8/8; `nothingui-theme-guard-test.sh` 12/12;
  `manifest-guard-test.sh` 31/31; `nothingui-home-role-guard-test.sh` 7/7;
  `verify-play-build-test.sh` all pass. Source guards widget/home/brand/theme/identity/role OK.
  `sh -n` clean on the three edited scripts; `git diff --check` clean.
- **Blocked/unknown:** no runtime, APK, pixel or CI claim. `manifest-guard.sh` needs a built merged
  manifest and was not run directly; its fixture suite passed. PR19 is not merged.

## done (previous run — PR19 CI136 DotWel provider-package correction)

- **CI136 failure diagnosed, not guessed:** Android `assemble` and all unit tests passed, but
  `Verify Play manifest and identity` failed the existing `play-brand-guard`. Its broad
  case-insensitive scan found the new default-workspace comment (`NothingUI`) and the two fully
  qualified `app.nothingui.widgets.NothingUiClockWidgetProvider` /
  `...NothingUiBatteryWidgetProvider` names in `play/res/xml/default_workspace_4x5.xml`. The guard
  was not weakened, skipped or excepted; the production references were renamed instead.
- **Provider package move:** only the two new provider classes moved to
  `lawnchair/src/app/dotwel/widgets/` as `DotWelClockWidgetProvider.kt` and
  `DotWelBatteryWidgetProvider.kt`, package `app.dotwel.widgets`, with matching class and
  `ComponentName` names. `NothingUiWidgetColors`, `NothingUiWidgetBudget`, `NothingUiBatteryArt`,
  `NothingUiWidgetMonitor` and the MIT `DotText` renderer stayed in `app.nothingui.widgets`; the
  moved providers import those helpers, and the monitor imports the two providers. Resource IDs,
  widget XML metadata, layouts, refresh logic and theme handling are untouched.
- **References updated:** Play manifest receivers, the fresh-install default workspace, the
  lifecycle monitor, `nothingui-widget-guard.sh` and its fixtures, the emulator smoke
  provider-instance parsers/fixtures and `docs/agent/emulator-verification.md`. The default
  workspace comment now says "original DotWel widgets". No provider alias and no second widget.
- **Preserved:** no visual, layout, data, permission, refresh, theme, workflow, Gradle/SDK,
  applicationId, signing, paid-service, database, wallpaper or preference change. `w/` remains
  untracked scratch.
- **Verification actually run (no Gradle, no emulator):** `play-brand-guard.sh` OK and its suite
  22/22; `nothingui-widget-guard.sh` OK and its suite 26/26; `nothingui-home-guard.sh` OK and its
  suite 18/18; `verify-play-build-test.sh` 11/11; `emulator-smoke-test.sh` 342/342;
  `emulator-smoke-drawer-test.sh` 38/38; `sh -n` clean on every edited script; `git diff --check`
  clean. The Android build, unit tests, spotless and API 37 emulator captures remain CI gates.
- **Blocked/unknown:** no runtime/emulator claim; CI must still compile, test and produce the clean
  dark/light home screenshots. PR19 is not merged.

## done (previous run — PR19 CI136 spotless Kotlin correction)

- **Formatter-only:** `DotText.pitchFor`'s short expression body now has `=` and
  `minOf(boxW / cols(text), boxH / ROWS).coerceAtLeast(0.5f)` on the same single line, as the
  formatter requested. One file, 1 insertion / 2 deletions; no behavior change.
- **Untouched:** layout data, workflows, Gradle/SDK, permissions, applicationId, signing and every
  other file. No Gradle build was run here.
- **Verification actually run:** `git diff --check` clean; the source diff is the single line above.

## done (previous run — home-widget-composition-v1 pre-CI checkpoint)

- **RemoteViews composition:** the clock layout's bare `<View>` surface is now an
  `<ImageView android:id="@+id/nothingui_clock_surface">`; the provider's runtime
  `setBackgroundResource` tile remains. Native `TextClock`, colours, battery art, layouts,
  preferences, wallpapers and light/dark/system handling are unchanged.
- **Compiled resource IDs:** new pure `WidgetPackageResolver` resolves the compiled numeric
  `launcher:packageName="@string/launcher_component"` ID to the running variant's `contextPackage`,
  and other compiled string IDs to their package component. `PendingWidgetParser` reads
  `getAttributeResourceValue(parser, ATTR_PACKAGE_NAME, 0)`, resolves its own `launcher_component`
  ID via `getResources().getIdentifier(...)`, keeps the `@string/...` text-fixture fallback, and
  never hardcodes `com.launchernos.dotwellabs`.
- **Unit coverage:** `WidgetPackageResolverTest` covers compiled own/other/no-slash IDs, a literal
  package, literal `@string/launcher_component`, another literal string, and a missing package. It
  was not run locally (no Gradle by instruction); CI owns it.
- **Guard:** `nothingui-widget-guard.sh` requires the resolver, the compiled-ID read, the
  `launcher_component` special case, `contextPackage`, and the string fallback; rejects a hardcoded
  applicationId and any bare `<View>` in clock/battery RemoteViews layouts; requires the clock
  `<ImageView>` tile. Fixtures add parser-without-resolution, text-prefix-only, hardcoded
  applicationId and bare-View negatives. The guard suite passes.
- **Smoke proof:** `verify_home_widgets` now dumps `dumpsys appwidget`, requires distinct
  launcher-owned AppWidgetIds for the NothingUI clock and battery through the record-aware parser,
  and requires the measured HOME XML to expose `nothingui_clock_time` with live `H:mm`/`HH:mm` text
  and `nothingui_battery_art` with a real `0..100%`/`--` description. It writes
  `home-widgets.txt`, `home-widgets-instances.txt` and `home-widgets-verified.txt`.
- **Clean HOME:** `capture_clean_home_theme` first requires the existing
  `pref_launcherTheme=system` choice (read-only), then captures dark/light under system night
  yes/no, runs the same widget-id/child-value proof per capture, stores per-mode widget evidence,
  restores the night mode and returns HOME. It runs before any third-party widget placement.
- **Fixtures:** the smoke tests cover API 37 current-format and legacy launcher-owned instances,
  provider-catalog-only and other-host negatives, distinct IDs, real/live clock and battery values,
  missing child IDs, plus static checks for the new HOME/clean-HOME proof. The docs list the new
  artifacts.
- **Preserved:** Play `applicationId`, `minSdk`/`targetSdk`, manifest/permissions, workflows,
  Gradle/SDK/emulator, DB/schema, preferences, wallpapers, non-Play branding, the MIT notice and the
  existing grid/picker/drawer flows. No hardcoded package, direct widget binding, DB injection or
  broad harness rewrite.
- **Verification actually run (no Gradle/emulator):** `nothingui-widget-guard.sh "$PWD"` OK; widget
  guard suite 26/26; home guard and suite OK/18; manifest suite 31/31;
  `verify-play-build-test.sh` 11/11; `emulator-smoke-test.sh` all pass (including the new
  instances/child/value/static checks); `emulator-smoke-drawer-test.sh` 38/38; `sh -n` clean on all
  edited scripts; `git diff --check` clean. The JUnit test, Play debug build, spotless and API 37
  smoke remain CI gates.
- **Blocked/unknown:** runtime success of the hosted-widget and clean-HOME proof is unverified until
  CI runs the API 37 emulator. No PR, merge or visual claim.

## done (previous run — A2 corrective checkpoint)

- **Root cause 1 (formatting):** `spotlessKotlinCheck` rejected short expression-body functions in
  `NothingUiNativeSurfaces.kt` because the `=` and expression were split across lines. The simple
  `if (dark) ... else ...` bodies and the `allAppsBackground(dark).copy(alpha = ...)` layer bodies
  now sit on one line; the multiline block `if` for `allAppsBlurForeground` keeps the project's
  existing `= if (dark) {` form. The private `neutral`/`static` helpers follow the same style.
- **Root cause 2 (alpha):** Compose sRGB `Color.copy(alpha = 0.50f).alpha` quantizes to 8 bits
  (`128/255 = 0.5019608`), so the old literal `0.50f` expectation was wrong. The drawer-layer test
  now derives the expected alpha with `Color.White.copy(alpha = ...).alpha` and asserts it exactly
  for all eight scrim/expressive/blur values (0.40, 0.50 and 0.32). Coverage is unchanged and the
  tolerance was not loosened.
- **Scope:** no functional, native UI redesign, workflow, Gradle, SDK, manifest, permission,
  applicationId, signing, asset, other-repo or slice-B change.
- **Verification actually run (no Gradle, no emulator):**
  `nothingui-native-surfaces-guard.sh "$PWD"` OK; its fixture suite 14/14;
  `verify-play-build-test.sh` 11/11; `git diff --check` clean. CI132's remaining 41 unit tests
  passed, including the native contrast tests; the corrected CI must rerun the Android build,
  `spotlessKotlinCheck`, unit tests and the API 37 smoke.
- **Next:** picker A3 after PR18 is green.

## done (previous run — A1 debug warning contrast)

- **Root cause read from the source:** `PreferencesDebugWarning` passed
  `MaterialTheme.colorScheme.errorContainer` to `WarningPreference`, whose text/icon default to
  `MaterialTheme.colorScheme.error`. The NothingUi converters never set
  `errorContainer`/`onErrorContainer`, so Play fell back to Material's dark-red container
  (`#93000A`) under the accent-red text (`#D7261E`) — 1.86:1, the unreadable pixels CI captured.
- **Neutral warning tokens:** `NothingUiColors` gains `warningContainer`/`onWarningContainer`.
  Dark uses `Gray700` on `Paper` (10.16:1); light uses `Gray100` on `Ink` (15.77:1). Both
  containers are true neutral greys; `error` stays `AccentRed` and `onError` stays `onAccent`, so
  restrained red elsewhere is unchanged.
- **Converter mapping:** both `toDarkColorScheme()` and `toLightColorScheme()` now set
  `errorContainer = warningContainer` and `onErrorContainer = onWarningContainer` instead of
  inheriting Material defaults.
- **Play-only debug warning:** `PreferencesDebugWarning` computes the content color as
  `onErrorContainer` on Play and `error` otherwise, passing it as both `textColor` and `iconTint`.
  The warning is still shown in exactly the same debug/nightly condition; non-Play pixels are
  identical because the fallback is the previous default value.
- **Regression coverage:** `NothingUiTokenTest` adds dark and light warning-content contrast checks
  (`>= 4.5:1`, plus neutral-channel assertions) and a converter-mapping check that
  `errorContainer`/`onErrorContainer` equal the palette values while `error` stays the accent.
  Existing typography and screenshot-smoke assertions are untouched.
- **Scope:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing, asset, native
  popup/drawer/picker or other-repo change. Patch is 3 files, 46 insertions.
- **Verification actually run (no Gradle, no emulator):** `nothingui-theme-guard.sh "$PWD"` OK;
  `nothingui-theme-guard-test.sh` 12/12; `verify-play-build-test.sh` 11/11; `sh -n` clean on the
  edited scripts; `git diff --check` clean. The new JUnit contrast/mapping test and the CI pixel
  recapture are left to PR #17 CI, which builds and runs the unit tests.
- **Next:** native `ThemeProvider`, popup, drawer and picker surfaces. Slice A is still not complete.

## done (previous run — A1 settings palette partial checkpoint)

- **Real settings entry wired, not the sample:** `LawnchairTheme` previously always built the
  inherited `MaterialExpressiveTheme`/`ThemeProvider` color scheme. It now short-circuits through
  `NothingUiTheme(darkTheme = darkTheme, content = content)` when
  `NothingUiFeature.themeEnabled` is true. The default parameter remains
  `isSelectedThemeDark`, so LIGHT, DARK and SYSTEM resolve exactly as before; github/nightly still
  take the inherited branch with the same `getColorScheme`, shapes and expressive motion.
- **Typography:** `NothingUiTypography` now uses `DotoFontFamily` for `headlineLarge`,
  `headlineMedium`, `headlineSmall`, `titleLarge` and their emphasized variants (normal headings
  keep normal weight; emphasized headings keep bold). `titleMedium`/`titleSmall`, all body and all
  label styles remain `FontFamily.SansSerif`, so settings copy stays readable.
- **Preserved:** no change to `ThemeProvider`, popup, drawer, picker, grid values, Apply behavior,
  manifest, permissions, SDK, applicationId, signing, assets, workflows or other repos. The
  diagnostic `THEME_SAMPLE` route remains debug + Play gated and is unchanged.
- **Regression tests outside production `src`:** `tests/unit/java/app/nothingui/theme/
  NothingUiTokenTest.kt` now requires Doto on the display/headline/titleLarge styles and sans on
  titleMedium/titleSmall/body/label. `scripts/nothingui-theme-guard.sh` now requires the Play gate,
  the resolved `darkTheme` call, the inherited non-Play branch, and Doto on every headline/titleLarge
  style. Its fixture suite adds missing-gate, hardcoded-dark, and sans-headline negatives (and
  updates the existing EdgeToEdge fixture so it still tests only its own rule).
- **Smoke:** `scripts/emulator-smoke.sh` adds `capture_settings_theme` and
  `assert_settings_theme_choice_system`. It reads `shared_prefs/com.android.launcher3.prefs.xml`
  through `run-as` and requires `pref_launcherTheme=system` (a clean install default; no write),
  records the current `cmd uimode night`, captures the real `PreferenceActivity` under night
  `yes`/`no` without the sample extra as `settings-theme-dark.xml`/`.png` and
  `settings-theme-light.xml`/`.png`, requires the real `Settings`/`General` dashboard and rejects
  the `DOTWEL` sample, then restores the previous night mode and returns HOME even when a capture
  fails. The existing grid-preview and widget-placement phases are unchanged.
- **Verification actually run (no Gradle, no emulator):** `nothingui-theme-guard.sh "$PWD"` OK;
  `nothingui-theme-guard-test.sh` all pass (13/13); `emulator-smoke-test.sh` all pass including the
  new settings-theme static checks; `sh -n` clean on the edited scripts; `git diff --check` clean.
  The Android build, JUnit, `spotlessCheck`, and the API 37 emulator dark/light captures are left
  to CI/PR review.
- **Next:** native `ThemeProvider`, popup, drawer and picker surfaces. Slice A is not complete; this
  is only the settings palette checkpoint.

## done (previous run — P11 preview header parity)

- **Root cause from the source, not guessed:** `LauncherPreviewRenderer` initialized
  `mWorkspaceSearchContainer` to `R.layout.smartspace_container` at field declaration, before the
  model callbacks. The real workspace instead inflates the selected `SmartspaceMode`'s
  `layoutResourceId` in `Workspace.bindAndInitFirstWorkspaceScreen()`, and `LawnchairSmartspace`
  resolves that to `nothingui_home_header` on Play (`NothingUiFeature.homeEnabled`) and to
  `smartspace_container` on github/nightly. The preview therefore always showed the inherited
  welcome card on Play while live HOME showed the NothingUI header.
- **Preview parity:** the field no longer has a hardcoded layout. The new pre-bind
  `getDefaultSmartspaceLayout(context, preferenceManager)` reads
  `PreferenceCacheExtensionsKt.firstCached(getSmartspaceMode())`, falls back in memory to
  `LawnchairSmartspace.INSTANCE` when the selected mode is unavailable (mirroring Workspace, without
  writing the preference from a preview), and returns `mode.getLayoutResourceId()`. It runs at the
  top of the constructor, before `model.addCallbacksAndLoad(this)`, so it is set before any bind.
- **Race review:** `LauncherModel.addCallbacksAndLoad()` can bind synchronously when the model is
  already loaded, so `LauncherPreviewView` now passes the dummy
  `R.layout.smartspace_widget_placeholder` override as a new constructor argument instead of calling
  `setWorkspaceSearchContainer()` after construction. The 5-arg and 6-arg constructors still
  delegate with a `0` sentinel, so `PreviewSurfaceRenderer` and other callers are unchanged apart
  from the corrected default.
- **Preserved:** `bindCompleteModel` still gates the first-page item on `getEnableSmartspace()`;
  the explicit dummy override still wins; `SmartspaceMode` keeps its `NothingUiFeature.homeEnabled`
  gate and inherited fallback; Google/Smartspacer selections still use their own layouts. No dot
  clock layout duplication and no hardcoded preview clock text — the preview inflates the existing
  `nothingui_home_header` / `NothingUiHomeHeaderView`.
- **Regression coverage:** `scripts/nothingui-home-guard.sh` now requires the preview renderer to
  read `getSmartspaceMode` and `getLayoutResourceId`, rejects a hardcoded
  `mWorkspaceSearchContainer = R.layout.smartspace_container`, requires the pre-bind override
  parameter, requires `LauncherPreviewView` to keep the dummy placeholder and to not call
  `setWorkspaceSearchContainer` after construction, and still requires `getEnableSmartspace`.
  `scripts/nothingui-home-guard-test.sh` adds three negatives (hardcoded container, missing selected
  mode, post-construction dummy override). JUnit sources were not added to `src/`.
- **Verification actually run (no Gradle, no emulator):** `nothingui-home-guard.sh "$PWD"` OK;
  `nothingui-home-guard-test.sh` 16/16; `verify-play-build-test.sh` 11/11;
  `emulator-smoke-test.sh` all pass; `emulator-smoke-drawer-test.sh` all pass; the identity,
  manifest, brand, theme, home-role, icon-render and drawer-trace fixture suites all pass; `sh -n`
  clean on both edited scripts; `git diff --check` clean. The Android build, unit tests, `spotlessCheck`
  and the API 37 emulator `grid-settings.png` pixel capture are left to CI.

## done (previous run — P10b safe Add tap and API37 ProviderId parser)

- **Root cause from CI120, not guessed:** the real picker exposed Add at `[434,1755][645,1881]`
  while the navigation bar begins around 1800. `tap_center_of_bounds` used the original centre 1818,
  which is inside the navigation bar, so the tap opened Android HOME. The existing viewport was never
  applied to Add.
- **Safe intersection:** `widget_picker_add_button_bounds` now requires `enabled="true"` as well as
  `clickable="true"`. New `widget_add_safe_bounds` intersects the Add with the viewport remeasured
  from the exposed Add hierarchy, subtracts a 32 px navigation-bar inset from the bottom, and prints
  bounds only when the result is at least 24 px in both dimensions. The CI120 box becomes
  `434 1755 645 1788`; the original 1818 centre is never tapped.
- **Bounded re-scroll:** if no safe box remains, `capture_widgets_picker` performs up to three
  genuine `input swipe` scrolls inside the measured real list, re-captures and re-resolves the Add
  after each, and logs every target. If Add disappears or the safe box never appears, it saves
  `widgets-add.xml`, `widgets-add-last.xml`/`.png` and fails with the original Add and viewport pixels
  instead of guessing a coordinate.
- **API37 provider wrapper:** `appwidget_new_providers` now accepts
  `provider=ProviderId{cmp:ComponentInfo{...}}` in addition to direct `provider=ComponentInfo{...}`.
  The wrapper is parsed only while a real `[N] id=N`/`AppWidgetId=N` block is active, and the same
  block must name this launcher in `host=HostId{... pkg:...}` or `hostPackage=`. Section headers
  flush the block, and a second provider line ends it, so provider catalogs and other hosts cannot be
  attributed to an old widget id.
- **Preserved:** real long-press, measured Widgets tap, native-picker readiness, search/scroll
  viewport, preview visibility, bind consent, new workspace host, launcher-owned appwidget id,
  header/dock band and HOME survival checks are unchanged. No direct picker/config start, fake drag,
  fixed coordinate, preference/DB write or direct binding was added.
- **Fixtures:** the actual CI120 Add bounds are covered as a partially hidden Add with a safe
  `434 1755 645 1788` intersection; a fully visible Add, a fully hidden Add, a barely visible Add and
  a horizontally outside Add are covered; a disabled Add is rejected. API37 fixtures cover a wrapped
  provider in a current launcher-owned `[N] id=N`/`HostId` block, a legacy `AppWidgetId`/`hostPackage`
  block, another launcher's host, an installed-provider catalog with and without a section header,
  and a wrapper outside any widget-id block.
- **Docs:** `docs/agent/emulator-verification.md` records the safe Add intersection, the bounded
  re-scroll and the API37 `ProviderId` rules.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 269/269;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` 11/11; `sh -n` clean on every
  edited script; `git diff --check` clean. This is source/fixture verification only, not a runtime
  claim. APK110 fallback is unchanged.

## done (previous run — P10b bind consent label-case review correction)

- **Root cause from the CI116 actual XML, not guessed:** `android:id/button1` is rendered with an
  uppercase `CREATE` label, while both helpers matched `text="Create"`/`text != "Create"` exactly.
  The old readiness also grepped the whole tree for the title, `Application:`/`Widget:` and the
  launcher/widget names, so unrelated text could satisfy it.
- **Case normalization:** `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds` now
  compare the button label with `tolower(...) == "create"`, so `CREATE` and `Create` both work.
- **Identity retained:** both helpers require `package="com.android.settings"` on the dialog nodes,
  the exact `android:id/alertTitle` title, and an enabled (`enabled="true"`) clickable
  (`clickable="true"`) `android:id/button1`; readiness also requires `android:id/alwaysUse`.
- **Message scoping:** the launcher and selected widget must appear in the `android:id/message` text
  as `Application: <launcher>` and `Widget: <widget>` (case-insensitive). Text elsewhere in the tree
  is rejected. `widget_bind_create_button_bounds` now takes the launcher/widget arguments, and the
  smoke passes `"$EXPECTED_LABEL" "$_cwp_provider_title"`.
- **Fixtures:** the pretty and compact titlecase positives now carry the Settings package and enabled
  controls. A new compact platform fixture matches the actual shape (system package, `alertTitle`,
  message naming DotWel Launcher and Calendar, unchecked `alwaysUse`, uppercase `CREATE`/`CANCEL`).
  New negatives cover wrong launcher, wrong widget, wrong package, loose launcher/widget text outside
  the message, a generic Create dialog, and a disabled Create button; the checked `alwaysUse` case
  still fails closed. Positive and negative bounds resolution is asserted.
- **Docs:** `docs/agent/emulator-verification.md` records the case-insensitive label, Settings
  package, message-scoped identity and disabled-button rejection.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 249/249;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` 11/11; `sh -n` clean on every
  edited script; `git diff --check` clean. This is source/fixture verification only, not a runtime
  claim. APK110 fallback is unchanged; the grid preview task was not started.

## done (previous run — P10b bind consent and Settings survival)

- **Evidence read, not guessed:** CI116 stopped after the Calendar preview Add on the genuine Android
  `AllowBindAppWidgetActivity`; the previous harness polled only for a workspace host and never
  handled the dialog. The actual AOSP dialog is an `AlertActivity` titled
  `Create widget and allow access?` with `Application:`/`Widget:` message text, the
  `android:id/alwaysUse` checkbox, `android:id/button1` Create and `android:id/button2` Cancel.
- **Exact consent gate:** `widget_bind_consent_is_ready` requires the exact title, `Application:` and
  `Widget:` labels, the launcher label, the selected provider title, the `button1` Create control and
  the `alwaysUse` checkbox. A generic Create dialog, another launcher, another widget, a missing
  button1 or a compact single-line dump is handled; only the exact dialog is accepted.
- **Safe Create route:** the flow captures the consent XML and PNG, refuses to continue if
  `Always allow` is already checked, measures `android:id/button1` and taps its centre. A second
  Create tap is suppressed while the dialog is still visible, and a dismissed dialog is never treated
  as success. The route and unchecked state are recorded in `widgets-add-log.txt`.
- **Launcher-owned instance:** `appwidget_new_providers` now parses current
  `Widgets:`/`[N] id=N`/`host=HostId{..., pkg:...}` dumps as well as legacy
  `AppWidgetId=N`/`hostPackage=` dumps, and accepts the new instance only when its host package is
  `$PKG`. The smoke polls `dumpsys appwidget` five times, so an installed provider or another
  launcher's host cannot satisfy placement.
- **Settings survival:** after placement it launches `android.settings.SETTINGS`, waits for the
  exact `com.android.settings` foreground, captures `widgets-settings-launched.xml/.png`, presses
  HOME, captures `widgets-home-after-home.xml/.png`, and requires the same widget bounds as before
  the app switch.
- **Fixtures:** modern launcher-owned, other-launcher and missing-ownership dumps, unchanged modern
  dump, legacy `hostPackage` positive/negative, pretty/compact consent, unrelated dialog, other
  launcher, other widget, missing button1, checked Always allow, and measured Create bounds. Static
  checks now require the consent/Settings path and only reject picker-specific direct starts.
- **Preserved:** the real long-press, measured Widgets tap, picker readiness, search/scroll viewport
  correction, no fake drag, no direct picker/config start, no preference/DB write and no direct
  widget binding. APK110 remains frozen.
- **Docs:** `docs/agent/emulator-verification.md` records the consent, launcher-owned appwidget and
  Settings-survival phases and artifacts.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 237/237;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` all pass;
  `verify-play-build.sh` passes every source guard and stops only at the expected missing
  `build/intermediates`; `sh -n` clean on every edited script; `git diff --check` clean. This is
  source/fixture verification only, not a runtime claim.

## done (previous run — P10b FINAL native picker viewport correction)

- **Evidence read, not guessed (CI114 / `11444966646679`):** the Calendar `widgets_list_header`
  expanded at `[29,1592][1051,1827]`; the `widget_preview_container` was `[297,1869][783,1920]`,
  only 51 px tall and below the navigation top 1794. The preview tap never reached the real preview,
  Add was never exposed, and the ordinary workspace swipe from `540,1894` to `810,834` hit the
  navigation bar and opened the drawer. The app itself was unchanged.
- **Viewport gate:** added `widget_picker_search_bar_bounds` (real
  `widgets_search_bar_edit_text`, falling back to `search_bar_container`/`widgets_search_bar`),
  `widget_picker_viewport_bounds` (root bounds, top below the search bar, bottom = root bottom -
  100), and `widget_picker_preview_is_visible` (height >= 100, fully inside the viewport, bottom
  strictly above root bottom - 100). A clipped preview is rejected even with a valid resource id.
- **Bring into view before selection:** the smoke focuses the real search input, types `Clock`, and
  polls the search results for a Clock `widgets_list_header`; if the query yields no header it clears
  the text and uses the measured list. It then selects Clock/Calendar only when the header's
  `widget_preview_container` is fully visible. If the preview is clipped or off-screen it performs up
  to three genuine vertical swipes inside the measured widget list
  (`primary_widgets_list_view`/`search_widgets_list_view`/`widgets_catalog`), clamped between the
  search-bar bottom and root bottom - 100, re-resolving the header and preview after every scroll.
  It expands a header only when no preview exists yet; a clipped preview is never re-tapped.
- **No fake drag:** the ordinary `input swipe` workspace fallback and the `widget_drop_target` helper
  are removed. If the measured `widget_add_button` is not exposed after tapping the fully visible
  preview, the run captures `widgets-add-last.xml`/`.png` and fails.
- **Preserved:** the placement proof still requires a new workspace `AppWidgetHostView`, a new bound
  `AppWidgetId`/provider in `dumpsys appwidget`, and the same widget bounds after HOME. The real
  long-press, measured Widgets tap, picker readiness, role consent, grid read-only checks and
  Settings/drawer flow are untouched. APK110 remains frozen.
- **Fixtures:** the actual CI114 clipped `[297,1869][783,1920]` preview is rejected; a fully visible
  preview is accepted; a preview above the search bar and a >=100 px preview whose bottom crosses
  the navigation margin are rejected; the search input bounds, viewport and clamped scroll target
  are asserted; static checks require the search/scroll path and reject the removed drag fallback.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 208/208;
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. This is source/fixture verification only, not a
  runtime claim.

## done (previous run — P10b widget placement review correction)

- **Compact hierarchy, not a line guess:** `home_widget_bounds` previously read attributes from the
  first `<node` on each physical line. A CI110-style UIAutomator dump is one line, so it could see
  only the root/first node and miss a nested workspace host. Both reference and current files are now
  split into node records (`tr '>' '\n'`) and tagged `R`/`C`; explicit markers preserve the
  reference/current distinction even when the reference is empty. A missing reference still means
  "no previous hosts", not "treat the current tree as the reference".
- **Workspace vs sheet preview:** the comparison tracks node nesting. A host inside
  `widget_preview_container`, `widgets_list_header`, `widgets_catalog`, a picker list, `WidgetCell`,
  `WidgetsListHeader`, a bottom sheet or an add-widget sheet is rejected. When the current hierarchy
  exposes a `workspace`/`Workspace` ancestor, only a host inside it is accepted; a workspace host is
  preferred over any non-workspace host.
- **New bound instance, not just a provider:** `appwidget_new_providers` now associates each
  `provider=ComponentInfo{...}` with its enclosing `AppWidgetId=N` block and reports only providers
  for AppWidgetIds absent from the before dump. An installed-provider list or a provider name that
  was already present cannot satisfy placement; a new AppWidgetId for an already-installed provider
  still can.
- **Expanded provider association:** after tapping a provider header, the smoke re-runs
  `widget_picker_provider_bounds` on the expanded capture by the selected `Clock`/`Calendar` title,
  then passes that fresh header to `widget_picker_preview_bounds`. A stale collapsed header cannot
  skip the real preview and select a later provider's preview. The next-header boundary still comes
  from the same expanded capture.
- **Add route preserved:** `widget_add_button` was verified in the inherited source
  (`res/layout/widget_cell_content.xml` and `src/com/android/launcher3/widget/WidgetCell.java`) and
  is unchanged.
- **Fixtures:** compact single-line positive host, pretty reference, unchanged compact reference,
  empty reference, no-host compact HOME, compact preview-only host, compact mixed preview/workspace
  host, host outside a present workspace, new AppWidgetId for an already-installed provider,
  installed-provider-only list and empty before dump; expanded-header stale/updated preview cases.
- **Limitation recorded:** if the actual hierarchy exposes no workspace node at all, the helper can
  only reject known picker/sheet preview containers, not prove workspace membership. The CI110
  `widgets-home-placed*.xml` / `widgets-home-after-home.xml` artifacts must be inspected; if the real
  `dumpsys appwidget` uses a different bound-instance shape, the helper fails closed and the
  captured dump must drive the update.

## done (previous run — P10b widget placement and HOME survival)

- **Evidence read, not guessed:** CI110's picker hierarchy (as reported in the task) has a clickable
  `widgets_list_header` with `app_title` Calendar and subtitle `1 widget`, Clock next, a
  long-clickable `widget_preview_container` inside a WidgetCell, and a DotWel row with only
  `1 shortcut`. The flow therefore selects only a header whose subtitle reports a positive widget
  count; a shortcut-only header is never eligible.
- **Provider selection:** `widget_picker_provider_bounds` parses the real nested
  `widgets_list_header`/`app_title`/`app_subtitle` nodes and returns the measured header bounds for
  Clock then Calendar. It does not use a class-name guess or a fixed coordinate.
- **Expansion and preview:** `widget_picker_preview_bounds` requires a clickable/long-clickable
  `widget_preview_container` below the selected header and above the next header. If the provider is
  already expanded the preview is used directly; otherwise the measured header is tapped and polled
  for up to five captures per attempt, bounded to two taps.
- **Add route:** `widget_picker_add_button_bounds` selects the exposed Add button by its real
  `widget_add_button` resource id (icon-only safe). The flow taps the measured preview, captures
  `widgets-add-attempt-N.xml`, then taps the measured Add. If Add is not exposed it uses a genuine
  measured drag to `widget_drop_target` (right-hand workspace, between the measured header and dock).
- **Placement proof:** the flow polls the real workspace for a new `AppWidgetHostView`-suffixed node
  against the pre-widget HOME and for a new `provider=ComponentInfo{...}` entry in
  `dumpsys appwidget`. A configuration activity or an unbound provider fails with
  `widgets-add-last.xml`/`.png` and the last resumed component recorded, rather than a fake pass.
- **HOME survival:** it captures `widgets-home-placed.xml`/`.png`, requires the widget bounds to stay
  between the measured header bottom and dock top (away from the later drawer swipe start), presses
  HOME through the existing `return_home widgets-picker`, captures
  `widgets-home-after-home.xml`/`.png`, and requires the same widget bounds to remain.
- **Preserved:** the real HOME long-press, measured Widgets tap, native-picker readiness, role
  consent Cancel, grid read-only checks, 1500 ms/four-attempt drawer, Settings search/tap and exact
  foreground checks are unchanged. No direct picker/config `am start`, preference/DB write, or widget
  binding was added.
- **Docs:** `docs/agent/emulator-verification.md` records the new provider/add/placement/survival
  phases and artifact names.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass
  (including the new provider/preview/Add/placed-widget/appwidget provider fixtures and negatives);
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. This is source/fixture verification only; the CI
  API 37 run and pixels are still the runtime gate.

## done (previous run — P10a popup readiness correction)

- **Evidence read, not guessed:** CI108 (`10844960564539`) proved the grid settings pass: three
  sliders, grey non-clickable Apply, and the actual preview pixels. The real HOME long-press 540/834
  opened all three attempts, but `home_popup_is_ready` rejected the actual
  `home-popup-attempt-1-1.xml`/`-1-6.xml` because it required classes that are not present.
- **Actual popup shape:** `pkg:id/popup_container` class `android.widget.LinearLayout` bounds
  `[472,180][1039,743]`, with four clickable `pkg:id/system_shortcut` FrameLayouts at
  `[472,180][1039,317]`, `[472,322][1039,459]`, `[472,464][1039,601]` and `[472,606][1039,743]`.
  Each contains a `pkg:id/bubble_text` TextView labelled Wallpapers, Widgets, Apps list and Home
  settings; the Widgets label itself is not clickable and shares its parent's bounds.
- **Readiness fix:** `home_popup_is_ready` now parses nesting, requires `popup_container`, at least
  two clickable `system_shortcut` rows, a `Widgets` label inside a clickable row and a
  `Home settings`/`Wallpapers` label inside a clickable row. It no longer accepts a page that merely
  contains the text or an item menu.
- **Tap bounds:** `ui_clickable_label_bounds` was inspected against the actual nested shape; it
  already returns the nearest clickable ancestor, so the Widgets tap resolves to
  `472 322 1039 459`. Fixtures now lock that behaviour, including a non-clickable label and its
  clickable parent.
- **Failure evidence:** the popup-not-ready branch captures
  `home-popup-attempt-<N>-last.png` before pressing BACK. The genuine long-press gesture, measured
  target and real route are unchanged; no coordinates are hard-coded.
- **Fixtures:** the positive popup is the actual `popup_container`/`system_shortcut`/`bubble_text`
  shape. New negatives cover the real HOME, English-only text without the real ids, an item menu with
  Widgets but no home-level option, a popup without Widgets, and a single clickable shortcut with a
  home option outside any clickable shortcut. `widget_picker_is_ready` is unchanged until device
  evidence exists.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass (including
  every new positive/negative); `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean. This is source/fixture verification only, not a runtime claim.

## done (previous run — P10a grid/widget harness correction)

- **Evidence read, not guessed:** CI106 (`10644959244281`) passed assembly/style/units and the real
  grid editor opened, but the new readiness failed on class assumptions. The actual
  `grid-settings-attempt-6.xml` and pixels show the title `Home screen grid`; three visible
  `SeekBar`s with Columns 4, Rows 6, Dock icons 4; a preview `AndroidViewHolder[375,294][706,883]`
  containing a `ViewGroup` `...:id/workspace` at `375,313..706,844` with
  `hotseat`/`search_container_workspace`; there is no `LauncherPreviewView`/`LauncherPreviewLayout`
  class. Apply is a separate `TextView` at `488,1663..592,1716`, `enabled="true"`,
  `clickable="false"`, inside a non-clickable ancestor `View` and an empty non-clickable
  `android.widget.Button` at `42,1637..1038,1742`; the pixels are grey.
- **Preview readiness:** new `grid_preview_is_ready` requires a `/workspace` ViewGroup with valid
  bounds strictly inside the window root, strictly smaller than the root in both dimensions, above
  every `SeekBar`, and containing a `hotseat`/`search_container_workspace` node. No preview class
  name is required. `grid_settings_is_ready` keeps the title, four labels and three-SeekBar checks.
- **Apply readiness:** `grid_apply_is_unchanged` finds the `Apply` label bounds, rejects a clickable
  Apply, and requires a non-clickable `android.widget.Button` whose bounds contain the label. It does
  not depend on the label class or the accessibility `enabled` flag.
- **Failure evidence:** `capture_grid_settings` now captures
  `grid-settings-attempt-<last>.png` before failing when readiness never succeeds.
- **Unsafe fallback removed:** `home_longpress_target` returns failure when every measured candidate
  in the header/dock band is occupied instead of printing the band centre. The real measured HOME
  long-press Widgets route and all existing checks are otherwise unchanged.
- **Fixtures:** `emulator-smoke-test.sh` now models the actual hierarchy (preview
  ViewGroup/workspace/hotseat/search container, Apply TextView inside a non-clickable Button) and
  adds negatives for a missing workspace preview, a preview not above the controls, a preview
  without its hotseat, a clickable Apply, a missing containing Button, and a fully occupied
  long-press band.
- **Docs:** `docs/agent/emulator-verification.md` describes the bounds-based preview, the
  non-clickable Apply and the last-attempt PNG.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass (including
  every new positive/negative); `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh`
  all pass; `sh -n` clean on all edited scripts; `git diff --check` clean. This is source/fixture
  verification only, not a runtime claim.

## done (previous run — P10a initial real grid settings and widget-picker smoke)

- **Grid, read-only and real:** `capture_grid_settings` starts the existing
  `PreferenceActivity` with `lawnchair://settings/home-screen-grid` (the real
  `HomeScreenGrid.deepLink`), polls UIAutomator for the `Home screen grid` title, a
  `LauncherPreviewView`/`LauncherPreviewLayout`, `Columns`/`Rows`/`Dock icons`, at least three
  accessibility `SeekBar` nodes and `Apply`, and requires `Apply` to remain disabled. It captures
  `grid-settings.xml/.png`, never taps a control or writes a preference, then presses HOME and
  re-verifies the actual HOME clock/date.
- **Widgets, real long-press and native picker:** `capture_widgets_picker` derives an empty central
  point from the actual HOME hierarchy (header bottom from `search_container_workspace`, dock top
  from the lowest labelled row, with 4% margins), uses a genuine
  `input swipe x y x y 1000`, captures the real `OptionsPopupView`/`DeepShortcutView` popup, taps
  `Widgets` via its measured clickable bounds, and requires the native picker: the Compose
  `widgetpicker:id/widgets_catalog` plus search/tab labels, or the inherited
  `widgets_search_bar`/`search_bar_container` plus `primary_widgets_list_view`/
  `search_widgets_list_view`. The picker hierarchy must differ from the pre-long-press HOME. It
  captures `home-popup.xml/.png` and `widgets-picker.xml/.png`, returns HOME and re-verifies it.
  Bounded to three attempts; no `am start` for the picker, no fake view, no DB/pref write.
- **Pure helpers and regression:** `emulator-smoke-lib.sh` adds `ui_header_bottom`,
  `ui_point_is_free`, `home_longpress_target`, `grid_settings_is_ready`,
  `grid_apply_is_unchanged`, `home_popup_is_ready` and `widget_picker_is_ready`.
  `emulator-smoke-test.sh` adds positive fixtures, negatives for loose English-only text, a missing
  preview, fewer than three sliders, an enabled Apply, an item-specific popup and a picker without
  search/list; it also asserts the exact deep link, existing activity, no Apply tap, no pref writes,
  real gesture, measured Widgets tap, picker-not-HOME, bounded attempts and the preserved role
  consent/1500 ms/four-attempt/Settings-foreground checks. `PREFERENCES_ACTIVITY` names the existing
  settings activity explicitly; `THEME_SAMPLE_ACTIVITY` remains an alias.
- **Docs:** `docs/agent/emulator-verification.md` records the two phases, native markers and
  artifact names.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass;
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass;
  `verify-play-build.sh` runs the shell suites and repo guards OK, then stops at the expected
  missing `build/intermediates` because no APK was built here; `sh -n` clean on all edited scripts;
  `git diff --check` clean. CI must still build, unit-test and run the API 37 smoke; the actual
  preview/picker accessibility markers remain device-verification unknowns until that run.

## done (previous run — P9 Play settings announcement cleanup)

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

- This run: `sh scripts/nothingui-home-guard.sh "$PWD"` -> OK.
- This run: `sh scripts/nothingui-home-guard-test.sh` -> 16/16 pass, including the new hardcoded
  preview container, missing selected smartspace mode and post-construction dummy override negatives.
- This run: `sh scripts/verify-play-build-test.sh` -> 11/11 pass.
- This run: `sh scripts/emulator-smoke-test.sh` -> all pass (unchanged widget placement coverage).
- This run: `sh scripts/emulator-smoke-drawer-test.sh` -> all pass (unchanged 1500 ms/4-attempt drawer).
- This run: identity, manifest, brand, theme, home-role, icon-render and drawer-trace fixture suites
  -> all pass.
- This run: `sh -n` clean on both edited scripts; `git diff --check` clean.
- Not run here: `spotlessCheck`, any Gradle build/test, the API 37 emulator smoke, or PR CI. This is
  source/fixture verification only; it is not a runtime or pixel claim.

## next

- Main/supervisor owns PR16 approval for `agent/p11-preview-header` at head `df2bfbc` (app fix
  `31d0963`). APK110 remains the fallback and does not depend on this branch.
- CI must be green on this head: `spotlessCheck`, `assembleLawnWithQuickstepPlayDebug`, the Play
  unit tests, `verify-play-build.sh`, both smoke suites and the API 37 emulator smoke.
- Inspect the CI `grid-settings.png` from the API 37 run: the preview's first page should now show
  the neutral NothingUI header card with a live Doto clock/date, red accent and dot strip, matching
  the real Play HOME `home.png`. If it still shows the inherited welcome card, capture
  `grid-settings.xml`/`.png` and verify the preview process resolved `getSmartspaceMode()` to
  `LawnchairSmartspace` with `NothingUiFeature.homeEnabled=true`; do not hardcode the header or add
  fake clock text.
- The existing widget-placement, bind-consent, safe-Add, role-consent and drawer artifacts must
  still pass unchanged.
- P8 remains open beyond these slices: appearance controls, backup/restore wiring and any broader
  onboarding. Pending gates: private-space runtime UI and a non-Play runtime control build.

## blockers

- The two PR16 CI runs (`df2bfbc` run `44987132494` and `941ffca` run `44987210606`) completed with
  `action_required`, not success/failure: GitHub is waiting for a maintainer to approve the
  workflow. The branch push used the runner's GitHub Actions token, so `gh` is unauthenticated and
  a `workflow_dispatch` returns 403. The Android compile, unit tests, `spotlessCheck` and the
  API 37 `grid-settings.png` pixels are therefore still unverified.
- Main/supervisor must approve PR16 and approve/re-run CI for `agent/p11-preview-header`.
- The preview mirrors the live workspace's smartspace availability fallback in memory only; it
  deliberately does not write the `smartspace_mode` preference from a preview renderer. If the real
  HOME would persist a fallback, the preview may briefly show the fallback layout until HOME reloads.
- The preview header is the same `nothingui_home_header`/`NothingUiHomeHeaderView` as HOME, so any
  future header layout change automatically affects the preview; the guard requires the preview to
  keep following `SmartspaceMode.getLayoutResourceId()` rather than a copied layout.
- The pre-existing local branch `agent/p11-preview-header-fix-only-gr` was at the same base and had
  no commits; the work is on the correctly named `agent/p11-preview-header`.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings (this run and prior P3a)

- P10b harness correction: the exposed Add is tapped only through its intersection with the
  remeasured viewport, pulled 32 px above the viewport bottom and at least 24x24 px. The original Add
  centre is never used. Cost if wrong: an Add that is mostly under the navigation bar causes a
  bounded measured scroll and then a fail with pixels instead of opening Android HOME.
- P10b harness correction: an API37 `ProviderId{cmp:ComponentInfo{...}}` provider is accepted only
  inside an active widget-id block whose host is this launcher; a section header or a second provider
  line ends the block. Cost if wrong: an unusual dump shape fails closed rather than accepting a
  provider catalog or another launcher's widget as placement.
- P10b review correction: both HOME hierarchies are normalised to node records with explicit R/C
  markers before comparison, and the helper rejects known picker/sheet preview ancestors. When a
  workspace node exists, the host must be inside it. Cost if wrong: a real widget host that the
  hierarchy does not nest under a workspace fails closed, and the captured CI110 XML must drive the
  next change; a picker preview can never be counted as placement.
- P10b review correction: placement proof requires a new `AppWidgetId` with a provider, not just a
  provider name in the installed-provider list. Cost if wrong: an unusual `dumpsys appwidget` shape
  fails closed rather than accepting an already-installed provider as a newly bound widget.
- P10b review correction: after expansion the provider header is re-resolved by its `app_title`
  before measuring the preview. Cost if wrong: a provider whose title disappears after expansion
  fails closed instead of associating a later provider's preview with the selected one.
- P10a harness correction: the grid preview is accepted from a `/workspace` ViewGroup whose bounds
  are above every slider, inside the root and smaller than it, with a `hotseat`/`search_container_workspace`
  child. Cost if wrong: a future preview without that resource-id fails closed; the captured XML
  must drive any update, and a class-name guess is never accepted.
- P10a harness correction: Apply is proven read-only by a non-clickable label inside a non-clickable
  `android.widget.Button`, not by the accessibility `enabled` flag. Cost if wrong: a future Apply that
  stays visually grey but becomes clickable fails the smoke, which is the intended safety direction.
- P10a harness correction: when every measured long-press candidate is occupied,
  `home_longpress_target` fails instead of returning the band centre. Cost if wrong: a crowded HOME
  aborts the widget phase rather than opening an item-specific menu, which is the safe outcome.
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

- 2026-11-22: P5 PR19 CI155 HOME long-press harness recovery on
  `agent/home-widget-composition-v1-new` (`3c00ebc`), from `62e1afd`. CI155 reached all three live
  own widgets and the measured device Settings shortcuts, then `home_longpress_target` returned
  `540,896` inside the non-clickable Device host and opened its resize frame. `ui_point_is_free` now
  counts `*AppWidgetHostView` classes and `/appwidget` ids as occupied regardless of clickable/label
  flags, keeps labelled clickable icon/folder protection, expands host bounds by the measured margin
  and adds bounded 90/95/100 percent candidates to reach the empty band below the Device card.
  Fixtures reject `540,896`, select `540,1300`, cover pending/unlabelled hosts and all-occupied
  fail-closed, and keep the legacy `540,834` empty target. Local smoke 450/450, drawer 38/38,
  widget guard 31/31, home guard 19/19, verify-play-build 11/11, `sh -n` and `git diff --check`
  clean. No Gradle/emulator/CI claim; PR19 not merged.
- 2026-11-22: P5 PR19 pending-widget smoke harness recovery on
  `agent/home-widget-composition-v1-new` (`089ca86`, `27c6baa`, `c39199a`), from `740b2cb`. The one
  reported fixture failure was reproduced: `home_pending_widget_bounds` set `saw_ws` only when a
  pending host was already inside a workspace, so the fallback returned a host outside a present
  workspace. `saw_ws` now tracks any workspace node. Added `own_widget_new_binding` (exactly one new
  numeric record, exact `$PKG` host/provider package, exact full DotWel class) and
  `foreground_is_component` (exact `.AllowBindAppWidgetActivity`). The own-widget round now requires
  real launcher HOME after Create and a one-pending decrease, failing closed otherwise. Added
  positive/negative fixtures and static flow gates. Java policy constants joined to one line for
  GJF AOSP. Local shell suites/guards pass; no Gradle/emulator/CI claim. PR19 not merged.
- 2026-11-22: P11 grid-preview header parity on `agent/p11-preview-header` (`31d0963`, `df2bfbc`),
  from `main` `e7c9240d` (P10b PR15 merged). `LauncherPreviewRenderer` no longer hardcodes
  `R.layout.smartspace_container`; it resolves the selected `SmartspaceMode.layoutResourceId` in the
  constructor before `addCallbacksAndLoad`, with an in-memory `LawnchairSmartspace` fallback when the
  mode is unavailable. On Play that is `nothingui_home_header`, so the grid/launcher preview matches
  the live HOME header; github/nightly keep the inherited container. Disabled smartspace, the dummy
  backup placeholder and the Google/Smartspacer modes are preserved. The dummy placeholder is passed
  through a new constructor argument so a synchronous bind cannot race the post-construction setter.
  The static home guard and its fixture suite now lock the preview source, reject the hardcoded
  container and the post-construction override, and require the disabled-smartspace gate. Local
  guard/verify/smoke/drawer/identity/brand/theme/role/icon/trace suites pass; `sh -n` and
  `git diff --check` clean. No grid values, Apply behavior, workflow, Gradle, SDK, manifest,
  permission, applicationId, signing or asset change. CI and `grid-settings.png` pixels still pending.
- 2026-11-21: P10a grid/widget harness correction on `agent/p10-grid-widget-smoke` (`f51fcb3`),
  from `main` `55a25a2`. CI106 (`10644959244281`) was assembly/style/unit green and the real grid
  editor opened, but the new readiness assumed a `LauncherPreviewView` class and an `enabled=false`
  Button that the actual hierarchy does not contain. The actual `grid-settings-attempt-6` dump has a
  preview `AndroidViewHolder` with a `/workspace` ViewGroup plus `hotseat`/`search_container_workspace`,
  and Apply is a non-clickable `TextView` inside a non-clickable empty `Button` with `enabled=true`
  and grey pixels. The smoke now validates the preview from its bounds (above the sliders, inside and
  smaller than the root, with the hotseat container), matches Apply by its non-clickable containing
  Button, rejects a clickable Apply, captures the last failed readiness PNG, and makes
  `home_longpress_target` fail instead of returning an occupied centre. Fixtures use the actual
  hierarchy and add the matching negatives. No app source, SDK, workflow, Gradle, manifest,
  permission, applicationId, signing, paid-service or asset change. Local smoke/drawer/verify test
  suites pass; `sh -n` and `git diff --check` clean. CI and device evidence are still required.
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
