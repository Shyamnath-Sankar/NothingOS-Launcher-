# Agent build state

Updated by the agent-dev workflow at the end of every run. The next dispatch reads this file
when no task input is given, and continues from "next".

- current_phase: **CI#329 `build-debug-apk` wallpaper-guard true-black fix on
  `agent/ci-329-build-debug-apk-fails-a`; local guard green, PENDING ACTUAL CI.**
  The guard no longer hardcodes the pre-ktlint `Black` constant name. It finds the
  `0xFF000000` background constant by value, requires it to be the `backgroundArgb` default and
  the full-surface fill (dots/lines/accent stay separate, non-black paints), and, when the real
  Play APK exists, reads the compiled `NothingWallpaperColors` background constant from
  `classes.dex` and requires exactly `-16777216`.
- branch: `agent/ci-329-build-debug-apk-fails-a`
- head: `d8118a9` (plus this docs commit); branch pushed and tracking `origin`.
- pr: **not created in this run** (no `gh` auth/token in the runner). Open a PR at
  https://github.com/Shyamnath-Sankar/NothingOS-Launcher-/pull/new/agent/ci-329-build-debug-apk-fails-a
- ci: **not run here** (no Gradle/APK/emulator/CI by instruction). Local guard is green; the
  compiled-dex path was exercised against a `d8`-compiled dex built from the real
  `NothingWallpaperArt.kt`. The pushed branch is the CI trigger.
- next: let CI run `build-debug-apk` (`verify-play-build.sh` → wallpaper guard) against the real
  Gradle-built Play APK; open the PR.
- blockers: no PR from this runner (gh unauthenticated); no real Gradle-built APK, emulator or CI
  here.

## done (this run — CI#329 wallpaper guard true-black reconciliation on `agent/ci-329-build-debug-apk-fails-a`, shell/dex-only)

- **Exact CI#329 cause, not a guess:** `scripts/nothingui-wallpaper-guard.sh` still grepped
  `const val Black: Int = 0xFF000000.toInt()`. CI#328 renamed that ktlint-invalid constant to
  `BLACK` (`NothingWallpaperArt.kt:31`), so the grep failed and the guard exited with
  `the procedural background is not true black` before any APK check.
- **Background, not accent, is checked:** the source check now finds the `NothingWallpaperColors`
  constant whose value is exactly `0xFF000000.toInt()` (whatever its name), requires
  `NothingWallpaperSpec.backgroundArgb` to default to it, and requires the renderer to paint the
  whole surface with `spec.backgroundArgb` before any `canvas.drawCircle`. `dotArgb`, `lineArgb`
  and `accentArgb` must stay separate paints, so the non-black dots/lines/accent are explicitly
  allowed and are never treated as the base. A rename back to `Black` still passes; a non-black
  background fails.
- **Strict against the real compiled APK:** when `build/outputs/apk/lawnWithQuickstepPlay/debug`
  contains APK(s), the guard extracts each `classes*.dex`, finds the compiled
  `Lapp/nothingui/wallpaper/NothingWallpaperColors;` class with `dexdump -f`, and requires the
  source-named background field to equal `-16777216` (`0xFF000000`). It locates `dexdump` via
  `PATH`/`ANDROID_HOME`/`ANDROID_SDK_ROOT` build-tools (highest version) and fails closed when an
  APK exists but the constant cannot be verified. The existing Torus `STRING_TOO_LARGE` sentinel
  check is unchanged.
- **Unit lock:** new `NothingWallpaperArtTest.backgroundIsExactlyOpaqueBlack` asserts
  `NothingWallpaperColors.BLACK` and all three procedural specs are exactly `0xFF000000`; the
  guard requires that test to exist.
- **Verification actually run (shell/dex only; no Gradle, real APK, emulator or CI):**
  `sh -n scripts/nothingui-wallpaper-guard.sh` clean; `sh scripts/nothingui-wallpaper-guard.sh`
  OK with no build (skips the APK check); compiled `NothingWallpaperArt.kt` with `kotlinc`, `d8`
  to `classes.dex`, verified `dexdump` reports `BLACK=-16777216` and `ACCENT_RED=-2677218`;
  packaged that dex plus the real Torus XML into a synthetic APK and the guard reported
  `compiled background BLACK is 0xFF000000` and OK; a `BLACK=0xFF000001` dex made the guard exit
  1 with `BLACK=-16777215, not 0xFF000000`; a `Black`-renamed source copy still passed the
  source check; `git diff --check` clean.
- **Missing evidence / not claimed:** no `./gradlew assembleLawnWithQuickstepPlayDebug` (execution
  rule says the PR triggers CI), no real Gradle-built APK, no emulator and no actual CI. The
  `verify-play-build-test.sh` suite was started but exceeded the 120 s tool timeout; its fixture
  roots skip the wallpaper guard, so it is not evidence either way. CI `build-debug-apk` is the
  final proof that the guard passes on the real APK.

## done (previous run — CI#328 Spotless fixes on `agent/fix-the-two-spotlesscheck-fail`, Gradle Spotless verified)

- **Failure 1 (property-naming):** `lawnchair/src/app/nothingui/wallpaper/NothingWallpaperArt.kt`
  `NothingWallpaperColors` used PascalCase `const val` names. Renamed to `BLACK`, `PAPER`,
  `GRAY_900`, `GRAY_700`, `GRAY_500`, `ACCENT_RED`; updated the spec defaults and
  `NothingWallpaperArtTest`. ARGB values are unchanged.
- **Failure 2 (paren-spacing):** `LazyColumnPreferenceGroup.kt` split each `@Composable()`
  annotation from its function-type parameter. ktlint 1.8.0 `standard:paren-spacing` flagged lines
  45 and 80 and the formatter could not resolve them ("Format was not able to resolve all
  violations"). Moved each annotation and type onto the parameter line. Formatting only.
- **Root cause evidence, not a guess:** the first `./gradlew spotlessApply` failed with the exact
  property-naming error at `NothingWallpaperArt.kt:L31`. The standalone ktlint 1.8.0 CLI (repo
  `.editorconfig` + the compose ruleset jar) then reported `standard:paren-spacing` at `45:18` and
  `80:18` on the original file and **exit 0** on both changed files after the fixes.
- **Verification actually run:** `./gradlew spotlessApply` → BUILD SUCCESSFUL;
  `./gradlew spotlessCheck --no-build-cache --no-configuration-cache --rerun-tasks` →
  **BUILD SUCCESSFUL**, 4 tasks executed; standalone ktlint 1.8.0 on both changed Kotlin files →
  exit 0; `grep` confirms no PascalCase `NothingWallpaperColors.` references remain. No app
  build/APK/emulator and no CI run here.
- **Missing evidence / not claimed:** no CI re-run and no APK. Local Spotless uses the same pinned
  ktlint 1.8.0 and repo config as CI, but the CI `check-style` job is the final proof.

## done (previous run — CI#327 default-launcher warning lookup on `agent/fix-the-ci-327-emulator-smoke`, shell-only)

- **CI#327 identity:** run `45877156543`, job `140107026048`, step `API 37 install and home smoke`
  failed with `settings did not expose the default-launcher warning`. The log/artifact requires auth
  unavailable in this runner, so the cause is source-derived, not guessed.
- **Root cause:** `PreferencesDashboard` renders `PreferencesSetDefaultLauncherWarning()` in a
  `PreferenceLayout` → `PreferenceColumn` Compose `verticalScroll` Column. The old smoke captured
  `role-consent-settings.xml` once and required `grep -Fq 'default launcher'`, so a delayed compose,
  a clipped card, or a shifted/restored scroll position false-failed.
- **Library helpers:** `ui_label_contains_bounds` returns the first node bounds whose
  text/content-desc contains a literal substring; `ui_label_contains_within` returns those bounds only
  when the whole rectangle sits inside the supplied viewport. Both fail closed on missing input, empty
  needle, empty viewport or malformed bounds.
- **Bounded finder:** `find_settings_default_launcher_warning` recaptures the hierarchy up to
  `2 × max` times, measures the strict scroll container (then the known settings container, then the
  root), finds the warning, and only accepts a fully visible rectangle. When clipped/absent it swipes
  inside the measured viewport in the measured direction, logs every attempt to
  `settings-warning-<tag>.txt`, and retains `settings-warning-<tag>-visible.xml` on success. It never
  taps and returns non-zero on exhaustion.
- **Consent wiring:** `verify_default_home_consent` now calls the finder, copies the found hierarchy to
  `role-consent-settings.xml`, captures `role-consent-settings.png`, runs the inherited-announcement
  check, and taps only the finder-measured bounds. The exact fail strings are preserved.
- **Tests:** 14 new shell assertions (8 static + 6 fixture) pin the finder helpers, the bounded loop,
  the measured swipe, the consent wiring and the tap-on-finder-bounds behavior; fixtures reject a
  clipped warning, the default-home active status and an empty viewport.
- **Docs:** `docs/agent/emulator-verification.md` now describes the bounded search/scroll lookup.
- **Verification actually run (shell only; no Gradle, Android build, emulator or CI):**
  `sh scripts/emulator-smoke-test.sh` → **1376 ok, 0 not ok, all passed** (1362 baseline + 14);
  `sh scripts/emulator-smoke-drawer-test.sh` all passed; `sh scripts/verify-play-build-test.sh` all
  passed; `sh scripts/nothingui-home-guard-test.sh` all passed;
  `sh scripts/nothingui-home-role-guard-test.sh` all passed; `sh scripts/nothingui-home-role-guard.sh`
  OK; `sh scripts/nothingui-wallpaper-guard.sh` OK; `sh scripts/nothingui-theme-guard.sh` OK;
  `sh -n` clean on all three edited scripts; `git diff --check` clean.
- **Missing evidence / not claimed:** no CI run for this branch, no APK, no emulator, no uiautomator
  dump from a device. The finder is fixture/source-verified; the actual Compose hierarchy and the
  real `RoleManager` consent flow remain unproven until the API 37 lane runs.

## done (previous run — procedural AMOLED true-black wallpapers on `agent/add-a-curated-set-of-amoled-fr`, shell/kotlinc-only)

- **Original art, no fetched assets:** new `NothingWallpaperArt.kt` defines the palette ARGB values,
  three motifs (`DOT_GRID`, `HORIZON`, `GLYPH`), a resolution-independent spec and deterministic
  geometry. `NothingWallpaperRenderer.kt` draws the same geometry to an ARGB bitmap for both the
  gallery preview and `WallpaperManager.setBitmap`.
- **True black + palette:** every background is `#000000`; dots use `#3A3A3A`, the horizon line and
  glyph centre use `#6E6E6E`, and the single accent line-dot/ring uses `#D7261E`. The unit test pins
  these to `NothingUiPalette`.
- **Phone sizes:** `NothingWallpaperSizes` curates `1080x1920`, `1080x2160`, `1080x2340`,
  `1080x2400`, `1440x3120`, `1440x3200`. `bestFor` normalizes the display to portrait, picks the
  closest aspect ratio and prefers the smallest covering size; invalid dimensions fall back safely.
- **Catalog + applier:** `AmoledWallpaperKind.PROCEDURAL` and a `spec` field were added. The three
  procedural choices sit beside Pitch Black and Wireframe Torus. `AmoledWallpaperApplier` renders
  the chosen size from `WindowMetrics` (API 30+) or `displayMetrics` and still sets only
  `FLAG_SYSTEM`, checks support/policy and confirms the returned Home id.
- **Picker:** `AmoledWallpaperPreferences` now lays the five tiles out in rows of three, and
  `WallpaperArtwork` renders procedural previews from the shared renderer with `ContentScale.Crop`.
  The existing apply/Cancel/credit/licence flow is unchanged.
- **Docs:** `docs/wallpapers/README.md` documents the procedural motifs, palette, sizes and the
  no-fetch/no-permission policy. `strings.xml` gains the three titles, a shared procedural credit and
  an updated gallery description.
- **Guard + tests:** `scripts/nothingui-wallpaper-guard.sh` now requires the five-entry catalog, the
  three procedural specs, true-black ARGB, the size catalog, the shared renderer and the applier
  branch, and rejects file/provider/network reads in the procedural sources. New
  `NothingWallpaperArtTest` covers palette sync, size selection, geometry determinism/bounds and
  every procedural choice at every size; `AmoledWallpaperCatalogTest` was updated to five entries.
- **Verification actually run (shell/kotlinc only; no Gradle, Android build, emulator or CI):**
  `kotlinc` compiled `NothingWallpaperArt.kt` (`rc=0`) and a pure JVM check passed exact/nearest/
  covering/invalid size selection, deterministic in-bounds geometry for all 6 sizes × 3 motifs, and
  invalid-spec rejection. `kotlinc` compiled the art + renderer + catalog + target + applier against
  `android-37.2/android.jar` with minimal R/annotation/coroutines stubs (`rc=0`), and compiled both
  unit tests with R/Compose/JUnit stubs (`rc=0`). `sh scripts/emulator-smoke-test.sh` reports
  **1362 ok, 0 not ok**; `sh scripts/verify-play-build-test.sh` all passed;
  `sh scripts/nothingui-wallpaper-guard.sh` OK; `sh scripts/nothingui-theme-guard.sh` OK;
  `sh -n` clean on the edited guard; `python3` XML parse of `strings.xml` OK; `git diff --check`
  clean.
- **Missing evidence / not claimed:** no APK, no Compose render, no device/emulator apply, no
  `dumpsys wallpaper` and no actual CI. The bitmap/`WallpaperManager` path and the Compose preview
  are source/type-verified only; the new procedural tiles were not applied on a device in this run.

## done (previous run — backup create/restore safely re-enabled on `agent/rebuild-backup-create-and-rest`, source/JVM-only)

- **Pure core:** new `lawnchair/src/app/lawnchair/backup/BackupArchive.kt` writes a zip with a
  trailing `manifest.txt` (format header + SHA-256, size and name per entry), validates the manifest
  and every payload digest/size before extraction, rejects missing/extra/duplicate/traversal entries
  and oversized payloads, and extracts into a private staging directory with a second digest check.
- **Atomic swap with rollback:** `RestoreTransaction` copies each existing target into a private
  rollback directory, moves the verified staged file into place with an atomic rename, and restores
  every already-swapped target on any failure. It never calls `deleteRecursively` on a live database
  or data directory and never deletes/moves user data before the staged replacement is verified.
- **Android wiring:** `LawnchairBackup.create` builds `info.pb`, wallpaper, screenshot and the
  launcher DB/shared prefs/preferences DB/datastore into a private temp archive, then copies it to
  the chosen document; sources are opened read-only. `restore` copies the document to a private temp
  file, validates, extracts to `noBackupFilesDir`, applies the swap, restores the wallpaper last,
  writes the grid state and runs the inherited `RestoreDbTask`; the live grid DB files are backed up
  first and restored on any failure. `BackupOperationResult` is now `Success`/`Failure`/`Unavailable`.
- **UI:** `BackupAndRestorePreference`, `CreateBackupScreen`, `RestoreBackupScreen` and
  `RestoreNovaBackupScreen` are restored with the real actions; `FeatureFlagsPreference` Export/
  Import and `PreferenceNavigation`'s `CreateBackupScreen(viewModel())` are restored. The
  unavailable notice is rendered only when an operation genuinely fails; the string now says the
  existing data was not changed.
- **Tests:** `tests/unit/java/app/lawnchair/backup/BackupArchiveTest.kt` has 14 JVM tests: round
  trip, source immutability, missing manifest/entry, checksum mismatch, truncation, unexpected entry,
  path traversal, corrupt/partial archive leaving targets untouched, valid apply, mid-swap rollback,
  unrelated-file preservation and rollback of newly-created targets.
- **Verification actually run:** `kotlinc` compiled `BackupArchive.kt` + the test with JUnit 4.13.2;
  `JUnitCore` reports **OK (14 tests)**. `LawnchairBackup.kt` + `BackupArchive.kt` compiled with
  `kotlinc` against `android-37.2/android.jar`, the coroutines jar and protobuf 3.25.5 with minimal
  project stubs (`rc=0`). `git diff --check` clean. No Gradle, Android build, emulator or CI.
- **Missing evidence / not claimed:** no APK, no Compose/device run, no actual `RestoreDbTask`
  execution and no CI. Legacy archives without a manifest are intentionally rejected as unsafe;
  the UI/DB finalisation is source-verified only.

## done (previous run — live MET weather enabled on `agent/enable-live-met-norway-weather`, source/shell-only)

- **Production gate:** `WeatherWorkFactory.WeatherNetworkMode.isEnabled` now returns `true` for every
  build, so `WeatherHomeRuntime` builds the real `MetWeatherRepository` and
  `OkHttpWeatherTransport` in the Play debug APK. `NoNetworkWeatherWork` remains only as an explicit
  offline test double.
- **Copy:** `WeatherSettingsCopy.networkEnabled` follows the same policy, so debug settings now show
  the release privacy, forecast, status and enabled-message strings. The debug setup-only resources
  remain in `strings.xml` for the offline seam.
- **Tests:** `WeatherSettingsCopyTest` now expects the release copy for `debugBuild = true` and pins
  `WeatherNetworkMode.isEnabled` true for both modes. `WeatherHomeOwnerTest` still covers
  `NoNetworkWeatherWork`. The instrumentation harness still injects a fake OkHttp interceptor
  through `WeatherWorkFactory`, so it makes no real call.
- **Smoke:** `emulator-smoke.sh` uses `WEATHER_RUNTIME_NOTICE_MODE=release` and the exact release
  enabled message. The enabled persistence proof calls `_weather_restart reload-enabled settings`,
  which force-stops the process but skips HOME; `_weather_open_weather` then reloads Preferences.
  Every other HOME resume runs with consent disabled. `emulator-smoke-test.sh` asserts the release
  copy and the settings-only branch.
- **Guard:** `nothingui-weather-guard.sh` requires `isEnabled(...) = true` and keeps the offline
  placeholder; its mutation suite rejects a policy that disables the live path.
- **Docs:** `docs/agent/emulator-verification.md` and
  `docs/agent/weather-runtime-proof-plan.md` were updated to the live policy.
- **Verification actually run:** `sh scripts/emulator-smoke-test.sh` → all checks passed;
  `sh scripts/nothingui-weather-guard-test.sh` → all passed; `sh -n` on both smoke and guard
  scripts; `git diff --check` clean. No Gradle, Android build, emulator or CI.
- **Missing evidence / not claimed:** no APK, no Compose/device run, no CI. The live debug copy and
  the no-HOME restart are source/shell-verified only.

## done (this run — backup create/restore disabled on `agent/disable-backup-create-and-rest`, source-only)

- **UI layer:** `BackupAndRestorePreference` now renders only `BackupUnavailableNotice`; the create,
  Lawnchair restore and Nova restore rows are gone. `CreateBackupScreen` and `RestoreBackupScreen`
  render the same notice and no longer call `LawnchairBackup.create`/`restore`.
  `RestoreNovaBackupContent` no longer takes an `onRestore` callback and shows the notice instead of
  a Restore button. The developer `FeatureFlagsPreference` Export/Import rows were replaced with the
  notice, so the `CreateBackup` navigation and `restoreBackupOpener`/`restoreNovaBackupOpener` have no
  callers. `restoreBackupOpener` was removed; `restoreNovaBackupOpener` remains defined but uncalled.
- **Non-UI layer:** `LawnchairBackup.restore` and `LawnchairBackup.create` now return
  `BackupOperationResult.UNAVAILABLE` immediately; the destructive bodies (database delete/restore,
  wallpaper set, zip write) were removed. `readInfoAndPreview` is read-only and untouched. No file
  under the app's data, `shared_prefs`, `datastore`, databases, backup files or wallpapers is touched.
- **String:** new `backup_temporarily_unavailable` = "Backup is temporarily unavailable in this build".
- **No tests changed:** no unit test asserted `LawnchairBackup.create`/`restore`; the existing
  `BackupAndRestoreDBSelectionTest` exercises AOSP `RestoreDbTask`, not these UI entry points.
- **Verification actually run (source/grep only; no Gradle, Android build, emulator or CI):**
  `grep -rn "LawnchairBackup\\.create" lawnchair/src` → none; `grep -rn "\\.restore("` in the backup
  and preferences UI → only `Canvas.restore()` in `Placeholder.kt`; `grep -rn
  "restoreBackupOpener()\\|restoreNovaBackupOpener()"` → only the Nova definition, no callers;
  `grep -rn "navigate(CreateBackup)\\|navigate(RestoreBackup"` → none; `LawnchairBackup.kt` shows
  both entries return `UNAVAILABLE`; `python3` XML parse of `strings.xml` OK; `git diff --check`
  clean.
- **Missing evidence / not claimed:** no APK, no Compose UI run, no emulator and no CI. The notice
  and disabled actions are source-verified only.

## done (previous run — native harness storage fix on `969f8a8`, harness-only, PENDING ACTUAL CI)

- **Root cause confirmed, not guessed:** `WeatherRuntimeInstrumentation` passed its own test-APK
  `context` to `WeatherRuntimeHarness.run`. The instrumentation process runs under the target
  application uid, so `context.noBackupFilesDir` resolved to
  `/data/user/0/com.launchernos.dotwellabs.debug.test/no_backup`, which the target uid cannot write.
  Logcat's `ContextImpl failed ensure` and the "owner consent could not persist" detail both trace to
  this one storage-ownership error. The six cases failed before any network/transport assertion.
- **Runner correction:** the isolated identity check is retained
  (`harnessContext.packageName == "${target.packageName}.test"`), but the harness now receives the
  **target** context. A new fail-closed guard requires
  `Process.myUid() == target.applicationInfo.uid` and reports the process/target uids and package.
- **Harness storage:** `openStorage` verifies the process uid, canonicalizes the target app's
  `noBackupFilesDir`, contains `dotwel-weather-harness-test` under it, rejects any overlap with
  `dotwel-weather-private`, checks both `mkdirs`, and uses a unique `run-<millis>-<pid>` directory.
- **Preflight before cases:** a real write/read/delete probe of `storage-probe.txt` runs before the
  six cases. Failure returns exactly one `storage-preflight` case with the actionable storage cause,
  so a future storage fault cannot masquerade as six network failures.
- **Safe cleanup:** only the unique run directory is deleted recursively. The shared harness root is
  removed only when this run created it (`!rootExisted`) and it is empty; pre-existing content is
  never deleted. A cleanup fault is surfaced as a `storage-cleanup` failure.
- **Unchanged contract:** the fake application interceptor still never calls `chain.proceed` (no
  socket, no MET, no permission); the six named cases and the synthetic `owner-lifecycle-seam` are
  unchanged; production consent/cache/throttle and all app source/policy are untouched.
- **Fixtures updated, 1352 baseline + 9:** `sh scripts/emulator-smoke-test.sh` reports **1361 ok,
  0 not ok, all passed**. New assertions pin target-context storage, the process-uid check, canonical
  containment, the separate harness/production names, the write/read/delete probe, the single
  actionable preflight failure, unique-run cleanup, and the absence of `WeatherRuntimeHarness.run(harnessContext)`
  or `WeatherPrivateStorage` in the harness.
- **Actual compile executed (required by this task):** with
  `JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64` (OpenJDK 21.0.13) and
  `ANDROID_HOME=/usr/local/lib/android/sdk` (build-tools 37.0.0), `timeout 900 ./gradlew
  assembleLawnWithQuickstepPlayDebugAndroidTest --stacktrace` → **BUILD SUCCESSFUL in 8m17s, 660
  tasks (497 executed, 163 cached), 0 compiler errors**. Test APK
  `com.launchernos.dotwellabs.debug.test`, runner
  `app.nothingui.weather.harness.WeatherRuntimeInstrumentation`, targetPackage
  `com.launchernos.dotwellabs.debug`, SHA-256
  `14500ea774043c1ec068596faa8687b5bbbc1d7977ded10e571dbd331ce3ed0e`. Evidence:
  `docs/agent/evidence/2026-11-24-harness-storage-fix/`.
- **Other executed checks:** `sh scripts/nothingui-weather-guard.sh` ok;
  `sh scripts/nothingui-weather-guard-test.sh` all passed;
  `sh scripts/emulator-smoke-drawer-test.sh` all passed; `sh -n` clean on the edited script;
  `git diff --check` clean.
- **Missing evidence / not claimed:** no emulator, no `am instrument`, no six-case device result, no
  forecast pixel and no actual CI for `969f8a8`. The previous shell cleanup proof (preinstall
  absence, final present uninstall success, after absence, trap absence) is untouched and not
  regressed.

## done (previous run — awk single-quote repair on `41362cc`, shell-only, PENDING ACTUAL CI)

- **Root cause confirmed, not guessed:** `weather_harness_pm_list_state` is an awk program opened
  with a shell single quote (`awk -v pkg=... '`). Its new/edited comments contained apostrophes:
  `'='` twice (the final-separator and base64-path notes) and the possessive `platform's`. The first
  `'` closed the shell string, so `sh -n scripts/emulator-smoke.sh` reported
  `Syntax error: "(" unexpected` at line 5577 and the extracted
  `weather-presence-functions.sh` failed to parse. This is why the real suite stopped after
  1234 ok even though the wrapper checkpoint was reported green.
- **Fix is comment-only, no escaping:** the three comment lines now say `equals sign`,
  `equals signs`, and `platform framework package`; no backslash was inserted inside the awk block.
  The awk regex, control flow, outputs and every assertion are unchanged.
- **Audited other single-quoted awk comments:** the remaining `awk '...'` blocks in
  `emulator-smoke.sh` (`weather_harness_pm_path_state` and the one-line programs) and the
  multi-line awk blocks in `emulator-smoke-test.sh` contain no apostrophe-bearing comments. The
  only apostrophes left in the fixed block are the two shell delimiters and a `printf` argument
  outside awk.
- **Verification actually executed to a terminal (not inferred from a wrapper):**
  `sh -n scripts/emulator-smoke.sh` → exit 0; `sh -n scripts/emulator-smoke-test.sh` → exit 0;
  `sh scripts/emulator-smoke-test.sh` → **exit 0, 1352 ok, 0 not ok, "all emulator-smoke tests
  passed"**; `sh scripts/nothingui-weather-guard.sh` → ok; `sh scripts/nothingui-weather-guard-test.sh`
  → all passed; `sh scripts/manifest-guard-test.sh` → all passed; `git diff --check` → clean.
- **Required parser fixtures ran and passed:** `a single-component framework package name is valid`,
  `a realistic platform list with the target anchors presence`, `a realistic platform list without
  the target proves absence`, plus the executed orchestration present/absent cases and
  `the platform android row never turns the present target into query failure` /
  `... never turns an absent target into query failure`.
- **Truthful correction:** state 121 (`41362cc`) is recorded as **not validated** (native
  instrumentation is still 0 cases executed here). The new parser does allow a single-component
  `android` package and realistic platform lists with the target present/absent, as proven by the
  fixtures above.
- **Missing evidence / not claimed:** no Android build, emulator, `am instrument`, forecast, APK,
  merge, release or hosting. This run fixes shell parsing and re-runs the shell suite only.

## done (previous run — presence-proof transport hardening on `8662ac4`, shell-only, PENDING ACTUAL CI)

- **Root cause confirmed, not guessed:** `weather_harness_package_state` recorded
  `_whq_enum_status` but only logged it; `weather_harness_presence_state` classified from the
  `pm list` payload and `pm path` alone. A complete valid-looking payload with `PM_ENUM_RC=0` plus
  a nonzero adb transport exit (1 or 124) could therefore prove absence before install or presence
  before cleanup. The old list parser also accepted `package:` lines without `=` as a valid
  non-match, so a corrupt query could read as absence.
- **Fail-closed fix:** the enumeration transport status is now passed into the presence proof, and
  any nonzero status returns `query_failure` regardless of how complete the payload looks. Present
  still requires a successful, non-empty `pm path`; absent still accepts real Android's empty
  `pm path` exit 1 only with a successful enumeration. The logged `presence_state` is the same
  failed final state, with a truthful transport diagnostic.
- **Strict grammar:** `package:/nonempty-path=valid.dotted.package` is required for enumeration
  rows, with the final `=` separating the name so real Android base64 paths that contain `=` stay
  valid. Malformed rows (missing `=`, empty path, empty name, no dot, bad character) are
  `query_failure`, never absence. `pm path` rows now require a non-empty `package:/...` path.
- **Executed regressions:** six orchestration fixtures inject rc1 and rc124 with a complete valid
  payload and sentinel: absent before install, present before cleanup, and absent after uninstall.
  All stay red; the absent/present-before cases never install or uninstall on unproven state, and
  the after-uninstall case reports `result=after_query_failure`, never cleanup success.
- **Demonstrated against the old code:** the pre-fix functions returned `absent` for a complete
  absence payload plus nonzero transport, `present` for a complete presence payload, and `absent`
  for a malformed `package:` line; the fixed functions return `query_failure` for all three.
- **Verification actually run (shell only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **1339 ok, 0 not ok, all passed** (the 1294 baseline
  plus 45 parser/fixture/static checks, including a realistic `==` path); `sh scripts/manifest-guard-test.sh`
  passes; `sh scripts/nothingui-weather-guard.sh` passes;
  `sh scripts/nothingui-weather-guard-test.sh` reports **34 ok, 0 not ok**;
  `sh scripts/emulator-smoke-drawer-test.sh` reports **38 ok, 0 not ok**;
  `sh scripts/verify-play-build-test.sh` reports **13 ok, 0 not ok**; `sh -n` is clean on both
  edited scripts and `git diff --check` is clean.
- **Missing evidence / not claimed:** no Android CI for `d095ce5`, no APK, no emulator, no
  `am instrument`, no forecast and no native Weather execution. The 301 units / 187 Weather tests
  are the parent's CI310 facts, not rerun here. This run is shell-only and does not claim native
  runtime behavior.

## done (previous run — compile-only native test-APK preflight on `24d8f98`, PASSED)

- **Actual AGP/Kotlin build, not a stub:** set `JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64`
  (OpenJDK 21.0.13) and `ANDROID_HOME=/usr/local/lib/android/sdk` (platform `android-37.2`,
  build-tools `37.0.0` already present; no SDK/repository change). Ran
  `timeout 900 ./gradlew assembleLawnWithQuickstepPlayDebugAndroidTest --stacktrace`:
  **BUILD SUCCESSFUL in 6m11s, 660 tasks (497 executed, 163 cached)**. The test APK was generated at
  `build/outputs/apk/androidTest/lawnWithQuickstepPlay/debug/lawnchair-lawn-withQuickstep-play-debug-androidTest.apk`,
  SHA-256 `f540599ce1ffacfeedf877d39bb280bbb619a4c5d364186eaf6e63d2b2b77348`.
- **Real AAPT2 defect found and fixed (harness scope only):** `find_aapt` prefers `aapt2`, but
  `aapt2 dump xmltree <apk> AndroidManifest.xml` fails with exit 1 and
  `missing required flag --file`. Real build-tools 37.0.0 requires
  `--file AndroidManifest.xml`; legacy `aapt` accepts the positional name. New
  `aapt_dump_xmltree` dispatches on the tool basename, and `run_weather_runtime_harness` now calls
  it. Both branches were executed against the real test APK with the real SDK tools (exit 0), and
  the old aapt2 form was re-run to capture the real failure.
- **Executed regression, not string-only:** the fixture `aapt2` stub now rejects the old positional
  form, the success fixture asserts the exact `--file` call, a new `aapt-v1` fixture asserts
  positional legacy syntax, and a direct negative check proves the stub rejects the old call.
  `sh scripts/emulator-smoke-test.sh` reports **1255 ok, 0 not ok** (previous 1247 plus 8).
- **Generated instrumentation contract matches the shell:** test package
  `com.launchernos.dotwellabs.debug.test`, runner
  `app.nothingui.weather.harness.WeatherRuntimeInstrumentation` (dotted), targetPackage
  `com.launchernos.dotwellabs.debug`, exactly matching `PKG.test` and the dotted component. The
  harness remains only in `tests/androidTest/java` via the dedicated `androidTest` source set, and
  the runner uses its own test-APK context and fails closed unless it is `<target>.test`.
- **Production APK harness absence, no runtime claim:** assembled
  `assembleLawnWithQuickstepPlayDebug` (**BUILD SUCCESSFUL in 1m14s**) only to hash and inspect it.
  Production APK SHA-256 `aa508f3839a598ae02db8e676a3bcbfdbbd08e732f42ac07efb37545b3538595`;
  production manifest has 0 `instrumentation` entries and 0 `WeatherRuntime` markers; production
  dex has 0 `Lapp/nothingui/weather/harness/` strings while the test dex has 46. No exported app
  switch, debug network policy, permission, applicationId, SDK or product source changed.
- **Evidence committed:** `docs/agent/evidence/2026-11-24-compile-preflight/` holds the full Gradle
  test/prod logs, the actual aapt2 badging and manifest dumps, the old-syntax failure, both real
  helper outputs, the production absence checks, hashes and the smoke log.
- **Verification actually run:** smoke **1255 ok / 0 not ok**; `nothingui-weather-guard.sh` pass;
  `nothingui-weather-guard-test.sh` pass; `verify-play-build-test.sh` pass;
  `emulator-smoke-drawer-test.sh` pass; `verify-android-resources.sh` aapt2 OK; `sh -n` clean on both
  edited scripts; `git diff --check` clean.
- **Missing evidence / not claimed:** no emulator, no `emulator-smoke.sh` device run, no
  `am instrument`, no MET request, no forecast, no release/signing/hosting. The compile and manifest
  proof is real; runtime and pixels are not.

## done (previous run — runtime-harness correction on `461822c`, harness-only, PENDING ACTUAL CI)

- **Runner component corrected:** `WEATHER_HARNESS_RUNNER` changed from the invalid
  `app/nothingui/weather/harness/WeatherRuntimeInstrumentation` to the dotted
  `app.nothingui.weather.harness.WeatherRuntimeInstrumentation`, so `am instrument` receives the
  valid `pkg/dottedclass` component.
- **Kotlin compile defect corrected:** `caseCancelLateResponse` now imports
  `kotlinx.coroutines.async` and calls `async(Dispatchers.IO)` on the enclosing `coroutineScope`
  receiver instead of the invalid unqualified static-style call.
- **Isolated test context corrected:** `WeatherRuntimeInstrumentation` now passes its own
  `context` (the test APK context) to `WeatherRuntimeHarness.run`, not `targetContext`, and finishes
  `RESULT_CANCELED` unless `harnessContext.packageName == targetContext.packageName + ".test"`.
  Harness writes therefore stay below the test APK's own `noBackupFilesDir` as the comments claim.
- **Cleanup evidence corrected:** `weather_harness_cleanup` no longer discards uninstall output. It
  records `pm path` before/after status and output plus the uninstall exit code, treats an adb query
  failure as a cleanup failure, and requires the package to be absent. The normal run fails if
  cleanup after a green harness fails; the EXIT trap records cleanup failure but returns the original
  `_trap_status`.
- **Bounded assemble:** the `assembleLawnWithQuickstepPlayDebugAndroidTest` call is now wrapped in
  `run_with_timeout 900` (15 minutes); install/instrument remained bounded at 180s/300s.
- **Evidence hardened:** the test-APK must be non-empty, its SHA-256 must be 64 hex characters, and
  both `aapt dump badging` and `aapt dump xmltree AndroidManifest.xml` failures are recorded in
  `weather-harness-test-apk.txt` and then fail the run instead of being ignored.
- **Executed orchestration fixture, not string greps only:** the suite sources the real
  `emulator-smoke.sh` in source-only mode, overrides only Gradle/AAPT/adb with stubs and a temp APK,
  and runs the real `run_weather_runtime_harness`. It asserts the exact
  `assembleLawnWithQuickstepPlayDebugAndroidTest --stacktrace` args, exactly one APK, the exact
  `com.launchernos.dotwellabs.debug.test/app.nothingui.weather.harness.WeatherRuntimeInstrumentation`
  component, `install -t -r`, `pm path`/uninstall/`pm path` ordering, the retained real SHA-256 and
  manifest dumps, and cleanup absence. Negative fixtures prove build, install, 300s-run timeout,
  crash marker, missing named case, uninstall-left-installed and AAPT-failure all stay red.
- **Full 826-line review + stubs compile:** all 826 lines of `WeatherRuntimeHarness.kt` and the
  runner were compared against the production weather contracts. `kotlinc` (no Gradle/Android build)
  compiles both files against minimal stubs mirroring those contracts, with no errors. This is a
  type/compile check only, not an Android instrumentation run.
- **Verification actually run (shell/Kotlin only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **1247 ok, 0 not ok, all passed** (previous 1155 plus
  the new executed orchestration/negative checks); `sh scripts/nothingui-weather-guard.sh` passes;
  `sh scripts/nothingui-weather-guard-test.sh` reports **34 ok, 0 not ok**;
  `sh scripts/emulator-smoke-drawer-test.sh` reports **38 ok, 0 not ok**;
  `sh scripts/verify-android-resources.sh` compiles `strings.xml` with SDK `aapt2` (OK); `sh -n` is
  clean on both edited scripts and `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for state 116, no APK, no emulator, no forecast,
  no native instrumentation result. The fixture proves the orchestrator contract; the stub compile
  proves types, not Android runtime behavior.

## done (previous run — Weather widget-tap artifact-path fix, scripts-only, PENDING ACTUAL CI)

- **Exact CI302 attempt2 finding, not a Weather failure:** the full Weather consent, invalid/draft,
  enable, restart, disable and cache-clear settings proof passed and the private state ended
  disabled. The native Weather widget produced one new binding, and tapping it opened the exact
  real `WeatherPreferences`; `_weather_confirm_settings_screen` succeeded and wrote its proof file.
  The next `capture_weather_widget` step copied `weather-widget-tap-screen-notice-activities.txt`
  and `.xml`, but the helper had been given tag `weather-widget-tap` and therefore produced
  `weather-weather-widget-tap-screen-notice-activities.txt`/`.xml`. The missing-source `cp` exited
  1 under `set -e`. Artifact `14899669684` holds the double-prefixed success proof.
- **Returned artifacts, no duplicated path:** `_weather_confirm_settings_screen` now also returns
  `_weather_screen_notice_activities` and `_weather_screen_fields_activities` (and clears all its
  returned globals at entry). The widget-tap caller copies `_weather_screen_notice_activities` and
  `_weather_screen_notice_xml`. It no longer reconstructs the helper's prefixed filename. The
  immediate PNG alias and the same-screen XML/activities aliases are unchanged.
- **Caller audit:** only `capture_weather_widget` passes a `weather-`-prefixed tag. Every
  `_weather_wait_screen` caller uses a plain tag (`fresh`, `invalid`, `valid-unchecked`,
  `draft-reset`, `draft-reset-enable`, `reload-enabled`, `reload-disabled`), so its
  `weather-<tag>-screen-*` contract is unchanged. Exact Preferences, notice, field, new-binding,
  preservation, tap, restart and resize gates were not weakened.
- **Executed path regression:** the test extracts the real `_weather_confirm_settings_screen` and
  the real widget-tap post-confirmation copy block from `scripts/emulator-smoke.sh`, runs them
  under `set -eu` with stubbed device captures, and asserts the same-screen XML, activities and
  immediate PNG aliases. The pre-fix code failed these checks (7 failures); the fix passes. Static
  checks require the returned notice/fields activities globals and forbid the old reconstructed
  `weather-widget-tap-screen-notice` path.
- **Verification actually run (shell only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **1155 ok, 0 not ok, all passed**;
  `sh scripts/nothingui-weather-guard.sh` passes; `sh scripts/nothingui-weather-guard-test.sh`
  reports **34 ok, 0 not ok**; `sh scripts/emulator-smoke-drawer-test.sh` reports **38 ok,
  0 not ok**; `sh scripts/verify-play-build-test.sh` reports **13 ok, 0 not ok**; `sh -n` is clean
  on both edited scripts and `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for `fe76343`, no APK, no emulator and no
  forecast. The fixture proves the orchestrator helper/caller path contract, not the device run.

## done (previous run — two-stage Weather screen identity, harness-only, PENDING ACTUAL CI)

- **Exact CI297 false failure, not a real app defect:** the fresh WeatherPreferences opened and
  showed the mode-correct long debug privacy notice, but the Location label and Latitude fields
  legitimately sat below the fold and were absent from every identical capture. The old
  `weather_settings_screen_identity` required the notice and both fields in one hierarchy, so it
  could never pass after the privacy copy grew; 10 captures over 14m01 failed closed. No app
  copy, layout, behaviour or network path was changed to accommodate the test.
- **Stage 1:** new pure `weather_settings_notice_identity <xml> <mode>` requires the exact unique
  `Before you enable` heading, unique `Terms of Service` link, the `Weather` title, and the
  build-mode-correct notice text (`This debug build has network requests disabled` plus `the IP
  address of this device` for debug; the release `are shared with MET Norway` copy for release,
  with the other mode's notice rejected). New `ui_label_contains`/`ui_label_lacks` prove the full
  long notice by substring without accepting a short invented fragment.
- **Stage 2:** new pure `weather_settings_field_identity`, `weather_settings_fields_identity` and
  `weather_settings_screen_provenance` use the existing label-association helpers. The Location
  label and Latitude are proven in their own measured field captures because they may not share a
  viewport after scrolling; the provenance helper rejects a missing field, the wrong screen, the
  other mode, or one artifact reused as its own proof.
- **Real orchestration:** new `_weather_confirm_settings_screen` proves the exact resumed
  `$PKG/$PREFERENCES_ACTIVITY` foreground and stage-1 notice, retains
  `weather-<tag>-screen-notice.xml/.png` plus the matching activities dump, then uses only the
  existing measured `_weather_measure_field` scroll/field helpers to reach the real Location label
  and Latitude fields on the same screen. It re-proves the exact resumed activity after scrolling,
  requires the combined provenance, and retains `weather-<tag>-screen-fields.xml/.png`. No guessed
  coordinates, reset, direct-activity bypass, database/preference write or scroll bypass was
  added.
- **All callers audited:** `_weather_wait_screen` (fresh entry and every reload via
  `_weather_open_weather`) and the later Weather-widget tap now use the same two-stage proof.
  The fresh privacy-copy gates read the retained initial notice XML instead of the post-scroll
  hierarchy, so a scrolled screen with the title offscreen no longer false-fails; field,
  checkbox, disable, restart and final-state gates still use their measured helpers and were not
  weakened.
- **Executed fixtures:** the actual 297 long-notice initial shape (built from the shipped runtime
  debug notice) is stage-1 true and stage-2 false; post-scroll Location and Latitude shapes are
  stage-2 true; the real notice plus both measured fields is provenance-true. Negative fixtures
  cover a fake/wrong-mode release notice, a title-only screen, a different settings screen, missing
  privacy, a missing Location field, a missing Latitude field and artifact reuse, all failing
  closed. Static gates forbid the old single-snapshot identity in both the settings and widget-tap
  bodies and require the notice/fields artifacts and the post-scroll foreground recheck.
- **Verification actually run (shell/aapt2 only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **1103 ok, 0 not ok, all passed** (the 1073 baseline
  plus 30 identity/fixture/static checks); `sh scripts/nothingui-weather-guard.sh` passes;
  `sh scripts/nothingui-weather-guard-test.sh` passes; `sh scripts/emulator-smoke-drawer-test.sh`
  all passed; `sh scripts/verify-play-build-test.sh` all passed;
  `sh scripts/verify-android-resources.sh` compiles `lawnchair/res/values/strings.xml` with the SDK
  `aapt2` (OK); `sh -n` is clean on all three edited scripts and `git diff --check` is clean.
- **Recorded parent CI facts, not rerun here:** 301 units and 187 Weather tests passed with 0 errors
  in CI29745336528197. No live MET request, forecast pixel, release wire or APK behavior is claimed.

## done (previous run — AAPT2 apostrophe resource fix, source-only, PENDING ACTUAL CI)

- **Actual failure recorded before the tests, not a unit assertion:** CI29445333776461 failed at
  resource flattening in 7m36. The raw AAPT diagnostics named
  `dotwel_weather_privacy_notice_debug`, `_privacy_notice_release`, `_enabled_status_release` and
  `_message_enabled_release` with `unescaped apostrophe in string`, `not a valid string` and
  `file failed to compile`. Reproduced locally with the Android SDK build-tools 37.0.0 `aapt2`
  compile of `lawnchair/res/values/strings.xml`: the four source values contained unescaped
  possessive apostrophes (`device's`, `location's`) even though the XML itself parsed.
- **Apostrophe-free, meaning-preserving wording:** `this device's IP address` became
  `the IP address of this device`, and `this location's cached forecast` became
  `the cached forecast for this location`. Both privacy variants still disclose that the selected
  coordinates and the device IP are shared with MET Norway only while Home is visible and unlocked,
  the debug notice still says network requests are disabled/setup-only, the release copy still
  describes the real opt-in request, and the forecast notice still describes the retained
  last-success value marked with its as-of age. No Kotlin, manifest, SDK, dependency, applicationId,
  Gradle or unrelated resource changed.
- **Focused AAPT validation:** new `scripts/verify-android-resources.sh` locates the SDK `aapt2`
  (PATH, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, standard SDK paths) and compiles
  `lawnchair/res/values/strings.xml` without running Gradle or an Android build.
  `scripts/verify-play-build.sh` invokes it for the real tree (minimal test fixtures skip it). A
  temporary fixture with `device's` fails with the real AAPT error; the shipped file compiles.
- **Executed regression guard and runtime-value copy:** `scripts/emulator-smoke-test.sh` now has
  `prod_string_raw` (raw source), `android_string_runtime_value` (decodes `\'`, `\"`, `\\`) and an
  unescaped-apostrophe detector. The copy assertions consume the decoded runtime value; a fixture
  proves a raw `device\'s` is rejected by the escaping guard and decoded to `device's` for copy,
  never leaving the raw escape in the assertion value. All eight Weather strings are guarded.
- **Static guard made escape-aware:** `scripts/nothingui-weather-guard.sh` decodes the runtime value
  before checking the privacy/forecast phrases, so a valid escaped apostrophe cannot cause a false
  failure; the mutation suite was updated to the new device-IP phrase.
- **Verification actually run (aapt2/shell only; no Gradle, Android build or emulator):** the
  pre-fix `aapt2 compile` failed with the exact four errors above; the post-fix compile succeeds.
  `sh scripts/emulator-smoke-test.sh` reports **1073 ok, 0 not ok, all passed** (the 1060 baseline
  plus 13 escaping/runtime checks); `sh scripts/nothingui-weather-guard.sh` passes;
  `sh scripts/nothingui-weather-guard-test.sh` reports **34 ok, 0 not ok**; the drawer smoke suite
  all passed; `sh scripts/verify-play-build-test.sh` all passed; `sh -n` is clean on every edited
  script and `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for `c4933cb`, no APK and no emulator. The local
  aapt2 compile validates resource flattening, not Compose/runtime behavior. The existing CI does
  not early-run this script before assemble (workflow files were not changed); it runs inside the
  CI-invoked Play verification and fails with the real AAPT diagnostic.

## done (previous run — build-mode-aware truthful Weather copy, source-only, PENDING ACTUAL CI)

- **Critical copy bug fixed:** `WeatherNetworkMode` keeps debug/test builds network-off, but the
  shared settings strings still promised a forecast request. New pure
  `app/nothingui/weather/WeatherSettingsCopy.kt` selects debug setup-only or release transmission
  copy from the same `WeatherNetworkMode.isEnabled(debugBuild)` boundary as the runtime, and maps the
  enabled confirmation through that mode. `WeatherPreferences` and the Home-screen Weather entry now
  compute the mode from `BuildConfig.DEBUG`; no exported/runtime switch, build type or activation
  policy was added.
- **Both-mode privacy disclosure:** debug says network requests are disabled and enabling is
  setup-only, while a release build would share the selected coordinates and device IP with MET
  Norway only while Home is visible and unlocked. Release says enabled requests share those selected
  coordinates and the device IP with MET Norway (met.no). Both say the location label stays on this
  device, keep the coordinates stored on device, and rule out GPS, network geocoding and background
  tracking. Neither claims coordinates are only stored without disclosing transmission.
- **Truthful forecast notice:** the old "instead of showing a stale or made-up value" claim
  contradicted `WeatherWidgetRender`, which retains the last success as stale. Both notices now say a
  failed refresh may leave the last successful forecast visible marked with its as-of age and that it
  is never replaced by a made-up value. The compact widget's exact `Off` / `Not connected` states and
  the consent gates were not weakened.
- **Executed contract checks:** the shell smoke suite resolves the shipped debug and release strings
  and asserts the transmission/IP/label/GPS/tracking disclosure, the debug network-off/setup-only
  truth, the distinct build-mode copy, the retained-last-success wording and the absence of the old
  contradictory phrase. It also asserts the copy object derives from `WeatherNetworkMode`, the
  Compose screen maps all mode-aware resources, the enabled message maps through the copy object, and
  the Home-screen subtitle uses the helper. New pure `WeatherSettingsCopyTest` covers both modes and
  the non-enabled message mapping. The weather guard now requires the copy object, both resource
  variants and the real Compose/home wiring; its mutation suite proves each new assertion can fail.
- **Runtime gates extended:** the debug emulator smoke gate now also asserts the real fresh screen
  shows the debug network-off privacy and device-IP disclosure, and the enabled screen shows the
  debug network-off status; the exact `WEATHER_ENABLED_MESSAGE` was updated to the shipped debug
  setup-only confirmation. No runtime was executed here.
- **Verification actually run (shell/kotlinc only; no Gradle, Android build, emulator, ktlint or
  actual CI):** `sh scripts/emulator-smoke-test.sh` reports **1060 ok, 0 not ok, all passed** (the
  1007 baseline plus 53 copy/wiring/fixture checks); `sh scripts/nothingui-weather-guard.sh` passes;
  `sh scripts/nothingui-weather-guard-test.sh` reports **34 ok, 0 not ok**; the drawer smoke suite
  all passed; widget/home/polish/wallpaper/role guards and the widget mutation suite passed;
  `sh scripts/verify-play-build-test.sh` all passed. The new copy object and its test compiled with
  `kotlinc` against minimal stubs (`rc=0`), `strings.xml` parsed, `sh -n` is clean on the edited
  scripts and `git diff --check` is clean. Standalone ktlint was not available and is not claimed.
- **Research-only plan:** `docs/agent/weather-runtime-proof-plan.md` records a small CI
  instrumentation option (inject the existing fake/loopback transport at `WeatherWorkFactory`, one
  opt-in endpoint-shape proof, real lifecycle assertions) without production keys, release signing,
  a new build type, a debug network toggle or a runtime backdoor. Not implemented.

## done (previous run — MET work wiring behind the gated owner, PENDING ACTUAL CI)

- **Pure composition root:** new `WeatherWorkFactory` constructs the existing `MetWeatherRepository`
  once with the injected transport, cache store, persisted throttle store, owner-backed
  `sessionProvider` and clock, and exposes it as the existing `WeatherLoadWork` seam. New pure
  `WeatherNetworkMode.isEnabled(debugBuild)` is the explicit build-type boundary: debug/test builds
  stay network-off, release builds keep the wired path. There is no exported/runtime test switch.
- **Runtime wiring:** `WeatherHomeRuntime` now builds `OkHttpWeatherTransport` with the actual
  `BuildConfig.VERSION_NAME`, `FileWeatherCacheStore` and `FileWeatherThrottleStore` both under
  `context.noBackupFilesDir` through `WeatherPrivateStorage`, behind the owner. Debug builds select
  `NoNetworkWeatherWork`. No activity is retained: the runtime keeps using the application context.
- **Circular-owner race closed:** new `WeatherRuntimeSessionProvider` resolves the current process
  owner lazily and fails closed with `WeatherSession.DISABLED` while the owner is null or closed. The
  runtime now clears `instance` before replacing/canceling the old owner, so a work graph built during
  replacement can never treat an uninitialized or replaced owner as its live session.
- **Existing gates preserved:** the owner still requires the persisted opt-in plus screen-on,
  unlocked, confirmed NORMAL HOME. Pause, drawer/overview, settings, screen-off, disable, edit and
  shutdown still invalidate the read epoch, cancel the controller job and drop late session results;
  the repository still checks the current session before committing a cache write. The widget remains
  render-only. No alarm, timer, worker, receiver, service, wake lock, background GPS or device
  location was added.
- **MET terms/identity:** the parent re-checked the current terms/FAQ on 2026-11-24. The wired path
  keeps the honest project User-Agent with the existing issues contact, the repository's four-decimal
  coordinate limit, conditional `If-Modified-Since` / `Expires` handling, visible-HOME-only requests,
  and the CC BY 4.0 attribution already in settings. No API call was made here.
- **Truthful copy:** settings strings no longer claim "no network request" or "forecast connection
  later"; they now state that a forecast is requested from MET Norway only while Home is visible and
  unlocked, with no background tracking and with disable clearing the location cache. Existing Off /
  Not connected widget legibility and the no-fabricated-forecast contract are unchanged.
- **Executed integration tests:** new pure-JVM `WeatherWorkFactoryTest` (8 tests) uses fake transports
  and a fake clock to prove: disabled/inactive sessions send zero HTTP; an enabled visible session
  makes one request and persists the gate; a fresh cache is served with no early repeat; a recreated
  work reads the persisted throttle and sends no request; 403/429 boundaries persist and block the
  next attempt; leaving HOME drops a late response with no cache commit; an uninitialized or closed
  owner resolves disabled; and disabling the persisted opt-in clears the location cache.
- **Verification actually run (offline JVM/shell only; no Gradle, no Android build, no emulator, no
  actual CI):** the whole non-OkHttp weather suite compiled and ran with kotlinc 2.4.21 + JUnit 4.13.2
  against Android 37.2 and the exact coroutines/serialization/OkHttp/Okio jars in `/tmp/opencode`
  only (no dependency change): **180 tests, OK (0 failures)**. The whole Android weather package,
  provider stub and runtime compiled against `android-37.2/android.jar` (`rc=0`). `sh
  scripts/emulator-smoke-test.sh` reports **1007 ok, 0 not ok, all passed** after updating the exact
  enabled-message fixtures; `sh scripts/emulator-smoke-drawer-test.sh` all passed;
  `sh scripts/nothingui-weather-guard.sh` passes and its mutation suite reports **27 ok, 0 not ok**;
  standalone ktlint 1.8.0 reports zero violations on every changed Kotlin file; `sh -n` is clean on
  the edited scripts and `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI, no APK, no emulator run and no live MET request.
  The factory test proves the composition/policy with fakes, not OkHttp, Compose, Android lifecycle or
  the real endpoint. The debug network-off boundary is proven only by source/pure policy until an
  actual emulator run. Release behavior and forecast pixels remain unproven.

## done (this run — CI283 attempt2 state-aware picker reveal, PENDING ACTUAL CI)

- **Exact CI283 attempt2 finding, not a placement failure:** the runtime ended in 24m16 at the Weather
  picker before Add/bind. `weather-widget-expand-1-1.xml` contained an expanded DotWel header at
  `[239,1441][557,1498]` and the real `WeatherWidgetCell` at `[69,1610][1011,1920]` with a content-desc
  ending "Weather settings", clipped by the viewport bottom. `widget_picker_description_preview_bounds`
  correctly returned empty because the cell's complete `widget_description`/`widget_preview_container`
  pair was not exposed. The loop treated the empty pair as "collapsed", tapped the header again, and
  `expand-2-1.xml` showed the provider collapsed; four scrolls then moved past it.
- **State-aware decision:** new pure `widget_picker_provider_state` classifies the exact measured
  header as `collapsed` (no cell content before the next header), `expanded` (any WidgetCell /
  preview / description / name / content-described child before the next header) or `none`.
  `widget_picker_weather_decision` is the actual loop decision and returns `select` (unique exact pair
  fully visible), `expand` (only when collapsed), `reveal` (expanded but clipped/missing pair),
  `search` (header absent) or `fail`. An expanded provider can never be expanded again, so the same
  collapse is impossible.
- **Measured reveal:** `widget_picker_provider_content_bounds` measures the expanded cell group;
  `widget_picker_weather_scroll_direction` chooses up/down against the measured viewport;
  `widget_picker_scroll_target_dir` produces the bounded gesture (the existing
  `widget_picker_scroll_target` is now the downward case and is unchanged). The loop captures fresh
  XML after every expansion and refuses to continue on a stale hierarchy, and captures PNG after
  every expansion and reveal scroll for future audit.
- **Strict gates retained:** selection still requires the exact `DotWel Launcher` provider header with
  a positive widget count, the unique exact `Weather, opens weather settings` description plus its own
  clickable preview, full viewport visibility, and the selected cell caption. Duplicates,
  wrong-provider cells, missing/unknown descriptions and ambiguous cells never select; the bounded
  scrolls end in `fail`.
- **Executed fixtures:** the real CI283 clipped-expanded shape is classified `expanded` and decides
  `reveal` even with expansion budget remaining; after the reveal shape the exact cell decides
  `select` and exposes its caption; a genuinely collapsed provider decides `expand` and never claims
  the next provider's preview; duplicate Weather cells and a wrong-provider cell never select and
  fail closed after the scroll budget.
- **Preserved:** the CI280 truthful Weather text contract (`a14c630`), the exact-id/provider binding
  helper (`dccec32`), the null-tag recycling fix (`1c672fb`), the caption identity fix (`f6f0475`)
  and every layout/binding/preservation/final-off gate. No app source, layout, resource, workflow,
  manifest, SDK, dependency, applicationId, signing or product gesture changed. Weather network stays
  OFF and the final consent stays disabled.
- **Verification actually run (shell only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **1007 ok, 0 not ok, all passed** (the 980 CI280 baseline
  plus 27 decision/fixture/static checks); `sh scripts/emulator-smoke-drawer-test.sh` all passed;
  `sh scripts/nothingui-weather-guard-test.sh` all passed; `sh -n` is clean on all three edited
  scripts; `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for `638d25d`, no emulator Add/bind/tap/restart/
  resize and no new pixel evidence. The fixtures prove the helper/static decision, not that the real
  CI283 picker now reaches the fully visible cell. Attempt 1's later second-drawer sparse MOVE is not
  waived or explained here.

## done (previous run — CI280 truthful Weather test contract, PENDING ACTUAL CI)

- **Exact CI280 finding, not a placement failure:** run45311806545 ended in 25m36 after the real
  Weather widget was placed and before the tap/restart/resize. The clock passed the post-grid strict
  check again. `1106312` had intentionally changed the visible detail to `Off` / `Not connected`
  with the full copy moved to the root content description, but the smoke helper still required the
  old long detail strings. The real XML was value `--`, detail `Off`, empty as-of and the full
  `Weather off · tap to set up` root description; the actual PNG showed `Off` clearly legible.
- **Exact production contract now encoded:** `weather_widget_text_is_truthful` requires value `--`;
  `Off` with an empty as-of and the full off root content description; `Not connected` with the
  exact `No forecast yet` as-of line and the full not-connected root content description. It
  rejects a contradictory state/as-of, any forecast number, Loading, Unavailable/unknown, a missing
  root description and a wrong root description. The accepted copy lives in named constants.
- **Executed fixtures, actual row shape:** both accepted states use the real root
  `nothingui_weather_root` content description plus the short child detail, and new negative
  fixtures cover a forecast number, a fake update timestamp, a contradictory as-of, missing root
  descriptions, a wrong root description, Loading, Unavailable and unknown. The smoke test reads
  `lawnchair/res/values/strings.xml` and `DotWelWeatherWidgetProvider.kt` and asserts every constant
  matches the shipped string and the provider's field-to-resource mapping, so future copy drift
  fails the suite instead of silently passing stale fixtures.
- **Restart/resize audit:** every post-restart and post-resize truthfulness assertion calls the same
  corrected helper. Bounds, exact AppWidgetId/provider, preserved bindings and final-disabled-consent
  assertions were re-read and have no contract mismatch; nothing was weakened.
- **Preserved:** the exact-id/provider/host helper from CI277 (`dccec32`), the null-tag recycling fix
  (`1c672fb`), the caption identity fix (`f6f0475`), and every strict layout/binding/preservation
  gate. No app source, layout or resource change; Weather network stays OFF and the final consent
  stays disabled.
- **Verification actually run (shell only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` reports **980 ok, 0 not ok, all passed** (the 959 baseline plus
  21 contract/drift checks); `sh scripts/nothingui-weather-guard-test.sh` all passed;
  `sh scripts/emulator-smoke-drawer-test.sh` all passed; `sh -n` is clean on both edited scripts;
  `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for `a14c630`, no emulator tap/restart/resize,
  and no new pixel evidence. The fixtures prove the helper/static contract, not that the real CI280
  page now completes. 290 units / 176 Weather tests are the parent's CI280 facts, not rerun here.

## done (this run — CI277 parser contract and compact Weather status, PENDING ACTUAL CI)

- **Exact CI277 finding, not a Weather placement failure:** run45306446146 ended in 24m39 after the
  real Weather widget was placed and its exact WeatherPreferences opened. The clock strict check
  passed all three hosts with no null-item error. The new failure was in the smoke parser contract:
  `appwidget_launcher_instances` returns `<numeric id><TAB><provider>` and its unused third `id`
  argument never changes that row shape, while four later Weather-presence probes piped it into
  `grep -qx "$_cww_new_id"`. A present id 10 therefore produced a false negative. The older
  null-tag recycling checkpoint `1c672fb` (`WidgetViewRecycling.resolveItemTag`, 3 unit tests) was
  already committed and is not the 277 cause.
- **Column-aware contract fix, helper unchanged:** new executed helper
  `appwidget_launcher_instance_is <dump> <host> <numeric id> [<package>/<class>]` first requires the
  launcher-owned host block and a numeric id, then compares the exact numeric first column and, when
  supplied, the exact full provider component. All four Weather presence probes pass the new id and
  `$PKG/app.dotwel.widgets.DotWelWeatherWidgetProvider`, so provider ownership and exact class are
  re-proven after tap, restart, resize and the final gate. The ignored `id` arguments were removed
  from the remaining plain-list callers, and `_cwg_widget_ids` now strips the provider column before
  its set comparison. `appwidget_launcher_instances` still emits `<id><TAB><provider>` and
  `appwidget_preserved_bindings` is unchanged, so no binding-preservation check was weakened.
- **Executed fixtures use the actual row shape:** id 10 with the exact Weather component passes; id
  11, the clock provider, a foreign host, a foreign provider package, a non-numeric id and a
  malformed provider all fail closed. A static gate also rejects a reappearance of the bare
  `grep -qx "$_cww_new_id"` check. `sh scripts/emulator-smoke-test.sh` reports **959 ok, 0 not ok,
  all passed** (the 949 baseline plus 10 parser checks).
- **Compact Weather status legibility:** the original layout keeps its bounded 2x1/2x2 row but the
  detail line now uses short visual labels `Off` and `Not connected` instead of the long setup copy
  that clipped to `Weather`. The full copy remains in the root content description, including the
  existing not-connected accessibility sentence. The detail line wraps to at most two lines and
  auto-sizes 8-11sp; the as-of line auto-sizes 7-9sp; padding/margin/weight give the status column
  more width. The default preview text is the short label. No forecast, network path, new feature or
  redesign was added.
- **Guard:** `scripts/nothingui-weather-guard.sh` now requires the short strings, the provider's
  short-detail/full-accessibility split, and a wrapping/auto-sizing detail line, and forbids
  reintroducing the long off/not-connected detail. The mutation suite adds three checks and reports
  **21 ok, 0 not ok**.
- **Verification actually run (shell/XML only; no Gradle, Android build, emulator or actual CI):**
  `sh scripts/emulator-smoke-test.sh` 959 ok; `sh scripts/nothingui-weather-guard-test.sh` 21 ok;
  `sh scripts/emulator-smoke-drawer-test.sh` all passed; `sh scripts/verify-play-build-test.sh` 13 ok;
  the home/widget/polish/weather/wallpaper/icon/role plus Play brand/identity guards and their
  selected mutation suites passed; the edited Weather layout, strings and widget-info XML all parse;
  `sh -n` is clean on the edited scripts and `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI for `dccec32`/`1106312`, no emulator restart,
  resize or 2x1/2x2 pixel proof, and no forecast connection. The parent-reported 290 units / 176
  Weather tests were not rerun here. This run is not all-green.

## done (this run — CI272 placed-widget caption identity correction, PENDING ACTUAL CI)

- **Exact CI272 attempt2 finding, not a Weather failure:** run45294228258 attempt2 ended in 20m28.
  The strict new HOME readiness passed on its first attempt (actual clock/date, all three original
  widget children, exact launcher foreground). `capture_widgets_picker` then selected the Clock
  provider header and the Analog clock preview caption, but
  `home_widget_bounds`/`search_home_pages_for_widget` were given the provider title `Clock` as the
  expected host label. The real `LauncherAppWidgetHostView` in `widgets-home-placed-attempt-15.xml`
  and every placement-page XML has content-desc `Analog clock` at bounds `38,107,524,517` with a real
  deskclock analog child inside the workspace, so every host/page check rejected it. The Weather gate
  was **NOT REACHED** and has no Weather artifact; this is not a Weather tile failure or success.
- **Identity split, no waiver:** the provider header/app title `Clock` remains only the picker
  selection and evidence label. The selected preview WidgetCell caption `Analog clock` is now the
  expected identity for the initial new-host detection, bind consent (already correct), placed-page
  geometry safety, initial page discovery, post-Settings survival page search and the final exact
  bounds re-check. Provider-title uses for those host/page identities were removed. The actual bound
  provider/component and new launcher-owned AppWidget ID proof (`appwidget_new_providers` with
  `$PKG`), workspace/header/dock geometry, unchanged-existing-host suppression, preview/pending
  rejection and exact-bounds preservation are unchanged; nothing was weakened to any-host or
  bounds-only identity.
- **Targeted executed fixtures:** a real Clock header plus selected `Analog clock` caption accepts
  the exact new CI272 host at `38,107,524,517`; the header `Clock`, sibling `Digital clock`, a wrong
  provider caption, an already-present host and a picker-preview host all fail closed. Static
  regressions require the caption for new-host identity, placed-page safety, initial discovery,
  survival discovery and the final re-check, and forbid the provider title in those paths.
- **No prohibited change:** no Gradle/Android build, emulator, workflow, dependency, permission,
  manifest, SDK, applicationId, signing, API/provider, HOME layout/theme/wallpaper, private-widget,
  merge, release or hosting change. No direct bind, reset, reseed, database/preference write or
  workspace item move/removal was added. Attempt 1's startup SystemUI ANR overlay was environmental
  and no app-code fix was made for it.
- **Verification actually run (shell only; no Gradle, Android build or emulator):**
  `sh scripts/emulator-smoke-test.sh` reports **949 ok, 0 not ok, all passed** (the 935 CI269 baseline
  plus 14 new caption/fixture checks); `sh scripts/emulator-smoke-drawer-test.sh` all passed;
  `sh -n` is clean on all three edited scripts; `git diff --check` is clean.
- **Missing evidence / not claimed:** no actual CI runtime, screenshot or device proof for
  `f6f0475`. The fixtures prove the helper/static control flow and fail-closed identity checks, not
  that the real CI272 page now completes. Weather placement/tap/restart/resize evidence remains
  pending actual CI, and no forecast is connected.

## done (this run — CI269 HOME readiness correction, PENDING ACTUAL CI)

- **Exact CI269 failure, not a Weather failure:** `capture_grid_settings` completed its read-only
  grid read and returned with the normal HOME key. `verify_nothing_home` then saw the
  `MON23NOV` date pill plus the battery and device hosts, but the clock host was still a
  `PendingAppWidgetHostView` and no live clock text was present. The old check made only four
  captures of one fixed `home.xml` and could not write a fresh PNG/appwidget/activity diagnosis for
  each attempt, so it failed while the launcher was still rebinding. The runtime never reached the
  Weather placement/tap/restart/resize gate and has no Weather artifact; do not report that gate as
  failed or passed.
- **Bounded STATE-based readiness:** `verify_nothing_home` now makes at most 15 one-second
  attempts. Each attempt captures its own `home-readiness-N.xml` and `home-readiness-N.png`, the
  resumed `dumpsys activity activities` and `dumpsys appwidget` state, and a readiness log line
  with foreground component, clock/date presence, clock/battery/device child ids, pending host
  count and PNG presence. Role holders and the resolved default HOME are captured once for the run.
  Readiness requires the exact `PKG/app.lawnchair.LawnchairLauncher` foreground and
  `primary_home_is_ready` on the fresh XML; the ready attempt is copied to `home.xml`/`home.png`
  and then `verify_home_widgets` still requires the real launcher-owned ids and child values.
- **No waiver, no reset:** the actual clock time text, date strip and all three original widget
  child ids remain required. A permanently missing clock still fails after the bounded attempts
  and writes `home-readiness-failure.txt` plus the last attempt XML/PNG/activity/appwidget evidence.
  No data reset, reseed, direct bind, database/preference edit, item removal/move or clock waiver
  was added. No app source or production behavior was changed.
- **Targeted fixtures:** new executed fixtures cover a transiently pending clock that is absent on
  attempts 1-4 and ready on attempt 5, and a permanently missing clock. They prove fresh per-attempt
  XML/PNG and diagnostics, promotion of the ready attempt, and fail-closed behavior when the clock
  never returns.
- **Stale run 103 corrected:** the previous worker run stalled before updating STATE but saved the
  `dacff49` checkpoint. This run resumed from that checkpoint rather than claiming the stalled work
  completed.
- **Verification actually run (shell only; no Gradle, Android build, emulator or new CI):**
  `sh scripts/emulator-smoke-test.sh` reports **935 ok, 0 not ok, all passed** (the 922-check
  baseline plus 13 new readiness checks); `sh scripts/emulator-smoke-drawer-test.sh` all passed;
  `sh -n` is clean on the edited scripts; `git diff --check` is clean;
  `nothingui-home-guard.sh`, `nothingui-widget-guard.sh`, `nothingui-polish-guard.sh`,
  `nothingui-weather-guard.sh`, `nothingui-wallpaper-guard.sh`, `nothingui-icon-render-guard.sh`,
  `nothingui-home-role-guard.sh` and their selected mutation tests pass.
- **Missing evidence / not claimed:** no actual CI runtime, APK, screenshot or device proof for
  `9ecfa82`. The executed fixtures use stubbed captures and a fixed launcher activity; they prove
  the poll/fail-closed control flow, not that the real emulator clock recovers or that CI269 will
  pass. Weather placement/tap/restart/conditional-resize evidence is still pending actual CI.

## done (previous run — Weather HOME widget render phase, PENDING CI)


- **Pure coordinate-free render model** — new `WeatherWidgetRender.kt`:
  `WeatherWidgetForecast` carries only `temperatureCelsius`, `symbolCode`, `asOf` and `stale`; the
  sealed `WeatherWidgetRender` is `Off`/`NotConnected`/`Loading`/`Forecast`/`Unavailable`; the pure
  `WeatherWidgetState` reducer commits a session and a result and clears the committed result on a
  disable/revoke (an edit disables first, so the next enable starts in `Loading` with no prior
  forecast). `WeatherWidgetStateStore` is the process-wide in-memory publication point (no ordinary
  prefs, no backup-visible file, no coordinates). `WeatherWidgetText` provides whole-degree Celsius,
  a truthful condition fallback (`Forecast`) for a missing/unknown provider symbol and bounded
  `now`/`Nm ago`/`Nh ago`/`Nd ago` labels. A no-network `CACHE_MISS` maps to `NotConnected`, never a
  fabricated current temperature.
- **Render-only provider** — new `DotWelWeatherWidgetProvider` (Play-only receiver). `onUpdate`,
  `onAppWidgetOptionsChanged` and `refreshAll` only read `WeatherWidgetStateStore.render()` and call
  a full `updateAppWidget`; there is no partial update, load, repository, transport, receiver
  registration, coroutine, thread, executor, worker, alarm, wake lock, service, location access,
  ordinary-preferences access or logging. The tile tap resolves the existing
  `PreferenceActivity.createIntent(context, WeatherSettings)` route and uses an explicit
  `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` activity `PendingIntent` (Play only).
- **Original resources** — new `nothingui_widget_weather.xml` reuses the paper/charcoal rounded tile,
  Doto fonts and muted/content colour tokens of the clock/battery/device widgets. A single compact
  row (auto-sized temperature + stacked condition/as-of) is legible at 2x1 and 2x2; no chart, vendor
  asset or private widget code. `nothingui_weather_widget_info.xml` targets a 2x2 cell, allows
  horizontal+vertical resize, shrinks to 40dp and requests no periodic updates. New strings cover
  off, not-connected, loading, unavailable/retry, updated/as-of and content descriptions.
- **Play-only declaration, no seed** — `play/AndroidManifest.xml` declares the receiver
  `exported="false"` with `APPWIDGET_UPDATE`/`APPWIDGET_OPTIONS_CHANGED` and the metadata. It adds
  no permission and is **not** added to `default_workspace_4x5.xml`; the existing clock/battery/
  device seed and layouts are untouched.
- **Shared publication** — `WeatherHomeRuntime` now passes the owner's `onSessionChanged` and
  `resultSink` into `WeatherWidgetStateStore` and repaints placed tiles with a main-thread
  `updateAppWidget` post. `NothingUiWidgetMonitor` also repaints the tile on resume/theme/config, so
  the surface colour follows the stored theme. The tile never becomes a load entry point.
- **Guard** — `scripts/nothingui-weather-guard.sh` now also requires the ready-state publication,
  the render-only provider, the real settings tap, the immutable PendingIntent, the resize metadata,
  the Play-only non-exported receiver, the truthful `CACHE_MISS -> NotConnected` mapping and the
  coordinate-free model. It forbids `requestLoad`, the session controller, repository, OkHttp,
  transport, consent store, location, worker/alarm, receiver registration, coroutine/thread/executor,
  wake lock, service, ordinary prefs, DataStore and logging in the provider, and forbids auto-seeding.
  `scripts/nothingui-weather-guard-test.sh` proves every assertion can fail (18 checks).
- **Verification actually run (offline JVM/shell only; no Gradle, no Android build, no emulator):**
  `WeatherWidgetRenderTest` (14 new tests) and the prior weather suite ran together as **176 tests,
  OK (0 failures)** via kotlinc 2.4.21 + JUnit 4.13.2 + kotlinx-coroutines 1.11.0 +
  kotlinx-serialization 1.13.0 + OkHttp 5.5.1 + Okio 3.16.0 (jars in `/tmp/opencode` only; no
  project dependency added). The whole weather package **plus** the new provider compiled against
  the local `android-37.0/android.jar` with small stubs for the generated `R` and project UI types
  (`rc=0`). Standalone ktlint 1.8.0 reports zero violations on every changed Kotlin file; the new
  and edited XML parses; `git diff --check` is clean. `nothingui-weather-guard.sh` passes and
  `nothingui-weather-guard-test.sh` reports all passed (18 checks). The pre-existing
  `nothingui-widget-guard.sh` and its mutation test still pass.
- **Missing evidence / not claimed:** no Gradle/Play/Spotless compile, no API 37 emulator, no
  screenshot/pixel review, no APK and no CI result for these commits. The provider/RemoteViews
  rendering, the settings tap and the resize behaviour are unproven on a device. No forecast is
  connected; the production work seam is still `NoNetworkWeatherWork`.

## done (previous run — HOME lifecycle review correction, PENDING CI)

- **Screen-off gates:** `WeatherHomeOwner.setScreenInteractive(false)` now clears its own
  `userPresent` value as well as `screenInteractive`, invalidates the read epoch and cancels the read
  job, and calls `controller.setScreenOn(false)` plus `controller.setUserPresent(false)`. A queued
  read dropped this way is retried only after HOME is confirmed, the screen is interactive and a
  genuine user-present signal arrives. `onScreenOff()` is the explicit hookup method.
- **Screen-on recheck:** the launcher's `ACTION_SCREEN_ON` and `ACTION_USER_PRESENT` receiver paths
  now call `refreshWeatherScreenState()`, which queries `PowerManager.isInteractive` and
  `KeyguardManager.isKeyguardLocked` every time. A missing keyguard manager fails closed as locked,
  and `ACTION_SCREEN_OFF` calls `onScreenOff()` directly instead of querying a possibly racing
  power state.
- **Transition start:** a new `weatherStateListener` calls `WeatherHomeSurfaceState.onTransitionStart`
  at `onStateTransitionStart`, so weather hides immediately when leaving NORMAL. A transition toward
  NORMAL stays hidden until `onStateTransitionComplete(NORMAL)`; a canceled or reversed transition
  leaves `homeConfirmed` false. `WeatherHomeWiring.isHomeVisible` now also requires
  `!transitionInProgress`.
- **Consent race:** `WeatherHomeConsentPolicy.choose` accepts every persisted disable, accepts a
  persisted enable only when it is strictly newer, and keeps the in-process state for an older enable
  or a same-generation enable/location conflict. The owner delegates to that policy instead of
  overwriting a newer in-process edit with older persisted coordinates.
- **Activity recreation:** `stopWeatherHome` unregisters the state listener and screen receiver and
  hides the HOME surface but never calls `shutdown()`, so the process-wide owner survives a
  recreated activity. `WeatherHomeRuntime` passes `applicationContext`, keeps no activity, and
  replaces an explicitly closed owner instead of reusing it.
- **Actual hookup guard:** new `scripts/nothingui-weather-guard.sh` statically checks the real
  launcher/owner/runtime/settings wiring (screen-off handling, system recheck, transition start,
  no shutdown on pause, no closed-owner reuse, no provider/transport/location construction and
  `NoNetworkWeatherWork`). `scripts/nothingui-weather-guard-test.sh` proves the guard passes the real
  source and rejects each mutated regression.
- **Preserved:** `NoNetworkWeatherWork` is still the production work seam; no repository, HTTP
  transport, worker, alarm, device location, permission, manifest, SDK, applicationId, signing,
  workflow, dependency, non-Play layout or private-widget change was made. Existing accepted
  HOME/widgets/settings/layout/theme/wallpaper code is untouched.
- **Verification actually run (offline JVM/shell only; no Gradle, Android build or emulator):**
  compiled the weather domain/consent/cache/controller/owner/lifecycle sources and the two HOME test
  classes with kotlinc 2.4.21 against JUnit 4.13.2, kotlinx-coroutines 1.11.0 and
  kotlinx-serialization 1.13.0 (jars in `/tmp/opencode` only; no project dependency added). JUnit ran
  **30 tests, OK (0 failures)** across `WeatherHomeOwnerTest` and `WeatherHomeLifecycleTest`, and the
  screen-off test asserts the queued read is canceled and retried after unlock. `WeatherHomeRuntime`
  plus `WeatherPrivateStorage` compiled against the local `android-37.0/android.jar`. ktlint 1.8.0
  reports zero violations on all five changed Kotlin files and the new test files; `git diff
  --check` is clean. `sh scripts/nothingui-weather-guard.sh` passes and
  `sh scripts/nothingui-weather-guard-test.sh` reports **9 ok, 0 not ok** including all mutated
  regressions.
- **Missing evidence / not claimed:** no Gradle/Play compile, no Spotless-in-Gradle, no API 37
  emulator and no runtime proof for these commits. `LawnchairLauncher.kt` is checked statically, not
  compiled locally. The pure tests use fake stores/work/dispatchers; they prove policy, cancellation
  and fencing, not the real Compose or device lifecycle. No forecast is connected.

## done (previous run — Weather HOME lifecycle/consent owner, superseded by this correction)

- **Superseded:** the claims below describe the pre-correction implementation. The screen-off,
  screen-on/keyguard, transition-start and stale-consent behavior in the section above is the
  authoritative current behavior.

- **Launcher-owned owner:** new pure-JVM `WeatherHomeOwner` wraps the existing
  `WeatherSessionController` and is the single bridge for HOME visibility and the settings consent
  observer. It reads the persisted consent through `WeatherConsentStore` off the main dispatcher on
  every false→true HOME transition, before any work can start, and fails closed (disabled, no work)
  when the read throws. It owns no repository, transport, timer, alarm, worker or location source.
- **HOME-only visibility:** `setHomeVisible` requires the resumed, visible NORMAL HOME surface. All
  Apps, Overview and a different activity hide it. `WeatherHomeWiring.isHomeVisible` is the pure
  guard. Repeated visible callbacks do not duplicate the read or the load.
- **Screen/user/destroy gates:** `setScreenInteractive` and `setUserPresent` feed the controller's
  `screenOn`/`userPresent` gates. `shutdown` permanently stops the session. Every pause, screen-off,
  user-absent, settings edit/disable and shutdown invalidates the pending consent read (read epoch)
  and lets the controller cancel the in-flight job.
- **Stale fencing:** a read launched before a pause or a newer settings decision is dropped. A
  persisted enable older than an in-process disable/edit cannot resurrect consent; a persisted
  disable is always trusted. Results are delivered only for the current session (existing controller
  guarantee).
- **Shared settings observer:** `WeatherPreferences.createController` now passes
  `consentObserver = WeatherHomeRuntime.observeConsent(appContext, state)`, so enable/edit/revoke
  cancels the visible session immediately. `WeatherHomeRuntime` is the one process-wide owner
  (application context, app-private no-backup consent store, explicit `NoNetworkWeatherWork`, no-op
  sink).
- **Real launcher hookup:** `LawnchairLauncher.onResume` starts the owner, queries
  `PowerManager.isInteractive` and `KeyguardManager.isKeyguardLocked`, registers a resumed-only
  `ACTION_SCREEN_ON/OFF/USER_PRESENT` receiver, and syncs visibility. `onStateSetEnd` re-syncs so
  All Apps/Overview hide it and returning to NORMAL re-reads consent. `onPause`/`onDestroy` stop and
  unregister. No widget broadcast starts a load.
- **Transport stays off:** production uses `NoNetworkWeatherWork`, which returns an honest
  `Unavailable` with no forecast and no network. No `OkHttpWeatherTransport`, repository, provider,
  synthetic CI coordinates, dependency, permission, manifest, SDK, applicationId, workflow, signing
  or non-Play layout changed. Existing truthful "no forecast yet" copy is untouched.
- **Verification actually run (offline JVM/shell only; no Gradle, Android build or emulator):** the
  full pure weather package compiled with kotlinc 2.4.21 against JUnit 4.13.2, coroutines 1.11.0,
  serialization 1.13.0, OkHttp 5.5.1 and Okio 3.16.0 (downloaded to `/tmp` only; no project
  dependency added). JUnit ran **149 tests, OK (0 failures)** across 15 weather classes: the 132
  prior weather tests plus 17 new `WeatherHomeOwnerTest` cases. The 17 new tests were written first
  and failed on the missing owner/wiring/work symbols before the implementation. ktlint 1.8.0
  reports zero violations on the new and edited files; `git diff --check` is clean.
- **Missing evidence / not claimed:** no Gradle/Play compile, no Spotless-in-Gradle, no API 37
  emulator and no runtime proof for `780b088`. The owner tests use fake work/store/dispatcher; they
  prove policy, cancellation and fencing, not the real Compose or device lifecycle. The real
  launcher wiring is committed but unproven until CI compiles it. No forecast is connected.


## done (this run — CI252 adb-join false-missing probe and real blur proof, PENDING ACTUAL RUNTIME)

- **Exact CI252 false negative, reproduced independently in the shell:** compile/style/units were
  green and the runtime failed after a real enable with `missing` from the store probe although the
  enabled UI was visible. `adb shell` joins its arguments, so the old
  `run-as "$PKG" sh -c "test -f '$WEATHER_CONSENT_REL'"` became
  `run-as PKG sh -c test -f path`; the device shell then ran `sh -c test` with `$0=-f`, `$1=path`,
  so `test` had no operand and returned 1 for an existing file. A local fake adb + fake run-as
  reproduced `rc=1` for the old form and `rc=0` for the direct form.
- **Direct probe, not another `sh -c`:** new `_weather_probe_private_file` calls
  `adb_cmd shell run-as "$PKG" test -f "$path"` with every argument intact. It returns `present`
  only for exit 0 with empty stderr, `absent` only for exit 1 with empty stderr, and `error` for
  every other run-as/transport outcome. `_weather_capture_consent` maps `absent` to `missing` and
  `error` to `probe-error`, and every existing enabled/disabled/fresh case fails closed on that
  token instead of treating it as an absent file. Every probe retains its path, exit, stderr and a
  private directory listing in `weather-probe-<tag>.txt`/`.err`.
- **Cache audit fixed too:** `_weather_cache_exists` now uses the same probe and fails the run on a
  run-as/transport error rather than letting an `if` test pass falsely; the disable assertion passes
  a `cache-after-disable` evidence tag.
- **Seed quoting fixed:** `_weather_seed_cache` builds one fully quoted device command with
  `weather_app_shell_command`/`shell_single_quote`, passes it to `adb shell` as a single argument,
  and pipes the fixture on stdin, so `mkdir -p` and `cat > file` both run as the app UID under the
  app data directory. It then probes the file and `cmp`s the exact bytes read back through
  `run-as cat`; a wrong-UID/outer-shell write cannot satisfy it.
- **Real blur proof:** the longitude step now asserts the focused capture reports
  `Longitude focused=true`, measures and taps the latitude EditText (another measured input),
  dismisses the IME, and asserts `Longitude focused=false`, `Latitude focused=true` and an
  unchanged latitude draft before naming `weather-valid-longitude-blurred.png`. Tapping the
  non-focusable hint had left Longitude focused, so it never proved a blur. New
  `ui_labelled_edit_text_focused` returns only the measured `focused` attribute and prints nothing
  for a missing/ambiguous field; the existing `ui_labelled_edit_text_state` output format and every
  accepted bound/typing check are unchanged. The red outline stays unproven theme focus; no
  production UI, validation or theme code changed.
- **Preserved:** every fresh/off, invalid, no-consent, draft-reset, real enabled Save, reload,
  Disable, cache-clear, app-private consent, no-backup, restart and final-off assertion remains.
  No fabricated JSON, `pm clear`, uninstall, preference write, direct bind or bypass was added.
- **No prohibited change:** no Gradle/Android build, emulator, workflow, dependency, permission,
  SDK, applicationId, signing, API/provider, Home hookup, private-widget, merge, release or hosting
  change. Existing accepted Home/widgets/layout/theme/wallpaper/non-Play code is untouched.
- **Verification actually run (shell only; no Gradle, Android build or emulator):**
  `sh scripts/emulator-smoke-test.sh` **891 ok, 0 not ok, all passed**, including executable
  adb-join misquote/present/absent/error/seed-clear fixtures, the focused/blurred field helper
  fixtures and the updated static gate assertions; `sh scripts/emulator-smoke-drawer-test.sh` all
  passed; `nothingui-wallpaper-guard.sh`, `nothingui-polish-guard.sh`, `nothingui-home-guard.sh`,
  `nothingui-widget-guard.sh` and `nothingui-icon-render-guard.sh` all OK (compiled wallpaper
  sentinel skipped, no APK); `sh -n` is clean on all three edited scripts; `git diff --check` is
  clean.
- **Missing evidence / not claimed:** no new runtime proof, screenshot, APK or CI result for
  `f3b9b9c`. The fake adb/run-as fixtures prove the quoting and fail-closed control flow, not the
  real device shell. Durable enabled state, the real success line, reload, disable and final-off
  remain for the next CI runtime.

## done (previous run — CI250 post-enable/disable offscreen evidence, PENDING ACTUAL RUNTIME)

- **Exact CI250 false negative:** compile/style/units were green and the runtime passed
  fresh/off, invalid, no-consent and draft-reset and clicked the actual enabled Save, then
  `_weather_enabled_poll` timed out. The 10 real enabled XML captures held the saved status
  (`Emulator test`, `60.0000,10.0000`) and a `Disable and clear location` control clipped at
  `[.,1901][.,1920]`, but the success line `Weather setup saved. No forecast is loaded in this
  version.` was below the fold and absent from the composed hierarchy. The old poll grep'd one
  unscrolled XML, so it failed before the store was read and before any scroll; CI250 never proved
  durable enabled state.
- **Post-action evidence first:** new `_weather_capture_action_evidence` reads the app-private
  consent record (JSON plus a `.state` file) and captures the top XML/PNG immediately after the
  Enable/Disable tap, before any assertion or scroll. A later failure therefore still leaves the real
  store state and pixels in CI artifacts.
- **Durable + measured + identity poll:** new `_weather_poll_action_state` makes at most 10
  one-second attempts. Each attempt reads the durable consent record and captures top XML/PNG; only
  an `enabled|*` or `disabled|*` record proceeds. It then uses the existing measured
  `_weather_measure_control` to scroll the measured container until the exact success line is fully
  inside the viewport, requires the real `Disable and clear location` (enable) or `Save and enable`
  (disable) identity in that revealed XML, and saves the scrolled XML/PNG. Exhaustion retains the
  final poll XML plus a failure XML/PNG. A raw grep of one unscrolled XML is no longer accepted.
- **Both directions covered:** the enabled flow and the disable flow both use the new poll, so the
  disable success line has the same below-fold protection. Top `weather-enabled.xml` and
  `weather-disabled.xml` snapshots are still captured for the existing saved-status, saved-label,
  Disable and Save assertions.
- **Focused vs blurred valid longitude:** after typing valid `10.0000`, the gate captures
  `weather-valid-longitude-focused.xml/png`, taps the measured harmless coordinates hint (neither a
  provider link nor an action), captures `weather-valid-longitude-blurred.xml/png`, and fails only if
  the exact longitude validation string appears. The red outline alone is not treated as an error and
  no production UI, validation or theme code changed.
- **No distant-pair requirement:** reentry/reopen still uses the existing privacy/field identity and
  measured scrolling; nothing requires the privacy notice and a distant button in one viewport.
- **Preserved:** every fresh/invalid/no-consent/draft-reset/enable/reload/disable/cache-clear/app-
  private consent/no-backup/restart assertion, the synthetic seeded cache proof, and the final
  disabled state. No Gradle/Android build, emulator, workflow, dependency, permission, SDK,
  applicationId, signing, network/provider, Home integration, private-widget, merge, release or
  hosting change. Existing HOME/widgets/layout/theme/wallpaper/non-Play code is untouched.
- **Verification actually run (shell only; no Gradle, Android build or emulator):**
  `sh scripts/emulator-smoke-test.sh` **854 ok** and `all emulator-smoke tests passed** (including the
  new CI250 clipped-Disable/unscrolled-message fixture, an executed poll that fails while the success
  line is unrevealed, an executed reveal that only then passes, and the blur/semantic-error checks);
  `sh scripts/emulator-smoke-drawer-test.sh` **38 ok** and all passed; `sh -n` is clean on all three
  edited scripts; `git diff --check` is clean.
- **Missing evidence / not claimed:** no new runtime proof, screenshot, APK or CI result for this
  fix. The executed poll uses stubbed device calls; it proves the control flow and fail-closed
  evidence retention, not the real Compose hierarchy. The next CI runtime must prove the durable
  enabled store, the measured lower success line, reload, disable, cache clearing and restart.

## done (previous run — CI243 Weather screen false negative, PENDING NEW RUNTIME)

- **Exact CI243 false negative:** compile/style/units were green, but `_weather_wait_screen fresh`
  failed. The 10 real `weather-fresh-screen-1..10` XML captures showed the Weather destination
  (`Before you enable`, privacy paragraphs, Terms/Source/License, Weather heading, `Location label`
  at `[126,1636][407,1699]`, clipped `Latitude` at `[126,1826][290,1889]`) while `Save and enable`
  was offscreen. The old detector required the privacy notice AND Save/Disable in the same initial
  viewport, so it never scrolled and failed on a real screen.
- **Screen identity:** new pure `weather_settings_screen_identity` requires the unique privacy
  heading and unique Terms link plus a present `Location label`, `Latitude` and Weather heading. It
  deliberately does not require Save, Disable, Longitude or any below-fold control. Presence (not
  uniqueness) is used for the field labels and heading because one label can be exposed as both a
  Text node and a field semantic. The wait now captures a screenshot before every XML probe and a
  `screen-failure.png` on timeout.
- **Field association:** new `ui_labelled_edit_text_state` associates an `android.widget.EditText`
  with its stable label (own text/content-description, descendant label, ancestor label, or
  immediately preceding non-EditText sibling) and returns the current draft. Duplicate label nodes
  that all point at the same field are accepted; missing or cross-field ambiguous labels print
  nothing, so `_weather_measure_field` never keys a field by visible document order. `_weather_type`
  clears an existing measured draft with an exact number of DEL keys and verifies the field is empty
  before typing, so re-entry cannot append duplicate text.
- **Both-direction measured scroll:** `weather_target_scroll_direction` chooses `up`/`down` from the
  measured target rectangle vs the measured viewport (fully or partly above => up, below => down);
  `_weather_scroll_band` keeps the swipe inside the strict-or-known measured container. The bounded
  loop tries the exact direction first, then a second measured pass for a target absent from the
  hierarchy, so a re-entered screen at its end can still reach an earlier field. No coordinate is
  guessed.
- **Preserved assertions:** the later fresh/invalid/no-consent/draft-reset/enable/reload/disable/
  restart checks, cache-clear seed, app-private consent store, no-backup prefs boundary and final
  disabled state are unchanged. The `Disable and clear location`, enabled message and disabled
  message checks are untouched.
- **No app change:** no Kotlin/Compose/app UI behavior, manifest, permission, SDK, applicationId,
  workflow, dependency, network/provider, Home lifecycle, private-widget, merge, release or hosting
  change. Only the two smoke scripts and this evidence doc/STATE changed.
- **Verification actually run (shell only; no Gradle, Android build or emulator):**
  `sh scripts/emulator-smoke-test.sh` **all passed (830 ok)**, including new fixtures for the
  initial privacy screen without Save/Enable, clipped `Latitude`, populated label association,
  duplicate-label failure, same-field duplicate semantics, up/down direction and the upward
  measured scroll band; `sh -n` is clean
  on all three edited scripts; `git diff --check` is clean.
- **Missing evidence / not claimed:** no new runtime proof, screenshot, APK or CI result for
  `c4ad8e9`. The helper fixtures are not evidence that the real screen was detected; the next CI
  runtime must prove it. CI241 green, CI243's green compile/style/units and its 132 weather tests
  are historical facts, not proof of this fix.

## done (previous run — WeatherPreferences unresolved-import fix, PENDING CI)

- **Exact CI239 finding:** `WeatherPreferences.kt` imported `app.lawnchair.theme.LawnchairTheme`,
  which does not exist, producing an unresolved reference at line 50 with cascades at 410/444.
- **One-line fix:** the import is now `app.lawnchair.ui.theme.LawnchairTheme`, matching the
  `LawnchairTheme` composable declared in `lawnchair/src/app/lawnchair/ui/theme/Theme.kt`, and was
  moved to keep the `app.lawnchair.ui.*` imports alphabetical (before `ui.util.preview`). No other
  source line changed.
- **Untouched:** no Gradle/Android/emulator run, no dependency, manifest, permission, SDK,
  applicationId, workflow, private widget or behavior change; all prior weather work is unchanged.
- **Verification actually run:** `git diff --check` clean and the diff is exactly the one import
  move. CI239's rerun is the compile gate.

## done (previous run — weather fail-closed correction and Compose emitter fix, PENDING CI)

- **Compose fix:** `WeatherPreferences.kt` now wraps the label/latitude/longitude fields in a single
  `Column`, so `LocationFields` emits one container instead of four top-level composables. The exact
  repository formatter (standalone ktlint 1.8.0 plus merged compose rules 0.6.8 including the
  `common-ktlint` classes) reports zero violations on all 12 production weather files, all 14 weather
  test files and `WeatherPreferences.kt`.
- **Settings/consent correction:** `load()` now calls `consentObserver(saved)` exactly once after a
  successful read, so a recreated settings/lifecycle boundary learns a persisted enabled or disabled
  decision. Disable/edit revocation still stops the in-process session immediately, but a storage
  failure or exhausted conflict keeps `revocationPending = true`, keeps `saved` disabled, shows
  `REVOKE_UNCONFIRMED`/`CONFLICT`, never claims a durable disable, never clears the old cache, and
  leaves `disable()` callable. Retry re-reads the stored state and revokes from durable truth, so it
  works even when the local state is already disabled but disk still says enabled. A conflict whose
  stored state is already disabled is accepted as a confirmed revocation; a conflict with a stored
  enabled record never calls the observer with that enabled state.
- **Session correction:** result delivery and the current-session equality check now happen in one
  `synchronized(lock)` block, so a pause/edit cannot interleave between the check and the sink. The
  controller owns a monotonic generation instead of `consent.generation + revision`; a consent reset
  cannot reuse a prior generation, and `Long.MAX_VALUE` exhaustion publishes a disabled session and
  starts no work. Work exceptions catch `Exception`, not `Throwable`, while cancellation still
  propagates.
- **Store correction:** `FileWeatherConsentStore` distinguishes missing, corrupt and valid records
  internally. A CAS requires the exact current generation and a strictly greater next generation; a
  store at `Long.MAX_VALUE` fails closed. Missing records may be initialized by a fresh enable, but
  an enable may not overwrite a corrupt record (a disable may, the safe direction). Corruption
  semantics are documented on the class.
- **Truthful copy:** privacy, forecast, consent, enabled-status and enabled-message strings now say
  this version only stores the label/rounded coordinates/consent locally, makes no network request
  and shows no forecast; the MET Norway connection and visible-HOME loading are described as a later
  version. The retry-disable action and the honest unconfirmed-revocation message were added.
- **Untouched:** no Gradle/Android/emulator build, live MET request, dependency, manifest,
  permission, SDK, applicationId, signing, workflow, hosting, merge, private widget or non-weather
  production change. The audited `6335e8c` Home/settings/widgets/layouts/non-Play work is preserved.
- **Verification actually run (offline JVM/shell only; no Gradle, no Android build, no emulator):**
  compiled the weather production sources and all weather tests with kotlinc 2.4.21 against JUnit
  4.13.2, kotlinx-coroutines 1.11.0, kotlinx-serialization 1.13.0, OkHttp 5.5.1 and Okio 3.16.0
  (downloaded to `/tmp` only; no project dependency added). JUnit ran **132 tests, OK (0 failures)**
  across 14 weather test classes. Fourteen new regressions were added; five key regressions were also
  run against the old `HEAD` source, where the two session tests (generation reset, overflow) and
  three store tests (same-generation CAS, generation exhaustion, enable over corruption) failed for
  the intended reasons. `strings.xml` parses, `git diff --check` is clean, and the formatter reports
  zero violations.
- **Missing evidence / not claimed:** no local Gradle/Compose compile, no Spotless-in-Gradle run, no
  API 37 emulator, no actual screen pixels and no CI result for `5e70fcf`. The JVM count is not a
  full-suite count and the Compose screen remains a CI compile/pixel gate.

## done (previous run — CI226 style-only ktlint wrapping, PENDING CI)

- **Exact CI226 facts:** the `build-debug-apk` job passed in 20m11 and the `unit` job passed in
  13m23. `check-style` failed in 2m37, reporting only three
  `standard:function-signature: First line of body expression fits on same line as function
  signature` findings at `OkHttpWeatherTransport.kt:75`, `WeatherCache.kt:167` and
  `WeatherThrottle.kt:98`.
- **Exact repository formatter:** `gradle/libs.versions.toml` pins
  `com.pinterest.ktlint:ktlint-cli:1.8.0` and `io.nlopez.compose.rules:ktlint:0.6.8`; `build.gradle`
  Spotless targets `lawnchair/src/**/*.kt` with that ktlint and compose ruleset; `.editorconfig`
  sets `ktlint_code_style = intellij_idea` and the listed standard-rule disables. The same
  standalone ktlint 1.8.0 CLI plus compose/common 0.6.8 jars were downloaded to `/tmp/opencode` for
  this check only (no project dependency or Gradle change) and run against the weather files, where
  they reproduced exactly those three findings and zero others.
- **Formatting changes only:** the formatter joined the three short expression-body first lines to
  their signatures and re-indented the affected bodies/blocks. The OkHttp callback structure, the
  cache-key predicate, the throttle `withStoreLock`/claim flow, every token, string, call and test
  are unchanged.
- **Verification actually run (no Gradle, no Android build, no emulator):** standalone ktlint 1.8.0
  now reports zero violations across all seven `lawnchair/src/app/nothingui/weather/*.kt` files;
  `git diff --check` is clean; and for each edited file a whitespace-stripped SHA-256 of
  `HEAD` versus the working tree is identical, proving the diff contains no non-whitespace change.
  The weather unit tests were **not** rerun locally; CI remains their gate.
- **Untouched:** no behavior, test, dependency, manifest, permission, SDK, applicationId, signing,
  release, workflow, hosting, merge, private widget or non-weather source change. Weather stays
  unwired and no live MET/API request was made. The audited customization from `b5a9918` and all
  weather cancellation/throttle tests are byte-for-byte preserved.
- **Missing evidence / not claimed:** no local Spotless/Gradle run, no rerun of the 66 JVM weather
  tests, and no CI result for `e218504` yet. `check-style` green and the whole pipeline green are
  not claimed until the next CI report.

## done (previous run — stalled-body cancellation and throttle-store safety, PENDING CI)

- **Transport root cause:** `Call.await()` resumed the coroutine when headers arrived, so `get` then
  called the blocking bounded body read on the caller's context (possibly Main). The
  `invokeOnCancellation` handler was registered on the already-completed headers suspension, so a
  cancellation during a stalled `input.read` could not run it and the `finally` could not close the
  response until the read returned.
- **Transport fix:** the coroutine is now resumed only after the whole bounded response is read
  inside the OkHttp callback, on OkHttp's worker thread; no body I/O runs on the caller/Main. The
  cancellation hook stays live for the entire call and invokes `Call.cancel()`, which closes a
  stalled response; `response.use` closes it in every path, including when cancellation wins after
  the response exists but before/after resume. `readBounded` checks `call.isCanceled()` each loop.
  `maxResponseBytes`, timeouts, `Expires`/`Last-Modified`/`Retry-After` headers and the User-Agent
  are unchanged.
- **Real loopback cancellation evidence:** new `StallingBodyServer` sends valid 200 headers with
  `Content-Length: 4096` and never a body byte. A test-only OkHttp interceptor signals exactly when
  the caller enters the body read, so the test waits for headers and body phase before cancelling
  (it cannot accidentally cancel while still waiting for headers). The test then cancels the
  repository load with a 5 s bound, proves the server sees the socket close and the cache stays
  empty. The existing no-header cancellation test and the normal/header/oversize tests are kept.
- **Required throttle injection:** `MetWeatherRepository` no longer defaults to a fresh
  `InMemoryWeatherThrottleStore`; every unit constructor now passes one explicitly. A production
  constructor still does not exist.
- **File store honesty:** `FileWeatherThrottleStore.recordRetryNotBefore` now fails closed on a
  corrupt/read-failing gate instead of replacing it with an empty gate. Lock/read/write failures are
  reported as `StorageFailure(false)`/`false`/`null` rather than thrown, and a process-wide monitor
  serializes same-process instances before the file lock (a JVM `FileLock` alone throws
  `OverlappingFileLockException`). Corrupt-gate, recreated-instance and 12-thread two-instance claim
  tests were added.
- **Provider boundary persistence:** the repository keeps the effective `Retry-After` boundary in
  memory (`localRetryBoundary`) and reports `Unavailable.retryPersisted=false` when the store could
  not persist it, so a later load cannot shorten a long provider delay within the instance. The
  persisted store still only moves `retryNotBefore` later, and there is still no automatic retry.
- **Cache write symmetry:** `FileWeatherCacheStore.write` now rejects the same blank/line-break/
  oversized key and oversized `Last-Modified` header that `decode` rejects, so a write can no longer
  return `true` for an entry that reads back as absent.
- **Untouched:** no Gradle/Android build, live MET request, opt-in/UI/lifecycle hookup, dependency,
  manifest, permission, SDK, applicationId, signing, release, workflow, hosting, merge or private
  widget code. Only `lawnchair/src/app/nothingui/weather/` and its unit tests changed; the audited
  Play slider/customization work from `b5a9918` is preserved byte-for-byte.
- **Verification actually run (JVM/shell only; no Gradle, no Android build, no emulator):**
  compiled the weather source and all weather tests with kotlinc 2.4.21 against JUnit 4.13.2,
  kotlinx-coroutines/serialization, OkHttp 5.5.1 and Okio 3.16.0 (downloaded to `/tmp` for this
  local check only; no project dependency added). JUnit ran **66 tests, OK (0 failures)** across
  `MetWeatherRepositoryTest`, `MetLocationForecastParserTest`, `WeatherCachePolicyTest`,
  `WeatherCoordinatesTest`, `RetryAfterParserTest`, `WeatherThrottleTest`,
  `FileWeatherCacheStoreTest` and `OkHttpWeatherTransportTest`. The three new regression tests
  (stalled-body cancellation, corrupt-gate `recordRetryNotBefore`, cache write/decode symmetry) were
  also run against the old `HEAD` source and failed there for the intended reasons;
  the concurrent two-instance claim test failed the old store with `OverlappingFileLockException`.
  `git diff --check` is clean. Source compilation is warning-free.
- **Missing evidence / not claimed:** no Play/Gradle compile, no Spotless-in-Gradle run, no API 37
  emulator or UI/lifecycle proof, and no production wiring of the opt-in UI, privacy notice, file
  stores or HOME pause/screen-off cancellation. The loopback tests are fixtures, not live MET
  evidence.

## done (previous run — weather transport/cache pre-CI correction, PENDING CI)

- **Global request throttle, no longer per-location-success only:** new
  `lawnchair/src/app/nothingui/weather/WeatherThrottle.kt` defines a persisted `WeatherAttemptGate`
  (`lastAttemptAt`, provider `retryNotBefore`), `WeatherAttemptDecision` and
  `WeatherThrottleStore`. `InMemoryWeatherThrottleStore` is the test seam;
  `FileWeatherThrottleStore` persists through a temp file plus `ATOMIC_MOVE` under a file lock. A
  claim is recorded **before** the transport call, so a changed location, manual `refresh()`,
  concurrent error loads and a recreated repository all hit the same floor. A missing record allows
  the first attempt; an unreadable/unwritable record fails closed (`CACHE_STORAGE`). A denied load
  returns the honest cached forecast with its stale flag, or `Unavailable` plus the true `retryAt`,
  never a synthesized forecast. The per-location `Expires` boundary is still honoured (tested at
  +4 h with `Expires` at +5 h and no transport).
- **Cancellable transport:** `OkHttpWeatherTransport` no longer calls blocking `execute()`. It uses
  `suspendCancellableCoroutine` + `enqueue`, registers `invokeOnCancellation { call.cancel() }`,
  re-checks `ensureActive()` around every bounded read, and cancels/closes in `finally` if the
  coroutine is no longer active. The repository re-checks cancellation after every suspension and
  immediately before every cache write/result, then checks the session. A loopback `ServerSocket`
  test wires the real OkHttp transport into the repository, cancels the job, proves the server sees
  the close and the cache stays empty. KDoc states the future owner must still cancel at HOME
  pause/screen-off and revoke the generation; already-sent bytes cannot be retracted.
- **`Retry-After` with the injected clock:** new `RetryAfterParser` accepts positive seconds
  (relative to the repository clock) and RFC-1123/ISO HTTP-dates, and returns null for blank, zero,
  negative, malformed or overflowing values. 403 uses a bounded 1 h fallback, 429 a bounded 60 s
  fallback, and there is no upper clamp, so a provider's longer delay is never shortened. The
  persisted `retryNotBefore` only moves later. The reported `retryAt` is
  `max(server delay, local attempt floor)`, so a 120 s server delay is not reported earlier than
  the enforced 3 h floor. No automatic retry loop exists.
- **Bounded, atomic cache:** `FileWeatherCacheStore` checks the file length and then reads through a
  bounded stream before decoding; it validates a format version, key/body/header sizes and all
  timestamps. Corruption returns null without deleting the file. `write` returns `Boolean`,
  rejects oversized entries, writes a temp file and replaces atomically with a non-atomic fallback,
  and a failed write leaves the previous entry intact. New temp-directory tests cover roundtrip
  (including revalidation), missing entry/directory, corruption, oversized read/write, unwritable
  directory preserving the prior entry, read failure and no leftover `.tmp` files. No external
  storage or Context is used.
- **Fresh vs stale is separate from retrieval:** `WeatherFreshness` marks a forecast stale when the
  latest evidence (`retrievedAt` or `revalidatedAt`) is 3 h old **or** when its `validAt` is more
  than 90 min in the past, so a six-hour-old only-available forecast is never shown as current. A
  304 now keeps the original `retrievedAt`, records `revalidatedAt`, and updates `Expires` /
  `Last-Modified`; `WeatherRefreshPolicy` counts revalidation as evidence. `Success.cacheUpdated`
  reports whether this call durably wrote the cache, and `Unavailable.lastSuccessStale` exposes the
  age of a preserved last success. Storage, network, local-throttle and provider-rate-limit failures
  are distinct (`CACHE_STORAGE`, `NETWORK`, `THROTTLED`, `FORBIDDEN`/`RATE_LIMITED`); a cache write
  failure still returns the real forecast with `cacheUpdated=false`.
- **Untouched:** no Gradle/Android build, no live MET request, no opt-in/network hookup, no UI,
  lifecycle, dependency, manifest, permission, SDK, signing or workflow change, and no private
  widget code. No file outside `weather/` and its unit tests changed, so the saved Play slider
  correction and all strict smoke assertions are preserved.
- **Verification actually run (JVM/shell only; no Gradle, no Android build, no emulator):**
  compiled the weather source and all weather tests with kotlinc 2.4.21 against JUnit 4.13.2,
  kotlinx-coroutines/serialization, OkHttp 5.5.1 and Okio 3.16.0 (downloaded to `/tmp` for this
  local check only; no project dependency added). JUnit ran **61 tests, OK (0 failures)** across
  `MetWeatherRepositoryTest`, `MetLocationForecastParserTest`, `WeatherCachePolicyTest`,
  `WeatherCoordinatesTest`, `RetryAfterParserTest`, `WeatherThrottleTest`,
  `FileWeatherCacheStoreTest` and `OkHttpWeatherTransportTest`. ktlint 1.8.0 reported zero
  violations on the weather source and tests; `git diff --check` was clean. Shell gates:
  `emulator-smoke-test.sh` all pass, `emulator-smoke-drawer-test.sh` all pass,
  `nothingui-polish-guard.sh` + test, `nothingui-widget-guard.sh` + test,
  `nothingui-home-guard.sh` + test, `nothingui-icon-render-guard.sh` + test,
  `nothingui-wallpaper-guard.sh` all OK (compiled sentinel skipped, no APK). These are fixtures and
  JVM evidence, not Android/runtime evidence.
- **Missing evidence / not claimed:** no Play/Gradle compile, no Spotless-in-Gradle run, no API 37
  emulator or UI/lifecycle proof, and no production wiring of the opt-in UI, privacy notice,
  `FileWeatherThrottleStore`, `FileWeatherCacheStore` or HOME pause/screen-off cancellation. The
  local loopback and fixture tests do not represent live MET behavior.

## done (previous run — PR19 Play icon-slider truthfulness, PENDING CI)

- **Root cause from the saved CI218 attempt 3 and source, not a flaky test:** the real Play default
  is `config_default_home_icon_size_factor = 0.76`, but the slider's 0.1 step made
  `snapSliderValue(0.5, 0.76, 0.1)` display 0.8 (80%). One DPAD step persisted 0.9, and the reverse
  step persisted 0.8 instead of the original 0.76, legitimately changing the widget-host geometry.
  Browse/Back/HOME replay behavior was already correct and is untouched.
- **Play-only fix:** the top Customize launcher icon slider now uses `step = 0.01f` with the same
  `0.5F..1.5F` range, so 0.76 is a real tick and the label reads 76%. The non-Play icon slider keeps
  0.1f, the Play resource default stays 0.76, opening the screen writes nothing, and an arbitrary
  pre-existing factor is displayed instead of being normalized.
- **Pure math:** `getSteps` and `snapSliderValue` moved unchanged into
  `SliderValueMath.kt` so they are JVM-testable. New `SliderValueMathTest` covers the 76% label, the
  100 one-point intervals, 0.76→0.77→0.76, arbitrary 0.7634→76 and 0.835→84, plus the unchanged
  0.1/0.05 steps used by other controls.
- **Smoke:** `ui_slider_percent` now accepts 50..150 integer percentages (76/77 fixtures), the gate
  expects a ±1 point step and the same-step reverse, and the new pure `datastore_float_factor`
  parser reads only `home_icon_size_factor` from the DataStore protobuf and prints percent plus the
  exact little-endian float bytes. Baseline, after-step and after-restore values are compared
  numerically; when a baseline factor was already stored its exact bytes must be restored. Fixtures
  cover 76/77/80, the target after another entry, out-of-range 0.49/1.6, a raw-text fake key and an
  empty file. The existing host-bounds, binding and wallpaper checks are unchanged.
- **Not touched:** weather source, Browse/Back/HOME replay logic, the non-Play slider, the 0.76
  default, permissions, manifest, SDK, applicationId, signing, workflows, dependencies or private
  widget code. No Gradle/Android build, emulator, APK or runtime claim was made.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **758 ok, 0 not ok**; `emulator-smoke-drawer-test.sh` all pass;
  `nothingui-polish-guard.sh`, `nothingui-home-guard.sh`, `nothingui-widget-guard.sh` and
  `nothingui-icon-render-guard.sh` OK, with their `-test.sh` suites all passing; `sh -n` clean on
  every edited script; `git diff --check` clean. The real `SliderValueMathTest` compiled with
  kotlinc 2.4.21 against JUnit 4.13.2 and ran **OK (5 tests)**. This is shell/JVM evidence only:
  Play compilation, Gradle style and every API 37 runtime claim remain CI gates.

## done (previous run — weather transport/cache offline slice, PENDING CI)

- **Pure domain:** `WeatherCoordinates.from` rejects NaN, infinities and out-of-range values and
  rounds HALF_UP to four decimals before the value can become a URL parameter or cache key. The
  `WeatherForecast` model is explicitly a forecast (not an observation) and carries provider,
  location key, Celsius units, optional symbol, `validAt` and `retrievedAt`; the label is a
  whole-degree value. `WeatherSession` holds the enabled/visible/generation/location gate and
  `WeatherLoadResult` reports success/stale, unavailable with last success, disabled and cancelled.
- **Parser:** `MetLocationForecastParser` refuses blank/oversized/malformed payloads, skips entries
  with a bad timestamp or missing/invalid temperature, rejects entries outside the 6h-past/24h-future
  window and then chooses the entry nearest to now. It does not take the first (frequently already
  elapsed) timeseries entry. Missing symbol data is accepted as `null`.
- **Cache:** `WeatherCacheEntry` stores the raw bounded body, `expiresAt`, exact `lastModified`,
  `retrievedAt` and `locationKey`. `FileWeatherCacheStore` takes a caller-supplied app-private
  directory and writes through a temp file with `ATOMIC_MOVE` (fallback replace); it is not wired to
  a Context. `InMemoryWeatherCacheStore` is the unit-test seam. `WeatherRefreshPolicy` requires the
  global 3h minimum and, when present, the later `Expires` boundary.
- **Repository:** `MetWeatherRepository` serialises one in-flight request, serves fresh cache without
  transport (manual `refresh()` cannot bypass the minimum), sends the exact previous
  `Last-Modified` as `If-Modified-Since`, accepts a 304 only with a still-valid cached body (no
  invented forecast time), preserves the last success on network/parse/HTTP failure, and sets a
  bounded in-memory backoff on 403/429 with no automatic retry loop. It re-checks the session
  generation/enabled/visible/location before writing a response, so a revoked opt-in or changed
  location cannot commit.
- **Transport seam:** `WeatherHttpRequest`/`WeatherHttpResponse`/`WeatherHttpTransport` are a pure
  injectable interface. `OkHttpWeatherTransport` is the only HTTP implementation; it uses the
  existing OkHttp dependency, bounded reads, finite connect/read/call timeouts, a 512 KiB cap and a
  `DotWelLauncher/<version> (+<public issues URL>)` User-Agent. Coordinates are at most four decimals.
- **Deliberately not wired:** no widget, settings, ViewModel, worker, boot receiver, alarm, GPS
  permission, periodic poll or production network entry point constructs the repository or the
  OkHttp transport. The network path stays disabled until a real explicit opt-in UI, valid label and
  coordinates, a privacy notice and the visible HOME lifecycle gate exist.
- **No prohibited changes:** no Gradle dependency (OkHttp already ships via the retrofit bundle), no
  manifest/permission/SDK/workflow/signing/applicationId change, no UI or existing home/widget/
  wallpaper/theme change, no copy of the private widgets repository or any third-party art. Test
  JSON is invented, non-personal fixture data and is **not** live MET evidence; no MET request was
  made.
- **Verification actually run (no Gradle, no Android build, no emulator):** all four weather test
  classes compiled with kotlinc 2.4.21 against JUnit 4.13.2 and the existing
  kotlinx-serialization/coroutines versions, then JUnit ran **24 tests, OK (0 failures)**, including
  coordinate rounding/cache keys, nearest-valid-period parsing, the 3h+Expires gate, exact
  conditional headers, 304 cache-miss, 429 backoff, last-success preservation, inactive sessions,
  generation/opt-in revocation and concurrent in-flight dedup. `OkHttpWeatherTransport.kt` compiled
  separately against okhttp-jvm 5.5.1/okio-jvm 3.16.0. ktlint 1.8.0 reported zero violations on all
  new files; `git diff --check` was clean. This is JVM-only evidence: Play compilation, style in the
  Gradle task and every Android/runtime claim remain CI gates.

## done (previous run — scripts-only pre-CI review correction, PENDING CI)

- **Gate abort fixed:** the `set -- "$_ccs_customize"` / `$2` pattern in
  `capture_customization_settings` created one positional from a 4-number bounds string and aborted
  under `set -u`. The order check now calls new production
  `customization_controls_in_order`, which extracts each top edge through new pure
  `ui_bounds_top_y`. That helper accepts only exactly four non-negative integers and prints nothing
  otherwise, so malformed or quoted bounds fail closed instead of leaving an unbound positional.
- **Executed regression, not a source grep:** `scripts/emulator-smoke-test.sh` extracts the actual
  production `customization_controls_in_order` function and runs it under `sh -eu` with real
  4-number measured strings. It passes the correct top-to-bottom order, fails a reversed order, and
  fails a 3-number string; the old quoted-`set` code would have aborted on the correct case.
- **Widget preservation now compared:** the restored HOME `ui_widget_host_bounds` lines are
  CR-stripped, sorted and `cmp`-ed against the baseline. A changed host count or geometry now fails
  the icon-size round-trip instead of only being retained as an artifact.
- **Wallpaper preservation now compared:** the baseline and restored `dumpsys wallpaper` captures
  are parsed with the existing `wallpaper_ids_from_dump` using explicit user `0`; Home/Lock IDs must
  be equal. New pure `wallpaper_component_from_dump` reads only the System section and prints the
  normalized `pkg/class` (or nothing). Baseline and restored components are compared, so equivalent
  absence is accepted when the initial static wallpaper exposes no component, and a DotField
  assumption is never made. Whole dumps with timers are never compared.
- **Lock preference claim removed:** the datastore check only finds the `lock_home_screen` key. Its
  artifact is now `lock_home_screen_marker=present (presence only; value not proven)` /
  `unavailable`, and the summary explicitly says this is NOT a value-preservation proof.
- **Known-format fixture:** added a `settings-theme-dark.xml`-shaped fixture with standard node
  ancestry and the known category `42 1009 1038 1198` / label `84 920 409 973` numbers, asserting
  the measured clickable ancestor is returned. The actual CI211 artifact is not in this coding job.
- **Unchanged:** full real UI step/revert gate, focused-slider and measured-percentage guards,
  Browse taps, Back/HOME repeats, bindings, app/source UI, manifest, workflow, dependencies,
  permissions, SDK, signing and applicationId. No Gradle, Android build, emulator, runtime or pixel
  claim.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **734 ok, 0 not ok**; `emulator-smoke-drawer-test.sh` all pass;
  `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no APK);
  `nothingui-polish-guard.sh` OK; `sh -n` clean on all three edited scripts;
  `git diff --check` clean. The new runtime gate still has **no CI/runtime approval**; the 734
  shell fixtures are not runtime evidence.

## done (previous run — measured customization dashboard/Browse/icon-size runtime gate, PENDING CI)

- **New bounded runtime step:** `scripts/emulator-smoke.sh` now calls
  `capture_customization_settings` immediately after `capture_clean_home_theme` and before
  `exercise_device_settings_shortcuts` / `capture_widgets_picker`, so it runs after the own-HOME
  baseline and before any third-party widget placement. It opens the real `PreferenceActivity`
  with no diagnostic extras, requires one exact `Customize launcher` label and one unique clickable
  `Icon size and home screen` entry, taps the measured candidate, and requires the top
  `Customize launcher` group, actual `android.widget.SeekBar` percentage and unique `Browse widgets`
  control in measured top-to-bottom order.
- **Browse proof:** the measured `Browse widgets` control opens the existing native picker helper;
  the resumed component is recorded (exact launcher or another launcher-package picker activity),
  XML/PNG and `dumpsys appwidget` are kept, Back must resume the exact launcher activity, and the
  launcher-owned binding list must match the baseline. Reopening Settings must keep the exact
  Settings activity with no automatic picker; a second explicit Browse tap must open the picker
  again; Back plus two ordinary HOME repeats must not reopen it.
- **Actual slider proof:** the top SeekBar is located from XML (never a guessed coordinate), its
  unique 50–150 step-of-10 percentage is read, TAB focus is bounded to 12 steps, and the exact top
  SeekBar must report `focused="true"`. One `DPAD_RIGHT` (<150) or `DPAD_LEFT` (150) step must change
  the actual percentage by exactly 10; HOME PNG/XML are captured before and after, the value is
  re-read after reopening Settings, one reverse key restores the original, and the final binding
  list must equal the baseline. Home widget-host bounds, private datastore/prefs presence, workspace
  DB availability and raw wallpaper dumps are retained; the PNGs are icon-pixel evidence for parent
  review, not claimed cell bounds.
- **Pure helpers added:** `ui_unique_label_bounds`, `ui_unique_clickable_label_bounds`,
  `ui_top_slider_bounds`, `ui_slider_percent`, `ui_focused_slider_bounds` and
  `ui_widget_host_bounds`. Missing/duplicate labels, missing/duplicate top sliders, non-SeekBar or
  unfocused controls, ambiguous/out-of-range percentages and malformed bounds all fail closed.
- **No faked state:** no preference write, direct widget bind, database/sqlite edit, picker activity
  start, reset, seed, clear-data, `setWallpaperComponent` or hardcoded tap coordinate was added.
  App UI, manifest, permissions, workflow, dependencies, SDK, signing and applicationId are
  untouched.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **715 ok**; `emulator-smoke-drawer-test.sh` **38 ok**;
  `nothingui-polish-guard.sh` OK; `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no
  APK); `sh -n` clean on every edited script; `git diff --check` clean.
- **Blocked/unknown:** the real dashboard labels, picker route, SeekBar class/focus and percent
  persistence are **not** proven until the next actual API 37 CI/emulator run. If the real picker is
  a separate launcher-package activity, the exact-launcher expectation after Back still applies.
  No workflow, release, merge or completion claim.

## done (previous run — pre-CI review correction, PENDING CI AND RUNTIME)

- **Defect 1 fixed:** the two hidden `Activity.isResumed` accesses in `tryOpenPendingWidgetPicker`
  were replaced with the documented public `BaseActivity.hasBeenResumed()` flag; window focus is now
  also required. Multi-window additionally requires `isTopResumedActivity()`, so a merely resumed
  launcher behind another focused window cannot post or open the picker.
- **Defect 2 fixed with a small pure helper:** new `app/nothingui/launcher/WidgetPickerRequestState`
  tracks the current request id, refuses stale completion, refuses a handled id, and cancels on a
  real `onPause`. `LawnchairLauncher` retries from `onResume`, the existing `onWindowFocusChanged`
  hook and `onStateSetEnd(NORMAL)` only; there is no poll loop. A non-NORMAL attempt leaves the
  request pending for the NORMAL transition instead of allowing a later unrelated resume to replay
  it. The expected `onNewIntent`-before-`onResume` path is not a pause, so it is preserved.
- **Request identity:** `WidgetPickerRequest` now adds an app-owned per-tap id extra (with a stable
  legacy fallback), removes both extras on consume, and returns the id. `handledId` is persisted in
  saved instance state so the same intent cannot replay; a newer request has a different id and is
  accepted even after an older handled request. Pending is intentionally not restored, so rotation
  never reopens it.
- **Fixtures:** new `tests/unit/java/app/nothingui/launcher/WidgetPickerRequestStateTest.kt` covers
  cold, warm, same-intent replay, non-NORMAL transition, expected resume, real pause/cancel,
  rotation/handled restore, stale completion, a newer request, and missing ids.
- **Untouched:** the existing Home popup/gesture `onNewIntent` path, Home app defaults/layouts,
  widget binding, Settings row, manifest/activity/permission/dependency/SDK/workflow/signing/
  applicationId, wallpaper, non-Play layout and private widget code. No emulator smoke was added
  this run; the measured Settings/Browse-widgets picker capture remains for the next phase.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `scripts/nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no APK);
  `scripts/nothingui-polish-guard.sh` OK; `sh -n` clean on both guards; `git diff --check` clean.
  Unit-test compilation/execution, style, Play build and every runtime lifecycle claim are CI/runtime
  gates and are NOT proven here.

## done (previous run — Play-customize dashboard entry, PENDING CI)

- **Dashboard:** a Play-only `Customize launcher` `PreferenceGroup` is added above the main group.
  Its single `PreferenceCategory` (`Icon size and home screen`, description `Icon size, labels and
  widgets`) navigates to the existing `HomeScreen` route with unchanged selection highlighting. The
  older main-group `Home screen` entry is hidden on Play only to avoid duplicate navigation; non-Play
  keeps the original dashboard exactly.
- **Home Screen:** a Play-only top `Customize launcher` group now hosts the actual existing
  `prefs2.homeIconSizeFactor` `SliderPreference` (same range 0.5–1.5, step 0.1, percentage display).
  The original slider block was MOVE-gated (`if (!isPlayStoreFlavor())`) out of the lower Icons
  group, so there is exactly one control per flavor and no duplicated preference. Icons labels /
  label size remain in the lower Icons group; widget switches/padding are untouched.
- **Strings:** three base additions — `customize_launcher_label`, `customize_launcher_description`,
  `icon_size_and_home_screen_label`. No unused import was added; both files already imported the
  helpers used.
- **Browse widgets explicitly deferred in that run:** no button was added then. The safe
  launcher-activity path is implemented in the newer section above; it is still PENDING CI/runtime.
- **Scope preserved:** no permissions, manifest, activity, dependency, SDK, workflow, signing,
  applicationId, theme, wallpaper, widget binding, HOME behavior or non-Play layout change.
- **Verification actually run:** `git diff --check` clean only. No Gradle/Android build, emulator,
  JUnit, APK or runtime rendering check. CI is the first compile/style check.

## done (previous run — runtime apply/pause-resume completion gate, PENDING CI)

- **Measured system confirmation only, after the static applies:** `capture_wallpaper_gallery` keeps
  `_cwg_preview_live_wallpaper` and both Pitch Black/Wireframe Torus applies, then calls the new
  `_cwg_apply_live_wallpaper`. It reopens the gallery through the existing measured
  `Preview live wallpaper` action and requires the exact `Dot Field (Live)` title from
  `com.android.wallpaper.livepicker` (`live_wallpaper_preview_is_dotfield`). It measures a positive
  `Set wallpaper` control fully inside the display above the measured navigation top and taps it
  once. No coordinate is hardcoded (CI208's `386,1638,693,1773` is evidence, not an input).
- **Destination fail-closed:** `live_wallpaper_destination_bounds` accepts only one exact, visible
  `Home screen` control above the navigation top. `live_wallpaper_destination_ambiguous` fails the
  run when a dialog offers only lock/lock-and-home options or duplicate Home screen labels. The
  smoke never taps a lock destination and never calls `setWallpaperComponent`, a shell wallpaper
  setter or a service binding. `dumpsys wallpaper` must report `DotFieldWallpaperService` in the
  System wallpaper state, with a changed Home ID and `wallpaper_lock_preserved`.
- **Real pause/resume, not a manual callback:** `_cwg_live_pause_resume` launches the opaque device
  Settings, proves Settings is the resumed activity, and requires a fresh post-baseline
  `visibility=false pending=false drawing=false` for one engine token. After a bounded hidden
  interval the normal HOME key resumes the exact same token with the exact same cumulative drawn
  count. Staying HOME and reopening Settings must hide the same token with a strictly larger drawn
  count. Each phase keeps baseline/full/sliced logcat, dumpsys, XML and screenshots; the shared
  crash history is never cleared and no global `logcat -c` is added.
- **Per-engine identity token:** `DotFieldWallpaperService` now stamps DEBUG transition lines with a
  stable `engine=<n>` token (`AtomicInteger`, no per-frame logging). The visible transition is
  logged before the resume frame is posted so its drawn count is exactly the hidden state. Existing
  `posted/drawn/pending/drawing` counters, the one-lock frame protocol and all gate/teardown fixes
  are preserved; the guard now requires the token.
- **Fixtures added:** hidden frame increase, no resume, mixed engine, pending/drawing true, stale
  visible outside the phase boundary, lock-only/duplicate/clipped/ambiguous destinations,
  non-numeric navigation top, System-vs-Lock service placement, and source wiring/order checks.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` all pass; `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped,
  no local APK); `nothingui-polish-guard.sh` OK; `sh -n` clean on every edited script;
  `git diff --check` clean. CI208 remains the preview-tested baseline; the runtime apply/pause gate
  is **PENDING** and must not be claimed until CI evidence is inspected.

## done (previous run — CI206 at-limit ScrollView measured viewport; CI208 then proved the preview)

- **Exact CI206 runtime failure, from the captured XML/pixels and not guessed:** on attempt 1 the
  `Preview live wallpaper` parent button was `[84,1678][572,1804]`, which crosses `navigation_top=1794`;
  the helper correctly rejected it and swiped. On attempt 2 the button was fully visible at about
  `[84,1447][572,1573]`, but the real scrolling surface was reported as
  `android.widget.ScrollView` bounds `[0,0][1080,1920]` with `scrollable="false"` because content was
  already at its end. `ui_scroll_container_bounds` accepts only `scrollable="true"`, returned nothing,
  and `_cwg_measure_control` failed even though the screenshot showed the unobscured red preview
  action above the navigation bar. CI206 logs established no app failure.
- **Minimal harness fix:** the strict generic `ui_scroll_container_bounds` is unchanged in behavior.
  New pure `ui_known_scroll_container_bounds` accepts only an exact `android.widget.ScrollView`
  (what UiAutomator reports for the Compose vertical-scroll surface) with `scrollable="false"`, a
  matching expected app package, and strictly positive measured bounds; it ignores arbitrary
  root/decor/other views, wrong-package nodes and missing/zero bounds, and clips below the measured
  navigation top exactly like the strict helper. `_cwg_measure_control` now tries the strict
  scrollable viewport first, then this package-scoped known-container fallback with `$PKG`. No
  coordinate is hardcoded, partially clipped controls still fail, and every navigation guard remains.
- **Regression fixtures:** a non-scrollable at-limit real ScrollView with a fully contained measured
  clickable ancestor now succeeds (and is clipped at both `1794` and `1700`); the initial control
  crossing the navigation top still fails; a root-only node, an arbitrary `android.view.View`, a
  ScrollView without bounds, a zero-bounds ScrollView, a wrong-package ScrollView and a missing
  expected package all fail. Source checks require the exact class/package/scrollable/bounds rules
  and the strict-before-fallback order. Existing source fixtures and drawer controls are preserved.
- **Preserved:** fresh-logcat prefix boundary and frame gate/lock fixes from `69b3541`/`71a7c90`,
  app/service/UI behavior, rendering, permissions, manifest, applicationId, SDK, signing, themes,
  HOME, widgets, static wallpaper, workflows and dependencies. No private widget code or artifact.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` all pass (**635 ok**); `emulator-smoke-drawer-test.sh` all pass;
  `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no local APK);
  `nothingui-polish-guard.sh` OK; `sh -n` clean on every edited script; `git diff --check` clean.
- **Still open:** preview, actual system apply and the pause/resume draw gate are unproven; do not
  claim the system preview passed. `2f619da` (CI196) remains the verified fallback. Weather,
  privacy, PrivateSpace, settings/backup round-trip, non-Play, large-screen and performance audits
  remain open. No merge, release or hosting.

## done (previous run — CI205 compile/style repair)

- **Exact CI205 failure:** unit job 137516923479 failed at `DotFieldWallpaperService.kt` line 26 and
  line 241 with unresolved `BuildConfig`; the service imported `app.lawnchair.BuildConfig` while the
  real generated class is `com.android.launcher3.BuildConfig` (module `namespace` in `build.gradle`
  line 151; `NothingUiFeature` and the rest of the fork use it). The unit tests did not run.
- **Compile fix (one import):** `DotFieldWallpaperService.kt` now imports
  `com.android.launcher3.BuildConfig`. No logic, lifecycle, lock, rendering, log text or line of engine
  behavior changed; `BuildConfig.DEBUG` still gates the transition trace.
- **Exact style failure:** style job 137516923552 reported only `DotFieldWallpaperPolicy.kt`
  `canDraw` and `verticalOffset`, each split after `=`. Both are now single-line expression bodies,
  exactly as ktlint requires; all tokens are preserved.
- **Narrow source regression:** `scripts/nothingui-wallpaper-guard.sh` now requires the service to
  import `com.android.launcher3.BuildConfig`, rejects `app.lawnchair.BuildConfig`, and requires the
  `BuildConfig.DEBUG` trace gate.
- **Preserved:** service/engine logic, rendering, manifest/permissions, themes, HOME, widgets, static
  wallpaper, workflow, dependencies, SDK, signing and applicationId are untouched; fixes `69b3541`
  and `71a7c90` remain intact. No private widget code or artifact.
- **Verification actually run (no Gradle, no Android build, no ktlint binary, no emulator):**
  `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no APK);
  `nothingui-polish-guard.sh` OK; `sh -n` clean on the edited guard; `git diff --check` clean.
  Unit compilation/tests were **not** executed this run.
- **Still open:** `2f619da` (CI196) remains the verified fallback; no new APK is ready. Runtime preview,
  actual system apply and the pause/resume draw gate are unproven. Weather, PrivateSpace,
  settings/backup round-trip, non-Play, large-screen and performance audits remain open. No merge,
  release or submission.

## done (previous run — PR19 review correction: logcat boundary and frame lifecycle)

- **Issue 1 — logcat history:** `_cwg_preview_live_wallpaper` no longer calls `logcat -c`. It saves a
  read-only `live-wallpaper-logcat-before.txt` baseline before the measured tap, captures the full
  `live-wallpaper-logcat.txt` as before, and derives preview-only
  `live-wallpaper-logcat-preview.txt` with the new pure `live_wallpaper_preview_log_after` helper.
  The helper requires the baseline to remain an exact prefix of the full capture; a missing baseline,
  empty/rotated buffer or non-numeric count fails closed. The full logcat is untouched for the final
  crash/ANR checks in `emulator-smoke.sh`.
- **Issue 2 — visibility, not surface:** `live_wallpaper_became_visible` now requires the engine's
  own `visibility=true` line in the fresh preview-only slice. `surface=created` alone, hidden-only,
  empty and unrelated logs fail closed. No rendered frame is claimed from visibility alone; the
  test description and docs were corrected.
- **Issue 3 — one frame protocol:** `DotFieldWallpaperService` now uses a single `ReentrantLock` plus
  an idle `Condition`. Gate (`policy.canDraw`), `framePending = true`, counter and enqueue happen in
  one `withLock`; teardown removes queued callbacks and awaits `drawing` on the condition.
  `beginFrame`/`finishFrame` publish `drawing` and `signalAll` under the same lock. Visibility
  false, surface destruction and engine destruction all call `cancelAndAwaitIdle`, so none can
  return with a queued frame or a draw still in flight. `await()` releases the lock (no join while
  locked). No new dependency, no per-frame allocation and no per-frame logging; DEBUG transition
  lines now carry cumulative `posted`/`drawn`/`pending`/`drawing` counters.
- **Regression checks actually run:** new shell fixtures cover the append boundary, a stale
  pre-baseline visibility line, a rotated buffer, a missing baseline and surface-only rejection.
  Source checks in `emulator-smoke-test.sh` assert the preview body has no `logcat -c`, uses the
  baseline/slice, and inspect the exact lock placement (`withLock` gate+enqueue, `idle.await`,
  `idle.signalAll`, all three teardown call sites, counters, no per-frame `logTransition`).
  `nothingui-wallpaper-guard.sh` also requires the lock/condition structure and the baseline/slice
  wiring.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped, no APK);
  `nothingui-polish-guard.sh` OK; `emulator-smoke-test.sh` all pass (**618 ok**);
  `emulator-smoke-drawer-test.sh` all pass; `sh -n` clean on every edited script;
  `git diff --check` clean. No workflow, manifest, permission, SDK, signing, applicationId or
  dependency was touched; static wallpaper, HOME, widgets and theme behavior are unchanged.
- **Blocked/unknown:** no local JUnit, APK, merged manifest or emulator result exists. The
  `ReentrantLock` protocol is source-checked, not concurrency-tested; apply and pause/resume remain
  explicitly unproven until CI runs the real preview. No merge, release or completion claim.

## done (previous run — original dot-field live wallpaper, preview-only runtime gate pending)

- **Original art, not a redesign:** a deterministic monochrome dot field is drawn on a Canvas at a
  visible frame cadence of about 15 fps with a restrained 14 s breathe/drift cycle and a sparse
  existing red accent (`0xFFD7261E`). Geometry derives from the real `SurfaceHolder` frame; there is
  no copied asset, network, location, storage, sensor, alarm, wake lock or foreground service.
- **Live policy (JVM-testable):** `DotFieldFramePolicy` gates every frame on engine alive + visible +
  valid non-zero surface, handles create/change/destroy and terminal engine destruction, and exposes
  the ~66 ms cadence. `DotFieldGeometry` rejects zero/negative sizes and resizes on rotation.
  `DotFieldMotion` supplies the bounded slow phase. The drawing loop uses preallocated paints and
  primitive canvas calls (no per-frame allocations).
- **Engine lifecycle:** `DotFieldWallpaperService.Engine` owns one drawing `HandlerThread`, checks
  `holder.surface.isValid` before locking, and calls `removeCallbacksAndMessages(null)` on visibility
  false, surface destruction and engine destruction. Frames are never posted unless the pure gate
  passes; a destroyed engine is terminal. Transition-only `Log.d` lines are DEBUG-only (no per-frame
  spam). Each engine has its own thread/policy, so independent preview instances are safe.
- **Play-only declaration:** `play/AndroidManifest.xml` adds only the service with
  `android:permission="android.permission.BIND_WALLPAPER"`, the
  `android.service.wallpaper.WallpaperService` action and `@xml/dotwel_dot_field_wallpaper`.
  `play/res/xml/dotwel_dot_field_wallpaper.xml` carries the description/thumbnail, and
  `play/res/drawable/dotwel_live_wallpaper_thumbnail.xml` is generated original dot geometry. No
  `uses-permission` was added; SDK/dependency/workflow/signing/applicationId are untouched.
- **Explicit settings action, separate from the two static choices:** the existing AMOLED screen gains
  a distinct `Live wallpaper` group whose button launches the platform
  `ACTION_CHANGE_LIVE_WALLPAPER` with `EXTRA_LIVE_WALLPAPER_COMPONENT` for our service, with
  resolution/failure feedback. Entering settings or the preview never applies anything, and the app
  never calls `setWallpaperComponent`. The two static tiles, preview/Apply/Cancel and lock guards are
  unchanged.
- **Guards and smoke:** `nothingui-wallpaper-guard.sh` now asserts the Play-only BIND_WALLPAPER
  service/action/metadata/thumbnail, no added permission or forbidden platform service, the frame
  gate and callback cleanup, and the explicit non-setting preview launch. `emulator-smoke.sh` adds a
  bounded `_cwg_preview_live_wallpaper` phase that measures the action, opens the real system picker,
  retains preview pixels and `dumpsys wallpaper`/logcat, requires a DEBUG `DotFieldWallpaper`
  visibility/surface transition, and requires Back to leave Home/Lock IDs unchanged. New pure
  `live_wallpaper_preview_is_ready` and `live_wallpaper_became_visible` helpers fail closed on the
  settings gallery, HOME, empty/unknown captures and hidden-only logs. No workflow was edited.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-wallpaper-guard.sh` OK (compiled sentinel skipped with no APK);
  `nothingui-polish-guard.sh` OK; `emulator-smoke-test.sh` all pass (**593 ok**, including the new
  preview/log fixtures and source wiring); `emulator-smoke-drawer-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. XML metadata/manifest/strings parse cleanly.
- **Blocked/unknown:** no local JUnit, APK, merged manifest or emulator result exists. The policy
  test, style, Play build and every runtime proof are CI gates. The debug transition assertion may
  need the first real CI logcat to confirm the platform picker binds our preview engine; if it does
  not within the bounded polls, the run fails closed. System confirmation was deliberately not
  accepted, so HOME dots/destination/widget/Lock and the pause/resume draw gate remain unproven.
  No merge, release or Play submission.

## done (previous run — wallpaper preview scroll ordering)

- **Root cause from the CI195 runtime stop, not guessed:** `capture_wallpaper_gallery` grepped the
  initial unscrolled `wallpaper-preview-<mode>.xml` for `Apply to Home screen`, `CC BY 4.0` and the
  licence URL before calling the measured-scroll helper. The selected preview begins near the viewport
  bottom, so the credit, licence and buttons are below the fold and absent from that XML.
- **Ordering only:** after the existing tile tap, initial preview XML/PNG capture, the smoke now uses
  the existing bounded, navigation-aware `_cwg_measure_control` scroll to reveal each item before
  asserting it, in both dark and light modes. No app, layout, resource, licence, asset, dependency,
  SDK, permission, manifest, signing, applicationId or workflow changed; no screen coordinate is
  hardcoded.
- **Exact evidence kept:** the CC BY 4.0 attribution is asserted from the revealed XML of the exact
  `Copyright (c) 2024 Tecdrop. CC BY 4.0.` credit; the licence is a measured visible control whose
  exact text is `License: https://creativecommons.org/licenses/by/4.0/`; Apply is a measured exact
  visible `Apply to Home screen` control, so the hint text mentioning Apply is not accepted. Cancel
  preview is still measured and tapped, never a fake undo.
- **Fresh evidence:** on every successful reveal the helper copies the measured XML to
  `wallpaper-scroll-<tag>-visible.xml` and captures the matching `wallpaper-scroll-<tag>-visible.png`,
  so attribution, licence, Apply and Cancel are checked in a measured visible viewport rather than
  requiring all offscreen content in one XML.
- **Preserved:** the initial preview XML/PNG, Cancel/Back/no-implicit-change proofs, both explicit
  Pitch Black/Torus Home-only applies, real Home/Lock ID assertions, widget/layout preservation,
  immutable selection while applying, safe navigation boundaries and all earlier theme/drawer/widget
  evidence. No assertion was weakened or skipped.
- **Regression fixture:** `emulator-smoke-test.sh` now extracts `capture_wallpaper_gallery` and checks
  that the attribution reveal precedes its `CC BY 4.0` assertion, the licence reveal precedes its URL
  assertion, and the exact Apply measurement precedes Cancel; it also checks both assertions read the
  `-visible.xml` evidence rather than the initial preview XML.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` all pass (576 ok); `nothingui-wallpaper-guard.sh` OK (compiled sentinel
  skipped with no local APK); `nothingui-polish-guard.sh` OK; `sh -n` clean on the edited scripts;
  `git diff --check` clean.
- **Blocked/unknown:** no local APK, JUnit, merged manifest or emulator result exists. CI195's
  compiled packaging/style/unit evidence is separate from the still-pending runtime proof: the
  scrolled preview attribution/licence/controls, Cancel/Back no-ID change, Pitch Black/Torus Home-ID
  changes, Lock preservation and widget/layout preservation are CI gates. CI195 stays withheld; the
  later known-good fallback is `2f619da` (CI196), not CI181/CI195. No merge, release or final design
  acceptance.


## done (this run — PR19 Torus packaging and formatter repair)

- **Root cause from source and the installed APK, not guessed:** one Torus source path is 41,359
  bytes. AAPT replaced it with `STRING_TOO_LARGE` inside the packaged
  `res/drawable-nodpi-v4/dotwel_wallpaper_wireframe_torus.xml`; Compose parsed that sentinel and
  failed on `R` in the `WallpaperTile` `painterResource` call.
- **Minimal packaging split:** only that path was split at existing independent absolute-`M`
  subpath boundaries into three consecutive `<path>` elements (15,732 / 15,534 / 10,093 bytes).
  Each repeats the exact source `fillColor`, `strokeColor` and `strokeWidth`; document order,
  every coordinate, subpath and appearance are unchanged. No geometry was simplified, rounded,
  redrawn or rasterized, and no other vector path or PNG changed.
- **Byte-identity proof:** concatenating the split `pathData` values reproduces the original 46,572
  bytes with SHA-256 `19ee5302492cf69ffae43392267f1fc1b9a386c4ab09634dc266848f528f7bcd`
  and all 69 subpaths. Source/recolored SVG hashes, licence texts, attribution and the PNG hash
  are unchanged. A short provenance note documents the packaging split.
- **Source guard:** `nothingui-wallpaper-guard.sh` now rejects any `pathData` of 16,000 bytes or
  more and re-checks the concatenated byte count, SHA-256 and subpath count.
- **Compiled sentinel guard:** when the real Play debug APK exists under
  `build/outputs/apk/lawnWithQuickstepPlayDebug`, the same guard inspects every packaged Torus XML
  for `STRING_TOO_LARGE` in ASCII, UTF-16LE or UTF-16BE and fails closed. With no APK it prints a
  skip and keeps source-only/minimal fixtures working. No workflow, dependency or infrastructure
  changed. A synthetic bad APK failed as expected; a clean synthetic APK passed.
- **Formatter-only Kotlin repair:** ran the matching ktlint 1.8.0 with compose rules 0.6.8 and
  applied only its output to the three diagnosed files: one Preferences import order swap,
  `java.io` before `kotlinx` in the applier, blank lines between the multiline `when` branches,
  and the two short expression bodies joined to their signatures. A rerun reports zero violations.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-wallpaper-guard.sh` OK (source checks; APK sentinel skipped because no local APK);
  `nothingui-polish-guard.sh` OK; `emulator-smoke-test.sh` all pass;
  `emulator-smoke-drawer-test.sh` all pass; `sh -n` clean; `git diff --check` clean; ktlint clean.
  The expensive nested `verify-play-build-test.sh` suite was deliberately not rerun.
- **Blocked/unknown:** no local APK, JUnit, merged manifest or emulator result exists. Compiled
  sentinel absence is **not** claimed until the real CI APK is inspected. The gallery opening,
  Torus preview, measured Apply/Cancel and pixel/ID proofs remain CI gates. No merge, release or
  final design acceptance.

## done (previous run — pre-CI wallpaper gallery repairs)

- **Wallpaper ID parser (current AOSP):** `wallpaper_ids_from_dump` now reads the real
  `WallpaperManagerService.dump`/`dumpWallpaper` format: `System wallpaper state:`,
  `Lock wallpaper state:` and `Fallback wallpaper state:` sections with
  ` User <id>: id=<wallpaperId>: mWhich=...: mSystemWasBoth=...: mBindSource=...` rows. It parses
  only the System/Lock sections, ignores the fallback and other users, accepts an explicit current
  user (or a single System user), and fails closed on missing or ambiguous target evidence. Legacy
  `Home wallpaper ID` / `mWallpaperId` / `mLockWallpaperId` fixtures still parse only when no current
  System section exists. `_cwg_read_ids` supplies the emulator user from `am get-current-user` and
  keeps every raw dump as an artifact. No protected wallpaper image is read.
- **Lock preservation tightened:** when the prior lock was shared/absent (`-`), a changed Home is
  preserved only if the lock materialises with an ID equal to the prior Home ID. A still-absent lock
  after a changed Home is no longer accepted as proof.
- **Fixtures:** new current-format separate-lock, truly empty Lock section/shared Home, multiple
  users (current and explicit user, ambiguous no-user, missing user), fallback-only, missing System
  section, empty System section and malformed inputs; the legacy fixtures remain.
- **Licence links in the APK UI:** `AmoledWallpaper` now carries the exact CC BY 4.0
  (`https://creativecommons.org/licenses/by/4.0/`) and CC0 1.0
  (`https://creativecommons.org/publicdomain/zero/1.0/`) URLs, and the preview shows a visible
  `License: <url>` button next to `Source: <url>`. Tecdrop copyright, the source link and the
  rename-only notice remain visible. Both link taps use `runCatching`, so an unsupported external
  link cannot crash Settings; there is no runtime download. `docs/wallpapers` and
  `licenses/wallpapers` are unchanged.
- **Cancel preview:** a new explicit `Cancel preview` control clears the selection and message
  without applying; normal Back is untouched and preview/Cancel never call the applier.
- **Apply-state guards:** the tile `selectable` is disabled while applying, its `onSelect` is
  guarded, the Apply button stays disabled during the job, and Cancel preview is disabled in flight
  (not a fake undo). The selected ID uses `rememberSaveable`; `applying`/the job are not saved, so a
  recreation cannot retrigger an apply.
- **Play route gate:** `composable<AmoledWallpapers>` (including its deep link) is now registered
  only when `isPlayStoreFlavor()` is true, matching the already-gated dashboard/Home Screen links.
  Other navigation and non-Play behavior are unchanged; no manifest change.
- **Measured scroll in the smoke:** new pure `ui_scroll_container_bounds`,
  `ui_clickable_label_within` and `settings_scroll_target` helpers read the real `scrollable="true"`
  settings container clipped to the measured navigation safe viewport. `_cwg_measure_control`
  re-captures, records each attempt, accepts only a fully visible tappable Apply/Cancel, swipes
  inside the measured band, and fails after four attempts. It replaces the direct Apply tap and
  drives Cancel preview; no hardcoded phone height or coordinates.
- **Preserved:** all assets/hashes/vector paths, palette/geometry, Home-only applier, the `69`
  spacing clip, existing native/widget smoke, and every workflow/dependency/SDK/permission/
  provider/signing/manifest/application-ID/system-nav/default-home setting. No gallery rebuild,
  theme reopen, release, merge or local Android build.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` all pass (including the new parser/scroll fixtures);
  `nothingui-wallpaper-guard.sh` OK; `nothingui-polish-guard.sh` OK;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean. No local `ktlint`/`spotless` binary is installed, so Kotlin style was checked by the
  existing source guard and manual import/trailing-comma review only.
- **Blocked/unknown:** no local JUnit, APK, merged-manifest or runtime pixel result. The actual
  emulator `dumpsys wallpaper` output, the measured Apply/Cancel scrolling, Cancel-preview IDs and
  the Play deep-link gate are **not** proven until the next combined API 37 CI. No completion claim;
  PR19 is not merged.

## done (previous run — offline AMOLED wallpaper gallery)

- **Assets fetched once, hashes exact:** Tecdrop `pitch-black-wallpaper-fhd-mobile-1080x1920-1bit.png`
  (348 B) SHA-256 `d0e03819…58181d` is committed as
  `lawnchair/res/drawable-nodpi/dotwel_wallpaper_pitch_black.png` with bytes unchanged and only the
  filename changed. Walldye `db0311a07de8.svg` (46,935 B) SHA-256 `db0311a0…fd074f0` is kept under
  `docs/wallpapers`; the literal-colour recolour hashes `cd1c1671…f5612d1`. Provenance, licence and
  transformation notes are in `docs/wallpapers/README.md` and `licenses/wallpapers/`; visible in-app
  credit, source link and the Tecdrop rename-only notice are rendered in the preview.
- **Vector conversion:** `dotwel_wallpaper_wireframe_torus.xml` keeps the 1080×2340 viewport, all
  source `pathData`, the rect geometry, literal stroke widths 1.2/1.6/3, source round caps and no
  fill on stroked paths, with the four recoloured values. No generator/site/tool code copied.
- **Gallery:** Play-only `AmoledWallpaperPreferences` uses the existing typed
  `AmoledWallpapers` `PreferenceRootRoute`, `PreferenceNavigation`, `PreferenceLayout` and normal
  Back. It is linked near Home Screen on the dashboard and inside the existing Home Screen wallpaper
  group. Exactly two labelled tiles (Pitch Black, Wireframe Torus) use Compose painters; selecting
  one shows a larger preview, credit, source link and a separate explicit `Apply to Home screen`
  button. Preview/Back never apply. No new activity, manifest entry or identity route.
- **Apply:** after the explicit tap, the applier checks `isWallpaperSupported` /
  `isSetWallpaperAllowed`, streams the PNG resource with
  `setStream(..., null, true, FLAG_SYSTEM)`, renders the vector to a bounded 1080×2340 bitmap on IO
  with `setBitmap(..., null, true, FLAG_SYSTEM)`, recycles the bitmap and confirms the positive
  returned ID equals `getWallpaperId(FLAG_SYSTEM)`. It guards repeat taps, rethrows cancellation and
  distinguishes unsupported/policy/security/IO/unconfirmed results. No FLAG_LOCK, provider,
  storage permission or protected-image read.
- **Harness:** `ui_navigation_bar_bounds` now also reads a visible modern
  `InsetsSource type=navigationBars` bracket or `Rect` frame before the display fallback, with new
  fixtures; legacy fixtures and fail-closed behavior stay. New `wallpaper_ids_from_dump` and
  `wallpaper_lock_preserved` helpers parse Home/Lock IDs and allow only the documented shared-lock
  sentinel. `emulator-smoke.sh` adds `capture_wallpaper_gallery` after the existing native/theme
  captures: dark/light gallery and Pitch Black preview captures, ID/widget-unchanged preview/Back
  proof, then explicit Pitch Black and Torus applies with Home-ID change, lock preservation, widget
  ID equality and `verify_home_widgets`. Drawer mid-scroll/end proof and all old checks are retained;
  no workflow was edited.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-wallpaper-guard.sh` OK; `nothingui-polish-guard.sh` OK and suite passed;
  `emulator-smoke-test.sh` all pass; `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean.
- **Blocked/unknown:** no local JUnit/APK/merged-manifest/pixel result. The runtime `dumpsys
  wallpaper` format, the deep-link gallery opening, the measured Apply button, and the new emulator
  captures are **not** proven until the next API 37 CI. No completion claim, no merge, no release.

## done (this run — Play-only drawer bottom drawing boundary)

- **Root cause from the live code, not guessed:** `ActivityAllAppsContainerView.applyAdapterSideAndBottomPaddings`
  already sets the recycler bottom padding to `max(mInsets.bottom, mNavBarScrimHeight)` and
  `AdapterHolder.applyPadding` adds the work/private/floating-search offsets. `all_apps_rv_layout.xml`
  explicitly keeps `android:clipToPadding="false"`, so scrolled children paint into that reserved
  bottom area even though the inset math is correct. This run changes the drawing boundary, not the
  padding.
- **Smallest Play-only clip:** new pure `app.nothingui.drawer.AllAppsBottomClip` returns
  `height - paddingBottom` (clamped at 0) only when the Play gate is on and `paddingBottom > 0`,
  otherwise `NO_CLIP`. `AllAppsRecyclerView.dispatchDraw` saves the canvas, clips only the bottom
  (`0..width`, `0..clipBottom`), draws children, and restores the save count. No `Rect` is allocated
  per frame, the top overflow is untouched, and `SearchRecyclerView` inherits the same boundary.
- **Gate:** reuses `NothingUiFeature.INSTANCE.getHomeEnabled()` (`NOTHINGUI_HOME_ENABLED`, Play
  only). Non-Play and zero/negative-inset layouts keep the inherited drawing exactly.
- **Preserved:** the existing bottom padding and the final row's ability to scroll fully into view;
  top padding overflow for floating headers/search; left/right geometry; fast scrolling; profile
  tabs and work/private/floating-search offsets; LIGHT/DARK/SYSTEM and every saved preference;
  wallpaper/workspace/widget IDs, navigation mode, activity flags, theme/opacity/background choices.
  No workflow, dependency, SDK, permission, signing, applicationId, manifest or release change.
- **Regression coverage:** new `tests/unit/java/app/nothingui/drawer/AllAppsBottomClipTest.kt`
  covers Play vs non-Play, zero/negative inset, exact fit, oversized padding and non-positive
  height. `emulator-smoke-test.sh` adds fixtures for navigation-bar frame/fallback/no-data, list
  bounds, sibling-search-bar exclusion, ancestry-scoped final row, stable/changed scroll signatures,
  the safe scroll gesture and a degenerate list, plus source-wiring checks for the helper, gate,
  save/restore and unchanged `clipToPadding="false"`.
- **Emulator script only:** `emulator-smoke.sh` gains `capture_drawer_bottom_boundary`, called after
  `exercise_app_drawer`. It captures mid-scroll and true end-of-list XML+PNG, the raw
  `dumpsys window` dump and resolved navigation bounds, then requires the measured final row bottom
  to be at or above the navigation top. Scrolling is bounded to six swipes and stops only on a stable
  row signature; missing navigation/list/row measurements fail closed. No workflow was edited.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **546/546**; `emulator-smoke-drawer-test.sh` all pass;
  `nothingui-polish-guard.sh` OK and its suite all pass; `verify-play-build-test.sh` all pass;
  `sh -n` clean on all three edited scripts; `git diff --check` clean.
- **Blocked/unknown:** no local JUnit, APK, merged-manifest or post-change pixel result. The new
  JUnit test, the Play build/style and the API 37 drawer/navigation captures are CI gates. The
  native-theme recreation candidate from the previous run is **not** re-proven here. PR19 is not
  merged. Wallpaper gallery and charcoal-not-AMOLED remain separate future work.

## done (previous run — Play HOME uiMode recreation candidate)

- **Candidate, not a claimed fix:** the only production change is `play/AndroidManifest.xml`,
  removing `uiMode` from the Play `LawnchairLauncher` `android:configChanges`. Every other flag and
  manifest field is unchanged; the non-Play manifests are untouched (the base launcher already
  omits `uiMode`). No `tools:replace` was needed because the Play overlay already supplies the
  higher-priority `configChanges` value and the base never declared `uiMode`; no source blocker was
  found.
- **Platform behavior:** an activity that does not declare `uiMode` is recreated by Android for a
  night-mode change and resolves fresh resources; declaring it transfers manual refresh to the app.
  The existing scoped `WallpaperThemeManager` callbacks/cleanup and debug `DotWelTheme` trace are
  preserved for independent proof. No global resource mutation, `updateConfiguration`, always-dark,
  `disabledSYSTEM`, theme preference write, delayed loop, force-stop or weakened readiness was
  added.
- **Guard/fixtures:** `nothingui-polish-guard.sh` now checks the source Play and base
  `LawnchairLauncher` `configChanges`: no `uiMode`, all inherited geometry flags retained, HOME
  still on the launcher, and the existing DotWel Settings MAIN/LAUNCHER/no-HOME routing.
  `verify-play-build.sh` applies the same `configChanges` and HOME/settings routing checks to the
  Gradle-merged manifest. New negatives cover Play/base `uiMode`, a missing geometry flag, and
  merged `uiMode`/missing flag.
- **Preserved:** LIGHT/DARK/SYSTEM, explicit transparency, wallpaper/workspace DB/widget IDs and
  placements, native back/OS navigation, non-Play, drawer opacity, settings entry and default-home
  status. No gallery/control-center/new-widget integration, release or hosting work. Bottom
  drawer/gesture crowding remains OPEN; this does not claim opacity or padding fixes it.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-polish-guard.sh` OK; `nothingui-polish-guard-test.sh` **12/12**;
  `verify-play-build-test.sh` **13/13**; `play-brand-guard.sh` and `play-identity-guard.sh` OK;
  `play-brand-guard-test.sh` passed; `nothingui-theme-guard.sh` OK and its suite passed;
  `sh -n` clean on all four edited scripts; `git diff --check` clean.
- **Blocked/unknown:** no local JUnit, APK, merged-manifest or pixel result. CI179's native dark
  readiness failure is not proven fixed; the next API 37 CI/pixels must confirm the recreation
  candidate. PR19 is not merged.

## done (previous run — Play polish: opaque drawer default, settings entry, default-home status)

- **Drawer opacity (unset only):** `PreferenceManager` keeps the same `pref_drawerOpacity` key and
  now passes `DrawerOpacityDefaults.forPlayFlavor(isPlayStoreFlavor())`. The pure helper returns
  `1.0f` on Play and `0.5f` on github/nightly. `FloatPref.get()` still reads
  `sp.getFloat(key, defaultValue)`, so every explicitly saved value (including `0.5`, `0`, or a
  custom one) wins and nothing migrates or resets the preference. Slider, text/background colour,
  scrim and all-apps header consumers all keep reading the same `drawerOpacity` preference.
- **Play settings entry:** `play/AndroidManifest.xml` adds only a MAIN/LAUNCHER intent-filter (and a
  clear `DotWel Settings` label via `play_settings_label`) to the existing
  `app.lawnchair.ui.preferences.PreferenceActivity`. It does not add HOME, does not add an
  activity-alias or a second app/package, and leaves `APPLICATION_PREFERENCES` and the
  `lawnchair://settings` deep link in `lawnchair/AndroidManifest.xml`. `LawnchairLauncher` keeps HOME
  and remains the launcher activity.
- **Default-home status:** the dashboard now remembers `isDefaultLauncher()` and re-checks it in
  `LifecycleResumeEffect`, so the card is correct after returning from the platform role dialog or
  cancelling. The not-default card still uses `DefaultHomeRoleConsent` only on the user tap, is
  Play-gated, and has a `runCatching`-guarded `Settings.ACTION_HOME_SETTINGS` fallback. When the
  app is default, Play shows a small matching `X is your default home` status card. No automatic
  role request, no silent default change.
- **Insets:** inspected `BottomSpacer`/`PreferenceLayout`; the Box takes the max of the nav-bar and
  IME spacer rather than summing them, so there is no clear duplicate-padding defect. Nothing was
  changed.
- **Regression checks:** new `DrawerOpacityDefaultsTest` (Play 1.0, inherited 0.5, distinct
  constants) and new `scripts/nothingui-polish-guard.sh`/`-test.sh` (unset-vs-saved fallback,
  Play gating, one MAIN/LAUNCHER settings entry with no HOME, preserved base filters, resume
  refresh, guarded fallback, no startup role request, duplicate-entry and negatives). The suite is
  wired into `verify-play-build.sh`; no workflow was edited.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `nothingui-polish-guard.sh` OK and its suite **9/9**; `nothingui-home-role-guard.sh` OK and suite
  **7/7**; `play-brand-guard.sh` OK and suite **22/22**; `verify-play-build-test.sh` **11/11**;
  `sh -n` clean on all three edited/new shell scripts; `git diff --check` clean.
- **Blocked/unknown:** no local JUnit, APK, merged-manifest or pixel result. CI174's native dark
  readiness failure is not addressed here; this run deliberately does not claim a native theme fix.
  PR19 is not merged.

## previous run — stale native theme refresh and AMOLED foundation (runtime unverified)

> Correction: CI174 later failed the API 37 native dark readiness check. Treat the native-refresh
> claims below as unproven, not as a fixed theme. `ca472427` only preserved diagnostics.

- **Diagnosed from the reported screenshots, not guessed:** the Compose settings screen changed with
  system night mode, but the native HOME long-press popup and app drawer, including the own widgets,
  stayed light while `pref_launcherTheme=system`. `WallpaperThemeManager` re-read the activity theme
  in `onConfigurationChanged` but did not remember the expected theme or re-check on resume, so a
  launcher stopped while the system theme changed could keep a stale native activity theme.
- **Native refresh fix:** `WallpaperThemeManager.updateTheme()` now returns early when the activity
  already has the expected theme, otherwise records it with `setTheme` and recreates for an actual
  change. A scoped `onActivityResumed` re-runs the check only for the manager's own activity.
  `onActivityDestroyed` now removes the wallpaper listeners, unregisters the component callbacks and
  the lifecycle callbacks, so no recreate loop or leaked callbacks remain. No theme preference,
  workspace or file label is changed.
- **Evidence:** new debug-only `DotWelTheme` trace
  `theme-refresh night=... resolvedDark=... expected=...` is emitted only when
  `BuildConfig.DEBUG`; it reads the resolved native activity theme through
  `UiColorMode(Themes.getAttrInteger(activity, R.attr.uiColorMode)).isDarkTheme`. Release builds
  carry no trace.
- **AMOLED foundation:** the dark settings background and native drawer/header/tab background are
  now `NothingUiPalette.Black` (pure black); popups, cards and elevated surfaces stay charcoal
  (`Gray900`/`Gray700`). `NothingUiPalette.Ink` is unchanged because it is also light-mode
  foreground text. Light colors are unchanged, and non-Play paths keep the inherited tokens. The
  settings top bars and the edge-to-edge navigation-bar scrim switch to the pure-black background
  only on the Play theme gate when the resolved background is black; Back/predictive navigation, nav/IME insets and the
  `BottomSpacer` behavior are untouched.
- **Smoke readiness:** before each native popup/drawer capture the smoke reads back
  `cmd uimode night`, then polls the debug trace from a per-mode logcat baseline until it reports the
  expected night and resolved dark state. It stores `native-theme-<mode>-system-night.txt` and
  `native-theme-<mode>-state.txt` before capturing. A stale pre-switch line cannot satisfy the next
  mode, and the smoke still never writes a theme preference. `docs/agent/emulator-verification.md`
  records the readiness and AMOLED evidence.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **517/517**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-theme-guard.sh` OK and suite 15/15; `nothingui-native-surfaces-guard.sh` OK and suite
  17/17; `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite
  19/19; `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-icon-render-guard-test.sh` 15/15; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; all source guards OK; `sh -n` clean on the edited scripts;
  `git diff --check` clean. `verify-play-build.sh` then stopped only at the expected missing
  `build/intermediates` because Gradle did not run.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the native dark/light popup and drawer
  now match settings and Home, and that the new readiness trace is present before each capture. No
  runtime, APK or pixel claim is made from fixtures. PR19 is not merged.

## done (previous run — CI165 no-header later-page swipe geometry recovery)

- **Root cause from CI165, not guessed:** `workspace_page_swipe` still required the labelled-row
  `ui_dock_top` and a nonempty `ui_header_bottom`. The genuine later page has workspace
  `0 0 1080 1920`, hotseat `0 1481 1080 1920`, the Calendar host at `38 107 524 738`, a
  Gallery/Settings icon row at y=1196 and no `search_container_workspace` header. The labelled row
  reported 1196 and the header was absent, so the helper printed nothing and the return swipe
  failed. The app, design, workflow, SDK, permissions, signing, release and AMOLED files were
  untouched.
- **Page-local swipe:** `workspace_page_swipe` now reads the actual `workspace` (or
  `workspace_right`/`workspace_grid`) and `hotseat` bounds, validates both are numeric and
  nondegenerate, and requires the hotseat top to be below the workspace top. It starts the safe
  band at the real `ui_header_bottom` when one exists, otherwise at the measured workspace top, and
  never inherits a first-page header or invents a fraction. y is the midpoint above the actual
  hotseat; x endpoints are absolute and strictly inside the actual workspace, including nonzero
  origins. Missing/malformed/degenerate workspace or hotseat, an impossible band, or an unknown
  direction fails closed. Generic drawer helpers and `ui_dock_top`/`ui_header_bottom` themselves are
  unchanged.
- **Handoff audit:** the only no-header assumption in the third-party handoff was this swipe helper.
  `search_home_pages_for_widget`, `restore_primary_home`/`primary_home_is_ready`,
  `verify_nothing_home`/`verify_home_widgets`, and the subsequent drawer/Settings/native checks do
  not require a later-page header. The smoke still completes third-party proof first, then restores
  the primary HOME with the normal HOME key and runs the existing `verify_nothing_home`.
- **Fixtures:** CI159 first page (header bottom 312, hotseat 1481) yields next `864 896 216 896` and
  prev `216 896 864 896`; the no-header later page (icon row 1196, hotseat 1481) yields
  `864 740 216 740` and `216 740 864 740`, proving the helper ignores icon row 1196. A nonzero-origin
  workspace `[40,120][1040,1800]` yields absolute `840 810 240 810`. Missing/malformed/degenerate
  workspace and hotseat, a hotseat above the workspace, a header reaching past the hotseat, and an
  unknown direction all fail closed. Existing selected `WidgetCell` caption separation, exact
  provider/bounds/new-ID proof, foreground/no-permanent-binding guards and primary-page assertions
  are unchanged.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **511/511**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; the widget/home/role/theme/icon/native/drawer-trace/brand/
  identity source guards all OK; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** CI has not yet rerun the API 37 runtime smoke at this head. No runtime, APK
  or pixel success is claimed from fixtures; the later-page return/recheck swipe must be observed
  to pass in the next CI. PR19 is not merged. Release and hosting remain paused.

## done (previous run — CI161 selected-preview caption and primary-HOME restore)

- **Root cause from CI161, not guessed:** the picker's Clock provider exposed both `Analog clock`
  and `Digital clock` `WidgetCell`s at the same vertical position. The smoke passed the provider
  header `Clock` to `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds`, so the
  exact platform dialog (`Widget: Analog clock`) was rejected and the run timed out. The app,
  workflow, SDK, permissions, signing and release configuration were untouched.
- **Two separate identities:** the selected provider/app title `Clock` remains only the HOME host
  and page-search identity. The new pure `widget_picker_selected_caption` reads the `widget_name`
  from the same actual `WidgetCell` (nearest ancestor class) that owns the measured
  `widget_preview_container` bounds in the saved pre-Add XML. It never uses the first global
  `widget_name` or the provider header. It prints a caption only when exactly one `WidgetCell` owns
  the selected preview and that cell exposes exactly one non-empty `widget_name`; missing, foreign,
  duplicate or ambiguous captions print nothing and the smoke fails closed.
- **Consent wiring:** both `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds`
  now receive `_cwp_widget_caption`; the provider title still feeds `home_widget_bounds`,
  `placed_widget_page_is_safe` and the bounded page search. The log records both values.
- **Primary HOME restore:** after the exact placed host/new launcher-owned id, Settings/HOME
  survival and bounded page recheck pass, new `restore_primary_home` sends one ordinary HOME key
  (the existing `Launcher.onNewIntent` default-page behavior), then polls `primary_home_is_ready`
  for up to 10 attempts. That readiness requires the date pill, live clock text and the clock,
  battery, device-storage value and device-progress child ids. Only then does `verify_nothing_home`
  run. No workspace item is reset, moved or deleted, and the primary-page assertions are unchanged.
- **Fixtures:** new Clock cells model `Analog clock`/`Digital clock` at the same vertical position
  with left/right preview selection; Calendar with the same provider/widget name; the own DotWel
  group with distinct captions; missing, ambiguous, unrelated and provider-header negatives. The
  CI161 platform consent fixture now expects `Analog clock`; `Clock` and `Digital clock` expectations
  fail to find a Create target, and Always allow stays unchecked. Existing wrong
  widget/launcher/dialog/package/disabled-button/checkbox negatives are retained.
- **Source regression guard:** the smoke test asserts the recheck line precedes the
  `restore_primary_home` call, which precedes `verify_nothing_home`; it also asserts the restore uses
  `KEYCODE_HOME` and never clears/moves/deletes workspace items.
- **Docs:** `docs/agent/emulator-verification.md` records the two identities, the same-`WidgetCell`
  caption rule, fail-closed ambiguity, primary-HOME restore and the new evidence files.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` **495/495**; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; the widget/home/role/theme/icon/native/drawer-trace/brand/
  identity source guards all OK; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** CI has not yet rerun the API 37 runtime smoke at this head. No runtime, APK
  or pixel success is claimed from fixtures; the Analog clock consent must be observed to pass in
  the next CI, and the primary/default HOME restore must be observed before `verify_nothing_home`.
  PR19 is not merged.

## done (previous run — CI159 placed-widget page-geometry recovery)

- **Diagnosed from the reported evidence, not guessed:** the old check measured
  `_cwp_ref_dock_top` and `_cwp_ref_header_bottom` from the pre-widget first page and applied them to
  the page where the Calendar was actually found. The later page legitimately has no launcher
  `search_container_workspace` header, so its Calendar top `107` is valid; the stale first-page
  header bottom `312` falsely rejected it.
- **Page-local geometry helper:** new pure `home_widget_page_geometry_ok <xml> <bounds>` reads the
  workspace actually present on the placed page (`workspace`/`workspace_right`/`workspace_grid`),
  the actual `hotseat` dock top, and `ui_header_bottom` only when a launcher header really exists on
  that page. It rejects out-of-workspace bounds, real header overlap, real dock overlap and
  missing/malformed workspace or dock geometry. It never inherits the first-page header and never
  invents the old 15 percent band. It deliberately does not use the labelled-row `ui_dock_top`,
  which can report `1196` for ordinary Gallery/Settings icons on a later page.
- **Identity retained:** new `placed_widget_page_is_safe` re-runs `home_widget_bounds` with the
  selected provider label and requires the exact placed bounds before the geometry check, so
  absent, foreign, picker-preview and mismatched hosts still fail closed.
- **Smoke wiring:** `capture_widgets_picker` now calls `placed_widget_page_is_safe` on
  `$_cwp_placed` with the reference, provider title and placed bounds. The stale
  `_cwp_ref_dock_top`/`_cwp_ref_header_bottom` block is gone. Add/Create, new AppWidgetId/host/
  provider ownership, later-page discovery, post-Settings/HOME survival, exact foreground,
  own-widget/header/dock and no-permanent-binding guards are unchanged.
- **Fixtures:** CI159 first page (header bottom `312`, Calendar `38 328 524 738`) and no-header
  later page (Calendar `38 107 524 738`, Gallery/Settings at `1196`) are accepted; first-page header
  overlap, dock overlap, out-of-workspace, missing hotseat, missing workspace, malformed/non-numeric/
  empty bounds, absent host, foreign label, picker preview and mismatched bounds are rejected. The
  later-page `ui_dock_top=1196` hazard is asserted explicitly.
- **Docs:** `docs/agent/emulator-verification.md` records the page-local validation, the no-header
  later-page rule and the fail-closed geometry.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` 469/469; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `play-brand-guard-test.sh` 22/22; `play-identity-guard-test.sh` 8/8;
  `nothingui-home-role-guard-test.sh` 7/7; `manifest-guard-test.sh` 31/31;
  `nothingui-theme-guard-test.sh` 12/12; `nothingui-icon-render-guard-test.sh` 15/15;
  `nothingui-native-surfaces-guard-test.sh` 14/14; `nothingui-drawer-trace-guard-test.sh` 8/8;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on all three edited scripts;
  `git diff --check` clean.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the later-page Calendar now passes and
  the strict first-page header/dock/workspace negatives still fail closed. No runtime, APK or pixel
  claim. PR19 is not merged; a fresh CI is required.

## done (previous run — CI155 HOME long-press widget-host recovery)

- **Diagnosed failure fixed in the harness:** CI155's `home_longpress_target` chose `540,896`,
  which is inside the third real widget host (`38,770,1042,1180`, the Device card). The old
  `ui_point_is_free` skipped every node whose `clickable` was not `true`, so a hosted widget exposed
  as a non-clickable `LauncherAppWidgetHostView` was treated as empty.
- **Occupancy:** `ui_point_is_free` now treats any `*AppWidgetHostView` class and any `/appwidget`
  resource-id as occupied regardless of `clickable`, `text` or `content-desc`; pending hosts are
  covered. Labelled clickable icons/folders keep their existing protection, and the header/dock/QSB
  band math is unchanged.
- **Safe candidate search:** widget-host bounds are expanded by the same measured 4% margin, and
  `home_longpress_target` adds bounded 90/95/100 percent candidates so it can reach the genuinely
  empty band below the Device card instead of a narrow gap or a widget edge. If all candidates are
  occupied it still fails closed; no widget is pressed and no UI is bypassed.
- **Fixtures:** new CI155 geometry (root 1080x1920, full-root workspace, hotseat at 1481, three
  non-clickable "DotWel Launcher" hosts) rejects `540,896` and selects `540,1300`, which is asserted
  below the Device card, above the dock and free. Added pending-host, unlabelled-host and
  all-widget-occupied fail-closed fixtures. The legacy empty-layout target remains `540,834`.
- **Docs:** `docs/agent/emulator-verification.md` records host occupancy, clearance and the
  below-Device-card candidates.
- **Verification actually run (no Gradle, no Android build, no emulator):**
  `emulator-smoke-test.sh` 450/450; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on the edited scripts; `git diff --check` clean.
- **Blocked/unknown:** the API 37 runtime smoke must confirm the new target opens the normal HOME
  popup. PR19 is not merged and no runtime/APK claim is made.

## done (previous run — CI155 style-only correction)

- **Formatter-only:** `NothingUiDeviceStorage.isKnown`'s short expression body now has `=` and
  `total > 0L && available >= 0L && available <= total` on one line, as CI155 `check-style`
  requested. One file, 1 insertion / 2 deletions; every token and all behavior preserved.
- **Untouched:** widgets, tests, models, workflows, dependencies, permissions, identity, signing and
  every other file. No Gradle, Android build, merge or CI dispatch was run here.
- **Verification actually run:** `git diff --check` clean; the source diff is the single line above.
- **Blocked/unknown:** CI155's independent Android/emulator lanes and their pixels remain unreviewed;
  a fresh CI run must confirm `spotlessKotlinCheck`/`spotlessJavaCheck`.

## done (previous run — PR19 provider identity, page discovery and device Settings proof)

- **Device storage fallback:** `NothingUiDeviceStorage` now exposes `UNKNOWN_MARKER = "--"` and a
  negative/unknown size renders `--`; the device layout's default storage value and the localized
  `Storage unavailable` detail are the short fallback. The unit expectation for
  `usedPercent(3L, 1L)` was corrected from `100` to `67` (integer rounding is 67%), and
  `formatSize(-1L)` expects `--`. The new `nothingui_device_storage_unknown_value` string is
  `translatable="false"`.
- **Provider identity, not geometry:** `home_widget_bounds` accepts an optional expected provider
  label, matches the real workspace host `content-desc`, ignores reference hosts with a different
  label, and rejects pending hosts, picker/sheet previews and hosts outside the workspace when an
  expected label is supplied. The inherited first-unseen behavior is preserved when no label is
  supplied. The unsafe `home_has_widget_bounds` helper was removed; no bounds-only placement claim
  remains. Fixtures cover new Calendar vs existing own Clock at the same geometry, a wrong provider
  at the same bounds, preview, outside workspace, pending host, and two own hosts before Calendar.
- **Measured page discovery:** after Add and bind consent, the smoke waits for a new
  launcher-owned `AppWidgetId`, then searches at most three measured HOME pages by provider label
  plus a real workspace host. It refuses to swipe unless the launcher is resumed and no bind consent
  is open, and saves per-page XML/PNG, activities/swipe logs and `widgets-page-log.txt`. The
  after-Settings survival search uses the provider label plus the exact placed bounds and rechecks
  that exact host. Static tests assert the three-page cap, foreground/consent safety, per-page
  evidence and no bounds-only helper.
- **Device Settings shortcuts:** `exercise_device_settings_shortcuts` taps the measured child bounds
  of `nothingui_device_wifi`, `nothingui_device_sound` and `nothingui_device_display`. It resolves
  each expected destination from the installed platform with
  `cmd package resolve-activity --brief` for `WIFI_SETTINGS`, `SOUND_SETTINGS` and
  `DISPLAY_SETTINGS`, falling back to `android.settings.SETTINGS` exactly as the widget does, and
  never guesses an alias. It requires the platform-resolved component foreground, captures the
  Settings activity/UI, returns HOME, requires the card and pill visible again, and re-reads
  `dumpsys appwidget` to prove all three own ids are distinct and unchanged. It never writes a
  setting or rebinds a widget.
- **Focused fixtures:** smoke tests now cover `parse_resolved_component` (brief, priority-prefixed,
  alias and no-activity output), device child bounds, device storage short fallback, device provider
  binding in `own_widget_new_binding`, static device provider/storage checks, and the device
  Settings flow/order. `_cows_max_rounds` was corrected to `3` with the label “at most three rounds”.
- **Verification actually run (no Gradle, no Android, no emulator):**
  `emulator-smoke-test.sh` 443/443; `emulator-smoke-drawer-test.sh` 38/38;
  `nothingui-widget-guard.sh` OK and suite 31/31; `nothingui-home-guard.sh` OK and suite 19/19;
  `verify-play-build-test.sh` 11/11; `sh -n` clean on every edited script; `git diff --check`
  clean. The JUnit test, Android build, style and API 37 runtime captures remain CI gates.
- **Blocked/unknown:** no local JUnit or runtime result. CI147's third-party detector failure is not
  fixed here; the page-discovery change is the intended correction but needs fresh CI evidence.
  PR19 is not merged and no pixel/APK claim is made.

## done (previous run — PR19 pending-widget smoke harness recovery)

- **Reported failure reproduced:** at `740b2cb` the smoke fixture suite had exactly one failure:
  `a pending host outside a present workspace is rejected` returned `40 900 500 1200`.
- **Root cause:** `home_pending_widget_bounds` set `saw_ws` only inside the pending-host branch, so
  a workspace with no pending host was invisible and the no-workspace fallback returned an outside
  host. `saw_ws` is now set for any workspace node, so the fallback applies only when no workspace
  is exposed. Fixtures keep the no-workspace fallback positive and the outside-host negative.
- **Exact own-provider acceptance:** new `own_widget_new_binding` accepts exactly one newly bound
  record with a numeric id, the running `$PKG` as both host and provider package, and exactly
  `app.dotwel.widgets.DotWelClockWidgetProvider` or
  `...DotWelBatteryWidgetProvider`. The old substring `case` is gone. Fixtures cover one clock,
  one battery, unchanged, foreign provider package, class prefix/suffix lookalikes, short class,
  wrong provider, two records, mixed own/foreign multiline, foreign host and non-numeric id.
- **Exact consent activity:** new `foreground_is_component` matches the resumed component exactly.
  The own-widget consent now requires `com.android.settings/.AllowBindAppWidgetActivity` (or its
  fully qualified form), grounded in the CI134 `activities-widget-placed-1.txt` evidence. Fixtures
  cover the CI134 shape, the fully qualified form, another Settings activity, a foreign package, a
  class suffix lookalike and the exact package requirement.
- **Per-round completion:** after Create the flow now requires the real launcher HOME
  (`$PKG/$LAUNCHER_ACTIVITY`) and finishes a round only when exactly one new own provider is bound
  and the pending count decreases by exactly one. A missing decrease, a still-open dialog or a
  wrong provider fails closed. Max two rounds, 12 bounded polls, unexpected-dialog failure, Always
  allow unchecked and ordinary measured taps are unchanged; before/consent/after XML+PNG retained.
- **Unchanged proofs:** `verify_home_widgets` still proves distinct launcher-owned ids, the live
  `TextClock` value and a real battery percentage/`--`; `capture_clean_home_theme` and the
  third-party picker/consent/placement/Settings-survival flow are untouched.
- **Formatting:** the Java policy constants were joined to one line (94/98 columns) to match
  google-java-format AOSP, since every existing split constant in `src/com/android/launcher3` is
  >100 columns. The Kotlin policy test matches the existing `tests/unit` style (header, imports,
  4-space indent, trailing commas); no Gradle was run here.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 389/389;
  `emulator-smoke-drawer-test.sh` 38/38; `nothingui-widget-guard-test.sh` 31/31;
  `nothingui-home-guard-test.sh` 18/18; `play-brand-guard-test.sh` 22/22;
  `play-identity-guard-test.sh` 8/8; `nothingui-theme-guard-test.sh` 12/12;
  `manifest-guard-test.sh` 31/31; `nothingui-home-role-guard-test.sh` 7/7;
  `verify-play-build-test.sh` all pass. Source guards widget/home/brand/theme/identity/role OK.
  `sh -n` clean on the three edited scripts; `git diff --check` clean.
- **Blocked/unknown:** no runtime, APK, pixel or CI claim. `manifest-guard.sh` needs a built merged
  manifest and was not run directly; its fixture suite passed. PR19 is not merged.

## done (previous run — PR19 CI136 DotWel provider-package correction)

- **CI136 failure diagnosed, not guessed:** Android `assemble` and all unit tests passed, but
  `Verify Play manifest and identity` failed the existing `play-brand-guard`. Its broad
  case-insensitive scan found the new default-workspace comment (`NothingUI`) and the two fully
  qualified `app.nothingui.widgets.NothingUiClockWidgetProvider` /
  `...NothingUiBatteryWidgetProvider` names in `play/res/xml/default_workspace_4x5.xml`. The guard
  was not weakened, skipped or excepted; the production references were renamed instead.
- **Provider package move:** only the two new provider classes moved to
  `lawnchair/src/app/dotwel/widgets/` as `DotWelClockWidgetProvider.kt` and
  `DotWelBatteryWidgetProvider.kt`, package `app.dotwel.widgets`, with matching class and
  `ComponentName` names. `NothingUiWidgetColors`, `NothingUiWidgetBudget`, `NothingUiBatteryArt`,
  `NothingUiWidgetMonitor` and the MIT `DotText` renderer stayed in `app.nothingui.widgets`; the
  moved providers import those helpers, and the monitor imports the two providers. Resource IDs,
  widget XML metadata, layouts, refresh logic and theme handling are untouched.
- **References updated:** Play manifest receivers, the fresh-install default workspace, the
  lifecycle monitor, `nothingui-widget-guard.sh` and its fixtures, the emulator smoke
  provider-instance parsers/fixtures and `docs/agent/emulator-verification.md`. The default
  workspace comment now says "original DotWel widgets". No provider alias and no second widget.
- **Preserved:** no visual, layout, data, permission, refresh, theme, workflow, Gradle/SDK,
  applicationId, signing, paid-service, database, wallpaper or preference change. `w/` remains
  untracked scratch.
- **Verification actually run (no Gradle, no emulator):** `play-brand-guard.sh` OK and its suite
  22/22; `nothingui-widget-guard.sh` OK and its suite 26/26; `nothingui-home-guard.sh` OK and its
  suite 18/18; `verify-play-build-test.sh` 11/11; `emulator-smoke-test.sh` 342/342;
  `emulator-smoke-drawer-test.sh` 38/38; `sh -n` clean on every edited script; `git diff --check`
  clean. The Android build, unit tests, spotless and API 37 emulator captures remain CI gates.
- **Blocked/unknown:** no runtime/emulator claim; CI must still compile, test and produce the clean
  dark/light home screenshots. PR19 is not merged.

## done (previous run — PR19 CI136 spotless Kotlin correction)

- **Formatter-only:** `DotText.pitchFor`'s short expression body now has `=` and
  `minOf(boxW / cols(text), boxH / ROWS).coerceAtLeast(0.5f)` on the same single line, as the
  formatter requested. One file, 1 insertion / 2 deletions; no behavior change.
- **Untouched:** layout data, workflows, Gradle/SDK, permissions, applicationId, signing and every
  other file. No Gradle build was run here.
- **Verification actually run:** `git diff --check` clean; the source diff is the single line above.

## done (previous run — home-widget-composition-v1 pre-CI checkpoint)

- **RemoteViews composition:** the clock layout's bare `<View>` surface is now an
  `<ImageView android:id="@+id/nothingui_clock_surface">`; the provider's runtime
  `setBackgroundResource` tile remains. Native `TextClock`, colours, battery art, layouts,
  preferences, wallpapers and light/dark/system handling are unchanged.
- **Compiled resource IDs:** new pure `WidgetPackageResolver` resolves the compiled numeric
  `launcher:packageName="@string/launcher_component"` ID to the running variant's `contextPackage`,
  and other compiled string IDs to their package component. `PendingWidgetParser` reads
  `getAttributeResourceValue(parser, ATTR_PACKAGE_NAME, 0)`, resolves its own `launcher_component`
  ID via `getResources().getIdentifier(...)`, keeps the `@string/...` text-fixture fallback, and
  never hardcodes `com.launchernos.dotwellabs`.
- **Unit coverage:** `WidgetPackageResolverTest` covers compiled own/other/no-slash IDs, a literal
  package, literal `@string/launcher_component`, another literal string, and a missing package. It
  was not run locally (no Gradle by instruction); CI owns it.
- **Guard:** `nothingui-widget-guard.sh` requires the resolver, the compiled-ID read, the
  `launcher_component` special case, `contextPackage`, and the string fallback; rejects a hardcoded
  applicationId and any bare `<View>` in clock/battery RemoteViews layouts; requires the clock
  `<ImageView>` tile. Fixtures add parser-without-resolution, text-prefix-only, hardcoded
  applicationId and bare-View negatives. The guard suite passes.
- **Smoke proof:** `verify_home_widgets` now dumps `dumpsys appwidget`, requires distinct
  launcher-owned AppWidgetIds for the NothingUI clock and battery through the record-aware parser,
  and requires the measured HOME XML to expose `nothingui_clock_time` with live `H:mm`/`HH:mm` text
  and `nothingui_battery_art` with a real `0..100%`/`--` description. It writes
  `home-widgets.txt`, `home-widgets-instances.txt` and `home-widgets-verified.txt`.
- **Clean HOME:** `capture_clean_home_theme` first requires the existing
  `pref_launcherTheme=system` choice (read-only), then captures dark/light under system night
  yes/no, runs the same widget-id/child-value proof per capture, stores per-mode widget evidence,
  restores the night mode and returns HOME. It runs before any third-party widget placement.
- **Fixtures:** the smoke tests cover API 37 current-format and legacy launcher-owned instances,
  provider-catalog-only and other-host negatives, distinct IDs, real/live clock and battery values,
  missing child IDs, plus static checks for the new HOME/clean-HOME proof. The docs list the new
  artifacts.
- **Preserved:** Play `applicationId`, `minSdk`/`targetSdk`, manifest/permissions, workflows,
  Gradle/SDK/emulator, DB/schema, preferences, wallpapers, non-Play branding, the MIT notice and the
  existing grid/picker/drawer flows. No hardcoded package, direct widget binding, DB injection or
  broad harness rewrite.
- **Verification actually run (no Gradle/emulator):** `nothingui-widget-guard.sh "$PWD"` OK; widget
  guard suite 26/26; home guard and suite OK/18; manifest suite 31/31;
  `verify-play-build-test.sh` 11/11; `emulator-smoke-test.sh` all pass (including the new
  instances/child/value/static checks); `emulator-smoke-drawer-test.sh` 38/38; `sh -n` clean on all
  edited scripts; `git diff --check` clean. The JUnit test, Play debug build, spotless and API 37
  smoke remain CI gates.
- **Blocked/unknown:** runtime success of the hosted-widget and clean-HOME proof is unverified until
  CI runs the API 37 emulator. No PR, merge or visual claim.

## done (previous run — A2 corrective checkpoint)

- **Root cause 1 (formatting):** `spotlessKotlinCheck` rejected short expression-body functions in
  `NothingUiNativeSurfaces.kt` because the `=` and expression were split across lines. The simple
  `if (dark) ... else ...` bodies and the `allAppsBackground(dark).copy(alpha = ...)` layer bodies
  now sit on one line; the multiline block `if` for `allAppsBlurForeground` keeps the project's
  existing `= if (dark) {` form. The private `neutral`/`static` helpers follow the same style.
- **Root cause 2 (alpha):** Compose sRGB `Color.copy(alpha = 0.50f).alpha` quantizes to 8 bits
  (`128/255 = 0.5019608`), so the old literal `0.50f` expectation was wrong. The drawer-layer test
  now derives the expected alpha with `Color.White.copy(alpha = ...).alpha` and asserts it exactly
  for all eight scrim/expressive/blur values (0.40, 0.50 and 0.32). Coverage is unchanged and the
  tolerance was not loosened.
- **Scope:** no functional, native UI redesign, workflow, Gradle, SDK, manifest, permission,
  applicationId, signing, asset, other-repo or slice-B change.
- **Verification actually run (no Gradle, no emulator):**
  `nothingui-native-surfaces-guard.sh "$PWD"` OK; its fixture suite 14/14;
  `verify-play-build-test.sh` 11/11; `git diff --check` clean. CI132's remaining 41 unit tests
  passed, including the native contrast tests; the corrected CI must rerun the Android build,
  `spotlessKotlinCheck`, unit tests and the API 37 smoke.
- **Next:** picker A3 after PR18 is green.

## done (previous run — A1 debug warning contrast)

- **Root cause read from the source:** `PreferencesDebugWarning` passed
  `MaterialTheme.colorScheme.errorContainer` to `WarningPreference`, whose text/icon default to
  `MaterialTheme.colorScheme.error`. The NothingUi converters never set
  `errorContainer`/`onErrorContainer`, so Play fell back to Material's dark-red container
  (`#93000A`) under the accent-red text (`#D7261E`) — 1.86:1, the unreadable pixels CI captured.
- **Neutral warning tokens:** `NothingUiColors` gains `warningContainer`/`onWarningContainer`.
  Dark uses `Gray700` on `Paper` (10.16:1); light uses `Gray100` on `Ink` (15.77:1). Both
  containers are true neutral greys; `error` stays `AccentRed` and `onError` stays `onAccent`, so
  restrained red elsewhere is unchanged.
- **Converter mapping:** both `toDarkColorScheme()` and `toLightColorScheme()` now set
  `errorContainer = warningContainer` and `onErrorContainer = onWarningContainer` instead of
  inheriting Material defaults.
- **Play-only debug warning:** `PreferencesDebugWarning` computes the content color as
  `onErrorContainer` on Play and `error` otherwise, passing it as both `textColor` and `iconTint`.
  The warning is still shown in exactly the same debug/nightly condition; non-Play pixels are
  identical because the fallback is the previous default value.
- **Regression coverage:** `NothingUiTokenTest` adds dark and light warning-content contrast checks
  (`>= 4.5:1`, plus neutral-channel assertions) and a converter-mapping check that
  `errorContainer`/`onErrorContainer` equal the palette values while `error` stays the accent.
  Existing typography and screenshot-smoke assertions are untouched.
- **Scope:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing, asset, native
  popup/drawer/picker or other-repo change. Patch is 3 files, 46 insertions.
- **Verification actually run (no Gradle, no emulator):** `nothingui-theme-guard.sh "$PWD"` OK;
  `nothingui-theme-guard-test.sh` 12/12; `verify-play-build-test.sh` 11/11; `sh -n` clean on the
  edited scripts; `git diff --check` clean. The new JUnit contrast/mapping test and the CI pixel
  recapture are left to PR #17 CI, which builds and runs the unit tests.
- **Next:** native `ThemeProvider`, popup, drawer and picker surfaces. Slice A is still not complete.

## done (previous run — A1 settings palette partial checkpoint)

- **Real settings entry wired, not the sample:** `LawnchairTheme` previously always built the
  inherited `MaterialExpressiveTheme`/`ThemeProvider` color scheme. It now short-circuits through
  `NothingUiTheme(darkTheme = darkTheme, content = content)` when
  `NothingUiFeature.themeEnabled` is true. The default parameter remains
  `isSelectedThemeDark`, so LIGHT, DARK and SYSTEM resolve exactly as before; github/nightly still
  take the inherited branch with the same `getColorScheme`, shapes and expressive motion.
- **Typography:** `NothingUiTypography` now uses `DotoFontFamily` for `headlineLarge`,
  `headlineMedium`, `headlineSmall`, `titleLarge` and their emphasized variants (normal headings
  keep normal weight; emphasized headings keep bold). `titleMedium`/`titleSmall`, all body and all
  label styles remain `FontFamily.SansSerif`, so settings copy stays readable.
- **Preserved:** no change to `ThemeProvider`, popup, drawer, picker, grid values, Apply behavior,
  manifest, permissions, SDK, applicationId, signing, assets, workflows or other repos. The
  diagnostic `THEME_SAMPLE` route remains debug + Play gated and is unchanged.
- **Regression tests outside production `src`:** `tests/unit/java/app/nothingui/theme/
  NothingUiTokenTest.kt` now requires Doto on the display/headline/titleLarge styles and sans on
  titleMedium/titleSmall/body/label. `scripts/nothingui-theme-guard.sh` now requires the Play gate,
  the resolved `darkTheme` call, the inherited non-Play branch, and Doto on every headline/titleLarge
  style. Its fixture suite adds missing-gate, hardcoded-dark, and sans-headline negatives (and
  updates the existing EdgeToEdge fixture so it still tests only its own rule).
- **Smoke:** `scripts/emulator-smoke.sh` adds `capture_settings_theme` and
  `assert_settings_theme_choice_system`. It reads `shared_prefs/com.android.launcher3.prefs.xml`
  through `run-as` and requires `pref_launcherTheme=system` (a clean install default; no write),
  records the current `cmd uimode night`, captures the real `PreferenceActivity` under night
  `yes`/`no` without the sample extra as `settings-theme-dark.xml`/`.png` and
  `settings-theme-light.xml`/`.png`, requires the real `Settings`/`General` dashboard and rejects
  the `DOTWEL` sample, then restores the previous night mode and returns HOME even when a capture
  fails. The existing grid-preview and widget-placement phases are unchanged.
- **Verification actually run (no Gradle, no emulator):** `nothingui-theme-guard.sh "$PWD"` OK;
  `nothingui-theme-guard-test.sh` all pass (13/13); `emulator-smoke-test.sh` all pass including the
  new settings-theme static checks; `sh -n` clean on the edited scripts; `git diff --check` clean.
  The Android build, JUnit, `spotlessCheck`, and the API 37 emulator dark/light captures are left
  to CI/PR review.
- **Next:** native `ThemeProvider`, popup, drawer and picker surfaces. Slice A is not complete; this
  is only the settings palette checkpoint.

## done (previous run — P11 preview header parity)

- **Root cause from the source, not guessed:** `LauncherPreviewRenderer` initialized
  `mWorkspaceSearchContainer` to `R.layout.smartspace_container` at field declaration, before the
  model callbacks. The real workspace instead inflates the selected `SmartspaceMode`'s
  `layoutResourceId` in `Workspace.bindAndInitFirstWorkspaceScreen()`, and `LawnchairSmartspace`
  resolves that to `nothingui_home_header` on Play (`NothingUiFeature.homeEnabled`) and to
  `smartspace_container` on github/nightly. The preview therefore always showed the inherited
  welcome card on Play while live HOME showed the NothingUI header.
- **Preview parity:** the field no longer has a hardcoded layout. The new pre-bind
  `getDefaultSmartspaceLayout(context, preferenceManager)` reads
  `PreferenceCacheExtensionsKt.firstCached(getSmartspaceMode())`, falls back in memory to
  `LawnchairSmartspace.INSTANCE` when the selected mode is unavailable (mirroring Workspace, without
  writing the preference from a preview), and returns `mode.getLayoutResourceId()`. It runs at the
  top of the constructor, before `model.addCallbacksAndLoad(this)`, so it is set before any bind.
- **Race review:** `LauncherModel.addCallbacksAndLoad()` can bind synchronously when the model is
  already loaded, so `LauncherPreviewView` now passes the dummy
  `R.layout.smartspace_widget_placeholder` override as a new constructor argument instead of calling
  `setWorkspaceSearchContainer()` after construction. The 5-arg and 6-arg constructors still
  delegate with a `0` sentinel, so `PreviewSurfaceRenderer` and other callers are unchanged apart
  from the corrected default.
- **Preserved:** `bindCompleteModel` still gates the first-page item on `getEnableSmartspace()`;
  the explicit dummy override still wins; `SmartspaceMode` keeps its `NothingUiFeature.homeEnabled`
  gate and inherited fallback; Google/Smartspacer selections still use their own layouts. No dot
  clock layout duplication and no hardcoded preview clock text — the preview inflates the existing
  `nothingui_home_header` / `NothingUiHomeHeaderView`.
- **Regression coverage:** `scripts/nothingui-home-guard.sh` now requires the preview renderer to
  read `getSmartspaceMode` and `getLayoutResourceId`, rejects a hardcoded
  `mWorkspaceSearchContainer = R.layout.smartspace_container`, requires the pre-bind override
  parameter, requires `LauncherPreviewView` to keep the dummy placeholder and to not call
  `setWorkspaceSearchContainer` after construction, and still requires `getEnableSmartspace`.
  `scripts/nothingui-home-guard-test.sh` adds three negatives (hardcoded container, missing selected
  mode, post-construction dummy override). JUnit sources were not added to `src/`.
- **Verification actually run (no Gradle, no emulator):** `nothingui-home-guard.sh "$PWD"` OK;
  `nothingui-home-guard-test.sh` 16/16; `verify-play-build-test.sh` 11/11;
  `emulator-smoke-test.sh` all pass; `emulator-smoke-drawer-test.sh` all pass; the identity,
  manifest, brand, theme, home-role, icon-render and drawer-trace fixture suites all pass; `sh -n`
  clean on both edited scripts; `git diff --check` clean. The Android build, unit tests, `spotlessCheck`
  and the API 37 emulator `grid-settings.png` pixel capture are left to CI.

## done (previous run — P10b safe Add tap and API37 ProviderId parser)

- **Root cause from CI120, not guessed:** the real picker exposed Add at `[434,1755][645,1881]`
  while the navigation bar begins around 1800. `tap_center_of_bounds` used the original centre 1818,
  which is inside the navigation bar, so the tap opened Android HOME. The existing viewport was never
  applied to Add.
- **Safe intersection:** `widget_picker_add_button_bounds` now requires `enabled="true"` as well as
  `clickable="true"`. New `widget_add_safe_bounds` intersects the Add with the viewport remeasured
  from the exposed Add hierarchy, subtracts a 32 px navigation-bar inset from the bottom, and prints
  bounds only when the result is at least 24 px in both dimensions. The CI120 box becomes
  `434 1755 645 1788`; the original 1818 centre is never tapped.
- **Bounded re-scroll:** if no safe box remains, `capture_widgets_picker` performs up to three
  genuine `input swipe` scrolls inside the measured real list, re-captures and re-resolves the Add
  after each, and logs every target. If Add disappears or the safe box never appears, it saves
  `widgets-add.xml`, `widgets-add-last.xml`/`.png` and fails with the original Add and viewport pixels
  instead of guessing a coordinate.
- **API37 provider wrapper:** `appwidget_new_providers` now accepts
  `provider=ProviderId{cmp:ComponentInfo{...}}` in addition to direct `provider=ComponentInfo{...}`.
  The wrapper is parsed only while a real `[N] id=N`/`AppWidgetId=N` block is active, and the same
  block must name this launcher in `host=HostId{... pkg:...}` or `hostPackage=`. Section headers
  flush the block, and a second provider line ends it, so provider catalogs and other hosts cannot be
  attributed to an old widget id.
- **Preserved:** real long-press, measured Widgets tap, native-picker readiness, search/scroll
  viewport, preview visibility, bind consent, new workspace host, launcher-owned appwidget id,
  header/dock band and HOME survival checks are unchanged. No direct picker/config start, fake drag,
  fixed coordinate, preference/DB write or direct binding was added.
- **Fixtures:** the actual CI120 Add bounds are covered as a partially hidden Add with a safe
  `434 1755 645 1788` intersection; a fully visible Add, a fully hidden Add, a barely visible Add and
  a horizontally outside Add are covered; a disabled Add is rejected. API37 fixtures cover a wrapped
  provider in a current launcher-owned `[N] id=N`/`HostId` block, a legacy `AppWidgetId`/`hostPackage`
  block, another launcher's host, an installed-provider catalog with and without a section header,
  and a wrapper outside any widget-id block.
- **Docs:** `docs/agent/emulator-verification.md` records the safe Add intersection, the bounded
  re-scroll and the API37 `ProviderId` rules.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 269/269;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` 11/11; `sh -n` clean on every
  edited script; `git diff --check` clean. This is source/fixture verification only, not a runtime
  claim. APK110 fallback is unchanged.

## done (previous run — P10b bind consent label-case review correction)

- **Root cause from the CI116 actual XML, not guessed:** `android:id/button1` is rendered with an
  uppercase `CREATE` label, while both helpers matched `text="Create"`/`text != "Create"` exactly.
  The old readiness also grepped the whole tree for the title, `Application:`/`Widget:` and the
  launcher/widget names, so unrelated text could satisfy it.
- **Case normalization:** `widget_bind_consent_is_ready` and `widget_bind_create_button_bounds` now
  compare the button label with `tolower(...) == "create"`, so `CREATE` and `Create` both work.
- **Identity retained:** both helpers require `package="com.android.settings"` on the dialog nodes,
  the exact `android:id/alertTitle` title, and an enabled (`enabled="true"`) clickable
  (`clickable="true"`) `android:id/button1`; readiness also requires `android:id/alwaysUse`.
- **Message scoping:** the launcher and selected widget must appear in the `android:id/message` text
  as `Application: <launcher>` and `Widget: <widget>` (case-insensitive). Text elsewhere in the tree
  is rejected. `widget_bind_create_button_bounds` now takes the launcher/widget arguments, and the
  smoke passes `"$EXPECTED_LABEL" "$_cwp_provider_title"`.
- **Fixtures:** the pretty and compact titlecase positives now carry the Settings package and enabled
  controls. A new compact platform fixture matches the actual shape (system package, `alertTitle`,
  message naming DotWel Launcher and Calendar, unchecked `alwaysUse`, uppercase `CREATE`/`CANCEL`).
  New negatives cover wrong launcher, wrong widget, wrong package, loose launcher/widget text outside
  the message, a generic Create dialog, and a disabled Create button; the checked `alwaysUse` case
  still fails closed. Positive and negative bounds resolution is asserted.
- **Docs:** `docs/agent/emulator-verification.md` records the case-insensitive label, Settings
  package, message-scoped identity and disabled-button rejection.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 249/249;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` 11/11; `sh -n` clean on every
  edited script; `git diff --check` clean. This is source/fixture verification only, not a runtime
  claim. APK110 fallback is unchanged; the grid preview task was not started.

## done (previous run — P10b bind consent and Settings survival)

- **Evidence read, not guessed:** CI116 stopped after the Calendar preview Add on the genuine Android
  `AllowBindAppWidgetActivity`; the previous harness polled only for a workspace host and never
  handled the dialog. The actual AOSP dialog is an `AlertActivity` titled
  `Create widget and allow access?` with `Application:`/`Widget:` message text, the
  `android:id/alwaysUse` checkbox, `android:id/button1` Create and `android:id/button2` Cancel.
- **Exact consent gate:** `widget_bind_consent_is_ready` requires the exact title, `Application:` and
  `Widget:` labels, the launcher label, the selected provider title, the `button1` Create control and
  the `alwaysUse` checkbox. A generic Create dialog, another launcher, another widget, a missing
  button1 or a compact single-line dump is handled; only the exact dialog is accepted.
- **Safe Create route:** the flow captures the consent XML and PNG, refuses to continue if
  `Always allow` is already checked, measures `android:id/button1` and taps its centre. A second
  Create tap is suppressed while the dialog is still visible, and a dismissed dialog is never treated
  as success. The route and unchecked state are recorded in `widgets-add-log.txt`.
- **Launcher-owned instance:** `appwidget_new_providers` now parses current
  `Widgets:`/`[N] id=N`/`host=HostId{..., pkg:...}` dumps as well as legacy
  `AppWidgetId=N`/`hostPackage=` dumps, and accepts the new instance only when its host package is
  `$PKG`. The smoke polls `dumpsys appwidget` five times, so an installed provider or another
  launcher's host cannot satisfy placement.
- **Settings survival:** after placement it launches `android.settings.SETTINGS`, waits for the
  exact `com.android.settings` foreground, captures `widgets-settings-launched.xml/.png`, presses
  HOME, captures `widgets-home-after-home.xml/.png`, and requires the same widget bounds as before
  the app switch.
- **Fixtures:** modern launcher-owned, other-launcher and missing-ownership dumps, unchanged modern
  dump, legacy `hostPackage` positive/negative, pretty/compact consent, unrelated dialog, other
  launcher, other widget, missing button1, checked Always allow, and measured Create bounds. Static
  checks now require the consent/Settings path and only reject picker-specific direct starts.
- **Preserved:** the real long-press, measured Widgets tap, picker readiness, search/scroll viewport
  correction, no fake drag, no direct picker/config start, no preference/DB write and no direct
  widget binding. APK110 remains frozen.
- **Docs:** `docs/agent/emulator-verification.md` records the consent, launcher-owned appwidget and
  Settings-survival phases and artifacts.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 237/237;
  `emulator-smoke-drawer-test.sh` 38/38; `verify-play-build-test.sh` all pass;
  `verify-play-build.sh` passes every source guard and stops only at the expected missing
  `build/intermediates`; `sh -n` clean on every edited script; `git diff --check` clean. This is
  source/fixture verification only, not a runtime claim.

## done (previous run — P10b FINAL native picker viewport correction)

- **Evidence read, not guessed (CI114 / `11444966646679`):** the Calendar `widgets_list_header`
  expanded at `[29,1592][1051,1827]`; the `widget_preview_container` was `[297,1869][783,1920]`,
  only 51 px tall and below the navigation top 1794. The preview tap never reached the real preview,
  Add was never exposed, and the ordinary workspace swipe from `540,1894` to `810,834` hit the
  navigation bar and opened the drawer. The app itself was unchanged.
- **Viewport gate:** added `widget_picker_search_bar_bounds` (real
  `widgets_search_bar_edit_text`, falling back to `search_bar_container`/`widgets_search_bar`),
  `widget_picker_viewport_bounds` (root bounds, top below the search bar, bottom = root bottom -
  100), and `widget_picker_preview_is_visible` (height >= 100, fully inside the viewport, bottom
  strictly above root bottom - 100). A clipped preview is rejected even with a valid resource id.
- **Bring into view before selection:** the smoke focuses the real search input, types `Clock`, and
  polls the search results for a Clock `widgets_list_header`; if the query yields no header it clears
  the text and uses the measured list. It then selects Clock/Calendar only when the header's
  `widget_preview_container` is fully visible. If the preview is clipped or off-screen it performs up
  to three genuine vertical swipes inside the measured widget list
  (`primary_widgets_list_view`/`search_widgets_list_view`/`widgets_catalog`), clamped between the
  search-bar bottom and root bottom - 100, re-resolving the header and preview after every scroll.
  It expands a header only when no preview exists yet; a clipped preview is never re-tapped.
- **No fake drag:** the ordinary `input swipe` workspace fallback and the `widget_drop_target` helper
  are removed. If the measured `widget_add_button` is not exposed after tapping the fully visible
  preview, the run captures `widgets-add-last.xml`/`.png` and fails.
- **Preserved:** the placement proof still requires a new workspace `AppWidgetHostView`, a new bound
  `AppWidgetId`/provider in `dumpsys appwidget`, and the same widget bounds after HOME. The real
  long-press, measured Widgets tap, picker readiness, role consent, grid read-only checks and
  Settings/drawer flow are untouched. APK110 remains frozen.
- **Fixtures:** the actual CI114 clipped `[297,1869][783,1920]` preview is rejected; a fully visible
  preview is accepted; a preview above the search bar and a >=100 px preview whose bottom crosses
  the navigation margin are rejected; the search input bounds, viewport and clamped scroll target
  are asserted; static checks require the search/scroll path and reject the removed drag fallback.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 208/208;
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. This is source/fixture verification only, not a
  runtime claim.

## done (previous run — P10b widget placement review correction)

- **Compact hierarchy, not a line guess:** `home_widget_bounds` previously read attributes from the
  first `<node` on each physical line. A CI110-style UIAutomator dump is one line, so it could see
  only the root/first node and miss a nested workspace host. Both reference and current files are now
  split into node records (`tr '>' '\n'`) and tagged `R`/`C`; explicit markers preserve the
  reference/current distinction even when the reference is empty. A missing reference still means
  "no previous hosts", not "treat the current tree as the reference".
- **Workspace vs sheet preview:** the comparison tracks node nesting. A host inside
  `widget_preview_container`, `widgets_list_header`, `widgets_catalog`, a picker list, `WidgetCell`,
  `WidgetsListHeader`, a bottom sheet or an add-widget sheet is rejected. When the current hierarchy
  exposes a `workspace`/`Workspace` ancestor, only a host inside it is accepted; a workspace host is
  preferred over any non-workspace host.
- **New bound instance, not just a provider:** `appwidget_new_providers` now associates each
  `provider=ComponentInfo{...}` with its enclosing `AppWidgetId=N` block and reports only providers
  for AppWidgetIds absent from the before dump. An installed-provider list or a provider name that
  was already present cannot satisfy placement; a new AppWidgetId for an already-installed provider
  still can.
- **Expanded provider association:** after tapping a provider header, the smoke re-runs
  `widget_picker_provider_bounds` on the expanded capture by the selected `Clock`/`Calendar` title,
  then passes that fresh header to `widget_picker_preview_bounds`. A stale collapsed header cannot
  skip the real preview and select a later provider's preview. The next-header boundary still comes
  from the same expanded capture.
- **Add route preserved:** `widget_add_button` was verified in the inherited source
  (`res/layout/widget_cell_content.xml` and `src/com/android/launcher3/widget/WidgetCell.java`) and
  is unchanged.
- **Fixtures:** compact single-line positive host, pretty reference, unchanged compact reference,
  empty reference, no-host compact HOME, compact preview-only host, compact mixed preview/workspace
  host, host outside a present workspace, new AppWidgetId for an already-installed provider,
  installed-provider-only list and empty before dump; expanded-header stale/updated preview cases.
- **Limitation recorded:** if the actual hierarchy exposes no workspace node at all, the helper can
  only reject known picker/sheet preview containers, not prove workspace membership. The CI110
  `widgets-home-placed*.xml` / `widgets-home-after-home.xml` artifacts must be inspected; if the real
  `dumpsys appwidget` uses a different bound-instance shape, the helper fails closed and the
  captured dump must drive the update.

## done (previous run — P10b widget placement and HOME survival)

- **Evidence read, not guessed:** CI110's picker hierarchy (as reported in the task) has a clickable
  `widgets_list_header` with `app_title` Calendar and subtitle `1 widget`, Clock next, a
  long-clickable `widget_preview_container` inside a WidgetCell, and a DotWel row with only
  `1 shortcut`. The flow therefore selects only a header whose subtitle reports a positive widget
  count; a shortcut-only header is never eligible.
- **Provider selection:** `widget_picker_provider_bounds` parses the real nested
  `widgets_list_header`/`app_title`/`app_subtitle` nodes and returns the measured header bounds for
  Clock then Calendar. It does not use a class-name guess or a fixed coordinate.
- **Expansion and preview:** `widget_picker_preview_bounds` requires a clickable/long-clickable
  `widget_preview_container` below the selected header and above the next header. If the provider is
  already expanded the preview is used directly; otherwise the measured header is tapped and polled
  for up to five captures per attempt, bounded to two taps.
- **Add route:** `widget_picker_add_button_bounds` selects the exposed Add button by its real
  `widget_add_button` resource id (icon-only safe). The flow taps the measured preview, captures
  `widgets-add-attempt-N.xml`, then taps the measured Add. If Add is not exposed it uses a genuine
  measured drag to `widget_drop_target` (right-hand workspace, between the measured header and dock).
- **Placement proof:** the flow polls the real workspace for a new `AppWidgetHostView`-suffixed node
  against the pre-widget HOME and for a new `provider=ComponentInfo{...}` entry in
  `dumpsys appwidget`. A configuration activity or an unbound provider fails with
  `widgets-add-last.xml`/`.png` and the last resumed component recorded, rather than a fake pass.
- **HOME survival:** it captures `widgets-home-placed.xml`/`.png`, requires the widget bounds to stay
  between the measured header bottom and dock top (away from the later drawer swipe start), presses
  HOME through the existing `return_home widgets-picker`, captures
  `widgets-home-after-home.xml`/`.png`, and requires the same widget bounds to remain.
- **Preserved:** the real HOME long-press, measured Widgets tap, native-picker readiness, role
  consent Cancel, grid read-only checks, 1500 ms/four-attempt drawer, Settings search/tap and exact
  foreground checks are unchanged. No direct picker/config `am start`, preference/DB write, or widget
  binding was added.
- **Docs:** `docs/agent/emulator-verification.md` records the new provider/add/placement/survival
  phases and artifact names.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass
  (including the new provider/preview/Add/placed-widget/appwidget provider fixtures and negatives);
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. This is source/fixture verification only; the CI
  API 37 run and pixels are still the runtime gate.

## done (previous run — P10a popup readiness correction)

- **Evidence read, not guessed:** CI108 (`10844960564539`) proved the grid settings pass: three
  sliders, grey non-clickable Apply, and the actual preview pixels. The real HOME long-press 540/834
  opened all three attempts, but `home_popup_is_ready` rejected the actual
  `home-popup-attempt-1-1.xml`/`-1-6.xml` because it required classes that are not present.
- **Actual popup shape:** `pkg:id/popup_container` class `android.widget.LinearLayout` bounds
  `[472,180][1039,743]`, with four clickable `pkg:id/system_shortcut` FrameLayouts at
  `[472,180][1039,317]`, `[472,322][1039,459]`, `[472,464][1039,601]` and `[472,606][1039,743]`.
  Each contains a `pkg:id/bubble_text` TextView labelled Wallpapers, Widgets, Apps list and Home
  settings; the Widgets label itself is not clickable and shares its parent's bounds.
- **Readiness fix:** `home_popup_is_ready` now parses nesting, requires `popup_container`, at least
  two clickable `system_shortcut` rows, a `Widgets` label inside a clickable row and a
  `Home settings`/`Wallpapers` label inside a clickable row. It no longer accepts a page that merely
  contains the text or an item menu.
- **Tap bounds:** `ui_clickable_label_bounds` was inspected against the actual nested shape; it
  already returns the nearest clickable ancestor, so the Widgets tap resolves to
  `472 322 1039 459`. Fixtures now lock that behaviour, including a non-clickable label and its
  clickable parent.
- **Failure evidence:** the popup-not-ready branch captures
  `home-popup-attempt-<N>-last.png` before pressing BACK. The genuine long-press gesture, measured
  target and real route are unchanged; no coordinates are hard-coded.
- **Fixtures:** the positive popup is the actual `popup_container`/`system_shortcut`/`bubble_text`
  shape. New negatives cover the real HOME, English-only text without the real ids, an item menu with
  Widgets but no home-level option, a popup without Widgets, and a single clickable shortcut with a
  home option outside any clickable shortcut. `widget_picker_is_ready` is unchanged until device
  evidence exists.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass (including
  every new positive/negative); `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean. This is source/fixture verification only, not a runtime claim.

## done (previous run — P10a grid/widget harness correction)

- **Evidence read, not guessed:** CI106 (`10644959244281`) passed assembly/style/units and the real
  grid editor opened, but the new readiness failed on class assumptions. The actual
  `grid-settings-attempt-6.xml` and pixels show the title `Home screen grid`; three visible
  `SeekBar`s with Columns 4, Rows 6, Dock icons 4; a preview `AndroidViewHolder[375,294][706,883]`
  containing a `ViewGroup` `...:id/workspace` at `375,313..706,844` with
  `hotseat`/`search_container_workspace`; there is no `LauncherPreviewView`/`LauncherPreviewLayout`
  class. Apply is a separate `TextView` at `488,1663..592,1716`, `enabled="true"`,
  `clickable="false"`, inside a non-clickable ancestor `View` and an empty non-clickable
  `android.widget.Button` at `42,1637..1038,1742`; the pixels are grey.
- **Preview readiness:** new `grid_preview_is_ready` requires a `/workspace` ViewGroup with valid
  bounds strictly inside the window root, strictly smaller than the root in both dimensions, above
  every `SeekBar`, and containing a `hotseat`/`search_container_workspace` node. No preview class
  name is required. `grid_settings_is_ready` keeps the title, four labels and three-SeekBar checks.
- **Apply readiness:** `grid_apply_is_unchanged` finds the `Apply` label bounds, rejects a clickable
  Apply, and requires a non-clickable `android.widget.Button` whose bounds contain the label. It does
  not depend on the label class or the accessibility `enabled` flag.
- **Failure evidence:** `capture_grid_settings` now captures
  `grid-settings-attempt-<last>.png` before failing when readiness never succeeds.
- **Unsafe fallback removed:** `home_longpress_target` returns failure when every measured candidate
  in the header/dock band is occupied instead of printing the band centre. The real measured HOME
  long-press Widgets route and all existing checks are otherwise unchanged.
- **Fixtures:** `emulator-smoke-test.sh` now models the actual hierarchy (preview
  ViewGroup/workspace/hotseat/search container, Apply TextView inside a non-clickable Button) and
  adds negatives for a missing workspace preview, a preview not above the controls, a preview
  without its hotseat, a clickable Apply, a missing containing Button, and a fully occupied
  long-press band.
- **Docs:** `docs/agent/emulator-verification.md` describes the bounds-based preview, the
  non-clickable Apply and the last-attempt PNG.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass (including
  every new positive/negative); `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh`
  all pass; `sh -n` clean on all edited scripts; `git diff --check` clean. This is source/fixture
  verification only, not a runtime claim.

## done (previous run — P10a initial real grid settings and widget-picker smoke)

- **Grid, read-only and real:** `capture_grid_settings` starts the existing
  `PreferenceActivity` with `lawnchair://settings/home-screen-grid` (the real
  `HomeScreenGrid.deepLink`), polls UIAutomator for the `Home screen grid` title, a
  `LauncherPreviewView`/`LauncherPreviewLayout`, `Columns`/`Rows`/`Dock icons`, at least three
  accessibility `SeekBar` nodes and `Apply`, and requires `Apply` to remain disabled. It captures
  `grid-settings.xml/.png`, never taps a control or writes a preference, then presses HOME and
  re-verifies the actual HOME clock/date.
- **Widgets, real long-press and native picker:** `capture_widgets_picker` derives an empty central
  point from the actual HOME hierarchy (header bottom from `search_container_workspace`, dock top
  from the lowest labelled row, with 4% margins), uses a genuine
  `input swipe x y x y 1000`, captures the real `OptionsPopupView`/`DeepShortcutView` popup, taps
  `Widgets` via its measured clickable bounds, and requires the native picker: the Compose
  `widgetpicker:id/widgets_catalog` plus search/tab labels, or the inherited
  `widgets_search_bar`/`search_bar_container` plus `primary_widgets_list_view`/
  `search_widgets_list_view`. The picker hierarchy must differ from the pre-long-press HOME. It
  captures `home-popup.xml/.png` and `widgets-picker.xml/.png`, returns HOME and re-verifies it.
  Bounded to three attempts; no `am start` for the picker, no fake view, no DB/pref write.
- **Pure helpers and regression:** `emulator-smoke-lib.sh` adds `ui_header_bottom`,
  `ui_point_is_free`, `home_longpress_target`, `grid_settings_is_ready`,
  `grid_apply_is_unchanged`, `home_popup_is_ready` and `widget_picker_is_ready`.
  `emulator-smoke-test.sh` adds positive fixtures, negatives for loose English-only text, a missing
  preview, fewer than three sliders, an enabled Apply, an item-specific popup and a picker without
  search/list; it also asserts the exact deep link, existing activity, no Apply tap, no pref writes,
  real gesture, measured Widgets tap, picker-not-HOME, bounded attempts and the preserved role
  consent/1500 ms/four-attempt/Settings-foreground checks. `PREFERENCES_ACTIVITY` names the existing
  settings activity explicitly; `THEME_SAMPLE_ACTIVITY` remains an alias.
- **Docs:** `docs/agent/emulator-verification.md` records the two phases, native markers and
  artifact names.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass;
  `emulator-smoke-drawer-test.sh` all pass; `verify-play-build-test.sh` all pass;
  `verify-play-build.sh` runs the shell suites and repo guards OK, then stops at the expected
  missing `build/intermediates` because no APK was built here; `sh -n` clean on all edited scripts;
  `git diff --check` clean. CI must still build, unit-test and run the API 37 smoke; the actual
  preview/picker accessibility markers remain device-verification unknowns until that run.

## done (previous run — P9 Play settings announcement cleanup)

- **Root cause, read not guessed:** `PreferencesDashboard` called `AnnouncementPreference()`
  unconditionally. That component renders whatever the inherited live-information endpoint
  (`https://lawnchair.app/live-information.json`) returns, which on the actual Play settings screen
  was the Lawnchair 16 sneak-peek card plus two placeholder "important announcement" cards.
- **Play gate:** the dashboard now calls `AnnouncementPreference()` only inside
  `if (!isPlayStoreFlavor())`. The inherited cards disappear on Play; github/nightly keep the exact
  inherited behavior. Nothing was rebranded and no DotWel news card was added.
- **Preserved:** `SyncLiveInformation()`, the debug-build warning, the default-home warning/dialog
  (`PreferencesSetDefaultLauncherWarning` + `DefaultHomeRoleConsent`), the About screen and the
  upstream `NOTICE.md` attribution. No other live-information function, permission, manifest,
  Gradle, SDK, applicationId, signing, paid-service or workflow change.
- **Guard:** `play-brand-guard.sh` now requires exactly one `AnnouncementPreference()` call in the
  dashboard, requires a `!isPlayStoreFlavor()` gate immediately above it, requires the
  `isPlayStoreFlavor` import, rejects a removed non-Play call, rejects `DotWel` in
  `AnnouncementPreference.kt`, and rejects announcement/news/live-information strings in `play/res`.
  Its fixture suite adds ungated-announcement, removed-announcement, fabricated-DotWel-news and
  Play-announcement-resource negatives.
- **Smoke:** `verify_default_home_consent` now captures `role-consent-settings.xml` + the clean
  `role-consent-settings.png`, then asserts the captured hierarchy has no `Lawnchair`, `sneak peek`,
  `important announcement` or `announcement` text **before** tapping the default-launcher warning.
  The genuine 1500 ms / 4-attempt bounded drawer, search, exact Settings foreground, HOME-return and
  role-Cancel checks are unchanged.
- **Verification actually run (no Gradle, no emulator):** `play-brand-guard.sh "$PWD"` OK; its
  fixture suite all pass (including the four new negatives); `emulator-smoke-test.sh` all pass
  (including the new announcement checks and ordering); `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; the repo-level identity, theme, home, home-role, icon and
  drawer-trace guards OK and their suites pass; `sh -n` clean on every edited script;
  `git diff --check` clean. CI must still build, unit-test and run the API 37 smoke.

## done (previous run — 1500 ms harness pacing and gesture input summary)

- **Evidence read, not guessed:** CI100 (`44951103338`) compiled, styled and unit-tested green;
  the real role-consent cancel passed and the Play hint pixels say `DotWel Launcher`. Geometry was
  correct on all four attempts (`start=540,1616 end=540,96 duration=500`), yet the drawer never
  became ready. The actual traces reported last displacement/progress `-726.84 / .37856`,
  `-194.84 / .10148`, `-188.76 / .09831` and `-264.76 / .13790`, all at velocity 0 and accepted
  Normal->AllApps. The requested 1520 px MOVE travel was not fully observed: attempt 1 DOWN
  `21:32:40.016`, dragStart `.072`, dragEnd `41.781` (>500 ms); the others took 1.54/1.29/.98 s.
  `BaseSwipeDetector` deliberately does not update coordinates on ACTION_UP; only MOVE events drive
  progress.
- **Harness pacing:** `scripts/emulator-smoke.sh` now uses a bounded `swipe_duration=1500` (was 500)
  and still logs the duration with every attempt. The four-attempt bound, the genuine swipe,
  search, exact `com.android.settings` foreground and HOME-return assertions are unchanged.
- **Per-gesture input summary:** `AbstractStateChangeTouchController` counts MOVE events and emits
  exactly one `gestureSummary` at UP/CANCEL with `action`, `downX`, `downY`, `downTime`,
  `moveCount`, `lastMoveY`, `lastMoveTime` (`none` when no MOVE arrived), `upY`, `upTime` and
  `history`. It is gated by `DotwelDrawerTrace.ENABLED` (debug Play only) and a start state of
  `NORMAL`, so unrelated input is not logged. There is deliberately no per-MOVE log line.
- **Explicit non-change:** app gesture thresholds, `BaseSwipeDetector`/UP semantics, success
  assertions and the drawer readiness rules were not changed. The longer duration is harness-only.
- **Guards:** `scripts/nothingui-drawer-trace-guard.sh` now requires the summary fields, the debug
  Play and Normal gates, the MOVE counter, and rejects per-MOVE logging (literal and inside a MOVE
  case). Its fixture suite adds missing-summary, realistic per-MOVE and literal per-MOVE negatives.
  `emulator-smoke-test.sh` and `emulator-smoke-drawer-test.sh` require the logged 1500 ms duration.
- **Verification actually run (no Gradle, no emulator):** `nothingui-drawer-trace-guard.sh "$PWD"`
  OK; its suite all pass; `emulator-smoke-test.sh` all pass; `emulator-smoke-drawer-test.sh` all
  pass; `verify-play-build-test.sh`, home/theme/home-role/icon/brand/identity/manifest suites all
  pass; the repo-level identity, brand, theme, home, home-role and icon guards OK; `sh -n` clean on
  every edited script; `git diff --check` clean.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, paid-service or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — dock-row parser and Play default-launcher hint)

- **Root cause from the CI97 actual XML, not guessed:** the dock icons (Phone, Messaging, Contacts,
  WebView Browser Tester) share y=1375..1568. The bottom QSB is three `content-desc="Search"` nodes
  with no resource-id at y=1626..1794, y=1642..1778 and y=1679..1742. The old `ui_dock_bottom`
  selected the deepest labelled node below 55% height, so it returned 1794; `drawer_swipe_target`
  then started at `1794 + (1794 - 1375) / 4 = 1898` instead of 1616. The old synthetic fixture
  omitted those bottom nodes, so it could not catch this.
- **Parser fix:** `ui_dock_bottom` now finds the same lowest labelled row as `ui_dock_top` and takes
  the maximum bottom only from nodes within a 2%-of-height row tolerance. The bottom `Search` nodes
  are excluded even without resource-ids; the existing `search_container_workspace` and `qsb_top`
  exclusions remain. The dock band is therefore 1375..1568 on the actual HOME.
- **Regression:** `scripts/emulator-smoke-test.sh` now uses the full actual hierarchy including all
  three id-less bottom `Search` nodes and derives the target from the parsed dock top/bottom/QSB
  instead of hardcoded values. It asserts dock bottom 1568, start 1616 in the 1568..1626 gutter,
  no 1183 fallback, no 1898 start, >1500 px travel and 0.7917 fraction. Before the parser fix the
  same test failed with dock bottom 1794 and target 1898, proving the regression is real.
  `scripts/emulator-smoke-drawer-test.sh` now uses the same actual hierarchy and requires every
  attempt to start in 1568..1626 and travel more than 1500 px.
- **No gesture/threshold change:** the swipe duration stays at 500 ms. CI97 sampled progress
  .229/.182/.293/.152 at zero release velocity because the start was on the bottom `Search` nodes,
  not because the MOVE sample count was proven low. App gesture logic, the 0.4 success threshold,
  readiness, the genuine swipe/search/Settings-foreground/HOME assertions and the bounded four
  attempts are unchanged; no blind retry or longer duration was added.
- **Play hint:** `play/res/values/strings.xml` now overrides `set_default_launcher_tip` with
  `DotWel Launcher` (single l). `lawnWithQuickstepPlay` already owns `play/res` and outranks the
  single `lawn` flavor, so the combined-variant resource priority is unchanged. The non-Play
  `lawnchair/res/values/strings.xml` text keeps `Lawnchair`, and `NOTICE.md` attribution is
  untouched. `play-brand-guard.sh` now requires the Play hint, rejects `Lawnchair` in it, requires
  the non-Play base to keep `Lawnchair`, and requires `PreferencesDashboard.kt` to still consume
  `R.string.set_default_launcher_tip`. Its fixture suite adds missing-Play-hint, Lawnchair-Play-hint,
  rebranded-non-Play-base and consumer-drift negatives.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` all pass;
  `emulator-smoke-drawer-test.sh` all pass; `play-brand-guard.sh "$PWD"` OK; its fixture suite all
  pass; `nothingui-home-role-guard-test.sh` all pass; `verify-play-build-test.sh` all pass;
  `sh -n` clean on every edited script; `git diff --check` clean. The Android build, unit tests and
  API 37 emulator run are left to CI.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, paid-service, app gesture or threshold change. The untracked local `w/` scratch directory
  was left uncommitted.

## done (previous run — P8 Play-only HOME role consent)

- **Play-only UI entry:** `PreferencesSetDefaultLauncherWarning` now calls
  `DefaultHomeRoleConsent.requestRole(context)` only when `isPlayStoreFlavor()` is true. If the
  platform dialog cannot be shown (API < 29, role unavailable, role already held, or the intent
  throws), it falls through to the inherited `Settings.ACTION_HOME_SETTINGS` path and finishes the
  settings activity exactly as before. Non-Play is unchanged.
- **Pure policy:** `DefaultHomeRolePolicy.resolve` returns `REQUEST_ROLE` only when
  `sdkInt >= 29 && roleAvailable && !roleHeld`; every other case returns `OPEN_HOME_SETTINGS`.
  `DefaultHomeRolePolicyTest` covers API 26, API 28, API 29, unavailable and already-held roles.
- **Native helper:** `DefaultHomeRoleConsent` uses `RoleManager.ROLE_HOME`, `isRoleAvailable`,
  `isRoleHeld` and `createRequestRoleIntent`; it starts the platform consent with
  `startActivityForResult` from the settings activity (or `FLAG_ACTIVITY_NEW_TASK` from a
  non-Activity context). It never uses `cmd role`, `add-role-holder`, or any privileged bypass. The
  result is not interpreted, so cancelling leaves the current default-home choice unchanged. No
  startup/launcher code calls it.
- **Guards:** added `scripts/nothingui-home-role-guard.sh` (7/7 fixture checks) and wired it plus its
  test into `scripts/verify-play-build.sh`. It rejects a missing API gate, a missing already-held
  check, a non-Play request, a missing Home settings fallback, a privileged bypass, and any
  startup/application reference.
- **Smoke:** `scripts/emulator-smoke.sh` now opens the existing settings warning before granting the
  role, taps the warning, waits for the real platform HOME consent, captures
  `role-consent-settings.xml/.png` and `role-consent.xml/.png`, taps the platform Cancel control,
  and requires the role holder list to be unchanged. It then grants the role for the existing
  HOME/drawer/Settings assertions, which are untouched. `emulator-smoke-test.sh` is 69 checks;
  `emulator-smoke-drawer-test.sh` remains 38. `docs/agent/emulator-verification.md` describes the
  new consent phase.
- **Verification actually run (no Gradle, no emulator):** `DefaultHomeRolePolicy` TDD harness RED
  then GREEN; `nothingui-home-role-guard.sh` OK; its suite 7/7; `emulator-smoke-test.sh` 69; drawer
  suite 38; `verify-play-build-test.sh` 11; brand 14, identity 8, manifest 31, theme 9, home 13,
  icon 15, trace 6; `sh -n` clean; `git diff --check` clean. CI must still run the Android build,
  unit tests and the API 37 emulator consent capture.
- **Scope reminder:** no manifest, permission, SDK, Gradle, workflow, applicationId, signing,
  release, paid-service or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — neutral Play icons and QSB)

- **Root cause, not guessed:** the Play policy only changed *which* renderer ran. `MonoIconThemeController`
  and `MonoThemedBitmap` still defaulted to `ThemedIconDrawable.getColors`, and
  `LawnchairProcessInitializer` sets the process-wide `COLORS_LOADER` to the wallpaper-derived
  `Accent1`/`Accent2` swatches. That is why the actual icons and the themed QSB glyph stayed
  blue/lavender after CI93.
- **Neutral palette:** added `NothingUiIconColors` using the original `NothingUiPalette.Ink`/`White`
  pair in `[background, foreground]` order, with the inherited transparent-background preference
  preserved. No wallpaper color is read on the Play path.
- **Inherited loader:** the Play branch of `LawnchairProcessInitializer` now returns the neutral pair,
  so every `ThemedIconDrawable.getColors` consumer (including themed clock icons) is neutral in
  Play. Non-Play keeps the exact inherited accent loader.
- **Controller and cache:** `NothingUiIconThemeController` passes the neutral provider to the native
  renderer and the generated fallback; `LawnchairThemeManager` uses the neutral pair in the Play
  freshness key while keeping `ThemedIconDrawable.getColors` for non-Play.
- **QSB:** `QsbIconUtil.setThemedIconResource` uses `NothingUiHomeChrome.textColor` for themed
  layers and the single-tint path only behind `NothingUiFeature.homeEnabled`. Non-Play keeps
  `QsbIconTint*`/`ColorAccent`. Search actions, accessibility, workspace, wallpaper and the red
  header accent are unchanged.
- **Style:** `NothingUiIconThemeController.policyFor` now puts `NothingUiIconPolicy.resolve(` on the
  same line as `=` with 8-space arguments, fixing the only CI93 spotless/ktlint violation.
- **Tests/guards:** added `NothingUiIconColorsTest` (black/white pairs, neutral channels, contrast,
  stable order). Extended `nothingui-icon-render-guard.sh` and its fixture suite from 13/13 to
  15/15 with the neutral palette, controller provider, Play/non-Play cache keys, QSB gate and
  Play/non-Play loader checks.
- **Verification actually run (no Gradle, no emulator):** `nothingui-icon-render-guard.sh "$PWD"`
  OK; `nothingui-icon-render-guard-test.sh` 15/15; `nothingui-home-guard.sh` OK and suite passes;
  `nothingui-theme-guard.sh` OK and suite passes; `play-brand-guard-test.sh`,
  `play-identity-guard-test.sh`, `manifest-guard-test.sh` and `verify-play-build-test.sh` all pass;
  `sh -n` clean on both edited scripts; `git diff --check` clean. No Android build or emulator run
  happened here; CI must produce the HOME/drawer pixels for review.
- **Scope reminder:** no workflow, Gradle, SDK, manifest, permission, applicationId, signing,
  release, smoke-harness or asset change. The untracked local `w/` scratch directory was left
  uncommitted.

## done (previous run — Play icon renderer wiring)

- **Root cause, not guessed:** the Play defaults lived only in `BoolPref` (`themed_icons` and
  `pref_forceIconMonochrome` default true), while the inherited renderer read the raw preference
  keys with false defaults. `LawnchairThemeManager` therefore built no theme controller on a fresh
  Play install, and `MonoIconThemeController`'s forced branch also read
  `shouldForceMonochrome()` with a false default. The provider's force branch returned early before
  icon-pack/per-app overrides, so changing preferences alone could not make the actual pixels
  monochrome and would have ignored explicit choices.
- **Provider wiring:** `LawnchairIconProvider.getIcon` resolves `NothingUiIconPolicy` from the Play
  gate, the themed-icons preference, the force preference and a per-component custom-selection
  decision. The forced native fallback skips the icon pack only when the policy says so; an
  explicit icon-pack or per-app override returns its own drawable and is not replaced.
- **Renderer wiring:** added `NothingUiIconThemeController`, installed only when
  `NothingUiFeature.homeEnabled`. It applies the policy per icon using `SourceHint.key`, delegates
  monochrome-layer apps to the inherited `MonoIconThemeController`, and generates the missing-layer
  fallback with the inherited `MonochromeIconFactory` + `MonoThemedBitmap`. File drawables are not
  forced. Custom selections return no themed bitmap and cached custom entries return
  `ThemedBitmap.NOT_SUPPORTED`.
- **Cache isolation:** the Play `getStateForApp` freshness string now appends the policy cache key
  (`ni=native|fallback|off`), in addition to the existing icon-pack, themed-source, themed, drawer,
  force and override state.
- **Non-Play:** `LawnchairThemeManager` still uses
  `iconControllerFactory.createThemeController()` and the original force-preference branch, and
  the provider keeps the original force/native decision. No non-Play cache string change.
- **Regression actually run (no Gradle, no emulator):** new
  `nothingui-icon-render-guard.sh` OK and its fixture suite 8/8; `nothingui-home-guard.sh` OK and
  13/13; `nothingui-theme-guard.sh` OK and 9/9; drawer-trace guard OK and 6/6;
  `emulator-smoke-test.sh` and `emulator-smoke-drawer-test.sh` all pass;
  `verify-play-build-test.sh` all pass; `sh -n` clean on every edited script; `git diff --check`
  clean.
- **Next:** let CI89+/PR #11 build and confirm the real HOME/drawer pixels are neutral monochrome.
  Then move to the search/QSB slice; do not treat this as visual sign-off until CI pixels are read.
- **Scope reminder:** no Gradle, workflow, SDK, manifest, permission, applicationId, signing,
  release or asset change. Drawer smoke is untouched. No Nothing assets were used. The untracked
  local `w/` scratch directory was left uncommitted.

## done (previous run — actual-home fixture and header rejection)

- **Root cause from CI87, not guessed:** the old fixture invented a bottom QSB node with the
  `search_container_workspace` id at `[0,1640][1080,1775]`, so `ui_qsb_top` returned 1640 and the
  geometry looked correct in tests. The actual UIAutomator dump instead puts that id on the HEADER
  at `[22,91][1058,294]`; the bottom QSB is only visible in the PNG at 1640..1775. The header
  therefore made `qsb_top=91`, failed the `qsb_top > dock_bottom` gutter condition, and fell back
  to `hotseat_top - margin` = 1183. The runtime trace confirmed the same `0.366` progress.
- **Geometry fix:** `ui_qsb_top` now requires a numeric dock bottom and accepts only a
  `search_container_workspace` whose top is strictly below it, so the y=91 header is rejected.
  `ui_dock_bottom` excludes search containers by resource-id, so the dock band is the hotseat
  icons (1375..1568), not the header or QSB. `drawer_target_for_dump` computes `dock_bottom` first
  and passes it to `ui_qsb_top`.
- **No-QSB start:** when the bottom QSB is absent (the actual HOME), `drawer_swipe_target` starts
  at `dock_bottom + (dock_bottom - hotseat_top) / 4`: 1568 + 48 = 1616, ending at 96. Travel is
  1520 px (>1500), start is inside the measured 1568..1640 gutter. A real bottom QSB still uses the
  midpoint start (1604).
- **Duration:** the swipe is now 500 ms instead of 300 ms and the duration is logged with every
  attempt, so adb delivers more MOVE samples for the zero-velocity gesture.
- **Fixtures:** replaced the synthetic bottom-QSB "actual" fixture with the real CI87 HOME shape
  (header at `[22,91][1058,294]`, hotseat node `[0,1375][1080,1920]`, four icons ending at 1568,
  no bottom QSB) and kept a separate real-bottom-QSB fixture. Assertions require start >1568,
  start <1640, travel >1500 and no 1183 fallback. The mock-adb drawer test uses the same actual
  HOME and requires >1500 px travel, a 1568..1640 start and a logged 500 ms duration.
- **Regressions actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` 61 checks pass;
  `emulator-smoke-drawer-test.sh` 38 checks pass; `nothingui-drawer-trace-guard-test.sh` 6/6;
  `nothingui-home-guard-test.sh` 13/13; `verify-play-build-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean.
- **Scope reminder:** no app gesture logic, threshold, animation, manifest, permission, SDK,
  applicationId, signing, release or workflow change. The debug Play `DotwelDrawerTrace` stays
  until the longer gesture is verified in CI. Colored icons and the blue QSB remain pending.

## done (previous run — smoke gesture length only)

- **Root cause read from the actual CI84 trace, not guessed:** the old measured target started at
  y 1183 and ended at y 384 (799 px on a 1920 shift range). The runtime trace showed only
  `-722.0703` displacement and `0.3760783` progress at zero velocity, below the 0.4 phone
  NORMAL→ALL_APPS success threshold, so the launcher snapped back to Normal exactly as designed.
- **Fix in the harness only:** `drawer_swipe_target` now accepts the measured dock icon bottom and
  QSB top. When both are present it starts in the empty gutter between them (actual HOME: dock
  bottom 1568, QSB top 1640 → start 1604) and ends at 5 percent of the display (96 on 1920), a
  1508 px / 78.5 percent travel. Without those measurements it keeps the safe above-dock start.
  The x stays at the horizontal centre because the start row is below every dock icon.
- **New pure helpers:** `ui_dock_bottom` (excludes the QSB and anything at/below its top),
  `ui_qsb_top` (matches the `search_container_workspace` id suffix), `drawer_swipe_is_long_enough`
  (strictly more than half the display height), and `drawer_swipe_travel_fraction`.
- **Orchestration:** `drawer_target_for_dump` measures `ui_dock_top`, `ui_qsb_top` and
  `ui_dock_bottom` from the same pre-swipe HOME XML and passes all three to the geometry. The
  four bounded attempts, before/after XML+PNG, swipe log and per-attempt debug trace are unchanged.
- **Regressions actually run (no Gradle, no emulator):** `emulator-smoke-test.sh` passes with new
  actual-1080x1920 geometry (`540 1604 540 96`, 0.7854), old-799-px reject (0.4161) and CI84
  trace reject (0.3760); `emulator-smoke-drawer-test.sh` passes and now also requires every mock
  attempt to swipe more than half the 1920 px display. Drawer-trace guard 6/6, home guard 13/13,
  theme guard 9/9, brand/identity/manifest suites pass, repo-level identity/brand/theme/home/trace
  guards OK, `sh -n` clean, `git diff --check` clean.
- **Scope reminder:** no app gesture logic, threshold, animation, manifest, permission, SDK,
  applicationId, signing, release or workflow change. The debug Play `DotwelDrawerTrace` stays
  until the longer gesture is verified in CI. Colored icons and the blue QSB remain pending.

## done (previous run — micro compile fix only)

- `Launcher.java` now logs `DisplayController.getNavigationMode(this).name()` (NavigationMode is a
  Java enum), not the invalid `.name` field.
- `AbstractStateChangeTouchController` now routes all four DOWN/UP diagnostics through the existing
  `stateName(...)` helper, and that helper uses `LauncherState.toString()` (the verified
  `TestProtocol.stateOrdinalToString` identifier), not the nonexistent `state.name` field.
- `nothingui-drawer-trace-guard.sh` fails if either file contains a `.name` field access without a
  call (`.name` not followed by `(`); its fixture suite adds navigation-mode and LauncherState
  negatives (now 6/6). The existing debug Play gate, per-attempt `logcat -s DotwelDrawerTrace`
  capture and swipe evidence checks are unchanged.
- Verification actually run (no Gradle, no emulator): drawer-trace guard OK and 6/6;
  `verify-play-build-test.sh`; home guard 13/13; theme guard 9/9; brand guard 14/14; identity
  guard 8/8; manifest guard all pass; emulator-smoke and drawer suites all pass; the repo-level
  identity/home/theme/brand guards OK; `sh -n` clean; `git diff --check` clean.

## done (previous run — P3b runtime drawer diagnostic)

- **Micro diagnostic only:** added `src/com/android/launcher3/touch/DotwelDrawerTrace.java`, a
  temporary log helper gated by `BuildConfig.DEBUG && "play".equals(BuildConfig.FLAVOR_channel)`.
  Release and github/nightly builds never emit the tag.
- **Selected factory:** `Launcher.createTouchControllers()` logs the selected controller class
  names and `DisplayController.getNavigationMode(...).name` when the trace is enabled.
- **Central controller:** `AbstractStateChangeTouchController` logs ACTION_DOWN accept/skip with
  state, ACTION_UP with no-intercept/dragging/state, `onDragStart` with start displacement and
  from/to state, and `onDragEnd` with velocity, fling, last displacement, progress and target
  state. There is deliberately no per-MOVE logging.
- **Smoke evidence:** `scripts/emulator-smoke.sh` runs a bounded
  `adb logcat -d -s DotwelDrawerTrace` into `appdrawer-trace-N.txt` after every swipe attempt,
  before the readiness check, so a no-op swipe still leaves a trace artifact.
- **Regression:** added `scripts/nothingui-drawer-trace-guard.sh` and its fixture test (debug gate,
  factory/controller trace points, no MOVE logging, per-attempt smoke capture); wired into
  `scripts/verify-play-build.sh`. The mock-adb drawer test now also requires
  `appdrawer-trace-N.txt` for all four attempts.
- **Verification actually run (no Gradle, no emulator):** trace guard OK and its test 4/4;
  `emulator-smoke-drawer-test.sh` all pass (now 42 checks); `emulator-smoke-test.sh` 34/34;
  `nothingui-home-guard-test.sh` 13/13; `verify-play-build-test.sh` 11/11; `sh -n` clean on edited
  scripts; `git diff --check` clean.
- **Scope reminder:** no gesture routing, animation, workflow, SDK, manifest, permission,
  applicationId, signing, Gradle or app-visual change. No guessed fix was applied. The untracked
  local `w/` scratch directory was left uncommitted.

## done (this run — P3b smoke harness retry-state repair)

- **CI70 hang read correctly:** run `44924192206` on PR #11 was canceled after 22m. The real
  `open_app_drawer` loop never advanced because every helper was a plain POSIX function writing
  globals. `capture_ui_xml` set `attempt=1` on each capture, and `wait_for_launcher_idle` /
  `wait_for_foreground` did the same, so the outer `attempt` was reset before it could reach
  `max_attempts=4`. The helper variables `name`, `label`, `target`, `xml`, `root`, `width` and
  `height` were also shared with callers. No assertion was weakened.
- **Helper isolation:** all pure/parsing helpers in `scripts/emulator-smoke-lib.sh` and the smoke
  script are now POSIX subshell functions `foo() ( ... )`, so their variables cannot leak. Helpers
  that must call `fail`/`exit` stay in the current shell but use unique names (`_rh_*`, `_cai_*`,
  `_cab_*`, `_cts_*`, `_vnh_*`, `_ead_*`). The `open_app_drawer` loop now keeps its `attempt` and
  `poll` state, while the exact Settings foreground proof and the real drawer UI path are unchanged.
- **Bounded operations:** added `run_with_timeout` (GNU `timeout`, or a background/kill fallback)
  and bounded every `adb_cmd` call: 60s default, 20s for uiautomator dump/pull and screencap, 30s
  for logcat, 300s for install, 180s for the base-APK pull, 60s for uninstall. Timeouts print the
  operation to stderr.
- **Evidence on failure:** `fail` marks the evidence as captured, and an `EXIT` trap in the live
  flow captures logcat + screenshot and prints the artifact directory for any other nonzero exit.
  This keeps evidence for `set -e` failures that do not go through `fail`.
- **Mock-adb regression:** added executable `scripts/emulator-smoke-drawer-test.sh`. A mock `adb`
  returns an unchanged HOME hierarchy, the test sources the real smoke script in a source-only mode
  (no device), runs the real `open_app_drawer`, and requires exit 1 (not a timeout), exactly four
  swipes, before/after XML+PNG and swipe command/log per attempt, retained logcat+screenshot, and
  the terminal failure/evidence message, all inside a 30s host timeout. It is wired into
  `scripts/verify-play-build.sh`. Temporarily reverting the `capture_ui_xml` subshell reproduces
  the old behavior (timeout 124 and more than four swipes), so the regression is real.
- **Verification actually run (no Gradle, no emulator):** `emulator-smoke-drawer-test.sh` passes
  (31 checks); `emulator-smoke-test.sh` 34/34; `verify-play-build-test.sh` all pass;
  `nothingui-home-guard-test.sh` 13/13; `nothingui-theme-guard-test.sh` all pass; `sh -n` clean on
  every edited script; `git diff --check` clean. The regression was also proven to fail against a
  temporary reverted copy of the smoke script.
- **Scope reminder:** this run changed only the smoke harness and its tests. No app visual change;
  the actual HOME grid/drawer visuals, colored icons and blue QSB are still pending and must not be
  claimed as visually ready. User workspace/wallpaper choices were not touched. No workflow, SDK,
  manifest, permission, applicationId, signing or Gradle change was made. The untracked local `w/`
  scratch directory was left uncommitted.

## done (prior run — P3b drawer-readiness smoke repair)

- **CI68 failure read correctly:** run `44921875638` on PR #11 was green for compile/style/unit but
  the API 37 smoke failed at `appdrawer` with no search label. The coordinator downloaded the actual
  `home.xml` and `appdrawer.xml`; both were identical HOME (clock `4:10`, dock Phone/Messaging/
  Contacts/WebView/Browser/Tester), so the swipe did not transition and the Settings launch phase
  was never reached. The emulator's `ColorBuffer74` log noise was not assumed to be infra, and no
  assertion was lowered.
- **Root cause:** `open_app_drawer` swiped from `height * 3 / 4` (~1440 on 1920) to `height / 4`.
  The dock occupies roughly 1375–1568, so the gesture started on the Phone icon instead of the
  workspace and was consumed by the dock.
- **Fix:** `open_app_drawer` now runs up to 4 bounded, state-based attempts. Each attempt waits for
  the launcher to be the idle resumed foreground, captures `appdrawer-attempt-N-before.xml` +
  `.png`, computes the target from the live HOME hierarchy, swipes, then polls for the real drawer
  search input or app-list container. Every attempt also writes `appdrawer-attempt-N.xml` + `.png`
  and an `appdrawer-swipe-log.txt` line plus `appdrawer-swipe-N.txt`.
- **Geometry:** the swipe target uses the UIAutomator root bounds (so current insets/root bounds
  apply), finds the dock top from the lowest labelled row, and starts in the empty workspace above
  it (e.g. 1920 px display / 1400 px dock top -> start y 1208, end y 384). `wm size` is only a
  measured fallback when the hierarchy is unavailable. The old 75% dock hit point is gone.
- **Readiness:** `drawer_is_ready` accepts an actual search input (`/input`, `EditText`,
  `AllAppsSearchInput`, `search_container_all_apps`) or app-list container (`apps_list_view`,
  `SearchContainerView`); a closed HOME is not ready. The dump must also differ from the pre-swipe
  HOME, so a swipe that did nothing cannot be mistaken for an opened drawer. The pre-search
  `Settings` label assertion was removed because Settings may be off the first screen; the real
  search-result assertion remains.
- **Mandatory flow preserved:** the drawer is still opened by a real swipe, search is still typed
  into the real input, the clickable Settings result is still tapped, and the exact
  `com.android.settings/` foreground poll is still required (bounded 15 s). There is still no
  `am start` shortcut to Settings. Clock/date, app-info, About, theme-sample, and crash checks are
  unchanged.
- **Regression:** `scripts/emulator-smoke-test.sh` is now 34/34, adding pure fixtures for root
  bounds, dock-top detection, the measured swipe target (including the old 75% case and fallback),
  drawer readiness (including an unchanged reference HOME), and static
  assertions that each attempt is bounded, captures evidence, and no longer uses the 75% start.
- Pending visuals are untouched: **colored icons and the blue QSB still need pixel repair; the
  header fits the pinned row but is not visually ready.** Private-space runtime UI, the in-app
  `RoleManager.ROLE_HOME` prompt and the non-Play runtime control remain pending. No Gradle,
  workflow, SDK, manifest, permission, applicationId, signing, release, paid-service or YouTube
  change was made. The untracked local `w/` scratch directory was left uncommitted.

## done (prior run — P3b bounded finish)

- Reviewed the existing branch diff against `main` and kept the saved work rather than restarting.
  The branch already contained: the Play-only `NOTHINGUI_HOME_ENABLED` flag, the original
  `NothingUiHomeHeaderView` (live Doto clock/date, red accent, dot strip), `NothingUiHomeClock`,
  the smartspace-slot hook, monochrome icon defaults, QSB and page-dot hooks, a static home guard,
  a JUnit clock test and the extended emulator smoke.
- **Fixed the specific review concern (chrome contrast).** `NothingUiHomeChrome` no longer pairs
  `Themes.getColorBackgroundFloating` (pale) with `Themes.getAttrColor(workspaceTextColor)` (often
  wallpaper-derived white). It now selects an explicit original pair from `NothingUiPalette`:
  light theme -> `Paper` surface + `Ink` text; dark theme -> `Gray900` surface + `Paper` text.
  The choice follows the inherited user light/dark theme (`R.attr.isMainColorDark`), matching the
  inherited day/night QSB icon and page-dot tints. The header, QSB pill and page dots all share
  this pair.
- **Header row fit.** Reduced the header clock to 30 sp, date to 10 sp, outer padding to 10/2 dp,
  card padding to 14/6 dp, corner radius to 22 dp and the dot strip to 48×5 dp so the card fits the
  existing single-row pinned smartspace cell without clipping. The header still uses the live clock,
  date, red accent and monochrome dot motif; it is not a sample-only screen.
- **Guard coverage added.** `scripts/nothingui-home-guard.sh` now asserts the original palette pair,
  the `isMainColorDark` theme choice, that the header shares the pair, and that the chrome never
  falls back to `getColorBackgroundFloating` / `workspaceTextColor`. It also locks the fitted
  clock/date text sizes. The fixture suite adds an inherited-floating/wallpaper negative case.
- **Smoke evidence.** `scripts/emulator-smoke.sh` captures the actual HOME (`home.xml` + `home.png`)
  and requires live clock/date text with no inherited `Lawnchair` text. It opens the inherited app
  drawer (`appdrawer.xml` + `.png`), searches for Settings, taps the real result, verifies
  `com.android.settings` is foreground, then returns HOME. The app-info, About, theme-sample and
  crash checks are retained.
- Pending items are untouched: private-space runtime UI, the in-app `RoleManager.ROLE_HOME` prompt
  and the non-Play runtime control. No manifest, permission, SDK, applicationId, signing, release,
  paid-service, workflow or YouTube change was made. The untracked local `w/` scratch directory was
  left uncommitted.

## verification actually run (no Gradle, no emulator, no CI)

- This run: `sh scripts/nothingui-home-guard.sh "$PWD"` -> OK.
- This run: `sh scripts/nothingui-home-guard-test.sh` -> 16/16 pass, including the new hardcoded
  preview container, missing selected smartspace mode and post-construction dummy override negatives.
- This run: `sh scripts/verify-play-build-test.sh` -> 11/11 pass.
- This run: `sh scripts/emulator-smoke-test.sh` -> all pass (unchanged widget placement coverage).
- This run: `sh scripts/emulator-smoke-drawer-test.sh` -> all pass (unchanged 1500 ms/4-attempt drawer).
- This run: identity, manifest, brand, theme, home-role, icon-render and drawer-trace fixture suites
  -> all pass.
- This run: `sh -n` clean on both edited scripts; `git diff --check` clean.
- Not run here: `spotlessCheck`, any Gradle build/test, the API 37 emulator smoke, or PR CI. This is
  source/fixture verification only; it is not a runtime or pixel claim.

## next

- Main/supervisor owns PR16 approval for `agent/p11-preview-header` at head `df2bfbc` (app fix
  `31d0963`). APK110 remains the fallback and does not depend on this branch.
- CI must be green on this head: `spotlessCheck`, `assembleLawnWithQuickstepPlayDebug`, the Play
  unit tests, `verify-play-build.sh`, both smoke suites and the API 37 emulator smoke.
- Inspect the CI `grid-settings.png` from the API 37 run: the preview's first page should now show
  the neutral NothingUI header card with a live Doto clock/date, red accent and dot strip, matching
  the real Play HOME `home.png`. If it still shows the inherited welcome card, capture
  `grid-settings.xml`/`.png` and verify the preview process resolved `getSmartspaceMode()` to
  `LawnchairSmartspace` with `NothingUiFeature.homeEnabled=true`; do not hardcode the header or add
  fake clock text.
- The existing widget-placement, bind-consent, safe-Add, role-consent and drawer artifacts must
  still pass unchanged.
- P8 remains open beyond these slices: appearance controls, backup/restore wiring and any broader
  onboarding. Pending gates: private-space runtime UI and a non-Play runtime control build.

## blockers

- The two PR16 CI runs (`df2bfbc` run `44987132494` and `941ffca` run `44987210606`) completed with
  `action_required`, not success/failure: GitHub is waiting for a maintainer to approve the
  workflow. The branch push used the runner's GitHub Actions token, so `gh` is unauthenticated and
  a `workflow_dispatch` returns 403. The Android compile, unit tests, `spotlessCheck` and the
  API 37 `grid-settings.png` pixels are therefore still unverified.
- Main/supervisor must approve PR16 and approve/re-run CI for `agent/p11-preview-header`.
- The preview mirrors the live workspace's smartspace availability fallback in memory only; it
  deliberately does not write the `smartspace_mode` preference from a preview renderer. If the real
  HOME would persist a fallback, the preview may briefly show the fallback layout until HOME reloads.
- The preview header is the same `nothingui_home_header`/`NothingUiHomeHeaderView` as HOME, so any
  future header layout change automatically affects the preview; the guard requires the preview to
  keep following `SmartspaceMode.getLayoutResourceId()` rather than a copied layout.
- The pre-existing local branch `agent/p11-preview-header-fix-only-gr` was at the same base and had
  no commits; the work is on the correctly named `agent/p11-preview-header`.

## decisions locked

- applicationId for the Play rebrand: com.launchernos.dotwellabs (approved by the owner 2026-11-21).
- Play display label: DotWel Launcher (single l), approved 2026-11-21; display label only.
- Public Play listing name: OPEN, release blocker, do not guess or claim clearance.
- Free models/services only. Cache heavy installs in workflows.

## rulings (this run and prior P3a)

- P10b harness correction: the exposed Add is tapped only through its intersection with the
  remeasured viewport, pulled 32 px above the viewport bottom and at least 24x24 px. The original Add
  centre is never used. Cost if wrong: an Add that is mostly under the navigation bar causes a
  bounded measured scroll and then a fail with pixels instead of opening Android HOME.
- P10b harness correction: an API37 `ProviderId{cmp:ComponentInfo{...}}` provider is accepted only
  inside an active widget-id block whose host is this launcher; a section header or a second provider
  line ends the block. Cost if wrong: an unusual dump shape fails closed rather than accepting a
  provider catalog or another launcher's widget as placement.
- P10b review correction: both HOME hierarchies are normalised to node records with explicit R/C
  markers before comparison, and the helper rejects known picker/sheet preview ancestors. When a
  workspace node exists, the host must be inside it. Cost if wrong: a real widget host that the
  hierarchy does not nest under a workspace fails closed, and the captured CI110 XML must drive the
  next change; a picker preview can never be counted as placement.
- P10b review correction: placement proof requires a new `AppWidgetId` with a provider, not just a
  provider name in the installed-provider list. Cost if wrong: an unusual `dumpsys appwidget` shape
  fails closed rather than accepting an already-installed provider as a newly bound widget.
- P10b review correction: after expansion the provider header is re-resolved by its `app_title`
  before measuring the preview. Cost if wrong: a provider whose title disappears after expansion
  fails closed instead of associating a later provider's preview with the selected one.
- P10a harness correction: the grid preview is accepted from a `/workspace` ViewGroup whose bounds
  are above every slider, inside the root and smaller than it, with a `hotseat`/`search_container_workspace`
  child. Cost if wrong: a future preview without that resource-id fails closed; the captured XML
  must drive any update, and a class-name guess is never accepted.
- P10a harness correction: Apply is proven read-only by a non-clickable label inside a non-clickable
  `android.widget.Button`, not by the accessibility `enabled` flag. Cost if wrong: a future Apply that
  stays visually grey but becomes clickable fails the smoke, which is the intended safety direction.
- P10a harness correction: when every measured long-press candidate is occupied,
  `home_longpress_target` fails instead of returning the band centre. Cost if wrong: a crowded HOME
  aborts the widget phase rather than opening an item-specific menu, which is the safe outcome.
- P3b actual-home fix: the bottom QSB is only accepted when its top is strictly below the measured
  dock icon bottom; the same `search_container_workspace` id on the header is rejected. Cost if
  wrong: a device whose QSB sits above the dock icons would fall back to the icon-band gutter
  instead of the dock/QSB midpoint, which is still a >1500 px swipe.
- P3b actual-home fix: when the bottom QSB is absent, start a quarter of the measured icon band
  below the icon bottom (1568 + 48 = 1616). Cost if wrong: a shorter icon band starts closer to
  the icons, but the start remains below every icon and above the PNG-visible QSB top.
- P8 drawer diagnostic: the harness swipe duration is now 1500 ms instead of 500 ms. Cost if wrong:
  the gesture takes longer on a slow emulator, but it is still a bounded `input swipe` and gives adb
  more MOVE samples at zero release velocity. This is a harness/fixture change only; the app's
  gesture logic, threshold and ACTION_UP semantics are untouched.
- P8 drawer diagnostic: the per-gesture `gestureSummary` is emitted once at UP/CANCEL and only for a
  debug Play gesture that started in `NORMAL`. Cost if wrong: a gesture that never reaches this
  controller leaves no summary, but that is exactly the lost-input case the existing DOWN/UP
  interception lines already show; no unrelated input is logged and there is no per-MOVE flood.
- P3b drawer-readiness repair: derive the swipe target from the live HOME hierarchy (root bounds +
  lowest labelled row) rather than a fixed display fraction. Cost if wrong: the hierarchy adds one
  uiautomator dump per attempt, but the gesture can no longer land on the dock; if no labelled row
  is found the measured `wm size` fallback uses 55% height, still above a 71%-height dock.
- P3b drawer-readiness repair: require an actual drawer search input or app-list container before
  proceeding. Cost if wrong: a future drawer that exposes neither id will fail rather than silently
  testing HOME, which is the intended fail-closed behavior.
- P3b drawer-readiness repair: require the post-swipe dump to differ from the pre-swipe HOME. Cost
  if wrong: a drawer that opens and produces a byte-identical hierarchy would be rejected, but the
  inherited drawer changes the visible tree, and this directly rejects the CI68 closed-HOME case.
- P3b drawer-readiness repair: drop the pre-search `Settings` label assertion but keep the real
  search-result assertion and the exact foreground poll. Cost if wrong: a drawer that opens without
  Settings on the first screen still proceeds to search, which is the behavior the task needs.
- P3b smoke repair: the app-launch assertion reads only the live
  `topResumedActivity`/`mResumedActivity` fields and matches the exact package boundary; task
  history is never treated as foreground. Cost if wrong: a dump that omits both fields fails the
  smoke instead of passing on a historical record.
- P3b smoke repair: the drawer taps the clickable Settings result node (or its nearest clickable
  ancestor), never an earlier bare `text="Settings"` label. Cost if wrong: if the result container
  is not clickable the nearest ancestor is used, and if no clickable node exists the label bounds
  are the last-resort fallback.
- P3b chrome pair: use the original `Paper`/`Ink` (light) and `Gray900`/`Paper` (dark) pair selected
  by `R.attr.isMainColorDark`, not the inherited wallpaper text plus floating surface. Cost if
  wrong: with a light theme on a dark wallpaper the card is light rather than wallpaper-matched,
  but it keeps high contrast and follows the user's light/dark choice, matching QSB/day-night tints.
- P3b header: keep the original header in the inherited pinned smartspace slot, sized to one row,
  rather than hard-wiring it into `Workspace` or adding a second launcher surface. Cost if wrong:
  the header is less tall than a multi-row Nothing-style clock widget, but it cannot clip the grid.
- P3a repair: the forbidden-font check inspects lowercased basenames only. Cost if wrong: a
  forbidden font hidden inside a directory name would not be caught, but fonts live flat in
  `lawnchair/res/font` and the guard still checks the whole file list there.
- P3a repair: the diagnostic route reuses the existing exported `PreferenceActivity` and an
  explicit extra instead of adding a component. Cost if wrong: the extra is discoverable in debug
  Play builds, but it is inert outside `BuildConfig.DEBUG` + Play and has no release exposure.
- P3a repair: the smoke starts the sample with
  `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_MULTIPLE_TASK` (`0x18000000`) so the extra is delivered
  to a fresh instance. Cost if wrong: the sample task is separate from the HOME task and is
  auto-removed from recents; if `am` ignores the flag on a future API the smoke fails rather than
  silently reusing About.
- P3a: the Play-only gate is a `BuildConfig` boolean (default false, true in the `play` flavor)
  rather than a resource or a source-set split. Cost if wrong: the shared theme code still compiles
  for github/nightly and the guard must keep asserting the flag; the font bytes add ~281 KB to
  those APKs even though they are unused.
- P3a: Doto is bundled as static 400/700 instances generated from the official variable font, not
  as the variable font itself. Cost if wrong: a future display weight outside 400/700 needs another
  static instance and an attribution hash update.
- P3a: body/title/label text uses `FontFamily.SansSerif`, not a bundled font. Cost if wrong: the
  launcher follows the platform sans rather than a fixed brand sans, which is intentional for
  legibility and avoids another font license.
- P3a: the safe gate requires a `fallback` slot, so a caller cannot silently render a blank
  non-Play surface. Cost if wrong: future callers must supply the inherited theme explicitly.
- P3a: the new theme guard is called from `verify-play-build.sh` rather than a workflow edit,
  because `.github/workflows/` is off-limits. Cost if wrong: a future CI refactor that stops
  calling `verify-play-build.sh` also drops the theme guard.
- P3a system-bar repair: the diagnostic sample passes its own dark flag into `EdgeToEdge` and skips
  the inherited early `enableEdgeToEdge()` call, so bar contrast follows the requested sample mode
  and never the inherited system/preference theme. Normal settings keep the inherited path. Cost if
  wrong: the sample's window setup is not byte-for-byte the settings sequence, so a settings-only
  regression must still be caught by the normal-path guard and the smoke's `return_home
  theme-sample` resume check.

## prior rulings still binding (P2c)

- Play resources live in the `lawnWithQuickstepPlay` multi-flavor source set, not the single
  `play` flavor. `flavorDimensions` puts `app` (lawn) before `channel` (play), so a single-flavor
  Play resource loses same-name lawn resources at merge time. The brand guard asserts the source
  set ownership.
- The Play manifest lists both `android:label` and `android:icon` in `tools:replace`; the overlay
  owns both values and the base values are discarded at merge.
- All Play icon artwork lives in `play/res`; github/nightly keep the inherited Lawnchair icon.
  The Play icon is an original near-black/white/red dot grid, not a Nothing asset.
- Play locale overrides replace only the `Lawnchair` brand token in `onboarding_welcome`.
  `derived_app_name` is a Play-gated variant-level `resValue` because the build-type value outranks
  flavor resources.
- The brand guard is called from `verify-play-build.sh`, not a workflow file, so CI keeps it
  without editing `.github/workflows/`.

## log

- 2026-11-22: P5 PR19 CI155 HOME long-press harness recovery on
  `agent/home-widget-composition-v1-new` (`3c00ebc`), from `62e1afd`. CI155 reached all three live
  own widgets and the measured device Settings shortcuts, then `home_longpress_target` returned
  `540,896` inside the non-clickable Device host and opened its resize frame. `ui_point_is_free` now
  counts `*AppWidgetHostView` classes and `/appwidget` ids as occupied regardless of clickable/label
  flags, keeps labelled clickable icon/folder protection, expands host bounds by the measured margin
  and adds bounded 90/95/100 percent candidates to reach the empty band below the Device card.
  Fixtures reject `540,896`, select `540,1300`, cover pending/unlabelled hosts and all-occupied
  fail-closed, and keep the legacy `540,834` empty target. Local smoke 450/450, drawer 38/38,
  widget guard 31/31, home guard 19/19, verify-play-build 11/11, `sh -n` and `git diff --check`
  clean. No Gradle/emulator/CI claim; PR19 not merged.
- 2026-11-22: P5 PR19 pending-widget smoke harness recovery on
  `agent/home-widget-composition-v1-new` (`089ca86`, `27c6baa`, `c39199a`), from `740b2cb`. The one
  reported fixture failure was reproduced: `home_pending_widget_bounds` set `saw_ws` only when a
  pending host was already inside a workspace, so the fallback returned a host outside a present
  workspace. `saw_ws` now tracks any workspace node. Added `own_widget_new_binding` (exactly one new
  numeric record, exact `$PKG` host/provider package, exact full DotWel class) and
  `foreground_is_component` (exact `.AllowBindAppWidgetActivity`). The own-widget round now requires
  real launcher HOME after Create and a one-pending decrease, failing closed otherwise. Added
  positive/negative fixtures and static flow gates. Java policy constants joined to one line for
  GJF AOSP. Local shell suites/guards pass; no Gradle/emulator/CI claim. PR19 not merged.
- 2026-11-22: P11 grid-preview header parity on `agent/p11-preview-header` (`31d0963`, `df2bfbc`),
  from `main` `e7c9240d` (P10b PR15 merged). `LauncherPreviewRenderer` no longer hardcodes
  `R.layout.smartspace_container`; it resolves the selected `SmartspaceMode.layoutResourceId` in the
  constructor before `addCallbacksAndLoad`, with an in-memory `LawnchairSmartspace` fallback when the
  mode is unavailable. On Play that is `nothingui_home_header`, so the grid/launcher preview matches
  the live HOME header; github/nightly keep the inherited container. Disabled smartspace, the dummy
  backup placeholder and the Google/Smartspacer modes are preserved. The dummy placeholder is passed
  through a new constructor argument so a synchronous bind cannot race the post-construction setter.
  The static home guard and its fixture suite now lock the preview source, reject the hardcoded
  container and the post-construction override, and require the disabled-smartspace gate. Local
  guard/verify/smoke/drawer/identity/brand/theme/role/icon/trace suites pass; `sh -n` and
  `git diff --check` clean. No grid values, Apply behavior, workflow, Gradle, SDK, manifest,
  permission, applicationId, signing or asset change. CI and `grid-settings.png` pixels still pending.
- 2026-11-21: P10a grid/widget harness correction on `agent/p10-grid-widget-smoke` (`f51fcb3`),
  from `main` `55a25a2`. CI106 (`10644959244281`) was assembly/style/unit green and the real grid
  editor opened, but the new readiness assumed a `LauncherPreviewView` class and an `enabled=false`
  Button that the actual hierarchy does not contain. The actual `grid-settings-attempt-6` dump has a
  preview `AndroidViewHolder` with a `/workspace` ViewGroup plus `hotseat`/`search_container_workspace`,
  and Apply is a non-clickable `TextView` inside a non-clickable empty `Button` with `enabled=true`
  and grey pixels. The smoke now validates the preview from its bounds (above the sliders, inside and
  smaller than the root, with the hotseat container), matches Apply by its non-clickable containing
  Button, rejects a clickable Apply, captures the last failed readiness PNG, and makes
  `home_longpress_target` fail instead of returning an occupied centre. Fixtures use the actual
  hierarchy and add the matching negatives. No app source, SDK, workflow, Gradle, manifest,
  permission, applicationId, signing, paid-service or asset change. Local smoke/drawer/verify test
  suites pass; `sh -n` and `git diff --check` clean. CI and device evidence are still required.
- 2026-11-21: P9 Play settings announcement cleanup on `agent/newtinybranchagent-p9-settings`
  (`ad05a12`), from `main` `5da711d` (PR12 merged after green CI102 `10244953269478`, 11m49).
  `PreferencesDashboard` now renders `AnnouncementPreference()` only inside
  `if (!isPlayStoreFlavor())`, so the inherited Lawnchair 16 sneak-peek and placeholder
  "important announcement" cards no longer appear in Play settings; non-Play keeps them and nothing
  was rebranded or fabricated. The debug warning, default-home warning/role consent, About and
  NOTICE attribution are untouched. `play-brand-guard.sh` now requires the gate and import, rejects
  a removed non-Play call, DotWel text in the announcement component and announcement resources in
  `play/res`; its suite adds four negatives. The real settings smoke asserts no inherited
  announcement markers and captures the clean `role-consent-settings.png` before tapping the
  default-launcher warning; the 1500 ms / 4-attempt drawer, search, exact Settings foreground,
  HOME-return and role-Cancel checks are unchanged. All local guard/smoke/verify suites pass;
  `sh -n` and `git diff --check` clean. CI/device evidence and PR creation are still pending.
- 2026-11-21: Drawer input pacing and per-gesture summary on `agent/p8-home-role-consent`
  (`d341e51`). CI100 (`44951103338`) was compile/style/unit green, the role consent cancel passed
  and the Play hint pixels say `DotWel Launcher`. Geometry was correct on all four attempts
  (`540 1616 540 96`, 500 ms), but the traces showed last displacement/progress `-726.84 / .37856`,
  `-194.84 / .10148`, `-188.76 / .09831`, `-264.76 / .13790`, all velocity 0 and accepted
  Normal->AllApps; the requested 1520 px MOVE travel was not fully observed. The harness now uses a
  bounded 1500 ms swipe (still logged per attempt) and the debug Play controller emits one
  `gestureSummary` at UP/CANCEL with DOWN x/y/time, MOVE count, last MOVE y/time, UP y/time and
  history size. No per-MOVE log, no app threshold/UP/success change. The drawer-trace guard now
  requires the summary fields/gates and rejects per-MOVE logging; smoke fixtures assert 1500 ms.
  Local trace, smoke, drawer and all guard suites pass; `sh -n` and `git diff --check` clean. CI and
  device evidence are still required.
- 2026-11-21: Dock-row parser and Play hint repair on `agent/p8-home-role-consent` (`e40fc3b`,
  `f83603d`). CI97 (`44949228055`) passed compile/style/unit and captured/cancelled the real native
  `ROLE_HOME` dialog with an unchanged role holder list, but the drawer phase failed four attempts.
  The actual HOME XML has three id-less bottom `Search` nodes at y=1626..1794; the old
  `ui_dock_bottom` returned 1794 and `drawer_swipe_target` started at 1898 instead of 1616.
  `ui_dock_bottom` now takes the bottom only from the same icon row as `ui_dock_top`, so id-less
  bottom Search nodes are excluded. The actual-hierarchy regression now includes all three nodes,
  derives the target from parsed values and asserts dock bottom 1568, start 1616 in the 1568..1626
  gutter, no 1898 and >1500 px travel; the old parser fails it with 1794/1898. The mock-adb drawer
  test uses the same hierarchy. Duration stays 500 ms because CI97's low progress came from the
  1898 start, not proven sampling loss; no gesture/threshold change. Also added the Play-only
  `set_default_launcher_tip` "DotWel Launcher" override in `play/res` (non-Play keeps Lawnchair),
  with brand-guard checks for the Play text, non-Play inherited text and the dashboard consumer.
  Local smoke, drawer, brand, role and verify suites pass; `sh -n` and `git diff --check` clean.
  No workflow, Gradle, SDK, manifest, permission, applicationId, signing or paid-service change.
- 2026-11-21: P8 Play-only HOME role consent slice on `agent/p8-home-role-consent` (`7f5a6c9`,
  `567203f`, `38348e7`). The existing settings warning now requests `RoleManager.ROLE_HOME` only on
  Play, through a pure API/role-state policy and a native consent helper; non-Play keeps the inherited
  `ACTION_HOME_SETTINGS` path. Cancelling leaves the role unchanged; API < 29, unavailable and
  already-held roles fall back to Home settings. Added `DefaultHomeRolePolicyTest`, a 7/7 static
  guard, and a smoke phase that taps the warning, captures and cancels the real platform consent,
  and proves the holder list is unchanged before granting the role for the existing HOME/drawer
  assertions. Local shell suites pass; CI/PR12 and runtime consent are pending. Corrected CI93
  (style failure, not fully green) and recorded CI95 as fully green with verified pixels.
- 2026-11-21: Neutral Play icon/QSB fix on `agent/p3b-actual-home-visual-slice-n` (`9fc5a33`).
  CI93 (`44944409947`) on `9076be5` had assembly, unit tests and emulator pass but a style failure;
  it was not fully green. CI95 (`44946373901`) was fully green in 11m40 and its actual pixels were
  verified black/white icons and black HOME/drawer QSB. Before CI95, the inspected HOME/drawer pixels
  kept the wallpaper-derived blue/lavender tint on the icon fallback and the QSB glyph. Root cause was the
  inherited process-wide `ThemedIconDrawable.COLORS_LOADER`, not the policy. Added
  `NothingUiIconColors`, gated the loader to the neutral black/white pair in Play (non-Play
  unchanged), passed the provider through the controller and fallback, kept the Play freshness key
  neutral, neutralized themed QSB layers behind the Play gate, and fixed the CI93 `policyFor`
  style. Icon-render guard now 15/15 with `NothingUiIconColorsTest`. CI95 then verified the
  black/white icons and black HOME/drawer QSB pixels.
- 2026-11-21: Actual-home fixture fix on `agent/p3b-actual-home-visual-slice-n` (`039a41d`).
  CI87 (`44935461427`, artifact `14719887963`) still traced `0.366` progress target Normal. The
  actual HOME XML puts `search_container_workspace` on the y=91 HEADER, not the bottom QSB, so
  `ui_qsb_top` returned 91 and the gutter branch fell back to start 1183. The fixture had invented
  a bottom-QSB id at 1640. `ui_qsb_top` now requires a dock bottom and rejects candidates at or
  above it; `ui_dock_bottom` excludes search containers; `drawer_target_for_dump` derives the dock
  bottom first. With no bottom QSB, the start is dock_bottom + icon_band/4 = 1568 + 48 = 1616,
  ending at 96 (1520 px, 79.2 percent). The swipe duration is 500 ms and is logged. The real CI87
  HOME is now the fixture; a separate bottom-QSB fixture still proves the 1604 midpoint. Local
  shell suites: smoke 61 checks, drawer 38 checks, trace 6/6, home 13/13, verify suite all pass;
  `sh -n` and `git diff --check` clean. No app logic, thresholds, manifest, permissions, SDK,
  applicationId, signing or workflow change. New API 37 evidence is still required.
- 2026-11-21: Smoke gesture length fix only on `agent/p3b-actual-home-visual-slice-n`
  (`96e2f7b`, `4ebc2b5`). CI84 (`44933644538`, artifact `14719700048`) showed the route works
  (DOWN accepted, Normal→AllApps) but the old test swipe covered only 799 px of the 1920 shift
  range, so `dragEnd` at velocity 0 recorded progress `0.3760783` and correctly returned Normal.
  The harness now measures the dock icon bottom and QSB top from the same HOME XML and starts in
  the empty gutter between them, ending at 5 percent of the display (actual 1080x1920:
  `540 1604 540 96`, 1508 px / 0.7854). Added pure `ui_dock_bottom`, `ui_qsb_top`,
  `drawer_swipe_is_long_enough` and `drawer_swipe_travel_fraction`, plus regressions that reject
  the old 0.4161 geometry and the CI84 0.3760 trace. The mock-adb drawer test now requires every
  attempt to exceed half the display. App gesture logic, thresholds, visuals, manifest,
  permissions, SDK, applicationId, signing and workflows are unchanged. Local shell suites pass;
  the longer gesture still needs a new API 37 smoke run to produce the AllApps `dragEnd` trace.
- 2026-11-21: Micro compile fix only on `agent/p3b-actual-home-visual-slice-n`. CI81
  (`44932685973`) on `f2377c5` failed javac on the new diagnostics: `NavigationMode` is a Java
  enum, so `getNavigationMode(this).name` became `.name()`, and `LauncherState` has no `name`
  field, so all four state logs use `stateName(...)` backed by the verified `toString()`. The
  drawer-trace guard now rejects `.name` field access and its fixture suite is 6/6. Debug Play
  gating and per-attempt trace artifacts unchanged; no app behavior change.
- 2026-11-21: P3b smoke harness retry-state repair on `agent/p3b-actual-home-visual-slice-n`
  (`d5122ad`, `50176d8`). CI70 (`44924192206`) was canceled after 22m because plain POSIX helper
  functions shared globals: `capture_ui_xml` reset the outer `open_app_drawer` `attempt`, so the
  4-attempt loop could repeat forever; `name`/`label`/`target`/`xml` also leaked between helpers and
  callers. Pure helpers are now subshell functions, effectful helpers use unique `_*` names, every
  adb/uiautomator call is bounded by `run_with_timeout`, and an `EXIT` trap retains evidence on
  failure. Added executable `emulator-smoke-drawer-test.sh` (mock adb, real `open_app_drawer`,
  unchanged HOME, exactly four swipes, per-attempt evidence, exit 1 inside 30s) and wired it into
  `verify-play-build.sh`; a temporary revert reproduces the old timeout/5+ swipes. Local shell
  suites pass; no Gradle/emulator run here. Colored icons + blue QSB still need pixel repair; header
  fits but is not visually ready.
- 2026-11-21: P3b drawer-readiness repair on `agent/p3b-actual-home-visual-slice-n` (`522516b`,
  `fb5aa61`, `83c3ad8`). CI68 (`44921875638`) was compile/style/unit green but the API 37 smoke failed because
  `appdrawer.xml` was identical to `home.xml`; the 75%-height swipe started inside the dock/Phone
  hit region. `open_app_drawer` now uses up to 4 bounded state-based attempts, waits for launcher
  idle, derives the target from live root bounds + dock top, captures before/after XML+PNG and a
  swipe log per attempt, and requires a real drawer input/container that differs from the pre-swipe
  HOME. The real swipe -> search -> Settings tap -> exact
  foreground flow is unchanged. `emulator-smoke-test.sh` is 34/34. Static checks only; CI and pixels
  pending. Colored icons + blue QSB still need pixel repair; header fits but is not visually ready.
- 2026-11-21: P3b smoke repair on `agent/p3b-actual-home-visual-slice-n` (`84a0493`). The app-launch
  false positive came from grepping the whole dumpsys dump; only the live resumed fields now count,
  polled with a bounded wait. The drawer taps the clickable Settings result instead of the first
  text match, captures `settings-launched` and `home-after-app-launch` XML/PNG, and fails if either
  foreground assertion is wrong. Added `emulator-smoke-lib.sh` and a 14-case regression wired into
  `verify-play-build.sh`; existing guard suites and 16 unit tests unchanged. Colored icons + blue
  QSB still need pixel repair; the header fits but is not visually ready. No visual edits this run.
- 2026-11-21: P3b bounded finish on `agent/p3b-actual-home-visual-slice-n` (`ac31c4e`). Fixed the
  chrome white-on-white risk with an explicit neutral surface/ink pair selected by the inherited
  light/dark theme, shared it across the header/QSB/page dots, sized the header to the single pinned
  row, extended the home guard (13/13) and kept the actual-HOME + drawer/search/launch smoke. Static
  checks only; CI and pixel review pending. Pending private UI / RoleManager / non-Play runtime
  unchanged.
- 2026-11-21: P3b saved work checkpointed on the branch: Play-gated clock header, pure clock
  formatter, monochrome icon defaults, QSB/page-dot chrome hooks, home guard + tests, and the
  actual-HOME/drawer smoke. Run was cancelled before closeout; resumed and finished above.
- 2026-11-21: P3a system-bar repair: CI62 (`44909523145`) on `e359a9a` was green (7 token + 4
  predicate JUnit tests, 0 skipped) but the real dark sample kept dark status/nav icons. Root
  cause: the sample branch used the inherited `EdgeToEdge()`/`enableEdgeToEdge()` theme preference
  instead of the requested sample mode. Added an explicit `darkTheme` parameter, passed
  `themeSampleDark` from the diagnostic branch, skipped the inherited early call there, and added
  guard fixtures (9/9). P3a is merged; HOME styling moved to P3b.
- 2026-11-21: P3a repair/visual-evidence slice: reproduced and fixed the CI53 guard false positive
  (full-path vs basename scan), added the `NothingOS-Launcher`/ndot regression suite, added the
  DEBUG+Play diagnostic sample route, and extended the API 37 smoke to capture dark/light sample
  XML+PNG and return HOME.
- 2026-11-21: P3a foundation implemented: palette/spacing/motion/typography, Doto OFL assets,
  Play-only `BuildConfig` gate, sample screen and previews, pure token tests, and a static theme
  guard wired into `verify-play-build.sh`.
- 2026-11-21: P2c verified by the coordinator: CI51 (`44903885094`) on `e6ea08b` green with 4
  Gradle tests and API 37 install/HOME/role/crash checks; HOME says `Welcome to DotWel Launcher`
  and About/app-info show the dot-grid icon and name.
- 2026-11-21: PR9 merged to `main` at `02ac058`; the P3a branch was cut from that merge.
- 2026-11-21: CI42 (`44901579949`) on `293f96e` was fully green; the earlier About icon and HOME
  welcome defects were repaired by moving `play/res` to the `lawnWithQuickstepPlay` multi-flavor
  source set.
- 2026-11-21: CI37 (`44900708538`) failed the Play manifest merge; the `android:icon`
  `tools:replace` repair and its guard regression landed before PR9.
- 2026-11-21: PR8 merged at `4bd5c39`; PR7 merged the Play label and guard suites.
- 2026-11-21: P2a complete (Play applicationId `com.launchernos.dotwellabs` + identity/authority
  guard + docs).
- 2026-11-21: P1c complete (private-space permission + locked-profile search filter + bug-report
  receiver/provider removal).
