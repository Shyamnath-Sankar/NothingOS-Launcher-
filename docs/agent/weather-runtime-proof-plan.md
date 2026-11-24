# Weather runtime proof — research-only plan

Status: **research only**. No harness, build type, network toggle or activation-policy change was
implemented in the 2026-11-24 copy-correction run. The parent decides whether to schedule this.

## Purpose

Prove the real MET work graph, OkHttp transport and HOME lifecycle gates at runtime without
production keys, release signing or Play credentials. This closes the gap left by pure-JVM tests:
those prove policy and composition with fakes, not OkHttp, Compose or the Android lifecycle.

## Current production boundary (do not change in the correction)

- `WeatherNetworkMode.isEnabled(BuildConfig.DEBUG)` keeps debug/test builds network-off and release
  builds on the real opt-in path.
- `WeatherHomeRuntime` builds the real `MetWeatherRepository` only through `WeatherWorkFactory`
  with the app-private no-backup cache, persisted throttle and owner-backed session provider.
- Debug settings copy is explicitly setup-only; release copy discloses coordinate and device-IP
  transmission to MET Norway. No exported or runtime test switch exists.

## Proposed small harness (parent decision)

1. **Native instrumentation test APK in CI** (`connectedLawnWithQuickstepPlayDebugAndroidTest` or a
   dedicated instrumentation task). Do not add a new build type and do not change
   `WeatherNetworkMode`.
2. **Fake transport at the existing pure seam.** `WeatherWorkFactory.create` already accepts a
   `WeatherHttpTransport`. Instrumentation injects a fake/loopback transport in-process, so no
   production endpoint, key or signing material is needed.
3. **Single endpoint proof.** Run one test that uses a local `MockWebServer`/loopback stub and
   asserts the OkHttp request shape: method, URL path, four-decimal coordinates, project
   User-Agent, conditional `If-Modified-Since`/`Expires` handling, timeout and response parsing.
   A real MET hit stays out of CI unless the parent supplies a dedicated CI-only endpoint policy.
4. **Lifecycle proof.** Drive the real launcher/settings through `ActivityScenario` or a test
   activity: verify no request while paused/off HOME, screen-off cancellation, late-result fencing,
   cache/throttle persistence, and the disabled/revoked cache clear.
5. **Evidence.** Upload the test APK logs, `dumpsys appwidget`, request stubs and assertions. Assert
   no wake lock, worker, alarm, service or device-location access is present.

## Explicit non-goals in this correction

- No new build type.
- No debug network toggle or exported/runtime backdoor.
- No change to the production opt-in policy.
- No production key, release signing or hosting change.

## Blockers for execution

- CI network policy and a decision on loopback-only versus a real CI endpoint.
- Parent approval to add the instrumentation harness.
- A release-build live forecast test remains a separate gate; it must not be claimed from debug
  setup-only evidence.
