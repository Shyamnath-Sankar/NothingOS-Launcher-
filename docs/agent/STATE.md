# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P1a (Play-safe manifest) — complete; P1b next
- branch: agent/p1a-play-safe-manifest-first-s
- pr: pending (agent-dev workflow opens it after this run)

## done
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
- P1b: remove `app.lawnchair.LawnchairAccessibilityService` and the feed / foreground-sync
  components (`app.lawnchair.bugreport.UploaderService`) from the Play variant, plus their
  settings entry points. Then run the guard against the merged manifest.
- P1c: `ACCESS_HIDDEN_PROFILES` + private-space containers; locked profiles never surface in
  drawer, search or recents.
- P9: wire `scripts/manifest-guard.sh` into CI (workflows were intentionally not touched in P1a).

## blockers
- None. The guard currently reports the P1b entries on the Play manifest by design.

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
## log
- 2026-11-21: agent-dev loop verified
