# Compile-only native test-APK preflight — 2026-11-24

Task: `home-widget-composition-v1-new`, compile-only native test-APK preflight on
`24d8f98`, before any emulator run. This is the actual AGP/Kotlin/test-manifest
build in the existing GitHub Actions coding runner. It is not an emulator,
instrumentation or runtime proof.

## Runner environment

| Item | Value |
|---|---|
| `JAVA_HOME` | `/usr/lib/jvm/temurin-21-jdk-amd64` |
| Java | OpenJDK 21.0.13 (Temurin) |
| `ANDROID_HOME` / `ANDROID_SDK_ROOT` | `/usr/local/lib/android/sdk` |
| compile SDK | `android-37.2` (release 37, minor 2) |
| build-tools | `37.0.0` |
| Gradle | 9.9.2 (wrapper, unchanged) |
| AGP | 9.5.2 (unchanged) |
| Kotlin | 2.4.21 (unchanged) |

Platform 37.2 and build-tools 37.0.0 were already installed. No SDK install,
repository configuration, workflow, dependency, Gradle or product change was
made.

## Commands actually run

```sh
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME=/usr/local/lib/android/sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
timeout 900 ./gradlew assembleLawnWithQuickstepPlayDebugAndroidTest --stacktrace
timeout 900 ./gradlew assembleLawnWithQuickstepPlayDebug --stacktrace
```

## Results

| Build | Result | Duration | Log |
|---|---|---|---|
| `assembleLawnWithQuickstepPlayDebugAndroidTest` | **BUILD SUCCESSFUL**, 660 tasks (497 executed, 163 cached) | 6m 11s | `gradle-test-apk.log` |
| `assembleLawnWithQuickstepPlayDebug` | **BUILD SUCCESSFUL**, 643 tasks (20 executed, 622 up-to-date) | 1m 14s | `gradle-prod-apk.log` |

The production debug APK was assembled only to prove the harness is absent and
to record its hash. No runtime behaviour is claimed for either APK.

## Test APK

```text
build/outputs/apk/androidTest/lawnWithQuickstepPlay/debug/lawnchair-lawn-withQuickstep-play-debug-androidTest.apk
sha256 f540599ce1ffacfeedf877d39bb280bbb619a4c5d364186eaf6e63d2b2b77348
```

Actual generated instrumentation contract from the test APK manifest
(`test-apk-manifest-aapt2.txt`):

```text
package: name='com.launchernos.dotwellabs.debug.test'
instrumentation name='app.nothingui.weather.harness.WeatherRuntimeInstrumentation'
instrumentation targetPackage='com.launchernos.dotwellabs.debug'
```

This matches the smoke-shell contract:

```text
PKG=com.launchernos.dotwellabs.debug
WEATHER_HARNESS_TEST_PKG="$PKG.test"                    # com.launchernos.dotwellabs.debug.test
WEATHER_HARNESS_RUNNER=app.nothingui.weather.harness.WeatherRuntimeInstrumentation
WEATHER_HARNESS_COMPONENT="$WEATHER_HARNESS_TEST_PKG/$WEATHER_HARNESS_RUNNER"
```

The runner class is dotted, not slash-separated. The harness source is only in
`tests/androidTest/java`, wired through the dedicated `androidTest` source set
in `build.gradle`, and the runner passes its own test-APK `context` and fails
closed unless the package is `<target>.test`.

## AAPT2 compatibility finding and fix

`find_aapt` prefers `aapt2`, but the old command was:

```sh
"$AAPT" dump xmltree "$apk" AndroidManifest.xml
```

Real build-tools 37.0.0 `aapt2` rejects that with exit 1:

```text
missing required flag --file

dump xmltree [options] --file arg files...
```

`aapt2` requires `--file AndroidManifest.xml`; legacy `aapt` accepts only the
positional name. The smoke script now calls the compat helper
`aapt_dump_xmltree`, which selects the correct form from the tool basename.
Both branches were executed against the real test APK with the real SDK tools:

| Tool | Evidence | Result |
|---|---|---|
| `aapt2` | `test-apk-helper-real-aapt2.txt` | exit 0, manifest printed |
| `aapt` | `test-apk-helper-real-aapt1.txt` | exit 0, manifest printed |
| old `aapt2` positional form | `test-apk-old-positional-failure.txt` | exit 1, `missing required flag --file` |

The executed regression in `scripts/emulator-smoke-test.sh` now makes the
fixture `aapt2` stub reject the old positional syntax, asserts the exact
`--file` call, and adds a legacy-`aapt` scenario asserting positional syntax.
`emulator-smoke-test.sh` reports **1255 ok, 0 not ok**.

## Production APK harness-absence checks

```text
build/outputs/apk/lawnWithQuickstepPlay/debug/Lawnchair.16.Dev.(#118).play.debug.apk
sha256 aa508f3839a598ae02db8e676a3bcbfdbbd08e732f42ac07efb37545b3538595
package com.launchernos.dotwellabs.debug
```

`prod-apk-harness-absence.txt` records:

```text
instrumentation_entries_in_prod_manifest=0
harness_markers_in_prod_manifest=0
harness_class_strings_in_prod_dex=0
harness_class_strings_in_test_dex=46
```

No `WeatherRuntimeInstrumentation`, harness class, or test instrumentation entry
is present in the production APK. No exported app switch, debug network policy,
manifest permission, applicationId, SDK level, workflow or product source was
changed in this run.

## Other verification actually run

| Check | Result |
|---|---|
| `sh scripts/emulator-smoke-test.sh` | 1255 ok, 0 not ok |
| `sh scripts/nothingui-weather-guard.sh` | pass |
| `sh scripts/nothingui-weather-guard-test.sh` | pass |
| `sh scripts/verify-play-build-test.sh` | pass |
| `sh scripts/emulator-smoke-drawer-test.sh` | pass |
| `sh scripts/verify-android-resources.sh` | aapt2 compile OK |
| `sh -n scripts/emulator-smoke.sh scripts/emulator-smoke-test.sh` | clean |
| `git diff --check` | clean |

## Not run / not claimed

- No emulator, no `am instrument`, no `emulator-smoke.sh` device run.
- No MET request, forecast, API, private widget, paid, merge, release, signing
  or hosting action.
- No runtime, pixel, lifecycle or device behaviour is proven here. This is a
  compile and test-APK manifest/AAPT preflight only.
