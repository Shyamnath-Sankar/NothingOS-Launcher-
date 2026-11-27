# NOTICE

## Third-party attribution

This project is a derivative work of **Lawnchair 16**, which is itself a derivative of the
**Android Open Source Project (AOSP) Launcher3**.

| | |
|---|---|
| Upstream project | https://github.com/LawnchairLauncher/lawnchair |
| Upstream branch | `16-dev` |
| Base commit | `ebc3ac9fab` ("chore(deps): update plugin diffplug-spotless to v8.12.0 (#7573)") |
| Imported on | 2026-11-21 |

Copyright (c) 2005-2008, The Android Open Source Project
Copyright (c) 2024, Lawnchair

Licensed under the Apache License, Version 2.0. See [`LICENSE.txt`](LICENSE.txt).

### Statement of changes (Apache License 2.0, section 4(b))

This repository contains modifications and additions to the upstream work: the NothingUI design
layer (`lawnchair/src/app/nothingui`), a Play Store manifest overlay (`play/AndroidManifest.xml`),
original widgets and wallpapers, branding, and build/CI configuration.

## Original contributions

The original work in this repository — the NothingUI/DotWel Launcher design layer, the Play
manifest overlay and guard scripts, the original widgets and wallpapers, and the build/CI
configuration — is:

Copyright (c) 2026 the DotWel Launcher project contributors

and is licensed under the Apache License, Version 2.0 (see [`LICENSE.txt`](LICENSE.txt)), the same
license as the upstream work it builds on.

### History note

The upstream commit history was intentionally squashed into a single initial commit to keep the
repository small. Upstream commits are therefore **not** present in this repository. To review or
merge upstream changes, add the upstream remote:

```bash
git remote add upstream https://github.com/LawnchairLauncher/lawnchair.git
git fetch upstream 16-dev
```

## Third-party widget renderer

The battery widget's dot-matrix numerals/bar use an adapted copy of `DotText.kt` from
[`oceansde012/dotline-widgets`](https://github.com/oceansde012/dotline-widgets) at commit
`b53a12aaf09f3572582dbd2c4278ea65f6a83306`, Copyright (c) 2026 oceansde012, licensed under the MIT
License. The full license text, provenance and the list of changes are in
[`licenses/third-party/dotline-widgets-MIT.txt`](licenses/third-party/dotline-widgets-MIT.txt).
Only the self-drawn renderer was adapted; no upstream app, providers, media/ticker services, fonts
or assets were copied.

## Dotwel widget set

The Dotwel widget set is ported from
[`Shyamnath-Sankar/Dotwel-Widgets`](https://github.com/Shyamnath-Sankar/Dotwel-Widgets) at commit
`b0330f873c8f97682ddf6b735e6210a14b14fc8a`, Copyright (c) 2026 the Dotwel Widgets contributors,
licensed under the MIT License. The port excludes all weather widgets and does not declare a
notification-listener service. Full provenance and the MIT license texts are in
[`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md),
[`licenses/third-party/awesomeawidgets-MIT.txt`](licenses/third-party/awesomeawidgets-MIT.txt) and
[`licenses/third-party/kwgt-widgets-MIT.txt`](licenses/third-party/kwgt-widgets-MIT.txt). The texts
are also bundled as `lawnchair/res/raw/awesomeawidgets_mit.txt` and
`lawnchair/res/raw/kwgt_widgets_mit.txt`.

## Trademarks

NothingUI is an internal codename for this fork; the intended Play display label is **DotWel
Launcher**. This is an independent project and is **not** affiliated with, endorsed by, or sponsored
by Nothing Technology Limited. "Nothing", "Nothing OS" and "Nothing Launcher" are trademarks of
Nothing Technology Ltd. This project ships no Nothing assets (fonts, wallpapers, icons, weather art
or screenshots) and uses only original artwork and open-licensed (OFL) fonts.

The DotWel Launcher display label is not a claim of trademark or name clearance. The public Play
listing name remains an open release blocker.

Google, Android and Google Play are trademarks of Google LLC.
