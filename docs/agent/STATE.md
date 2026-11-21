# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P2a (Play applicationId) — complete; P2b (labels/icons/NOTICE) next
- branch: agent/p2a-implement-only-the-approve
- pr: pending (agent-dev workflow opens it after this run)
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/p2a-implement-only-the-approve

## done
- P2a: Play-only `applicationId` is now `com.launchernos.dotwellabs` in `build.gradle`; it replaces
  the old `app.lawnchair.play` (and the superseded plan value `dev.shyamnath.launcher`). github
  (`app.lawnchair`) and nightly (`app.lawnchair.nightly`) are unchanged, as are `namespace
  com.android.launcher3`, `minSdk 26`, `targetSdk 37`, manifest permissions, labels and icons.
  Because the inherited `launcher_component` resValue derives from `${applicationId}`, it follows
  the new Play id automatically.
- P2a: added `scripts/play-identity-guard.sh` (+ `scripts/play-identity-guard-test.sh`). The guard
  asserts the approved Play id, preserved github/nightly ids, namespace, minSdk/targetSdk, rejects
  superseded ids, and fails on any `android:authorities` not derived from `${applicationId}` /
  `${packageName}` (provider-authority collision guard). It is not wired into CI yet (workflows
  intentionally untouched).
- P2a docs: `AGENTS.md` §2 applicationId row marked DECIDED (Play only); spec D5 and plan P2 now
  carry the approved id instead of the stale `dev.shyamnath.launcher`.
- P2a tests actually run (no Gradle): `sh scripts/play-identity-guard-test.sh` → 8/8 pass;
  `sh scripts/manifest-guard-test.sh` → all 31 existing tests pass; `sh scripts/play-identity-guard.sh`
  on the repo → OK. No APK/merged-manifest was produced in this run.
- P1c: `play/AndroidManifest.xml` now declares `ACCESS_HIDDEN_PROFILES`, so the hidden private
  profile is discoverable and its inherited container can render.
- P1c: removed the remaining bug-report components from Play — `app.lawnchair.bugreport.FileProvider`
  (provider) and `app.lawnchair.bugreport.BugReportReceiver` (receiver), alongside the
  `UploaderService` removed in P1b. The bug-report subsystem is now absent from Play.
- P1c: `scripts/manifest-guard.sh` now flags every `app.lawnchair.bugreport.*` component and
  requires `ACCESS_HIDDEN_PROFILES` in the merged manifest.
  `sh scripts/manifest-guard-test.sh` → all 31 tests pass (includes the new provider/receiver,
  required-permission and overlay cases).
- P1c: search filters apps from locked profiles via `Sequence<AppInfo>.filterLockedProfiles()` in
  `SearchUtils.kt`, applied in both `SearchUtils` and `AppSearchProvider`. It drops
  `FLAG_DISABLED_QUIET_USER` apps, so locked private-space and paused work-profile apps never
  surface in search. Added `tests/multivalentTests/.../LockedProfileSearchFilterTest.kt` (Soong
  test source set; Gradle was not run per task).
- P1c recents: no code change needed. `RecentTasksList` calls
  `SystemUiProxy.getRecentTasks(numTasks, currentUserId)`, so recents only ever contains
  current-user tasks; locked private/work profiles are other users and cannot surface.
- P1c drawer: inherited `AlphabeticalAppsList`/`PrivateProfileManager` already hides private-space
  apps unless the container is enabled; no change needed.
- P1b: `play/AndroidManifest.xml` removes `app.lawnchair.LawnchairAccessibilityService` and the
  bug-report `UploaderService`; Play settings hide the accessibility-backed gesture/sleep options.
- P1a: `play/AndroidManifest.xml` removes the AGENTS.md §7 non-core permissions and the Google QSB
  / Smartspacer components with `tools:node="remove"`, wired as both the play-flavor and
  `lawnWithQuickstepPlay` variant manifest.
- Gradle was not run (per task); CI on the PR builds `assembleLawnWithQuickstepPlayDebug`.

## next
- P2b (remaining P2): app label, launcher activity label, icon, `mipmap-*`, default strings; keep
  the Apache `NOTICE` and add our `NOTICE` entry. Public Play listing/display name is still OPEN —
  do not invent branding.
- P9: wire `scripts/manifest-guard.sh` and `scripts/play-identity-guard.sh` into CI (workflows were
  intentionally not touched in P1a/P1b/P1c/P2a).
- P1 verification still pending (do not mark passed):
  - merged-manifest guard must run against the real Gradle-merged `lawnWithQuickstepPlay` manifest in
    CI; the guard fixture tests passing is not that verification.
  - runtime private-space validation on a device/emulator (locked profile hidden from drawer, search
    and recents) is still pending; APK CI passing is not that validation.

## blockers
- P1 merged-manifest guard verification: pending real merged-manifest run in CI.
- P1 runtime private-space validation: pending device/emulator check.
- No local Gradle run was possible by task rule; APK build is deferred to PR CI.

## decisions locked
- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Public Play listing name: OPEN, release blocker, do not guess.
- Free models/services only. Cache heavy installs in workflows.

## rulings this run
- P1c search filter uses `AppInfo.runtimeStatusFlags & FLAG_DISABLED_QUIET_USER` rather than a
  per-result `UserManager.isQuietModeEnabled` binder call. `LoaderTask` and
  `PackageUpdatedTask.OP_USER_AVAILABILITY_CHANGE` keep that flag in sync, so the filter is
  current and cheap. Cost if wrong: if a future code path creates `AppInfo` without the quiet
  flag, locked-profile apps could still surface in search.
- P1c recents is covered by the platform: `getRecentTasks` is scoped to `currentUserId`, so no
  app-side filter is needed. Cost if wrong: a future recents source that queries all users would
  need its own locked-profile filter.
- The guard now *requires* `ACCESS_HIDDEN_PROFILES`, which changes it from a pure forbidden-entry
  check to also assert a Play invariant. The clean-manifest fixture was updated accordingly.
  Cost if wrong: the guard fails on any manifest (e.g. a non-Play one) that legitimately omits the
  permission.
- Prior P1a/P1b rulings retained (play overlay wired as variant manifest; guard red until P1b;
  settings gating via `isPlayStoreFlavor()`).
- P2a: the identity guard is static (parses `build.gradle` and manifest sources) because Gradle is
  not run in this environment. It catches a hardcoded provider authority before merge, but only a
  real merged manifest proves the final authorities. Cost if wrong: a Gradle-generated literal
  authority from a dependency would not be seen by the static scan.
- P2a: the guard deliberately scans every `AndroidManifest*.xml` outside `build/`, including test
  manifests. They currently use `${applicationId}` / `${packageName}`, so the check is quiet; a
  future literal test authority would need an explicit allowance. Cost if wrong: false positive on
  a non-shipped test manifest.
- P2a: `AGENTS.md` §2 was updated from OPEN to DECIDED for the already-approved Play id only; the
  public listing name remains OPEN.

## log
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + static identity/
  authority guard + docs; no Gradle run)
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal)
