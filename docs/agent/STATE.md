# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P1c (private space + bug-report cleanup) — complete; P2 next
- branch: agent/p1c-final-slice-of-p1-private
- pr: pending (agent-dev workflow opens it after this run)
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/p1c-final-slice-of-p1-private

## done
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
- P2: rebrand — applicationId `com.launchernos.dotwellabs` for the Play channel only, app label,
  launcher activity label, icon, `mipmap-*`, default strings; keep the Apache `NOTICE`.
- P9: wire `scripts/manifest-guard.sh` into CI (workflows were intentionally not touched in
  P1a/P1b/P1c).

## blockers
- None.

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

## log
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal)
