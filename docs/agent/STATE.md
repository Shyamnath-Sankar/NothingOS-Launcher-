# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P2b (Play label + verification prep) — complete; P2 icon slice deferred
- branch: agent/p2b-focused-label-and-verifica
- pr: pending (agent-dev workflow opens it after this run)
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/p2b-focused-label-and-verifica

## done
- P2b label: Play-only `play_app_name` = **DotWel Launcher** (single l) in
  `play/res/values/strings.xml`; the Play `<application>` and launcher `<activity>` labels reference
  it. `github`/`nightly` keep the inherited `derived_app_name` ("Lawnchair"). Icons/`mipmap-*` were
  deliberately not touched; they are a separate visually-reviewed slice.
- P2b NOTICE: added a restrained original-contribution entry and stated the display label is not a
  name-clearance claim. The public Play listing name remains OPEN.
- P2b docs: `AGENTS.md` §2 has a DECIDED Play display-label row (listing name still OPEN); spec §7
  and plan P2 record the label and the icon deferral.
- P2b verification: added `scripts/verify-play-build.sh` (+ `scripts/verify-play-build-test.sh`).
  It runs the existing identity/manifest fixture suites, locates the Gradle-merged
  `lawnWithQuickstepPlayDebug` manifest under `build/intermediates/merged_manifest(s)`, fails closed
  on zero or more than one candidate, runs `manifest-guard.sh` on it, then checks the merged
  `package` equals the Play applicationId plus the existing debug `applicationIdSuffix` (`.debug`)
  and that every provider authority equals or is prefixed by that resolved id. Workflows were not
  touched; the coordinator wires it into CI.
- P2b tests actually run (no Gradle): `sh scripts/play-identity-guard-test.sh` → 8/8;
  `sh scripts/manifest-guard-test.sh` → 31/31; `sh scripts/verify-play-build-test.sh` → 7/7;
  `sh -n` clean on all four scripts; `sh scripts/play-identity-guard.sh .` → OK.
- P2b `LockedProfileSearchFilterTest`: not mirrored into Gradle. Exact blocker recorded below.
- Prior P2a: Play-only applicationId `com.launchernos.dotwellabs`; static identity/authority guard.
- Prior P1a/P1b/P1c: Play manifest overlay, accessibility/bug-report/feed removal,
  `ACCESS_HIDDEN_PROFILES`, locked-profile search filter, guard updates.

## next
- P2 remaining: original icon / `mipmap-*` slice with visual review (no Nothing assets).
- P9: wire `scripts/verify-play-build.sh` (and its fixture suites) into CI after
  `assembleLawnWithQuickstepPlayDebug`; keep workflows as the only execution hook.
- P1/P2 runtime gates still pending (do not mark passed): merged-manifest guard on the real CI
  build; install + default-home on emulator; private-space locked-profile validation.

## blockers
- No Gradle run in this coding session, so no APK or merged manifest exists locally. Running
  `scripts/verify-play-build.sh` in this checkout correctly fails closed until CI assembles the APK.
- P1 merged-manifest guard verification: pending the real CI-merged manifest run.
- P1 runtime private-space validation: pending device/emulator check (drawer, search, recents).
- P2 default-home gate: pending emulator install and `RoleManager.ROLE_HOME` request.
- `LockedProfileSearchFilterTest` Gradle mirror blocked: the repo has no Gradle unit-test source set
  (root `build.gradle` has no `testOptions` / `testImplementation` / `src/test`), and the test lives
  in the Soong-only `tests/multivalentTests/src/app/lawnchair/search/algorithms/` tree. It needs
  `@RunWith(AndroidJUnit4::class)`, `androidx.test.ext:junit`, Truth and Android framework classes
  (`ComponentName`, `UserHandle`). `libs.versions.toml` has junit/truth/androidx-junit but **no
  Robolectric**, which `AndroidJUnit4` requires on the JVM and which `UserHandle.of()` needs to
  avoid the "not mocked" error. Adding it means a new dependency plus `testOptions.unitTests` and a
  test source dir — not safe/small for this run. Exact future path:
  `src/test/java/app/lawnchair/search/algorithms/LockedProfileSearchFilterTest.kt` with
  `testImplementation` junit/truth/androidx-junit and `org.robolectric:robolectric`, or extract the
  status-flag predicate into a pure function and test that.

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
