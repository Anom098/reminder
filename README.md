# Voice Reminder

An offline-first reminder app for Android and iOS. Say what you need to
remember, and the phone announces it aloud at the right moment.

> "Remind me to call Mom tomorrow at 7 PM."

The app extracts the task (**Call Mom**), the date (**1 August**) and the time
(**19:00**), schedules it, and at 7 PM says: *"Reminder. Call Mom."*

Everything runs on the device. There is no account, no server, and no network
dependency.

---

## Contents

- [Status](#status)
- [Getting started](#getting-started)
- [How it works](#how-it-works)
- [Project layout](#project-layout)
- [Voice commands it understands](#voice-commands-it-understands)
- [Testing](#testing)
- [Platform notes](#platform-notes)
- [Documentation](#documentation)

---

## Status

Feature-complete, **compiling clean and fully green on tests**:

```
flutter analyze  →  0 errors, 0 warnings
flutter test     →  123/123 passing
```

Verified against Flutter 3.44.8 / Dart 3.12.2. Not yet run on physical
hardware — notification delivery, exact alarms and doze behaviour still need a
real device. See [TODO.md](TODO.md) for what remains.

---

## Getting started

### Prerequisites

| Tool | Version |
| --- | --- |
| Flutter | 3.27 or newer (stable) |
| Dart | 3.6 or newer (ships with Flutter) |
| JDK | 17 (Android builds) |
| Xcode | 15 or newer (iOS builds) |
| CocoaPods | 1.15 or newer (iOS builds) |

### First run

Two things are deliberately **not** in source control: Drift's generated code,
and the purely machine-generated platform files (the Xcode project, the Gradle
wrapper jar, launcher icons). One command materialises both:

```bash
# Windows
pwsh tool/bootstrap.ps1

# macOS / Linux
bash tool/bootstrap.sh
```

The script runs `flutter create` into a temporary directory and copies across
**only files that do not already exist here**, so the hand-written
`AndroidManifest.xml`, `build.gradle`, `Info.plist`, `AppDelegate.swift` and
`Podfile` in this repository are never overwritten. It then runs
`flutter pub get` and `build_runner`.

Then:

```bash
flutter run
```

### Doing it by hand

```bash
flutter create --platforms=android,ios --org com.voicereminder --project-name voice_reminder .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

> `flutter create .` overwrites some templated files. Prefer the bootstrap
> script, which does not.

### Regenerating code after a schema change

```bash
dart run build_runner build --delete-conflicting-outputs
# or, while iterating:
dart run build_runner watch --delete-conflicting-outputs
```

### Configuration

Runtime configuration lives in [`.env`](.env), which is committed and contains
no secrets. Every value has a safe default and the app boots correctly if the
file is missing entirely. For machine-local overrides, create `.env.local`
(git-ignored).

---

## How it works

### Reminders and time

A reminder holds two instants:

- **`anchorAt`** — the original due time. It never moves, and defines the
  wall-clock time and day-of-month that recurrence inherits.
- **`dueAt`** — the *next* time it will fire.

Occurrences are always computed from `anchorAt`, never from the last fire time.
That is what stops a "daily at 09:00" reminder from drifting to 09:04 after a
week of slightly late deliveries.

All calendar arithmetic happens in local wall-clock time, so a daily 09:00
reminder stays at 09:00 across a daylight-saving transition.

### Scheduling

iOS allows an app at most **64** pending local notifications, and Android
degrades badly past a few hundred alarms. A reminder that repeats hourly forever
therefore cannot be handed to the OS in full. Instead:

1. Each reminder is materialised as at most `SCHEDULING_HORIZON_OCCURRENCES`
   upcoming notifications (12 by default).
2. Notification ids are allocated as a **contiguous 64-slot block** derived
   deterministically from the reminder's UUID, so cancellation can clear the
   whole block without knowing how many slots were used.
3. A periodic background task tops the window up long before it drains, and
   `rescheduleAll()` runs at start-up, on resume and after a restore.

`rescheduleAll()` cancels everything and re-derives rather than diffing.
An incremental update can silently drift out of sync with the OS after a reboot
or a killed process, and the failure mode — a reminder that never fires — is
invisible until it matters.

### Speaking

A notification alone cannot run Dart code, so announcing a reminder needs a
platform-specific mechanism:

| Platform | Mechanism |
| --- | --- |
| Android | An exact alarm (`android_alarm_manager_plus`) wakes the device and a background isolate speaks. A single rolling "sweep" alarm points at the soonest upcoming reminder rather than one alarm per reminder, which stays well inside the OS alarm quota. |
| iOS | Background execution at an exact instant is not available. The notification alerts the user, and the reminder is spoken when the app next comes to the foreground. |

This asymmetry is deliberate and documented rather than hidden behind a
lowest-common-denominator abstraction that would under-serve Android.

### Errors

Nothing throws across a layer boundary. Every fallible operation returns a
sealed `Result<T>`, whose failure arm carries an `AppFailure` — a domain
description of what went wrong, with a message written for the end user. Because
`Result` and `AppFailure` are both sealed, `switch` statements over them are
exhaustiveness-checked, so a new failure mode cannot be silently ignored.

---

## Project layout

```
lib/
  core/                     Cross-cutting infrastructure
    config/                 Typed runtime configuration from .env
    constants/              Non-configurable constants and storage keys
    database/               Drift schema, tables and connection
    di/                     Riverpod provider graph
    errors/                 AppFailure hierarchy
    router/                 GoRouter routes and navigation helpers
    services/               Platform abstractions + implementations
      background/           WorkManager and AlarmManager entry points
      logging/              AppLogger and its console backend
      notifications/        NotificationService and background handler
      permissions/          PermissionService
      speech/               SpeechRecognitionService
      tts/                  TextToSpeechService
    theme/                  Material 3 theming, spacing and breakpoints
    utils/                  Result, Clock, date arithmetic, formatters

  features/
    reminders/
      data/                 Drift repositories, mappers, scheduler
      domain/               Entities, repository contracts, use cases
      presentation/         Controllers, screens, widgets
    voice/
      data/parsers/         Rule-based parser, lexicon, text masking
      domain/               ParsedReminderDraft, parser contract
      presentation/         Capture controller and sheet
    settings/
      data/                 Preferences repository, backup service
      domain/               AppSettings, contracts
      presentation/         Settings screens

  shared/
    startup/                Post-first-frame bootstrap
    widgets/                Reusable presentation widgets

  app.dart                  Root widget
  main.dart                 Entry point
```

The dependency rule is one-way: `presentation → domain ← data`. The domain layer
imports nothing from Flutter, Drift or any plugin, which is what makes it
testable without a binding.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full picture,
including a layer diagram and the reasoning behind each boundary.

---

## Voice commands it understands

The shipping parser is deterministic, rule-based and fully offline. It handles:

| You say | It creates |
| --- | --- |
| "Remind me to call Mom tomorrow at 7 PM" | Call Mom · tomorrow 19:00 |
| "Remind me to drink water every hour" | Drink water · hourly |
| "Wake me up tomorrow at six" | Wake up · tomorrow 06:00 |
| "Remind me in 20 minutes to check the oven" | Check the oven · +20 min |
| "Remind me to take my tablets every day at 8 AM" | Take my tablets · daily 08:00 |
| "Remind me every Monday at 10 to water the plants" | Water the plants · weekly, Mondays 10:00 |
| "Remind me to log my hours every weekday at 5 PM" | Log my hours · Mon–Fri 17:00 |
| "Remind me about the dentist on 12 August at 9:30" | Dentist · 12 Aug 09:30 |
| "Remind me urgently to pay the electricity bill" | Pay the electricity bill · urgent · Bills |
| "Remind me to stand up every 30 minutes" | Stand up · every 30 minutes |

It also infers a **category** from keywords (tablets → Medicine, flight →
Travel) and a **priority** from urgency words.

When something is missing, the app asks instead of guessing:

> "Remind me to call the bank" → *When should I remind you?*

When it does have to assume, it says so:

> "Assumed 7 PM because 7 AM has already passed today."

Typed input goes through the identical parser, so the microphone is never a
prerequisite.

### Adding an LLM parser later

`VoiceCommandParser` is a two-method interface, and
`CompositeVoiceCommandParser` already handles falling back from a model-backed
parser to the rule-based one when the model is unavailable, fails, or returns a
low-confidence answer. Adding one means implementing the interface and setting
`VOICE_PARSER=llm` — no call site changes.

---

## Testing

```bash
flutter test                      # unit + widget tests
flutter test --coverage           # with coverage
flutter test --exclude-tags db    # skip tests needing native sqlite3
flutter test integration_test     # on a device or emulator
```

| Layer | Approach |
| --- | --- |
| Domain | Pure unit tests. Recurrence expansion, state transitions and the parser are exhaustively covered with a `FixedClock`. |
| Data | Real in-memory SQLite. The value of the repository is the SQL it generates, so mocking the query layer would test nothing. |
| Presentation | Widget tests with hand-written fakes, including a large-text-scale overflow check. |
| End to end | `integration_test` against a real device or emulator. |

Hand-written fakes are preferred over generated mocks: the tests assert on
behaviour ("what ended up scheduled"), which a small in-memory implementation
expresses far more clearly than a stack of stubs.

---

## Platform notes

### Android

- `minSdk` 23, `targetSdk` 35, core library desugaring enabled (required by
  `flutter_local_notifications` 18).
- `USE_EXACT_ALARM` is declared for install-time grant, with
  `SCHEDULE_EXACT_ALARM` as the runtime-requested fallback on Android 12/13.
  Without the grant the scheduler degrades to an inexact alarm rather than
  failing to schedule — a reminder a few minutes late beats one that never
  arrives.
- Release builds are signed from `android/key.properties` when present, and fall
  back to the debug config when absent so CI can still build.
- `kotlin.incremental=false` is set in `android/gradle.properties` **on
  purpose**. Kotlin's incremental compiler cannot relativise paths across
  Windows drive letters, so when the project and the pub cache sit on different
  drives (e.g. project on `E:`, cache on `C:`) plugin compilation dies inside
  `RelocatableFileToPathConverter` — surfacing only as a bare
  `Compilation error` with no file or line. Full recompiles are slower but
  correct. Safe to re-enable on macOS/Linux, or if you move the pub cache onto
  the same drive with `PUB_CACHE`.

### iOS

- Deployment target 13.0.
- `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` and the
  `audio` background mode are set. A missing usage string is an automatic App
  Store rejection *and* a hard crash on first use.
- `permission_handler` is compiled with only the permissions this app requests,
  so review does not flag unused permission APIs.
- Only the JSON backup format is importable; CSV and SQLite are export-only.

---

## Documentation

| Document | What it covers |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layers, dependency rules, key decisions and their trade-offs |
| [docs/API.md](docs/API.md) | The public contracts each layer exposes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, coding standards, review expectations |
| [TODO.md](TODO.md) | Completed work, pending work, known issues |

---

## Licence

Not yet chosen. Add a `LICENSE` file before publishing.
