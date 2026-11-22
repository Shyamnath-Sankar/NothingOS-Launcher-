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

## Real grid and widget-picker verification

After the role is granted and the actual HOME is verified, the smoke runs two more read-only phases
against the real launcher UI. Neither phase writes a preference, starts a fake activity or fabricates
a view.

- **Home screen grid.** It opens the existing `PreferenceActivity` with the existing
  `lawnchair://settings/home-screen-grid` deep link, then polls the real UIAutomator hierarchy for
  the `Home screen grid` title, the `Columns`, `Rows` and `Dock icons` labels, at least three
  accessibility `SeekBar` controls and `Apply`. The preview is validated from the actual hierarchy
  shape: a `/workspace` ViewGroup inside the preview `AndroidViewHolder`/`ViewGroup`, above every
  slider, strictly smaller than the window root and containing a `hotseat`/`search_container_workspace`
  node. It does not require a `LauncherPreviewView`/`LauncherPreviewLayout` class. It captures
  `grid-settings.xml`/`.png` and requires `Apply` to be the greyed, non-clickable label inside a
  non-clickable `android.widget.Button` (the inherited screen keeps the accessibility `enabled` flag
  true); a clickable `Apply` or a missing containing button fails, proving no grid change was staged.
  It never taps a control or Apply. If readiness never succeeds it captures the last failed attempt's
  PNG before failing. It then presses HOME and re-verifies the actual HOME clock/date.
- **HOME long-press and Widgets.** It measures the empty central workspace from the actual HOME
  hierarchy: the header bottom comes from the workspace search container and the dock top from the
  lowest labelled row, so the long-press point stays below the header and above the dock icons and
  bottom QSB. If every measured candidate is occupied it fails rather than long-pressing an occupied
  centre. A real `input swipe x y x y 1000` long-press opens the real popup, which the actual
  hierarchy exposes as `popup_container` with several clickable `system_shortcut` rows whose
  `bubble_text` labels include `Widgets` plus `Home settings`/`Wallpapers`. Readiness comes from
  those resource ids and the clickable rows, not from `OptionsPopupView`/`DeepShortcutView` class
  names; an item menu or a page with incidental English text is rejected. The smoke captures
  `home-popup.xml`/`.png`, taps the `Widgets` item by the bounds of its clickable
  `system_shortcut` parent (the label itself is not clickable), and polls for the native picker. If
  the popup never becomes ready it captures the last failed attempt's PNG before pressing BACK. It
  accepts either
  the refactored Compose picker (`com.android.launcher3.widgetpicker:id/widgets_catalog` plus a
  search/list label) or the inherited picker (`widgets_search_bar`/`search_bar_container` plus
  `primary_widgets_list_view`/`search_widgets_list_view`). The picker hierarchy must differ from the
  pre-long-press HOME, so a closed HOME with incidental English text cannot pass. It captures
  `widgets-picker.xml`/`.png`.
- **Real widget placement and HOME survival (P10b).** Inside the native picker it selects a
  clickable `widgets_list_header` whose `app_title` is `Clock` or `Calendar` and whose `app_subtitle`
  reports a positive widget count. A shortcut-only header such as the one-shortcut DotWel row is
  rejected. It expands the measured header if needed, re-resolves the expanded title header by its
  `app_title` so a stale collapsed position cannot pick a later provider's preview, captures
  `widgets-provider.xml`/`.png`, and measures the `widget_preview_container` below that header and
  above the next header. It taps the preview, polls for the real `widget_add_button` resource id,
  captures `widgets-add.xml`/`.png`, and taps the measured Add button. If Add is not exposed it uses a
  measured drag to a free right-hand workspace point derived from the pre-widget HOME. It then polls
  for a new `AppWidgetHostView`-suffixed node in the workspace and a newly bound
  `AppWidgetId`/provider pair in `dumpsys appwidget`. The HOME comparison parses both hierarchies as
  node records, so a compact single-line UIAutomator dump is handled, and it ignores hosts inside
  picker/sheet previews. It captures `widgets-home-placed.xml`/`.png`, and fails with saved
  `widgets-add-last.xml`/`.png` if a configuration activity or an unbound provider blocks placement.
  The placed widget must sit between
  the measured header bottom and dock top, so it cannot cover the later drawer swipe start. It then
  presses HOME, captures `widgets-home-after-home.xml`/`.png`, and requires the same widget bounds to
  remain. It never starts the picker or a configuration activity directly, never binds an app widget,
  and never writes preferences or the database.

Evidence for these phases:

```text
grid-settings-launch.txt
grid-settings-attempt-N.xml
grid-settings-attempt-N.png
grid-settings.xml
grid-settings.png
grid-settings.txt
home-before-widgets-attempt-N.xml/.png
widgets-launcher-idle-N.txt
widgets-longpress-N.txt
widgets-longpress-log.txt
home-popup-attempt-N-P.xml
home-popup-attempt-N-last.png
home-popup.xml
home-popup.png
widgets-picker-attempt-N-P.xml
widgets-picker.xml
widgets-picker.png
widgets-picker.txt
widgets-add-log.txt
widgets-provider-N-P.xml
widgets-provider.xml
widgets-provider.png
widgets-add-attempt-N.xml
widgets-add.xml
widgets-add.png
widgets-drag.txt
widgets-home-placed-attempt-N.xml
widgets-home-placed.xml
widgets-home-placed.png
widgets-home-after-home.xml
widgets-home-after-home.png
widgets-appwidget-before.txt
widgets-appwidget-after.txt
widgets-appwidget-providers.txt
widgets-add-last.xml
widgets-add-last.png
activities-widget-placed-N.txt
```

Every wait is a bounded UIAutomator poll. The existing role-consent Cancel, the 1500 ms / four-attempt
drawer swipe, the Settings search/tap and the exact `com.android.settings` foreground check are
unchanged.

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
