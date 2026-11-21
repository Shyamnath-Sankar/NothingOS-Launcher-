# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P2c (Play icon + brand cleanup) — CI42 `44901579949` on `293f96e` was fully green,
  but inspected artifacts exposed two runtime brand defects. Root cause repaired this run (Play
  resource precedence); CI re-run and visual review pending. P2 is not complete.
- branch: agent/p2c-original-icon-and-play-bra
- pr: #9 (existing PR for this branch; resume it, do not open a duplicate):
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/9
  PR8 is already merged to `main` at `4bd5c39`.

## done

- This run (P2c visual repair): the dispatch reported an inspection of CI42 artifacts for run
  `44901579949` on `293f96e`; this environment has no artifact download access (no `gh` auth), so
  these are recorded as reported findings, not a re-inspection. Observed defects, not hypotheses:
  `app-info.png` shows the correct original dot-grid icon and `DotWel Launcher` label; the About
  screen shows the correct `DotWel Launcher` title but the OLD colored Lawnchair icon; the HOME
  screenshot still says `Welcome to Lawnchair`.
- This run (root cause, verified from AGP docs and the source tree): `flavorDimensions` is
  `["app", "recents", "channel"]`, so the `lawn` flavor (`lawnchair/res`) outranks the `play` flavor
  (`play/res`) for same-name resources. `R.string.onboarding_welcome` (HOME smartspace card) and
  `R.drawable.ic_launcher_home_comp` (About icon) were therefore resolved from `lawnchair/res`, not
  `play/res`. `ic_launcher_home_monochrome` had the same collision. The app-info icon worked because
  it resolves through the Play manifest `@mipmap/ic_launcher_home`, and the About title worked
  because `derived_app_name` is a variant-level `resValue` that outranks flavors.
- This run (fix): moved `play/res` from the single-flavor `play` source set to the
  `lawnWithQuickstepPlay` multi-flavor source set in `build.gradle`. A multi-flavor source set
  outranks every single flavor, so Play-only overrides now win while `lawnchair/res` and
  `nightly/res` remain untouched for github/nightly.
- This run (regression guards): `scripts/play-brand-guard.sh` now asserts that
  `lawnWithQuickstepPlay` owns `play/res`, that the single `play` flavor does not own it, that the
  `lawn`/`nightly` source sets still own their resource dirs, and that `About.kt` still consumes
  `R.drawable.ic_launcher_home_comp` and `OnboardingProvider.kt` still consumes
  `R.string.onboarding_welcome`. `play-brand-guard-test.sh` is now 14/14, including negative fixtures
  for precedence, stripped lawn resources, and consumer drift.
- This run (smoke): `scripts/emulator-smoke.sh` now dumps the HOME UIAutomator hierarchy after launch.
  When the smartspace welcome card is visible it requires `DotWel Launcher` and rejects `Lawnchair`;
  when no welcome text is visible it writes `home-welcome-pending.txt` instead of claiming a pass,
  and it fails closed if the HOME hierarchy cannot be dumped at all.
  The mandatory screenshot is unchanged, and the About UI XML plus `about.png` are preserved as icon
  evidence with an explicit note that the icon is reviewed visually, not pixel-asserted.
- This run, non-Gradle verification actually run: `play-brand-guard.sh .` OK; brand guard tests 14/14;
  `play-identity-guard-test.sh` all pass; `manifest-guard-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean. No local Gradle build or emulator run was performed; CI must prove the merged resource
  selection and the runtime screens.
- This run (P2c repair): CI37 run `44900708538` failed
  `processLawnWithQuickstepPlayDebugMainManifest` because the Play overlay set
  `android:icon="@mipmap/ic_launcher_home"` while the base manifest still set
  `android:icon="@drawable/ic_launcher_home"` and the overlay only listed
  `tools:replace="android:label"`. Added `android:icon` to that existing
  `tools:replace` list. Label, permissions and every component removal are unchanged.
- This run (P2c repair): added a narrow `play-brand-guard.sh` regression that fails when the Play
  application `tools:replace` does not include `android:icon`. Added a fixture test for exactly that
  missing directive. Guard fixture suite is now 10/10.
- This run (P2c repair): extended `scripts/emulator-smoke.sh` after the existing HOME screenshot to
  capture `app-info.png` + `app-info.xml` through
  `android.settings.APPLICATION_DETAILS_SETTINGS` for
  `package:com.launchernos.dotwellabs.debug`, return HOME and verify it, then open About through the
  existing `lawnchair://settings/about` deep link and confirm `About` plus `DotWel Launcher` in the
  UIAutomator hierarchy before capturing `about.png` + `about.xml`. No tap coordinates are guessed.
  About is written to `about-pending.txt` and reported as pending when it cannot be verified. The
  original `screenshot.png` and all existing checks are preserved.
- This run, non-Gradle verification actually run: `play-brand-guard.sh .` OK;
  `play-brand-guard-test.sh` 10/10; `sh -n scripts/emulator-smoke.sh` clean; `git diff --check`
  clean. No local Gradle build or emulator run was performed; CI must prove the manifest merge.
- Prior P2c run: added an original Play-only geometric dot-grid launcher icon under `play/res`.
  Near-black `#0B0B0B` adaptive background, 3×3 white `#FFFFFF` dots, one restrained red `#D7261E`
  accent, a white-only monochrome layer, matching round adaptive icon, and rounded-square in-app
  variants for `ic_launcher_home` / `ic_launcher_home_comp`. The Play manifest now points at
  `@mipmap/ic_launcher_home` and `@mipmap/ic_launcher_home_round`. No Nothing marks or assets.
- Prior P2c run: Play-only `onboarding_welcome` now reads `Welcome to DotWel Launcher!` in the
  default resource and in all 57 inherited locale configurations (the localized greeting is kept
  and only the brand token is replaced). Play `derived_app_name` is set to `DotWel Launcher` via a
  Play-gated variant-level `resValue`, so About/dialog text no longer says Lawnchair. github/nightly
  keep their inherited strings and labels.
- Prior P2c run: added `scripts/play-brand-guard.sh` and `scripts/play-brand-guard-test.sh`
  (9/9 pass). The guard checks icon files/layers/colours, XML well-formedness, Play manifest icon
  wiring, every locale override, the variant app-name override, absence of Nothing marks, and
  preserved `NOTICE.md` attribution. Wired into `scripts/verify-play-build.sh`, which CI already
  runs; no workflow file was edited.
- Prior P2c run, non-Gradle verification actually run: `play-brand-guard.sh .` OK; brand guard tests 9/9;
  `play-identity-guard.sh .` OK; identity tests 8/8; `manifest-guard-test.sh` all pass;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on every script; `git diff --check` clean; all 65
  `play/res` XML files parse.
- CI35 (`44898572590`) verified facts: real Gradle tests (4/4), merged-manifest guard, API 37
  install, HOME label, HOME role and crash checks passed. Its screenshot was visually inspected and
  still shows the inherited Lawnchair home surface. That is expected for P2c: this slice changes the
  icon and brand text only, not the home layout.
- PR8 merged to `main` at `4bd5c39`; PR7 merged the Play-only `play_app_name` label and the
  identity/manifest guard suite. Prior P2a set the Play `applicationId` to
  `com.launchernos.dotwellabs`; prior P1 work added the Play manifest overlay, private-space
  permission, locked-profile search filter and component removals.

## next

- A maintainer must approve the pending PR workflow runs. After approval, confirm the Play debug
  manifest merge, the merged resource selection, and the API 37 emulator smoke pass; do not claim
  them green before the run log exists.
- Inspect the new smoke artifacts: `screenshot.png` (HOME evidence), `home.xml` plus
  `home-welcome.txt` or `home-welcome-pending.txt`, `app-info.png` + `app-info.xml`, and `about.png`
  + `about.xml` or `about-pending.txt`.
- Confirm in the new HOME hierarchy that the welcome card reads `Welcome to DotWel Launcher!`, and in
  `about.png` that the About icon is the dot grid, not the inherited colored Lawnchair icon.
- Coordinator screenshot review using `docs/agent/p2c-icon-brand-visuals.md`: launcher/app-info
  icon, About icon/title, onboarding welcome title, app label, round icon, and a github/nightly
  control build. Static guards and the app-info screenshot alone cannot prove the About icon.
- Private-space runtime UI gate: provision a private space manually, run
  `scripts/private-space-check.sh`, then record the manual drawer/search/recents assertions. Keep
  the gate pending until that evidence exists.
- In-app `RoleManager.ROLE_HOME` onboarding prompt: still pending manual verification; the
  emulator `cmd role` grant is a disposable stand-in, not the prompt.
- P3 (theme/home surface) has not started. Do not begin it in this slice.

## blockers

- P1 runtime private-space validation: pending device/emulator UI evidence (drawer, search,
  recents). A private space needs a secure lock screen and explicit provisioning; do not
  auto-create it.
- P2 default-home gate: in-app `RoleManager` prompt pending manual verification. CI35's `cmd role`
  grant verifies the system role, not the prompt.
- P2c manifest gate: CI42 `44901579949` on `293f96e` was fully green, so the manifest merge is no
  longer the blocker. The remaining P2c blocker is the runtime brand repair in this run, which has
  not yet been proven by a new CI run.
- P2c visual gate: screenshot review pending; static guards do not prove what a device renders.
  CI42 proved the app-info icon/label and the About title, but the About icon and HOME welcome were
  still wrong at that point.
- About-screen smoke evidence: may be documented as pending if the deep link or UIAutomator
  hierarchy is unavailable; it is not treated as a brand pass without the captured UI.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings this run

- P2c: all icon artwork lives in `play/res` so github/nightly keep the inherited Lawnchair icon.
  Cost if wrong: the Play overlay has its own icon maintenance burden and must keep all three
  adaptive layers in sync.
- P2c: the manifest uses `@mipmap` adaptive resources for the app icon and `@drawable` vectors for
  in-app surfaces. This gives API 26+ adaptive/round resolution and a usable Compose/search image
  without duplicating bitmaps. Cost if wrong: a future launcher surface that requires a bitmap
  density variant needs legacy PNGs added.
- P2c: locale overrides were generated by replacing the `Lawnchair` token in each upstream
  `onboarding_welcome`, preserving the localized greeting. Cost if wrong: languages that inflect
  the brand may read slightly unnaturally, but no locale falls back to the inherited name.
- P2c: `derived_app_name` is overridden with a Play-gated variant-level `resValue`, because the
  build-type `resValue` outranks flavor resources. Cost if wrong: a future AGP variant-API change
  needs this block updated; the brand guard fails loudly if it disappears.
- P2c: the brand guard is called from `verify-play-build.sh` rather than a workflow edit, because
  `.github/workflows/` is off-limits this run. Cost if wrong: a future CI refactor that stops
  calling `verify-play-build.sh` also drops the brand guard.
- P2c repair: `tools:replace` lists both `android:label` and `android:icon` instead of removing
  either attribute. The Play overlay still owns the label and icon; the base manifest values are
  only discarded at merge time. Cost if wrong: a future base icon rename is invisible to the Play
  overlay, but the brand guard still pins the Play resources.
- P2c visual repair: `play/res` is owned by the `lawnWithQuickstepPlay` multi-flavor source set,
  not the single `play` flavor. AGP gives the `app` (lawn) dimension higher priority than the
  `channel` (play) dimension, so a single-flavor Play resource loses same-name lawn resources. A
  multi-flavor source set outranks every single flavor. Cost if wrong: the source-set wiring is
  unusual and the brand guard must keep asserting it; if AGP ever changes multi-flavor priority,
  the smoke HOME/About evidence will fail loudly.

## log

- 2026-11-21: CI42 (`44901579949`) on `293f96e` was fully green, but inspected artifacts showed the
  About icon still colored Lawnchair and the HOME welcome still `Welcome to Lawnchair`. Root cause:
  single-flavor `play/res` loses same-name resources to the higher-priority `lawn` flavor. Moved
  `play/res` to the `lawnWithQuickstepPlay` multi-flavor source set; extended the brand guard
  (14/14) and the emulator smoke (HOME welcome XML assertion, About icon evidence preserved). New
  CI run pending.
- 2026-11-21: CI37 (`44900708538`) failed `processLawnWithQuickstepPlayDebugMainManifest`: base
  `@drawable/ic_launcher_home` vs Play `@mipmap/ic_launcher_home` with only `android:label` in
  `tools:replace`. Repaired the directive, added a guard regression (10/10) and extended the
  emulator smoke with app-info and About evidence. Real CI re-run still pending.
- 2026-11-21: P2c complete (static): original Play-only dot-grid icon, Play-only welcome/app-name
  text, 57 locale overrides, variant-level `derived_app_name`, brand guard + tests, visual-review
  doc. Non-Gradle suites green; screenshot review, private-space UI and RoleManager prompt pending.
- 2026-11-21: CI35 (`44898572590`) green on the post-PR8 state: 4/4 Gradle tests, manifest, API 37
  install/HOME label/role/crash checks; screenshot still inherited Lawnchair home.
- 2026-11-21: PR8 merged at `4bd5c39`; PR7 merged the Play label and guard suites.
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + identity/authority
  guard + docs).
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal).
