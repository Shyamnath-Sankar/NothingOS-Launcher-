# AGENTS.md

> Instructions for coding agents working in this repository. Read this file before making changes.
> If something here conflicts with a direct instruction from the human, ask before proceeding.

## 1. What this project is

**NothingUI** (working name) is an Android home-screen replacement (launcher) inspired by the
monochrome, dot-matrix design language of Nothing OS. It ships its own widgets and wallpapers and is
intended for distribution on **Google Play**.

It is **not affiliated with, endorsed by, or sponsored by Nothing Technology Limited**.
"Nothing", "Nothing OS" and "Nothing Launcher" are trademarks of Nothing Technology Ltd. See §8.

## 2. Status and blocking decisions

| Decision | State | Notes |
|---|---|---|
| Base codebase | **DECIDED** | Fork Lawnchair 16 `16-dev` (**Apache 2.0**). Inherit its `lawn` / `withQuickstep` / `play` flavors and rebrand before the first release. |
| Public Play name | **OPEN — release blocker** | "NothingUI" is a working codename only. It contains a third-party mark and cannot ship as the Play listing name or repo name without clearance. "NothingOS" is strictly off-limits. |
| Play display label | **DECIDED** | `DotWel Launcher` (single l; owner-confirmed 2026-11-21), applied to the Play app and launcher-activity labels only. github/nightly keep their inherited Lawnchair branding. This is a display label, not a claim of trademark/name clearance, and it does not resolve the OPEN public Play listing name. |
| `applicationId` | **DECIDED** | Play channel only: `com.launchernos.dotwellabs` (owner-approved 2026-11-21). github/nightly keep `app.lawnchair` / `app.lawnchair.nightly`. Permanent once published. `com.nothing.*` belongs to Nothing Technology. |
| Monetization | OPEN | Default assumption: free + one-time Pro via Play Billing. No ads. |

**Agent rule:** stop and ask the human before changing any OPEN item or any of the values in §7.

## 3. Product scope

### v1 — must ship

- Home screen: 4×6 grid, dock, multi-page, long-press edit mode, drag & drop (if the base provides it).
- App drawer: A–Z, search, recent apps, folder support.
- Widgets: host third-party widgets (`AppWidgetHost`); ship 3–4 original widgets (dot-matrix clock,
  date, battery, weather).
- Wallpapers: static wallpaper picker (system Photo Picker) + at least one original live wallpaper.
- Icon system: monochrome/adaptive icon rendering, icon-pack support.
- Settings: grid size, labels, dock slots, theme, backup/restore.
- Default-home onboarding using `RoleManager.ROLE_HOME` (user-initiated only).

### Explicit non-goals for v1

- "Max Icons" / "Max Folders" clones.
- Notification dots / notification listener.
- Double-tap-to-sleep (needs Accessibility or Device Admin — see §7).
- Advanced gesture engine, AI features, app hiding.
- Ads of any kind.

## 4. Platform and tech stack

- **Language:** Kotlin (latest stable), Coroutines + Flow.
- **UI:** Jetpack Compose (latest stable BOM). Launcher3 views only where the base requires them.
- **SDK levels:** `compileSdk = 37`, `targetSdk = 37`, `minSdk = 26`, AGP 9.5.2, Gradle 9.9.2,
  JDK 21. This matches the upstream fork. Play's floor is `targetSdk ≥ 36` (since 2026-08-31, with
  an extension window to 2026-11-01 that has now closed); targeting 37 is higher than the floor and
  therefore allowed. **Never drop below 36.** Targeting 37 is a deliberate decision that makes the
  Android 17 constraints in §7 mandatory — see §7 "Android 17 (API 37) behavior contract".
- **DI:** Hilt. **Persistence:** Room + DataStore. **Widgets:** Glance where possible, `RemoteViews`
  where required. **Images:** Coil.
- **Build:** Groovy Gradle (inherited from Launcher3), version catalog (`gradle/libs.versions.toml`),
  JDK 21. Do not migrate the build to Kotlin DSL as part of unrelated work.
- **Quality:** ktlint + detekt, JUnit, Robolectric, Compose UI tests, Macrobenchmark for startup.
- **16 KB page size:** required if any native `.so` is shipped (Play update block from 2027-02-01).
  Pure Kotlin/Compose is already compatible.

Do not add a dependency without a one-line justification in the PR.

## 5. Architecture

### Inherited structure (Lawnchair 16 `16-dev`)

- One Gradle app module at the repo root (`namespace com.android.launcher3`); Lawnchair's Kotlin
  lives under `lawnchair/src/app/lawnchair/**`.
- AOSP Launcher3 is in the root source sets; `quickstep/` adds the recents UI; `systemUI/` and
  `wmshell/` are SystemUI/Quickstep support modules.
- Compose is already used for preferences, backup UI, all-apps search and the widget picker
  (`compose/`, `modules/widgetpicker`).
- Build variants are `lawn` (app) × `withQuickstep` (recents) × `github|nightly|play` (channel).
  Our Play artifact is `lawnWithQuickstepPlay`; the debug build is `lawnWithQuickstepPlayDebug`.
- `flowerpot/` is the app-categorization ruleset format, **not** the build flavor system.

### Where our code goes

- `lawnchair/src/app/nothingui/**` — our UI layer (theme, home surface, widgets, wallpaper, icons).
- `lawnchair/res/font/` — bundled OFL fonts.
- `lawnchair/src/app/nothingui/widgets/` — `AppWidgetProvider` + Glance definitions.
- `play/AndroidManifest.xml` — Play-only manifest overlay that removes non-core permissions.

Reuse the existing `app.lawnchair.*` / Launcher3 behavior; do not build a second parallel launcher
engine inside the fork.

- New Compose screens use unidirectional data flow: `ViewModel` exposes immutable
  `StateFlow<UiState>`; UI emits events.
- `LauncherApps` remains the single source of truth for installed apps. Do not duplicate its
  callbacks; debounce package add/remove bursts and never block the main thread.
- The existing `AppWidgetHost` stays process-wide singleton; do not create a second host.
- Every new screen needs `@Preview` composables and a stateless content composable.
- No business logic in composables. No `Context` in ViewModels.

## 6. Build, test and CI

### Local commands

```bash
./gradlew assembleLawnWithQuickstepPlayDebug          # Play-flavor debug APK
./gradlew bundleLawnWithQuickstepPlayRelease          # Play AAB (signed locally)
./gradlew spotlessCheck                               # style (inherited Spotless setup)
./gradlew testLawnWithQuickstepPlayDebugUnitTest      # unit tests, if the variant has them
./gradlew connectedLawnWithQuickstepPlayDebugAndroidTest  # device/emulator UI tests
```

The fork already ships `.github/workflows/ci.yml` and `build_release_apk.yml`. Adapt them instead of
creating duplicate workflows.

### GitHub Actions (required)

Two workflows in `.github/workflows/`:

1. **`ci.yml`** — on `pull_request` and pushes to `main`:
   - `actions/checkout@v7` with `submodules: true`
   - JDK 21 (Zulu) + `gradle/actions/setup-gradle@v6`
   - `spotlessCheck` and `assembleLawnWithQuickstepPlayDebug`
   - unit tests for the Play variant if the task exists
   - upload the debug APK as a build artifact; upload reports on failure
2. **`release.yml`** — on tags matching `v*`:
   - same checkout/JDK/Gradle setup
   - decode `KEYSTORE_BASE64` into `keystore.properties` + a temp `.jks`
   - `bundleLawnWithQuickstepPlayRelease`
   - upload the `.aab` and `mapping.txt`
   - optional: publish to the Play internal track with `PLAY_SERVICE_ACCOUNT_JSON`

Required repository secrets (never commit these):

```text
KEYSTORE_BASE64
KEYSTORE_PASSWORD
KEY_ALIAS
KEY_PASSWORD
PLAY_SERVICE_ACCOUNT_JSON   # only if automated publishing is enabled
```

CI rules:

- CI must be green before merge.
- Do not disable a failing check to get a merge; fix the cause.
- Keep `gradle/wrapper/gradle-wrapper.jar` and the Gradle version pinned.
- Pin Actions by major version (`actions/checkout@v4`) and keep them updated.

## 7. Play Store compliance invariants (hard rules)

These are non-negotiable. Any change to permissions or manifest entries requires human approval.

- **Target API 37.** `targetSdk = 37` is our shipped behavior level; 36 is Play's floor, 37 is
  allowed and is what the upstream fork targets. Because `targetSdk` opts the whole app into every
  Android 17 behavior change at once, the "Android 17 (API 37) behavior contract" below is binding.
  Re-verify the Play floor each year; raise the target when Play raises it, never lower it.

### Android 17 (API 37) behavior contract

These are consequences of `targetSdk = 37`, not optional polish. Every one of them is verified in CI
or it is not done.

- **Widget `RemoteViews` memory budget is enforced with an exception.** The system sums image memory
  across all orientation and size buckets and rejects payloads over `6 × width × height` bytes of the
  active display with `IllegalArgumentException: RemoteViews for widget update exceeds maximum bitmap
  memory usage`. At `targetSdk ≤ 36` this is only a `Slog.w`. Therefore every widget must:
  - budget from `WindowMetrics.currentWindowMetrics.bounds`, never `resources.displayMetrics`;
  - downsample to the widget's `maxWidthDp × maxHeightDp` with power-of-two `inSampleSize`, and use
    `RGB_565` for opaque art;
  - decode shared bitmaps once in `provideGlance`, before `provideContent`;
  - use full `updateAppWidget` for image changes, never `partiallyUpdateAppWidget`;
  - render a zero-bitmap fallback from `onCompositionError`.
  Verify with `adb shell dumpsys appwidget`.
- **`static final` fields are unmodifiable.** Reflective writes throw `IllegalAccessException`; JNI
  writes crash the process. No new code may reflectively write a static final field. The inherited
  `hidden-api` / `compatLib` shims are audited before any release.
- **New lock-free `MessageQueue`.** Code must not reflect on `MessageQueue` private fields.
- **Orientation, resizability and aspect-ratio limits are ignored on `sw ≥ 600dp` with no opt-out.**
  Grid and `DeviceProfile` math must derive from `WindowMetrics` and survive a resize or rotation
  mid-session on tablets and unfolded foldables.
- **Background activity launch is stricter.** Widget taps, shortcuts and deep links must use
  `MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE`-safe paths;
  `MODE_BACKGROUND_ACTIVITY_START_ALLOWED` is deprecated.
- **`ACCESS_LOCAL_NETWORK` is a runtime permission.** Do not add LAN features without it.
- **All of the above must hold on the Android 17 emulator lane**; `compileSdk 37` alone is not
  evidence.
- **`QUERY_ALL_PACKAGES`** is allowed only because the app *is* a launcher. It requires:
  - the Permissions Declaration Form in Play Console, and a demo video;
  - a listing that clearly promotes app launching / app search as core functionality;
  - **never** transmitting or selling the installed-app inventory, and no analytics/ads use of it.
- **Play manifest overlay.** `play/AndroidManifest.xml` must remove every non-core permission and
  component: `READ_CONTACTS`, `READ_MEDIA_*`, `READ_HISTORY_BOOKMARKS`, `PACKAGE_USAGE_STATS`,
  `INTERACT_ACROSS_USERS*`, `MANAGE_USERS`, `FORCE_STOP_PACKAGES`, `STATUS_BAR_SERVICE`,
  `SUSPEND_APPS`, Google QSB / Smartspacer, the inherited accessibility service, and feed /
  foreground-sync components. Verify the merged manifest in CI.
- **No `AccessibilityService` in v1.** If it is ever added (e.g. double-tap to sleep), it needs a
  prominent in-app disclosure, the Console accessibility declaration and a demo video. Launchers are
  explicitly *not* accessibility tools, so expect strict review. Prefer dropping the feature.
- **Do not add:** `MANAGE_EXTERNAL_STORAGE`, `SYSTEM_ALERT_WINDOW`,
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `READ_MEDIA_IMAGES`, `READ_SMS`, `READ_CALL_LOG`.
- **Wallpaper picking** uses the system Photo Picker / `ACTION_GET_CONTENT`; `SET_WALLPAPER` is fine.
- **Default home:** `RoleManager.ROLE_HOME`, user-initiated, no fake system dialogs, changes reversible.
- **Android 15+ Private Space:** declare `ACCESS_HIDDEN_PROFILES` and implement profile containers;
  never show locked-profile apps in search or recents.
- **Monetization:** Play Billing only for digital goods. No ads on the home screen (disruptive-ads
  policy). No misleading "free"/"Pro" claims.
- **Privacy policy + Data safety form** must match the shipped manifest exactly. On-device processing
  must be described as such.
- **No Nothing assets:** no NDot/NType fonts, wallpapers, icons, weather art or screenshots.
- **License compliance:** keep Apache `NOTICE`/attribution for any forked code. If a GPL base is used,
  the whole app must be GPLv3 and the source published — do not mix it with closed-source code.

## 8. Branding and assets

- **Fonts:** OFL only — Doto, Handjet, Workbench, Micro 5, DotGothic16. Keep the license files in
  `licenses/fonts/`.
- **Icons:** generate monochrome icons at runtime from `AdaptiveIconDrawable`'s monochrome layer
  (API 33+) with a grayscale/threshold fallback. Do not bundle a third-party icon pack.
- **Wallpapers/widgets:** original dot-field / halftone art only. No scraped assets.
- **Store listing:** never use "Nothing" in the title, icon, screenshots or keywords until the name
  is cleared; a disclaimer does not cure trademark use. Describe it as
  "minimalist monochrome, dot-matrix inspired".
- **Name clearance** (before submission): Play search, domain, USPTO/EUIPO, social handles.

## 9. Conventions

- Style: official Kotlin style, ktlint, 4-space indent, trailing commas, explicit imports.
- Commits: [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`).
- Branches: `feat/<slug>`, `fix/<slug>`.
- Keep PRs small and focused; include screenshots for UI changes and a test plan.
- Tests: unit tests for models/repositories, Robolectric for widget-host glue, Compose UI tests for
  screens, Macrobenchmark for cold start.
- Performance budgets: cold start under ~700 ms on a mid-range device, no visible jank in workspace
  scroll, no main-thread disk or package-manager work.
- Update `docs/architecture.md` and `CHANGELOG.md` when behavior or structure changes.

## 10. Agent workflow

1. Read this file and the relevant `docs/` page before touching code.
2. Check §2 for OPEN decisions; ask instead of guessing.
3. Make the smallest change that satisfies the task, following existing patterns.
4. Run `./gradlew lintDebug testDebugUnitTest` before declaring work complete. Report the actual
   output; never claim a green build you did not run.
5. Never commit secrets, keystores, `local.properties`, or generated build output.
6. Never change `applicationId`, `minSdk`, `targetSdk`, or manifest permissions without approval.
7. If you add a Play-sensitive feature, update §7 and the Play Console declarations in the same PR.

## 11. Definition of done

- [ ] Builds with `./gradlew assembleDebug`
- [ ] `lintDebug` and `testDebugUnitTest` pass
- [ ] New behavior has tests
- [ ] No new permissions unless approved and documented in §7
- [ ] No third-party assets without a compatible license
- [ ] Docs/CHANGELOG updated
- [ ] CI green
