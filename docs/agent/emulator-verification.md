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
- proves the three original widgets are actually hosted: `dumpsys appwidget` must contain distinct
  launcher-owned `AppWidgetId` records for `DotWelClockWidgetProvider`,
  `DotWelBatteryWidgetProvider` and `DotWelDeviceWidgetProvider` (current `[N] id=N`/`HostId` and
  legacy `AppWidgetId`/`hostPackage` shapes, including the API 37
  `ProviderId{cmp:ComponentInfo{...}}` wrapper). A provider catalog or a widget owned by another
  host fails. The measured HOME XML must expose the `nothingui_clock_time` child with a live
  `H:mm`/`HH:mm` value, the `nothingui_battery_art` child with a real `0..100%` or `--`
  description, and the device card's `nothingui_device_storage_value` plus
  `nothingui_device_storage_detail`; an unavailable storage read must show the short `--` marker and
  the localized `Storage unavailable` detail, never the long placeholder
- before any third-party widget is added, requires the existing `pref_launcherTheme=system` choice
  (read-only), captures `clean-home-dark.xml`/`.png` and `clean-home-light.xml`/`.png` under system
  night `yes`/`no`, runs the same launcher-owned widget-id and child-value proof for each capture,
  restores the previous night mode, and returns HOME
- then exercises the three real device-card Settings pills (`nothingui_device_wifi`,
  `nothingui_device_sound`, `nothingui_device_display`) by the bounds of each measured child, not
  the card centre. For each pill it resolves the expected destination from the installed platform
  with `cmd package resolve-activity --brief` for `android.settings.WIFI_SETTINGS`,
  `android.settings.SOUND_SETTINGS` and `android.settings.DISPLAY_SETTINGS`, falling back to
  `android.settings.SETTINGS` exactly as the widget does; it never guesses an activity alias. It
  requires the platform-resolved component to be foreground, captures
  `activities-device-settings-<action>.txt` and `device-settings-<action>.xml`/`.png`, presses HOME,
  requires the device card and pill to be visible again, and re-reads `dumpsys appwidget` to prove
  all three own widget ids are distinct and unchanged. It writes `device-settings-before.png`,
  `device-settings-home-<action>.png`, `device-settings-log.txt` and `device-settings.txt`, and it
  never changes a setting or rebinds a widget
- captures app-info and About evidence, then verifies the real Play settings palette. It reads the
  existing `pref_launcherTheme` preference and requires `system` (a clean install defaults to it; the
  smoke never writes the preference), switches the emulator with `cmd uimode night yes` and
  `cmd uimode night no`, launches the real exported `PreferenceActivity` without the diagnostic
  extra, and captures `settings-theme-dark.xml`/`.png` and `settings-theme-light.xml`/`.png`. Each
  hierarchy must expose the real Preferences dashboard (`Settings`, `General`) and must not contain
  the `DOTWEL` sample. The previous system night mode is restored before returning HOME, even when a
  capture fails.
- before each native HOME popup/app-drawer capture it reads back `cmd uimode night`, then polls the
  debug-only `DotWelTheme` `theme-refresh` trace from a per-mode logcat baseline until the launcher
  reports the expected `night=true|false` and `resolvedDark=true|false`. The trace now records
  `source=init|resume|config|config-post|color-hints|wallpaper-colors|manual`,
  `activity=<fully.qualified.Activity>`, `suppliedNight`, `appNight` and the actual
  `activity.resources` `night`, so the next run can identify which callback ran and whether the
  supplied configuration, activity resources and application resources disagree. Readiness only
  accepts a line for the real `app.lawnchair.LawnchairLauncher` and the current mode; a Settings or
  other-activity line, a stale pre-switch line and a mode-mismatched line cannot satisfy it. It
  stores `native-theme-<mode>-system-night.txt` and `native-theme-<mode>-state.txt`, and only then
  captures `native-popup-<mode>` and `native-drawer-<mode>`. If readiness times out it additionally
  stores `native-theme-<mode>-current.log`, `native-theme-<mode>-system-night-now.txt`,
  `native-theme-<mode>-activities.txt` and `native-theme-<mode>-failure.png`, and still restores the
  previous night mode instead of accepting a light/ambiguous frame. The smoke still never writes a
  theme preference. Dark drawer/header surfaces use pure black while popups and cards stay charcoal,
  so the captures also reveal an AMOLED regression.
- then opens the debug-only Play theme sample through the existing exported `PreferenceActivity` and
  the explicit `app.lawnchair.ui.preferences.THEME_SAMPLE` extra. It captures
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
  bottom QSB. A point is occupied when it is inside a labelled clickable item (app icon, folder or
  shortcut) or any real widget host, including `PendingAppWidgetHostView`; hosts count regardless of
  their `clickable`, `text` or `content-desc` flags because CI155 exposed the Device card as a
  non-clickable `LauncherAppWidgetHostView`. Widget-host bounds keep one measured margin of
  clearance, and the bounded candidate search reaches the empty band below a low widget such as the
  Device card. If every measured candidate is occupied it fails rather than long-pressing an
  occupied centre. A real `input swipe x y x y 1000` long-press opens the real popup, which the actual
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
  rejected. A picker row can sit at the bottom with its preview clipped under the navigation bar
  (CI114: the Calendar header at `[29,1592][1051,1827]` and a `[297,1869][783,1920]` preview, only
  51 px visible). The smoke therefore measures a viewport below the real
  `widgets_search_bar_edit_text`/`search_bar_container` and 100 px above the root bottom, and
  accepts a preview only when it is fully inside that viewport and at least 100 px tall. It brings
  the provider into view first by focusing the real search input and typing `Clock` (polling the
  search results for a Clock `widgets_list_header`), then falls back to a bounded genuine scroll
  inside the measured widget list (`primary_widgets_list_view`/`search_widgets_list_view`/
  `widgets_catalog`), re-resolving the header and preview after every scroll. A clipped preview is
  never tapped, even when its resource id is valid. It expands the measured header only when no
  preview exists yet, re-resolves the expanded title header by its `app_title` so a stale collapsed
  position cannot pick a later provider's preview, captures `widgets-provider.xml`/`.png`, and taps
  the fully visible `widget_preview_container`. It then polls for the real enabled, clickable
  `widget_add_button` resource id. The Add can sit partly under the navigation bar (CI120:
  `[434,1755][645,1881]` with the navigation bar beginning around 1800, so the original centre 1818
  opened Android HOME). The smoke remeasures the viewport from the exposed Add hierarchy, intersects
  the Add bounds with it, pulls the intersection 32 px above the viewport bottom so it clears the
  navigation bar, and taps only that safe intersection when it is at least 24 px in both dimensions.
  It never taps the original Add centre. If no large-enough safe intersection remains it performs up
  to three genuine vertical swipes inside the measured widget list, re-resolves the Add after every
  scroll, and fails with `widgets-add-last.xml`/`.png` rather than guessing a coordinate. It
  captures `widgets-add.xml`/`.png` and logs the original and safe bounds. The platform may then show
  the real `AllowBindAppWidgetActivity` consent. Two identities are kept separate: the selected
  provider/app header (`Clock`) is used only for HOME host and page-search matching, while the
  consent names the selected preview's own `widget_name` caption. CI161 showed that one Clock
  provider can expose both an `Analog clock` and a `Digital clock` cell at the same vertical
  position, so the caption is read strictly from the actual `WidgetCell` that owns the measured
  `widget_preview_container` in the saved pre-Add XML. The provider header and the first global
  `widget_name` are never used; a missing, foreign or ambiguous caption (including two different
  `widget_name` nodes in the selected cell) fails closed rather than guessing. Both consent calls
  receive the captured caption. The smoke accepts only the exact
  `Create widget and allow access?` dialog owned by `com.android.settings`, whose `android:id/message`
  names the launcher (`DotWel Launcher`) and the selected widget, and which exposes an enabled,
  clickable `android:id/button1` control whose label is `Create` or the platform-rendered `CREATE`,
  plus the `android:id/alwaysUse` checkbox. The title and launcher/widget identity must be in the
  dialog's own nodes; matching text elsewhere in the tree is rejected. It captures
  `widgets-bind-consent.xml`/`.png`, refuses to continue if `Always allow` is already checked, and
  taps Create by its measured `android:id/button1` bounds. A generic dialog with a Create button, a
  wrong package, a missing launcher/widget identity, or a missing/disabled button1 is rejected;
  dismissing the dialog is never treated as success. There is no ordinary
  workspace swipe fallback; if Add is not exposed it saves `widgets-add-last.xml`/`.png` and fails
  instead of faking the picker's long-press drag. It then polls for a new `AppWidgetHostView`-suffixed
  node in the workspace and, with bounded retries, a new `AppWidgetId` whose host package is this
  launcher in `dumpsys appwidget` (current `[N] id=N`/`host=HostId{..., pkg:...}` and legacy
  `AppWidgetId=N`/`hostPackage=` shapes are both parsed). API 37 wraps the provider in
  `ProviderId{cmp:ComponentInfo{...}}`; that wrapper is accepted only inside a real widget-id block
  and only when the same block is owned by this launcher. Provider catalogs and other hosts are
  rejected. The HOME comparison parses both hierarchies
  as node records, so a compact single-line UIAutomator dump is handled, and it ignores hosts inside
  picker/sheet previews.
  A denser factory HOME can put the new provider on a later page, so after Add and any bind consent
  the smoke waits for a new launcher-owned `AppWidgetId`, then searches at most three measured HOME
  pages. Identity is the picker-selected provider label plus a real workspace host, never geometry
  alone: a reference host with a different label, a pending host, a picker/sheet preview and an
  outside-workspace host are rejected. This keeps the inherited own Clock (same provider family) from
  satisfying a new third-party Clock placement. It saves `widgets-placement-page-N.xml`/`.png`,
  `widgets-survival-page-N.xml`/`.png`, the activities/swipe logs and `widgets-page-log.txt` for every
  page visited, and captures `widgets-home-placed.xml`/`.png` only for the exact matched host. The
  placed widget is validated against the geometry actually visible on the page where it was found:
  its bounds must sit inside that page's workspace and below any launcher
  `search_container_workspace` header that is really present, and above the actual `hotseat` dock.
  A genuine later page without the first-page header is valid; the reference page's header band is
  never inherited. Missing or malformed workspace/dock geometry fails closed, and the labelled-row
  `ui_dock_top` is not used because later-page app icons can make it report a row above the real
  dock. The check also re-proves the exact selected-provider workspace host, so absent, foreign and
  picker-preview hosts cannot pass. This keeps the widget off the later drawer swipe start. The same
  page-local rule governs the horizontal page swipes used by the bounded search, the return to the
  original page and the forward recheck. Each swipe is derived from the workspace and `hotseat`
  bounds actually exposed on the current page, never the labelled-row `ui_dock_top` and never the
  first page's header. When a real `search_container_workspace` header is present the safe band
  starts below it; on a genuine no-header later page the band starts at the measured workspace top.
  The y is the midpoint above the actual hotseat top, and the x endpoints stay inside the actual
  workspace, including nonzero origins. Missing, malformed or degenerate workspace/hotseat geometry,
  an impossible band, or an unknown direction fails closed instead of inventing a fraction. Fixtures
  pin the CI159 first page (header bottom 312, hotseat 1481) and the no-header later page (ordinary
  icon row 1196, hotseat 1481), so the later swipe uses the real hotseat and ignores the icon row. It
  then launches Settings with
  `am start -a android.settings.SETTINGS`, waits for the exact `com.android.settings` foreground,
  captures `widgets-settings-launched.xml`/`.png`, presses HOME, and searches the same bounded pages
  by provider label plus the exact placed bounds. It captures `widgets-home-after-home.xml`/`.png`
  and requires that exact host to remain. After that exact-host/new-id proof, the Settings/HOME
  survival check and the bounded page recheck all succeed, the smoke restores the existing
  primary/default HOME with an ordinary HOME key. `Launcher.onNewIntent` moves the workspace to its
  default page for that normal MAIN intent; the smoke does not reset, move or delete any workspace
  item. A bounded readiness poll requires the primary page's date pill, live clock and all three
  original widget child ids before `verify_nothing_home` runs again, so a widget-only later page
  left visible by the page search cannot weaken the primary-page assertion. It never starts the
  picker or a configuration activity
  directly, never binds an app widget itself, and never writes preferences or the database.

Evidence for these phases:

```text
home-widgets.txt
home-widgets-instances.txt
home-widgets-verified.txt
clean-home-dark.xml
clean-home-dark.png
clean-home-dark-widgets.txt
clean-home-dark-widgets-verified.txt
clean-home-light.xml
clean-home-light.png
clean-home-light-widgets.txt
clean-home-light-widgets-verified.txt
clean-home-night-before.txt
clean-home-night-restore.txt
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
widgets-picker-cleared.xml
widgets-search-N.xml
widgets-search.xml
widgets-picker.txt
widgets-add-log.txt
widgets-provider-N-P.xml
widgets-provider.xml
widgets-provider.png
widgets-scroll-N.xml
widgets-add-attempt-N.xml
widgets-add.xml
widgets-add.png
widgets-bind-consent.xml
widgets-bind-consent.png
widgets-placement-page-N.xml
widgets-placement-page-N.png
widgets-survival-page-N.xml
widgets-survival-page-N.png
widgets-page-log.txt
widgets-home-placed-attempt-N.xml
widgets-home-placed.xml
widgets-home-placed.png
widgets-settings-launch.txt
widgets-settings-launched.xml
widgets-settings-launched.png
activities-widget-settings.txt
widgets-home-after-home.xml
widgets-home-after-home.png
home-primary-N.xml
home-primary.xml
home-primary.png
primary-home-restored.txt
device-settings-before.xml
device-settings-before.png
activities-device-settings-wifi.txt
activities-device-settings-sound.txt
activities-device-settings-display.txt
device-settings-wifi.xml
device-settings-wifi.png
device-settings-sound.xml
device-settings-sound.png
device-settings-display.xml
device-settings-display.png
device-settings-home-wifi.xml
device-settings-home-wifi.png
device-settings-home-sound.xml
device-settings-home-sound.png
device-settings-home-display.xml
device-settings-home-display.png
device-settings-appwidget-before.txt
device-settings-appwidget-after-wifi.txt
device-settings-appwidget-after-sound.txt
device-settings-appwidget-after-display.txt
device-settings-instances-before.txt
device-settings-instances-after-wifi.txt
device-settings-instances-after-sound.txt
device-settings-instances-after-display.txt
device-settings-log.txt
device-settings.txt
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

## Drawer bottom drawing boundary

After the Settings search/tap flow, the smoke opens the drawer again and captures
`appdrawer-bottom-start.xml`/`.png`, then measures the real navigation bar from
`dumpsys window windows` (the separate SystemUI `NavigationBar` frame) with a stable-display-frame
fallback from `dumpsys window displays`. It writes the raw dump to
`appdrawer-navigation-window.txt` and the resolved values to `appdrawer-navigation-bounds.txt`.

It then swipes once for `appdrawer-mid-scroll.xml`/`.png` and keeps swiping, bounded to six attempts,
until the labelled clickable rows inside the real `apps_list_view` stop changing. The stable capture
is `appdrawer-end.xml`/`.png`; the final row bounds must sit at or above the measured navigation-bar
top, proving the bottom clip did not hide the end of the list. The check fails closed when the
navigation bar, the list bounds or the final row cannot be measured. The clip is Play-only and
bottom-only: the top padding overflow for floating headers/search, the left/right geometry, fast
scrolling, the work/private tabs and the floating-search offsets are unchanged. `SearchRecyclerView`
inherits the same recycler, so search results use the same bottom boundary without a separate
capture.

## Offline AMOLED wallpaper gallery

`emulator-smoke.sh` now resolves the modern navigation safe area from a visible
`InsetsSource type=navigationBars frame=[...]` when no `NavigationBar` window frame is present. The
API 181 activity artifacts report `frame=[0,1794][1080,1920]`; the parser accepts that modern
bracket frame and `frame=Rect(...)` syntax, ignores invisible sources, and keeps the legacy
`mFrame`/`mStable` fixtures and fail-closed behavior. The measured 1794 top is used; no phone height
is guessed.

After the native/theme captures, `capture_wallpaper_gallery` records `dumpsys wallpaper` Home/Lock
IDs and launcher-owned `dumpsys appwidget` IDs. It opens the Play-only gallery through the normal
`lawnchair://settings/amoled-wallpapers` route in dark and light, captures
`wallpaper-gallery-{dark,light}.xml/.png`, opens the Pitch Black preview, captures
`wallpaper-preview-{dark,light}.xml/.png`, then presses Back and requires both wallpaper IDs to be
unchanged. Preview, theme switching, Cancel and Back never call the applier. Widget IDs are re-read
after the previews and must match.

Only then does it tap Pitch Black and the separate Apply to Home screen button, poll up to ten times
for a changed Home ID, and repeat for Wireframe Torus. Each apply writes
`wallpaper-apply-<id>.{png,txt}`, `wallpaper-apply-<id>-ids-*.txt`,
`wallpaper-apply-<id>-widgets.txt` and `wallpaper-home-after-<id>.xml`; the existing
`verify_home_widgets` proof runs after each apply. A recorded lock ID must not move. An absent lock
ID may stay absent or materialise as the prior Home ID under the Home-only operation; it may not
take a different value. The applier uses `FLAG_SYSTEM` only, checks
`isWallpaperSupported`/`isSetWallpaperAllowed`, applies the PNG as an existing-resource stream and
renders the vector to a bounded 1080x2340 bitmap on IO, then confirms the positive returned ID
equals the current Home wallpaper ID. Lock is never targeted and protected image data is never
read.

Before those static applies, `_cwg_preview_live_wallpaper` measures the separate `Preview live
wallpaper` action with the same bounded settings scroll and taps it. It never clears the shared
logcat buffer: it keeps a read-only `live-wallpaper-logcat-before.txt` baseline and derives
`live-wallpaper-logcat-preview.txt` as only the appended tail, failing closed unless the baseline is
still an exact prefix of `live-wallpaper-logcat.txt` (a rotated buffer cannot be sliced safely). It
accepts only a real platform wallpaper-picker hierarchy (`com.android.wallpaper`,
`com.android.wallpaper.livepicker` or `com.google.android.apps.wallpaper`) with a measured confirm/
cancel control; the settings gallery, HOME, empty and unknown captures fail closed. It retains
`live-wallpaper-preview-<n>.xml` and `live-wallpaper-preview.png` and `live-wallpaper-dumpsys.txt`,
and requires the engine's own fresh `visibility=true` transition in the preview-only slice.
Surface creation alone, a hidden-only line and a stale pre-baseline visibility line are not
accepted; the fresh transition does not itself prove a rendered frame. Back must leave both Home/
Lock IDs unchanged; the post-Back logcat is retained as
`live-wallpaper-logcat-after-back.txt` for the paused/destroyed transition. The engine removes
queued callbacks and waits for an in-flight draw under one lock on hidden, surface destruction and
engine destruction, and DEBUG transition lines include a stable per-engine identity token plus
cumulative posted/drawn/pending/drawing counters (no per-frame logging). The visible transition is
logged before the resume frame is posted, so its drawn count is exactly the state left by the
preceding hide.

After both static applies, `_cwg_apply_live_wallpaper` reopens the gallery, measures the same
`Preview live wallpaper` action and requires the exact `Dot Field (Live)` title from
`com.android.wallpaper.livepicker`. It measures a positive, fully visible `Set wallpaper` control
inside the display above the measured navigation top and taps it once. Any normal system
destination dialog is resolved only through the single exact measured `Home screen` control; a
lock/lock-and-home destination, duplicate `Home screen` labels, a clipped control or a non-numeric
navigation top fails closed with the captured XML/screenshot, never a blind confirm. The app never
calls `setWallpaperComponent`, a shell wallpaper setter or a service binding. `dumpsys wallpaper`
must then report `DotFieldWallpaperService` in the System wallpaper state, the Home ID must change
and the existing `wallpaper_lock_preserved` rule must hold. Two timed HOME frames are retained
without treating an unchanged frame as a failure.

The runtime pause/resume gate uses real opaque activity transitions: it launches the device
Settings, proves through `dumpsys activity` that Settings is the resumed activity, and requires a
fresh post-baseline `visibility=false` with `pending=false drawing=false` for one engine token.
After a bounded hidden interval the normal HOME key must resume that exact token with the exact
same cumulative drawn count (no hidden drawing). Staying HOME and reopening Settings must produce a
second hide for the same token with a strictly larger drawn count (resumed frames). Mixed engines,
a missing resume, a pending/drawing hide, a stale pre-baseline visible line and a hidden-only slice
all fail closed. Every phase keeps its read-only baseline, full and sliced logcat, dumpsys, XML and
screenshots; the shared crash/ANR history is never cleared.

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
