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
- This run: extracted `isLockedProfile(runtimeStatusFlags)` into
  `lawnchair/src/app/lawnchair/search/algorithms/LockedProfilePredicate.kt`; `SearchUtils` and
  `AppSearchProvider` keep the same `FLAG_DISABLED_QUIET_USER` behaviour through
  `filterLockedProfiles()`. Added `src/test/java/.../LockedProfilePredicateTest.kt` (plain JUnit 4,
  no Robolectric) and `testImplementation libs.junit`. A `verifyLockedProfileTestWiring` task runs
  before `testLawnWithQuickstepPlayDebugUnitTest` and fails if the test file is missing or outside
  the `test` source set, so CI cannot silently pass NO-SOURCE.
- This run: added `scripts/emulator-smoke.sh`. It locates exactly one Play debug APK, requires API
  37, clean-installs only `com.launchernos.dotwellabs.debug`, verifies the installed package and
  installed app/launcher-activity label `DotWel Launcher`, resolves/launches HOME, grants and verifies
  `android.app.role.HOME` via `cmd role`, presses HOME, and captures screenshot/logcat/dumpsys/aapt
  evidence. It fails on install, launch, ANR or crash-stack problems.
- This run: added `scripts/private-space-check.sh` plus `docs/agent/emulator-verification.md`. The
  check detects an `android.os.usertype.profile.PRIVATE` user and its locked/quiet state, exits 77
  when the prerequisite is absent, and explicitly does not claim drawer/search/recents validation.
  It never creates profiles or accounts.
- This run: `scripts/verify-play-build-test.sh` now covers both AGP stages coexisting: the final
  `merged_manifests` output wins over the older `merged_manifest` stage, and a forbidden permission
  in the final stage still fails (no fallback to the clean old stage).
- This run, tests actually run (no Gradle): `sh scripts/verify-play-build-test.sh` → 11/11;
  `sh scripts/manifest-guard-test.sh` → all 31 pass; `sh scripts/play-identity-guard-test.sh` → 8/8;
  `sh -n` clean on all scripts; `sh scripts/play-identity-guard.sh .` → OK. The JUnit test was run
  with `kotlinc` + JUnit 4.13.2 against a stub `ItemInfoWithIcon` constant → 4/4 pass. The emulator
  scripts were exercised end-to-end with a local fake adb/aapt2 harness (success, wrong label,
  crash log, non-debug APK, no/locked/unlocked private profile) but not against a real emulator.
- Prior P2b: Play-only label and merged-manifest verification (see PR7/CI24 above).
- Prior P2a: Play-only applicationId `com.launchernos.dotwellabs`; static identity/authority guard.
- Prior P1a/P1b/P1c: Play manifest overlay, accessibility/bug-report/feed removal,
  `ACCESS_HIDDEN_PROFILES`, locked-profile search filter, guard updates.

## next
- Coordinator: run `scripts/emulator-smoke.sh` on the API 37 emulator lane after
  `assembleLawnWithQuickstepPlayDebug`; upload its artifact directory.
- Private-space runtime gate: provision a private space manually, run
  `scripts/private-space-check.sh` to confirm the locked prerequisite, then record the manual/UI
  drawer/search/recents assertions. Keep the gate pending until that evidence exists.
- P2 remaining: original icon / `mipmap-*` slice with visual review (no Nothing assets).
- P9: keep the merged-manifest guard and fixture suites wired in CI (already present in `ci.yml`);
  the coordinator wires the emulator lane separately.

## blockers
- No Gradle run in this coding session. The new JUnit test was executed with a local `kotlinc` +
  JUnit harness against a stub constant, not by `testLawnWithQuickstepPlayDebugUnitTest`; PR CI runs
  the real Gradle task. The emulator scripts were not run against a real API 37 emulator.
- P1 runtime private-space validation: pending device/emulator check (drawer, search, recents).
  A private space needs a secure lock screen and explicit provisioning; do not auto-create it.
- P2 default-home gate: pending emulator install and `RoleManager.ROLE_HOME` request. The smoke
  script's `cmd role` grant is a disposable-emulator stand-in, not the in-app onboarding flow.
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
- This run: added only `testImplementation libs.junit`; no Robolectric. The extracted predicate has
  no Android runtime dependency, so a plain JVM test is sufficient. Cost if wrong: the full
  `AppInfo`-level filter still relies on the Soong multivalent test.
- This run: added a fail-closed `verifyLockedProfileTestWiring` dependency instead of relying on the
  test task's NO-SOURCE behaviour. Cost if wrong: a future test-source-set rename needs the guard
  path updated, but it fails loudly rather than silently skipping.
- This run: emulator default-home uses `cmd role add-role-holder` because it is supported on the
  disposable API 37 emulator and verifies the real system role. It does not exercise the in-app
  `RoleManager` onboarding prompt; that remains manual.
- This run: private space is a separate prerequisite probe, not auto-provisioned. Creating it needs
  a secure lock screen and may add profile data/accounts; the script only detects and reports.
- Prior P1/P2a/P2b rulings retained (see git history).

## log
- 2026-11-21: verification slice (emulator smoke + private-space probe + pure locked-profile JUnit
  test + AGP-stage coexistence tests; no Gradle/emulator run here)
- 2026-11-21: PR7 merged; CI24 merged-manifest guard passed (AGP stage selection + exact debug
  LeakCanary authority); P2b label complete; icons deferred
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + static identity/
  authority guard + docs; no Gradle run)
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal)
