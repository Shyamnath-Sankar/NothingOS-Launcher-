# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P3a (theme foundation only). The theme tokens, Doto font bundle, Play-only flag,
  sample screen and token tests are implemented. The home surface, grid, drawer, widgets, wallpaper
  and settings are not restyled in this run.
- branch: agent/p3a-theme-foundation-only-star (cut from `main` at the PR9 merge `02ac058`).
- pr: not created in this environment (no authenticated `gh`). Branch is pushed; open it at
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/compare/main...agent/p3a-theme-foundation-only-star?expand=1
  or let the workflow open it. PR9 is merged at `02ac058`.

## done

- P2c rebrand verified by the coordinator: CI51 run `44903885094` on head `e6ea08b` was green with
  4 actual Gradle tests plus the API 37 install, HOME, role and crash checks. The coordinator
  inspected the artifacts and confirmed HOME reads `Welcome to DotWel Launcher` and About/app-info
  show the correct dot-grid icons and `DotWel Launcher` name. This is recorded as coordinator
  evidence, not re-run in this environment.
- P3a: added `lawnchair/src/app/nothingui/theme` with an original monochrome palette
  (`#0B0B0B` ink, `#F2F2F2` paper, neutral grays, the existing restrained `#D7261E` red accent),
  semantic light/dark color tokens, a 4 dp spacing scale, motion durations/easings, and a Compose
  `Typography` where Doto is limited to display and numeric styles while body/title/label styles
  use `FontFamily.SansSerif`.
- P3a: bundled Doto Regular 400 and Bold 700 as static TrueType resources
  (`lawnchair/res/font/doto_regular.ttf`, `doto_bold.ttf`). They were generated from the official
  Google Fonts variable font `ofl/doto/Doto[ROND,wght].ttf` at repo commit
  `7380f7cebbf2250460c23fd301b51bcbab162edf`; glyphs are unchanged and only the axes are pinned.
  The verbatim OFL 1.1 text is in `licenses/fonts/OFL-Doto.txt`; source, upstream commit, version,
  derivation and SHA-256 hashes are in `licenses/fonts/doto.md`. No Nothing font or asset is used.
- P3a: the theme is gated by `BuildConfig.NOTHINGUI_THEME_ENABLED`: false in `defaultConfig`, true
  only in the `play` flavor. `NothingUiFeature.themeEnabled` exposes it and
  `NothingUiThemeIfEnabled(fallback = ...)` requires an explicit non-Play fallback. The
  github/nightly themes and resources were not changed; the shared font resources add size but are
  not used by those channels.
- P3a: added `NothingUiThemeSampleScreen` (stateless) plus dark/light `@Preview`s using the tokens,
  and `tests/unit/java/app/nothingui/theme/NothingUiTokenTest.kt` for contrast targets, ordered
  spacing/motion, the accent constant, Doto-only display/numeric styles, and display-vs-body sizes.
- P3a: added `scripts/nothingui-theme-guard.sh` and wired it into `scripts/verify-play-build.sh`.
  It checks the font magic bytes (not HTML), OFL text, attribution hashes, the default/Play/github/
  nightly flag wiring, the `NothingUiFeature` gate, sans body wiring, and the sample/preview.
- Verification actually run this run (no Gradle, no emulator): `nothingui-theme-guard.sh .` OK;
  `play-brand-guard.sh .` OK; `play-identity-guard.sh .` OK; `manifest-guard-test.sh` all pass;
  `play-identity-guard-test.sh` all pass; `play-brand-guard-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on edited scripts; `git diff --check` clean;
  standalone ktlint 1.8.0 clean on the new Kotlin files, and the compose ruleset clean except
  `compositionlocal-allowlist`, which `build.gradle` explicitly disables. `file` and fontTools
  confirmed real TrueType fonts at weights 400/700, 320 glyphs, no `fvar` table, and no HTML.

## next

- P3b (home/grid), the next slice:
  - derive a 4×6 `DeviceProfile` override from `WindowMetrics` (Android 17 large-screen rule), with
    no `resources.displayMetrics` math;
  - wire `NothingUiThemeIfEnabled` into the Play home surface only, passing the inherited
    `LawnchairTheme` as the fallback so github/nightly behavior is unchanged;
  - add the monochrome icon treatment hook and dot-matrix page indicator;
  - add Compose UI tests and `@Preview`s for the grid, and keep the existing workspace scroll free
    of jank.
- P4 (drawer) follows P3b: restyle the inherited all-apps surface, keep A–Z and search, and verify
  profile filtering.
- Pending gates before P3a can be called shipped:
  - CI on this branch must run `spotlessCheck`, `assembleLawnWithQuickstepPlayDebug`, the Play
    unit tests (including `NothingUiTokenTest`), `verify-play-build.sh` (including the new theme
    guard), and the API 37 emulator smoke. None of those Gradle/emulator runs happened here.
  - A visual review of the sample/preview and a non-Play control build are still pending.
  - P1 private-space runtime UI (drawer/search/recents) is still unverified.
  - P2 in-app `RoleManager.ROLE_HOME` onboarding prompt is still unverified; the emulator `cmd
    role` grant is only a stand-in.
  - The non-Play runtime control build has not been installed/launched; only its static wiring is
    guarded.

## blockers

- P3a CI evidence: no Gradle build or emulator run was allowed in this environment, so the branch
  is statically verified only. Do not call the theme green until the branch CI run exists.
- PR creation: `gh` is unauthenticated here, so the branch was pushed without opening a PR. A
  maintainer or the workflow must create it and approve the pending runs.
- P1 runtime private-space validation: pending device/emulator UI evidence (drawer, search,
  recents). A private space needs a secure lock screen and explicit provisioning; do not
  auto-create it.
- P2 default-home gate: in-app `RoleManager` prompt pending manual verification. CI35's `cmd role`
  grant verifies the system role, not the prompt.
- P2c visual gate: the coordinator verified HOME and About/app-info artifacts for CI51; the
  non-Play runtime control build remains unverified.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings this run

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

- 2026-11-21: P3a foundation implemented and pushed on
  `agent/p3a-theme-foundation-only-star`: palette/spacing/motion/typography, Doto OFL assets,
  Play-only `BuildConfig` gate, sample screen and previews, pure token tests, and a static theme
  guard wired into `verify-play-build.sh`. Static checks green; branch CI and visual/device review
  pending. Home/grid work is P3b.
- 2026-11-21: P2c verified by the coordinator: CI51 (`44903885094`) on `e6ea08b` green with 4
  Gradle tests and API 37 install/HOME/role/crash checks; HOME says `Welcome to DotWel Launcher`
  and About/app-info show the dot-grid icon and name. Private-space UI, the in-app RoleManager
  prompt and the non-Play runtime control remain unverified.
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
