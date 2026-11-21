# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: P0 (prove the base builds)
- branch: (none)
- pr: (none)

## done
- Repo created; Lawnchair 16 `16-dev` imported with full history and submodule.
- ci.yml fixed: `android-actions/setup-android` no longer installs the removed `tools` package
  (platform-tools only). P0 gate = CI green on main.

## next
- Confirm CI is green on main after the ci.yml fix. That closes P0.
- Then start P1 (Play-safe build): `play/AndroidManifest.xml` overlay removing the non-core
  permissions and components listed in AGENTS.md section 7, plus `scripts/manifest-guard.sh`
  wired into ci.yml.

## blockers
- (none)

## decisions locked
- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Public Play listing name: OPEN, release blocker, do not guess.
- Free models/services only. Cache heavy installs in workflows.
