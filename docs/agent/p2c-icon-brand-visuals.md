# P2c — expected Play icon and brand visuals

This page is the screenshot-review checklist for the P2c rebrand slice. It describes what a
coordinator should see in a Play (`lawnWithQuickstepPlayDebug`) build. It does not claim a visual
pass; the pass requires an emulator screenshot reviewed by a human.

## Launcher icon

- Artwork is original and geometric: a 3×3 dot grid on a near-black field.
- Background: `#0B0B0B` (near-black, not pure black).
- Dots: eight white `#FFFFFF` circles, radius 5.5 units on a 108×108 viewport, spaced 18 units
  apart and centred inside the adaptive-icon safe zone.
- Accent: exactly one dot, the top-right one, is `#D7261E` (restrained red). No other red.
- Adaptive layers: `play/res/mipmap-anydpi-v26/ic_launcher_home.xml` and
  `ic_launcher_home_round.xml`; both reference the same Play-only background, foreground and
  monochrome drawables.
- Monochrome layer: the same nine dots in white only, so Android 13+ themed icons tint correctly
  and do not keep a red dot.
- In-app surfaces (`R.drawable.ic_launcher_home`, `ic_launcher_home_comp`) use a rounded-square
  version of the same grid for gesture preferences, search and the About screen.
- API 26+ resolves the adaptive icon through `mipmap-anydpi-v26`; the round variant exists so
  legacy round-icon requests resolve to the same artwork.
- No Nothing marks, NDot/NType glyphs, or traced Nothing shapes are used.

## Text

- Application label and launcher-activity label: `DotWel Launcher` (single l).
- About screen and app-name dialog text (`derived_app_name`): `DotWel Launcher` on Play only.
- Onboarding smartspace title: `Welcome to DotWel Launcher!` on Play only. Every locale that has an
  upstream `onboarding_welcome` translation gets a Play override with the same localized greeting
  and the DotWel Launcher brand token.
- `github` and `nightly` builds keep the inherited Lawnchair labels and strings.
- `NOTICE.md` keeps the Lawnchair/AOSP attribution, the Apache License reference, and the DotWel
  Launcher display-label note.

## Screenshot inspection checklist

Capture on an API 37 emulator after installing the Play debug APK:

1. **Home / app icon** — the DotWel dot-grid icon appears for the launcher in the app list, app info,
   home-role picker, or recents entry. It must not be the inherited Lawnchair icon.
2. **App info** — the app name is `DotWel Launcher`, not `Lawnchair`.
3. **About screen** — the icon is the DotWel dot grid and the title is `DotWel Launcher`.
4. **Onboarding card** (if shown) — the title reads `Welcome to DotWel Launcher!`, not
   `Welcome to Lawnchair!`.
5. **Round-icon surface** (if exposed by the launcher) — the round variant resolves and shows the
   same dot grid, not a blank or broken icon.
6. **Non-Play control** — a `github` or `nightly` build still shows its inherited Lawnchair
   branding. This is a control check, not a Play screenshot.

The CI35 screenshot showed the inherited Lawnchair home surface. That is expected for this slice:
P2c changes the icon and brand text only. A still-inherited workspace layout is **not** a P2c
regression, but a still-inherited Lawnchair icon, app name, About title, or welcome title is.

## Static checks

Run without Gradle:

```bash
sh scripts/play-brand-guard.sh .
sh scripts/play-brand-guard-test.sh
sh scripts/verify-play-build-test.sh
```

`verify-play-build.sh` also runs the brand guard against the repository when `play/res` exists, so
the CI job that already calls it exercises these checks.
