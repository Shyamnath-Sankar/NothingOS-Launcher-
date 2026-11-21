# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P1b (accessibility + foreground-sync removal) — complete; P1c next
- branch: agent/p1b-second-slice-of-p1-remove
- pr: pending (agent-dev workflow opens it after this run)
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/p1b-second-slice-of-p1-remove

## done
- P1b: `play/AndroidManifest.xml` now removes `app.lawnchair.LawnchairAccessibilityService`
  and the bug-report foreground-sync service `app.lawnchair.bugreport.UploaderService` with
  `tools:node="remove"`. The classes stay compiled for the shared source set, but the Play build
  never declares them. github/nightly keep both.
- P1b settings entry points: Play (`BuildConfig.FLAVOR_channel == "play"`, via the existing
  `isPlayStoreFlavor()`) hides the accessibility-backed gesture options (`Recents`,
  `OpenNotifications`, `OpenQuickSettings`), removes `SleepMode.ACCESSIBILITY` from the sleep-mode
  list, drops `SleepMethodPieAccessibility` from `SleepGestureHandler`, and makes
  `GestureWithAccessibilityHandler` a no-op so it never opens a dead system accessibility screen.
- `scripts/manifest-guard-test.sh` now also asserts the Play overlay declares the two
  `tools:node="remove"` services. Test run: `sh scripts/manifest-guard-test.sh` → all 25 tests pass.
- Commits: d394373 (manifest + overlay test), 166b9b6 (settings gating).
- Gradle was not run (per task); CI on the PR builds `assembleLawnWithQuickstepPlayDebug`.
- P1a: `play/AndroidManifest.xml` removes the AGENTS.md §7 non-core permissions and the Google
  QSB / Smartspacer components with `tools:node="remove"`.
- Wired as the `play` flavor manifest and as the `lawnWithQuickstepPlay` variant manifest. The
  variant manifest has the highest merge priority, which is what makes the removal markers
  effective against entries declared by the higher-priority `lawn`/`withQuickstep` flavors.
- `scripts/manifest-guard.sh` + `scripts/manifest-guard-test.sh`: POSIX guard fails on forbidden
  permissions/components from AGENTS.md §7, including the accessibility and feed/foreground-sync
  entries that P1b will remove. Test run: `sh scripts/manifest-guard-test.sh` → all 22 tests pass.
- Commits: e5347d0 (manifest overlay), a11239e (guard), 54bcb72 (accessibility/feed checks).
- Gradle was not run (per task); CI on the PR builds `assembleLawnWithQuickstepPlayDebug`.

## next
- P1c: `ACCESS_HIDDEN_PROFILES` + private-space containers; locked profiles never surface in
  drawer, search or recents.
- P9: wire `scripts/manifest-guard.sh` into CI (workflows were intentionally not touched in P1a/P1b).
- Follow-up (not in P1b scope): the bug-report receiver/provider still exist in Play while
  `UploaderService` is gone, so the crash-notification "Upload" action can leave a stuck
  notification. Either gate the upload action off in Play or remove the whole bug-report subsystem.

## blockers
- None.

## decisions locked
- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Public Play listing name: OPEN, release blocker, do not guess.
- Free models/services only. Cache heavy installs in workflows.

## rulings this run
- The play flavor manifest is lower merge priority than the `lawn`/`withQuickstep` flavor
  manifests (flavor dimension order), so a play-flavor-only `tools:node="remove"` cannot remove
  their entries. Ruling: also wire `play/AndroidManifest.xml` as the `lawnWithQuickstepPlay`
  variant manifest (highest priority) and include the launcher activity/application block there.
  Cost if wrong: the launcher declaration is duplicated and could drift from
  `quickstep/AndroidManifest-launcher.xml`.
- The guard checks the full §7 list (accessibility + feed/foreground-sync) even though P1a does not
  remove those yet. Ruling: make the guard fail until P1b lands. Cost if wrong: the guard is red
  on Play until P1b, which is the intended signal.
- P1b settings gating uses the existing `isPlayStoreFlavor()` (`BuildConfig.FLAVOR_channel`) rather
  than a `play/res` boolean. Reason: flavor resource priority follows dimension order, so a
  `play`-flavor resource would lose to `lawnchair/res` (`lawn` dimension); a variant-only resource
  would also miss `lawnPlay`. Cost if wrong: if a future build adds a non-`play` channel that still
  lacks the service, its settings would show dead accessibility options.
- P1b hides `Recents`, `OpenNotifications` and `OpenQuickSettings` in Play, not just the explicit
  "Accessibility service" sleep option, because all three either require or fall back to the
  removed service and would otherwise prompt for a service that cannot be enabled. Cost if wrong:
  Play loses the reflection-based notification/Quick Settings gesture shortcut.
## log
- 2026-11-21: P1b complete (accessibility + bug-report foreground service removed from Play)
