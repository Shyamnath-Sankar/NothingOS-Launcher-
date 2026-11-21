# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P2b (Play label + verification) — merged in PR7; verification slice in progress
- branch: agent/verification-slice-after-pr7-n
- pr: pending (agent-dev workflow opens it after this run)
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/verification-slice-after-pr7-n

## done
- PR7 merged to `main`: Play-only `play_app_name` = **DotWel Launcher** (single l); Play
  `<application>` and launcher `<activity>` labels reference it. `github`/`nightly` keep the
  inherited "Lawnchair" branding. Icons/`mipmap-*` remain deferred to a visual-review slice.
- PR7 merged: `scripts/verify-play-build.sh` runs the identity/manifest fixture suites, selects the
  final AGP `merged_manifests` output (falling back to the older `merged_manifest` stage), fails
  closed on zero/ambiguous candidates, runs `manifest-guard.sh`, checks the resolved Play debug
  package and provider authorities, and accepts only the exact debug LeakCanary application-scoped
  authority.
- CI24 on `main` passed the real merged-manifest guard after the AGP-stage selection fix
  (`e8f9503`) and exact debug LeakCanary handling (`ee3662f`). This clears the P1 merged-manifest
  verification blocker; it is not runtime/device evidence.
- P2b tests actually run before the merge (no Gradle): `sh scripts/play-identity-guard-test.sh` →
  8/8; `sh scripts/manifest-guard-test.sh` → 31/31; `sh scripts/verify-play-build-test.sh` → 7/7;
  `sh -n` clean on all four scripts; `sh scripts/play-identity-guard.sh .` → OK.
- Prior P2a: Play-only applicationId `com.launchernos.dotwellabs`; static identity/authority guard.
- Prior P1a/P1b/P1c: Play manifest overlay, accessibility/bug-report/feed removal,
  `ACCESS_HIDDEN_PROFILES`, locked-profile search filter, guard updates.

## next
- This run: emulator smoke script for install/label/launch/default-home evidence; Gradle JUnit
  coverage for a pure locked-profile predicate; AGP-stage coexistence tests.
- P2 remaining: original icon / `mipmap-*` slice with visual review (no Nothing assets).
- P9: keep the merged-manifest guard and fixture suites wired in CI (already present in `ci.yml`);
  coordinator wires the emulator lane separately.
- P1/P2 runtime gates still pending (do not mark passed): install + default-home on emulator;
  private-space locked-profile validation.

## blockers
- No Gradle run in this coding session, so the new JUnit test is not executed here; PR CI runs
  `testLawnWithQuickstepPlayDebugUnitTest`. The emulator smoke script is also not run here (no
  device/emulator); the coordinator wires the API 37 lane.
- P1 runtime private-space validation: pending device/emulator check (drawer, search, recents).
  A private space needs a secure lock screen and explicit provisioning; do not auto-create it.
- P2 default-home gate: pending emulator install and `RoleManager.ROLE_HOME` request.
- `LockedProfileSearchFilterTest` remains Soong-only (Robolectric/AndroidJUnit4). The new Gradle
  test deliberately covers only the extracted pure flag predicate with plain JUnit.

## decisions locked
- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings this run
- P2b: implemented the label as a Play-only `play_app_name` resource referenced by the Play manifest
  instead of a play-flavor `derived_app_name` override, because build-type `resValue` outranks flavor
  resources and would have leaked the label or been ignored. Cost if wrong: the in-app
  `derived_app_name` strings (About/dialogs) still say "Lawnchair" for Play until a follow-up uses
  variant-level resValues.
- P2b: added `tools:replace="android:label"` on the Play `<application>` so the different label is
  explicit and merge-safe. Cost if wrong: harmless duplicate of the inherited marker.
- P2b: `verify-play-build.sh` fails closed on more than one merged-manifest candidate rather than
  picking one. Cost if wrong: a future AGP emitting two identical paths needs the search narrowed.
- P2b: did not add Robolectric or a Gradle test source set just to mirror one test. Cost if wrong:
  `filterLockedProfiles` remains covered by the Soong multivalent suite, not Gradle CI.
- Prior P1/P2a rulings retained (see git history).

## log
- 2026-11-21: P2b complete (Play-only DotWel Launcher label + NOTICE/docs + merged-manifest
  verification script; icons deferred; no Gradle run)
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + static identity/
  authority guard + docs; no Gradle run)
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal)
