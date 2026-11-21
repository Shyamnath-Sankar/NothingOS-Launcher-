# Emulator verification

These scripts are for the API 37 emulator lane. They are not run by the normal Gradle CI job; the
coordinator wires the lane.

## `scripts/emulator-smoke.sh`

Run after `assembleLawnWithQuickstepPlayDebug` has produced the Play debug APK:

```bash
sh scripts/emulator-smoke.sh --serial emulator-5554
```

It fails closed and writes evidence to `build/emulator-smoke/<timestamp>/`:

- selects exactly one APK under `build/outputs/apk/.../lawnWithQuickstepPlayDebug/` (or `--apk`)
- requires an API 37 device and clean-installs only `com.launchernos.dotwellabs.debug`
- pulls the installed APK and verifies its package plus the installed application and launchable
  activity label are `DotWel Launcher`
- before granting the role, opens the settings default-launcher warning, taps it, waits for the
  real platform `RoleManager` HOME consent screen, captures `role-consent-settings.xml`/`.png` and
  `role-consent.xml`/`.png`, taps Cancel, and verifies the role holder list is unchanged
- then grants `android.app.role.HOME` with `cmd role add-role-holder` and verifies the role holder
  and default-home resolution
- presses HOME, verifies the launcher is resumed, captures a screenshot/logcat/dumpsys, and fails on
  install, launch, ANR or crash-stack problems
- captures app-info and About evidence, then opens the debug-only Play theme sample through the
  existing exported `PreferenceActivity` and the explicit
  `app.lawnchair.ui.preferences.THEME_SAMPLE` extra. It captures
  `theme-sample-dark.xml`/`.png` and `theme-sample-light.xml`/`.png`, requires `DOTWEL` in both UI
  hierarchies, and returns HOME. The extra is inert unless the build is both debug and Play, so
  release and non-Play builds keep the normal settings surface.

The smoke now captures and cancels the real user-initiated
`RoleManager.createRequestRoleIntent(ROLE_HOME)` consent after tapping the settings warning, before
using the `cmd role` grant as disposable-emulator setup for the remaining HOME/drawer checks. The
grant remains test setup, not an app bypass. The broader onboarding flow is still a manual check.

## Locked private-space validation

`scripts/private-space-check.sh` is deliberately separate. It detects an
`android.os.usertype.profile.PRIVATE` user and checks that it is quiet/locked. It does **not** claim
the launcher's drawer, search or recents filtering passed, and it never creates a profile or
account automatically.

Exit codes: `0` locked private profile detected (prerequisite satisfied), `77` no private profile or
not locked, `1` adb/device error.

Private space needs a secure lock screen and explicit provisioning. On a disposable API 37 emulator
the manual prerequisite is:

1. Create the private space in Settings > Security & privacy > Private space (or use the Settings
   search entry). Set a device lock screen/PIN when prompted.
2. While the private space is unlocked, install a marker app only into its user, for example:
   `adb install --user <private-id> <marker.apk>`.
3. Lock the private space (lock the device, or use the private-space lock action).
4. Run `sh scripts/private-space-check.sh --serial emulator-5554`; it should report the locked
   profile and exit `0`.
5. Manually (or in a dedicated UI test) verify the marker app is absent from the launcher drawer,
   search and recents while locked, then unlock and verify it returns.

Do not treat a passing `private-space-check.sh` as the runtime gate. The gate stays pending until
the drawer/search/recents assertions above are recorded.
