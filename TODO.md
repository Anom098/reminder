# TODO

Running record of what is done, what is outstanding, and what is known to be
imperfect.

Last updated: 2026-08-01.

---

## Completed

### Project setup
- [x] Flutter project scaffold, `pubspec.yaml`, strict `analysis_options.yaml`
- [x] Android platform config — manifest, Gradle (minSdk 23 / targetSdk 35),
      desugaring, ProGuard rules, notification receivers, launch theme
- [x] iOS platform config — `Info.plist` with usage strings and background
      modes, `AppDelegate.swift` with audio session, `Podfile` with trimmed
      `permission_handler` flags
- [x] `tool/bootstrap.ps1` / `tool/bootstrap.sh` — materialise generated
      platform files without clobbering curated ones
- [x] `.env` runtime configuration with safe defaults

### Core
- [x] `Result<T>` + sealed `AppFailure` hierarchy
- [x] `AppLogger` abstraction with console backend and `NoopLogger`
- [x] `AppConfig` with tolerant parsing; boots correctly without `.env`
- [x] `Clock` abstraction (`SystemClock` / `FixedClock`)
- [x] Calendar arithmetic preserving wall-clock time and clamping month ends
- [x] Formatters, `Debouncer`, constants and storage keys
- [x] Riverpod provider graph

### Domain
- [x] `Reminder` with anchored recurrence and all state transitions
- [x] `RecurrenceRule` — once / hourly / custom minutes / daily / weekly /
      monthly / yearly, weekday sets, `until`, `maxOccurrences`
- [x] `ReminderCategory` with nine built-ins
- [x] `ReminderFilter` / `ReminderSort` / `ReminderBucket`
- [x] `AppSettings`, `ParsedReminderDraft`
- [x] Repository and service contracts
- [x] Seven use cases

### Data
- [x] Drift schema with indexes and `ON DELETE SET NULL`
- [x] `DriftReminderRepository` — SQL filtering, sorting, pagination, search
      across title / notes / category name
- [x] `DriftCategoryRepository` with idempotent seeding
- [x] `PreferencesSettingsRepository` with synchronous reads
- [x] Mappers with graceful degradation on malformed rows

### Platform services
- [x] `LocalNotificationService` — channels, actions, exact-alarm fallback,
      launch-action replay, time-zone setup
- [x] Notification background isolate handler (Done / Snooze while closed)
- [x] `NotificationReminderScheduler` — windowed scheduling, contiguous id
      blocks, full rebuild, missed reconciliation
- [x] `FlutterTtsService` with iOS audio session handling
- [x] `PlatformSpeechRecognitionService` — single-session, stream-adapted
- [x] `PermissionHandlerService` with Android-specific settings deep links
- [x] WorkManager top-up task and Android alarm sweep for spoken reminders
- [x] `FileBackupService` — JSON / CSV / SQLite export, JSON import with three
      merge strategies

### Voice
- [x] `RuleBasedVoiceCommandParser` — lead-ins, priority, recurrence, relative
      offsets, dates, times, categories, confidence scoring
- [x] `TextMask` index-aligned masking
- [x] `ParserLexicon` — isolated vocabulary, ready for localisation
- [x] `CompositeVoiceCommandParser` — the LLM seam, with fallback

### UI
- [x] Material 3 theme with seed colours, high contrast, spacing scale
- [x] GoRouter with typed navigation helpers
- [x] Home screen with bucketed sections, swipe actions, filter and sort
- [x] Reminder editor — date, time, recurrence, priority, category, colour,
      notes, spoken-text override with preview
- [x] Reminder detail with duplicate / share / preview / delete
- [x] Voice capture sheet with live transcript, animated indicator, draft
      review, interpretation notes and a type-instead fallback
- [x] Search with debounce
- [x] Category management
- [x] Settings: appearance, voice, reminders, data, permissions
- [x] Backup screen; permissions screen with per-permission repair
- [x] Shared widgets — `AsyncValueView`, `ErrorView`, `EmptyState`,
      `showConfirmDialog`, `CategoryIcons`

### Tests, CI, docs
- [x] Unit tests: `Result`, recurrence, entity transitions, filters, buckets
- [x] Parser tests covering every documented phrasing
- [x] Repository tests against in-memory SQLite
- [x] Use-case tests with hand-written fakes
- [x] Widget tests including a large-text-scale overflow check
- [x] Integration tests
- [x] GitHub Actions: analyse + test + coverage, Android build, iOS build
- [x] README, ARCHITECTURE, API, CONTRIBUTING

---

## Verified on 2026-08-01 (Flutter 3.44.8 / Dart 3.12.2)

- [x] **Compiles clean** — `flutter analyze`: 0 errors, 0 warnings
- [x] **All tests pass** — `flutter test`: 138/138
- [x] **Debug APK builds** — `flutter build apk --debug`
- [x] **Release APKs build** — `flutter build apk --release --split-per-abi`,
      arm64-v8a 22.5 MB. Signed with the **debug key** until a real keystore
      exists; installable for testing, not publishable.

Three real defects were found and fixed by that first run, which is exactly
what the tests were written for:

1. **Monthly recurrence lost the 31st.** `occurrences()` advanced iteratively
   (`31 Jan → 28 Feb → 28 Mar`), so the month-length clamp compounded. Now every
   occurrence is computed from the anchor with a step count, giving
   `31 Jan → 28 Feb → 31 Mar`.
2. **The category foreign key was never created.** Drift could not resolve
   `.references(CategoryRows, #id)` and silently emitted the column with no
   constraint, so deleting a category left dangling `category_id` values.
   Replaced with an explicit `customConstraint`.
3. **Table indexes were never created.** `@TableIndex` takes Dart getter
   symbols, not SQL column names; `{'due_at'}` matched nothing and the indexes
   were skipped.

## Spoken reminders verified end-to-end on 2026-08-01

Confirmed on a Realme RMX5000 (Android 15 / ColorOS), release APK, from logcat:

```
06:03:00.017  AlarmManager -> AlarmBroadcastReceiver
06:03:00.064  [SpeakAlarm] Sweep alarm 90001 fired.
06:03:00.091  [SpeakAlarm] Announcing 1 reminder(s).
06:03:00.991  AudioTrack sampleRate 24000, pkg com.google.android.tts
06:03:01.001  AudioFlinger createTrack_l -> playing
```

Getting there took **five** defects, none of which any test or analyzer could
have caught, because every one of them lived in the gap between the app and the
OS. They are listed below in the order they were found.

---

Defects found by building and installing a release APK, which no amount of
analysis or unit testing would have surfaced:

4. **Spoken reminders never fired.** `scheduleSpeakSweep()` arms the exact alarm
   that speaks a reminder aloud, and its only caller was `_scheduleNextSweep()`
   — reachable solely from the WorkManager task and the speak-alarm callback.
   Nothing on the foreground path armed it, so the alarm could only ever be set
   by code that required an alarm to have already fired. Reminders showed their
   notification and stayed silent. The scheduler now arms the sweep on every
   `schedule` / `cancelById` / `rescheduleAll`, via an injected hook so the data
   layer keeps no dependency on `android_alarm_manager_plus`.
   `NotificationReminderScheduler` had **no test file at all**; it now has one,
   covering both of its outputs.
5. **The WorkManager ProGuard keep rule matched nothing.** It named
   `be.tramckrijte.workmanager`, the package from 0.5.x; 0.9 moved to
   `dev.fluttercommunity.workmanager`. R8 was free to strip the reflectively
   instantiated `BackgroundWorker`, breaking the periodic top-up in release
   builds only. Verified fixed by checking `mapping.txt` — the class now maps to
   itself. A stale `dev.fluttercommunity.androidalarmmanager.**` rule was
   removed for the same reason (the real package is
   `dev.fluttercommunity.plus.androidalarmmanager`, already covered).

6. **R8 broke `flutter_local_notifications`, which silenced everything.** The
   plugin stores its pending-notification cache as JSON and uses an anonymous
   `TypeToken<ArrayList<NotificationDetails>>` to recover the element type.
   Gson reads that from the class's `Signature` attribute, and R8 in full mode
   (the AGP 8 default) discards generic signatures — so `cancel` / `cancelAll`
   threw `IllegalStateException: TypeToken must be created with a type
   argument`. `-keepattributes Signature` alone is **not** sufficient in full
   mode; `InnerClasses`, `EnclosingMethod` and
   `-keep class * extends com.google.gson.reflect.TypeToken` are all required.
   Because scheduling cancels before it schedules and returned early on
   failure, *nothing was ever scheduled in any release build* — no
   notification, no announcement, and no visible error, because the `Result`
   pattern propagated the failure perfectly cleanly. `schedule` and
   `rescheduleAll` now log and continue: rebuilding on a stale schedule is
   recoverable, rebuilding nothing is not.
7. **`android_alarm_manager_plus`'s manifest components were never declared.**
   The plugin ships a deliberately empty manifest
   (`<manifest package="..." />`) and requires the host app to declare
   `AlarmService`, `AlarmBroadcastReceiver` and `RebootBroadcastReceiver`
   itself. The permissions from that same README section had been added but not
   the components, so `oneShotAt` handed AlarmManager a PendingIntent aimed at
   a receiver Android did not know existed. No error — the alarm simply never
   arrived. **This is why spoken reminders could never have worked, in any
   build.**
8. **`AndroidAlarmManager.initialize()`'s return value was discarded.** It
   reports failure by returning `false`, not by throwing. A dead speech
   subsystem was therefore indistinguishable from a healthy one: alarms still
   register, they just never reach Dart. Now checked and logged.
9. **Both background isolates logged only at `warning`.** In the one place with
   no debugger, no UI and no test coverage, "ran and found nothing" produced
   exactly the same evidence as "never ran". Raised to `info`, and the sweep
   callback now reports the alarm id, the preference state, how many reminders
   were in range, and any TTS error.

R8 also required `-dontwarn androidx.window.extensions.**` /
`androidx.window.sidecar.**`: those are OEM-supplied classes that `androidx.window`
probes for at runtime and lives without, so they are deliberately absent from the
compile classpath.

### The lesson worth keeping

Defects 5–8 share a shape: **a plugin's contract lives partly in its manifest,
its ProGuard rules and its return values — not in its Dart API.** The Dart code
was correct in every case. Type checking, 138 unit tests and a clean analyzer
run could not have found any of them, and four of the five were invisible
without a physical device. Treat "installs and launches" as the beginning of
verification, not the end.

Plugin and toolchain drift fixed:

- `flutter_local_notifications` still **requires**
  `uiLocalNotificationDateInterpretation` (it was not removed in 18.x as
  assumed).
- `speech_to_text` moved `localeId` / `listenFor` / `pauseFor` onto
  `SpeechListenOptions`.
- Drift's `CaseWhen` now takes two type parameters: `CaseWhen<bool, int>`.
- `intl` must match the version `flutter_localizations` pins (0.20.2).
- **`workmanager` 0.5.2 does not compile at all** — it still used Flutter's v1
  embedding (`ShimPluginRegistry`, `PluginRegistrantCallback`, `Registrar`),
  which has been removed. Upgraded to 0.9.x, which renamed
  `NetworkType.not_required` → `notRequired` and requires
  `ExistingPeriodicWorkPolicy` for periodic tasks.
- `custom_lint` / `riverpod_lint` were dropped: they had an unsatisfiable
  version conflict and were never wired into `analysis_options.yaml`, so they
  were inert.
- Gradle 8.14, AGP 8.11.1 and Kotlin 2.2.20, per Flutter's deprecation
  warnings.

## Pending — must happen before this ships

- [x] **Spoken reminders on a real device** — verified end-to-end, see above.
- [ ] **Remaining on-device checks.** Still unverified: notification action
      buttons (Done / Snooze) while the app is force-closed, delivery after a
      reboot, behaviour once ColorOS puts the app into deep sleep overnight, and
      the WorkManager top-up actually running at its 6-hour period.
- [ ] **Re-check on a non-ColorOS device.** The Realme battery manager needed
      "Allow background activity" and "Allow auto-launch" enabled by hand. How
      much of that is required on stock Android is unknown.
- [ ] **Migrate `RadioListTile` usages.** `groupValue`/`onChanged` are
      deprecated in favour of a `RadioGroup` ancestor (11 analyzer infos). They
      still work; the sheets pop on selection, so plain `ListTile`s with a
      trailing check may be the better replacement anyway.
- [ ] **App icons and a monochrome notification icon.** The notification
      currently falls back to `@mipmap/ic_launcher`; Android renders a coloured
      launcher icon in the status bar as a white square. Add
      `@drawable/ic_notification`.
- [ ] **Choose and add a `LICENSE`.**
- [ ] **Android release signing** — create `android/key.properties` from
      `key.properties.example` and a keystore.
- [ ] **Verify the iOS 64-notification cap** in practice with several repeating
      reminders configured.

## Pending — planned

- [ ] Encrypted storage for sensitive settings (`flutter_secure_storage` is a
      dependency but nothing currently needs it; wire it up when a secret
      exists rather than encrypting the theme colour)
- [ ] Attachments (`attachmentPath` exists on the entity; no UI)
- [ ] Time-zone travel handling (`timeZoneId` is recorded; scheduling always
      uses the device zone)
- [ ] Localisation — `ParserLexicon` and `Formatters` are the seams
- [ ] Home-screen widgets / quick settings tile
- [ ] Wear OS and watchOS companions
- [ ] Cloud sync (implement `ReminderRepository` as a decorator)
- [ ] LLM parser behind `VOICE_PARSER=llm`
- [ ] Whisper speech engine behind `SPEECH_ENGINE=whisper`

---

## Known issues and accepted trade-offs

| Issue | Status |
| --- | --- |
| iOS cannot speak a reminder in the background; it speaks on next foreground | **Accepted** — no API allows otherwise |
| Repeating reminders only occupy a bounded window of OS slots | **Accepted** — required by the 64-notification cap; topped up in the background |
| Search treats `%` and `_` as wildcards | **Accepted** — Drift's typed `LIKE` has no `ESCAPE` clause |
| The SQLite export may miss un-checkpointed WAL data | **Accepted** — JSON is the supported backup format |
| Parser is English-only | **Open** — vocabulary is isolated for translation |
| `listLocalBackups` reports `reminderCount: 0` for previously written files | **Accepted** — counting would mean parsing every file to render a list |
| Notification ids are derived from a UUID hash, so a collision is possible | **Accepted** — 64-slot blocks over a 31-bit space; collision odds are negligible at realistic reminder counts |
| No migration paths exist yet (schema v1) | **Expected** — add them alongside the first schema change |
