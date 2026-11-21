# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P2c (Play icon + brand cleanup) — static checks green; visual review pending
- branch: agent/p2c-original-icon-and-play-bra
- pr: #8 merged to `main` at `4bd5c39`; the P2c branch is pushed but has no PR yet (gh was not
  authenticated in this run). Compare/open:
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/compare/main...agent/p2c-original-icon-and-play-bra

## done

- This run (P2c): added an original Play-only geometric dot-grid launcher icon under `play/res`.
  Near-black `#0B0B0B` adaptive background, 3×3 white `#FFFFFF` dots, one restrained red `#D7261E`
  accent, a white-only monochrome layer, matching round adaptive icon, and rounded-square in-app
  variants for `ic_launcher_home` / `ic_launcher_home_comp`. The Play manifest now points at
  `@mipmap/ic_launcher_home` and `@mipmap/ic_launcher_home_round`. No Nothing marks or assets.
- This run (P2c): Play-only `onboarding_welcome` now reads `Welcome to DotWel Launcher!` in the
  default resource and in all 57 inherited locale configurations (the localized greeting is kept
  and only the brand token is replaced). Play `derived_app_name` is set to `DotWel Launcher` via a
  Play-gated variant-level `resValue`, so About/dialog text no longer says Lawnchair. github/nightly
  keep their inherited strings and labels.
- This run (P2c): added `scripts/play-brand-guard.sh` and `scripts/play-brand-guard-test.sh`
  (9/9 pass). The guard checks icon files/layers/colours, XML well-formedness, Play manifest icon
  wiring, every locale override, the variant app-name override, absence of Nothing marks, and
  preserved `NOTICE.md` attribution. Wired into `scripts/verify-play-build.sh`, which CI already
  runs; no workflow file was edited.
- This run, non-Gradle verification actually run: `play-brand-guard.sh .` OK; brand guard tests 9/9;
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

- Open the P2c PR from `agent/p2c-original-icon-and-play-bra` (do not duplicate merged PR8).
- Coordinator screenshot review using `docs/agent/p2c-icon-brand-visuals.md`: launcher/app-info
  icon, About icon/title, onboarding welcome title, app label, round icon, and a github/nightly
  control build. The CI35 home screenshot alone cannot prove the icon/brand pass.
- Re-run the CI35-style API 37 emulator lane on the P2c branch after the PR is open.
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
- P2c visual gate: screenshot review pending; static guards do not prove what a device renders.

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

## log

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
