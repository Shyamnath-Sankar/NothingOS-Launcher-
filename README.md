# NothingUI Launcher (working name)

An Android home-screen replacement inspired by monochrome, dot-matrix design. Built as a fork of
[Lawnchair 16](https://github.com/LawnchairLauncher/lawnchair) (`16-dev`, Apache 2.0).

> **Not affiliated with Nothing Technology Limited.** "Nothing", "Nothing OS" and "Nothing Launcher"
> are trademarks of Nothing Technology Ltd. This project is an independent, inspired work and ships
> no Nothing assets. The current name is a working codename; the public Play listing name must be
> cleared before release.

## Status

Early setup. The base fork has not been imported yet. See [AGENTS.md](AGENTS.md) for the plan,
conventions and Play Store compliance invariants.

## Stack (inherited from Lawnchair 16)

- Kotlin 2.4.x, Jetpack Compose, AOSP Launcher3
- Gradle 9.9.2, AGP 9.5.2, JDK 21
- `compileSdk` / `targetSdk` 37, `minSdk` 26
- Variants: `lawnWithQuickstepPlay` (Play), `lawnWithQuickstepGithub`, `lawnWithQuickstepNightly`

## Build

```bash
./gradlew assembleLawnWithQuickstepPlayDebug
```

## Docs

- [AGENTS.md](AGENTS.md) — architecture, CI, Play policy invariants
- `docs/superpowers/specs/` — design specs
