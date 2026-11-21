# NothingUI Launcher — v1 design spec

- **Date:** 2026-11-21
- **Status:** Approved (human approved start of build 2026-11-21; `targetSdk = 37` approved)
- **Working name:** NothingUI. Public Play listing name is still a **release blocker** (see §9).

## 1. Problem and goal

Build an Android home-screen replacement that ships a coherent monochrome, dot-matrix visual
language, its own widgets and wallpapers, and is publishable on Google Play without policy risk.

We do **not** build a launcher engine. We fork an existing, licensed, production launcher and add a
design language, our own widgets/wallpapers, and a Play-safe build.

## 2. Decisions

| # | Decision | Value | Why |
|---|---|---|---|
| D1 | Base | Lawnchair 16 `16-dev` (Apache 2.0) | Production Launcher3 plumbing: widget host, folders, drag/drop, work profiles, backup. |
| D2 | Import | `upstream` remote + merge, full history preserved | Apache attribution + future upstream merges. |
| D3 | Internal flavor | keep `lawn` | Avoid a re-name across ~9,700 files. Rebrand labels/ids only. |
| D4 | Play artifact | `lawnWithQuickstepPlay` for v1 | The fork's `recents` flavor dimension has a single `withQuickstep` flavor, so `lawnPlay` does not exist. Dropping Quickstep needs a new `withoutQuickstep` flavor — backlog, not v1. |
| D5 | `applicationId` | `com.launchernos.dotwellabs` (Play only; github/nightly unchanged) | Decoupled from the brand; permanent once published. |
| D6 | SDK | `compileSdk 37`, `targetSdk 37`, `minSdk 26` | Matches upstream. Play floor is 36; 37 is allowed and is the whole point of "works on Android 17". |
| D7 | Monetization | free + optional Pro via Play Billing, no ads | Deferred until after v1 ships; no billing code in v1. |

## 3. Scope

### In v1

- Home screen: 4×6 grid, dock, multi-page, long-press edit mode, drag & drop.
- App drawer: A–Z, search, recents, folders.
- 3–4 original widgets: dot-matrix clock, date, battery, weather.
- Hot third-party widgets via the inherited `AppWidgetHost`.
- Wallpaper: original static pack + one `WallpaperService` live wallpaper + system Photo Picker.
- Monochrome icon rendering with runtime adaptive-icon monochrome layer.
- Settings: grid size, labels, dock slots, theme, backup/restore.
- Default-home onboarding via `RoleManager.ROLE_HOME`.

### Out of v1

Notification dots, notification listener, double-tap-to-sleep, AccessibilityService, advanced
gestures, AI features, app hiding, ads, Max-Icons/Max-Folders clones.

## 4. Architecture

Inherit the fork; do not create a parallel engine.

```
lawnchair/src/app/nothingui/**          our UI layer
  theme/                                palette, Doto typography, spacing, motion
  home/                                 grid override, monochrome icons, page indicator
  widgets/                              AppWidgetProvider + Glance definitions
  wallpaper/                            WallpaperService + static pack
  icons/                                monochrome icon processor
lawnchair/res/font/                     bundled OFL fonts
play/AndroidManifest.xml                Play-only manifest overlay
.github/workflows/{ci,release}.yml      adapted from the fork
```

Rules: unidirectional data flow (`StateFlow<UiState>`, events in), `LauncherApps` stays the single
source of truth for installed apps, one process-wide `AppWidgetHost`, `@Preview` + stateless content
composable per screen, no business logic in composables, no `Context` in ViewModels.

## 5. Play compliance

Hard rules live in `AGENTS.md` §7. Summary of what this spec commits to:

- `play/AndroidManifest.xml` removes every non-core permission and component (contacts, media,
  history, usage stats, cross-user, user management, force-stop, status bar, suspend, Google QSB,
  Smartspacer, the accessibility service, feed / foreground-sync).
- Keep `QUERY_ALL_PACKAGES` (launcher core function) with the Console declaration and demo video.
- Add `ACCESS_HIDDEN_PROFILES` and implement private-space containers.
- CI merged-manifest guard fails the build on any forbidden permission.
- No Nothing assets; OFL fonts only; original art only.

## 6. Android 17 (API 37) behavior contract

`targetSdk = 37` opts into all Android 17 changes. Binding, verified in CI:

1. **Widget bitmap memory** — enforced exception over `6 × width × height`. Budget from
   `WindowMetrics`, downsample to widget max dp with `RGB_565`, decode once in `provideGlance`, full
   `updateAppWidget` for images, zero-bitmap `onCompositionError` fallback.
2. **`static final` fields unmodifiable** — no reflective writes; audit inherited `hidden-api` and
   `compatLib` shims.
3. **Lock-free `MessageQueue`** — no reflection on its private fields.
4. **Large-screen constraints ignored** (`sw ≥ 600dp`, no opt-out) — grid math from `WindowMetrics`,
   survives resize/rotation mid-session.
5. **BAL hardening** — `MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE`-safe launches for widget
   taps, shortcuts, deep links.
6. **`ACCESS_LOCAL_NETWORK`** runtime permission if any LAN feature is ever added.

## 7. Identity and branding

- Internal label and code paths: "NothingUI".
- Play display label: **DotWel Launcher** (single l), owner-confirmed 2026-11-21. Applies to the
  Play app and launcher-activity labels only; github/nightly keep the inherited Lawnchair branding.
  This is a display label, not a claim of trademark/name clearance.
- Play listing name, icon, screenshots and keywords must not contain "Nothing" until clearance.
  Describe as "minimalist monochrome, dot-matrix inspired". The public Play listing name remains
  OPEN (see §9).
- Keep Apache `NOTICE` and file headers for all forked code.

## 8. Verification

| Gate | Command |
|---|---|
| Import compiles untouched | `./gradlew assembleLawnPlayDebug` |
| Style | `./gradlew spotlessCheck` |
| Unit tests | `./gradlew testLawnPlayDebugUnitTest` |
| Merged manifest is Play-safe | manifest guard script in CI |
| Widget memory | `adb shell dumpsys appwidget` on the Android 17 emulator |
| Cold start | Macrobenchmark, budget ~700 ms mid-range |

## 9. Open items (release blockers, not build blockers)

1. **Public Play name** — trademark clearance (Play search, domain, USPTO/EUIPO, social handles).
2. **Repo name** — `NothingOS-Launcher-` contains Nothing's OS mark and a trailing hyphen; rename
   before any public push.
3. Monetization shape, if any.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Widget memory exceptions at 37 | Budget enforced in the widget base class from the first widget; CI emulator check. |
| Inherited hidden-API code vs API 37 lockdown | Audit `hidden-api`/`compatLib` before release; emulator lane. |
| Tablet/foldable grid breakage | Derive from `WindowMetrics`; explicit resize tests. |
| Upstream divergence | Keep `upstream` remote, merge deliberately, never blind. |
| Play rejection over permissions | Manifest overlay + CI guard + Console declarations in the same PR. |
