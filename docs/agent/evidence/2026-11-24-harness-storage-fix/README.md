# Weather runtime harness storage fix — compile evidence (2026-11-24)

## Finding (CI 31845396672666)

The native Weather harness executed six cases and all six failed before any
transport request. Retained logcat showed `ContextImpl` failing to ensure
`/data/user/0/com.launchernos.dotwellabs.debug.test/no_backup`.

Root cause: `WeatherRuntimeInstrumentation` passed its own test-APK `context`
to the harness. An instrumentation process executes under the **target**
application uid, so the test APK's data directory is not writable. The harness
therefore could not create case directories or persist its synthetic owner
consent, which produced six misleading failures rather than one storage
failure. This was not a Weather network/forecast failure.

## Fix (harness only)

- The runner still requires `harnessContext.packageName == target.packageName + ".test"`,
  but now passes the **target** context to the harness and fails closed unless
  `Process.myUid() == target.applicationInfo.uid`.
- The harness opens a unique `dotwel-weather-harness-test/run-*` subtree under
  the target app's `noBackupFilesDir`, canonicalizes and contains it, and
  rejects any overlap with the production `dotwel-weather-private` directory.
- A real write/read/delete probe runs **before** any case. A failure returns a
  single `storage-preflight` case with an actionable message.
- Cleanup deletes only this invocation's unique run directory; the shared root
  is removed only when this run created it and it is empty. Pre-existing
  storage is never deleted.
- Production consent, cache, throttle, manifests, workflows, SDK levels,
  applicationId and network policy are untouched. The fake application
  interceptor still never calls `chain.proceed`, and the owner case remains a
  synthetic seam.

## Actual compile (not a stub)

```
JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
ANDROID_HOME=/usr/local/lib/android/sdk
timeout 900 ./gradlew assembleLawnWithQuickstepPlayDebugAndroidTest --stacktrace
```

Result: **BUILD SUCCESSFUL in 8m 17s**, 660 tasks (497 executed, 163 from
cache), 0 compiler errors. The generated test APK is:

- package `com.launchernos.dotwellabs.debug.test`
- runner `app.nothingui.weather.harness.WeatherRuntimeInstrumentation`
- targetPackage `com.launchernos.dotwellabs.debug`
- SHA-256 `14500ea774043c1ec068596faa8687b5bbbc1d7977ded10e571dbd331ce3ed0e`

`test-apk-badging.txt` and `test-apk-manifest.xmltree` are the real
build-tools 37.0.0 dumps. `compile-summary.txt` and `tool-versions.txt` record
the actual task result and toolchain.

## Executed shell verification (no emulator, no CI trigger)

- `sh scripts/emulator-smoke-test.sh` → **1361 ok, 0 not ok**, all passed
  (1352 baseline + 9 context/storage assertions).
- `sh scripts/nothingui-weather-guard.sh` → ok.
- `sh scripts/nothingui-weather-guard-test.sh` → all passed.
- `sh scripts/emulator-smoke-drawer-test.sh` → all passed.
- `sh -n scripts/emulator-smoke-test.sh` → clean; `git diff --check` → clean.

Not run/claimed: no emulator, no `am instrument`, no device runtime, no actual
CI rerun for this commit, no live MET request and no release/signing/hosting.
