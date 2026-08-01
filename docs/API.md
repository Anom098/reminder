# API reference

The contracts each layer exposes. Full member-level documentation is in the
source; run `dart doc` to generate it.

```bash
dart doc
open doc/api/index.html
```

---

## Core

### `Result<T>` — `core/utils/result.dart`

Sealed: `Success<T>(value)` | `Failure<T>(AppFailure)`.

| Member | Purpose |
| --- | --- |
| `isSuccess` / `isFailure` | Predicates |
| `valueOrNull` / `failureOrNull` | Nullable access |
| `getOrElse(fallback)` / `getOrElseWith(fn)` | Defaulting |
| `fold(onSuccess, onFailure)` | Collapse both arms |
| `map` / `flatMap` / `flatMapAsync` | Transform and chain |
| `mapFailure` | Rewrite the failure |
| `onSuccess` / `onFailure` | Side effects, returns `this` |
| `Result.guard` / `Result.guardAsync` | Wrap throwing third-party code |
| `Iterable<Result<T>>.sequence()` | List of results → result of list, short-circuiting |

### `AppFailure` — `core/errors/app_failure.dart`

Sealed. Every variant carries a user-safe `message`, an optional `cause` and
`stackTrace`, a machine-readable `code`, and `isRetryable`.

`DatabaseFailure` · `NotFoundFailure` · `ValidationFailure` ·
`PermissionFailure` · `SpeechRecognitionFailure` · `TextToSpeechFailure` ·
`ParsingFailure` · `NotificationFailure` · `SchedulingFailure` ·
`StorageFailure` · `SerializationFailure` · `UnexpectedFailure`

### `Clock` — `core/utils/clock.dart`

`now()` / `nowUtc()`. `SystemClock` in production, `FixedClock` in tests.

---

## Domain entities

### `Reminder`

Immutable. State transitions return new instances.

| Method | Behaviour |
| --- | --- |
| `complete({firedAt})` | Repeating → next occurrence, still scheduled. One-shot → completed. Exhausted → finished. |
| `snooze({duration, now})` | Moves `dueAt`, records `snoozedFrom`, clamps the duration |
| `advanceToNextOccurrence({now})` | Rolls forward without counting an acknowledgement (catch-up) |
| `markMissed({now})` | Marks an unacknowledged reminder missed |
| `setEnabled({enabled, now})` | Toggles; re-enabling a past reminder moves it forward |
| `validate()` | Field → message map; empty means valid |
| `isOverdue(now)` / `isDueToday(now)` / `isUpcoming(now)` | Derived state |
| `spokenText` | The announcement, honouring an override |
| `notificationId` | Deterministic 31-bit id derived from the UUID |

### `RecurrenceRule`

A pure value. Constructors: `once`, `daily`, `hourly`, `everyMinutes`, `weekly`,
`monthly`, `yearly`, `weekdaysOnly`, `weekendsOnly`.

| Member | Behaviour |
| --- | --- |
| `occurrences({anchor, limit})` | Lazy ascending sequence; **always bounded** by an internal cap |
| `nextOccurrence({anchor, after})` | First occurrence strictly after `after`, or `null` |
| `describe()` | "Every 2 weeks on Mon, Wed" |
| `toJson()` / `fromJson()` | Storage form; malformed input degrades to `once` |

Ends via `until` (inclusive) or `maxOccurrences`.

### `ReminderFilter`, `ReminderSort`, `ReminderBucket`

Query descriptors shared by the SQL and in-memory paths, so the two cannot
diverge. `ReminderFilter.matches()` and `ReminderSort.comparator` are the
in-memory implementations of what `DriftReminderRepository` expresses as SQL.

### `ParsedReminderDraft`

The parser's output. May be **incomplete** by design.

`transcript` · `title` · `dueAt?` · `recurrence` · `priority?` · `categoryId?` ·
`confidence` · `missingFields` · `interpretationNotes` · `isComplete` ·
`needsConfirmation(threshold)` · `clarificationPrompt`

---

## Repository contracts

### `ReminderRepository`

Streams are the primary read path, so the UI stays in sync when a reminder is
completed from a notification while a list is on screen.

`watchReminders` · `watchReminder` · `getReminders` · `getReminder` ·
`getDueBefore` · `getActive` · `create` · `update` · `updateAll` · `delete` ·
`deleteWhere` · `deleteAll` · `count`

`delete` is idempotent — a duplicate notification action must not surface an
error.

### `CategoryRepository`

`watchCategories` · `getCategories` · `getCategory` · `create` · `update` ·
`delete` · `seedBuiltIns`

Built-in categories can be hidden but not deleted; `seedBuiltIns` is idempotent
and runs on every launch as a self-healing step.

### `SettingsRepository`

`watch()` · `current` (synchronous) · `save` · `reset`

`current` is synchronous so the first frame already has the user's theme.

---

## Service contracts

### `ReminderScheduler`

`schedule` · `cancel` · `cancelById` · `rescheduleAll` · `reconcileMissed` ·
`ensureBackgroundRefreshScheduled`

`rescheduleAll` is idempotent by design: it cancels everything and re-derives.

### `NotificationService`

`actions` (stream, replays the launch action) · `initialize` ·
`requestPermission` · `hasPermission` · `canScheduleExactAlarms` · `schedule` ·
`scheduleAll` · `showNow` · `cancel` · `cancelMany` · `cancelAll` ·
`pendingIds` · `launchAction`

`schedule` rejects an instant in the past rather than firing immediately —
a stale reminder is more confusing than a dropped one.

### `TextToSpeechService`

`isSpeaking` · `initialize` · `speak` · `stop` · `pause` · `applySettings` ·
`availableLanguages` · `availableVoices` · `isLanguageAvailable` · `dispose`

`speak` interrupts rather than queues: reminders are time-sensitive, and a stale
queue is worse than a truncated announcement.

### `SpeechRecognitionService`

`state` · `soundLevel` · `isAvailable` · `initialize` · `listen` · `stop` ·
`cancel` · `availableLocales` · `dispose`

`listen` returns a stream of partial transcripts that closes after the final
one. Exactly one session may be active.

### `PermissionService`

`status` · `statuses` · `request` · `requestAll` · `openSettings` ·
`openPermissionSettings`

Requests run sequentially; Android drops concurrent permission dialogs.

### `VoiceCommandParser`

`isAvailable()` · `parse(transcript, {reference})`

`reference` is injected rather than read from a clock, so parsing is
deterministic.

### `BackupService`

`export({format, includeSettings, includeCompleted})` · `share` ·
`import(path, {strategy, restoreSettings})` · `listLocalBackups` ·
`deleteLocalBackup`

Only `BackupFormat.json` is importable. Import refuses payloads written by a
newer app version, which would otherwise be silently truncated.

---

## Use cases

Each is a single-method class taking its collaborators by constructor.

| Use case | Notable behaviour |
| --- | --- |
| `CreateReminder` | Rejects a past due time. A scheduling failure does **not** fail the operation — the reminder is saved and the background pass retries. |
| `UpdateReminder` | Re-anchors and resets the occurrence counter when timing changes. |
| `DeleteReminder` | Cancels notifications **before** deleting the row, so a cancellation failure cannot orphan an alarm. |
| `DuplicateReminder` | Fresh id and history; moves a past copy into the future. |
| `CompleteReminder` | Succeeds quietly when the reminder is already gone. Safe from a background isolate. |
| `SnoozeReminder` | Duration clamped by the entity. Safe from a background isolate. |
| `SetReminderEnabled` | Re-enabling a past reminder moves it forward rather than firing immediately. |

---

## Provider graph

Declared in `core/di/core_providers.dart` and `core/di/app_providers.dart`.

`appConfigProvider` and `sharedPreferencesProvider` **throw** unless overridden
in `ProviderScope`, so a missing bootstrap step is an immediate error rather
than silent misbehaviour. Both are overridden in `main()`.

Presentation state:

| Provider | Type |
| --- | --- |
| `settingsProvider` | `NotifierProvider<SettingsController, AppSettings>` |
| `reminderListQueryProvider` | `NotifierProvider<ReminderListController, ReminderListQuery>` |
| `reminderListProvider` | `StreamProvider<List<Reminder>>` |
| `bucketedRemindersProvider` | `Provider<Map<ReminderBucket, List<Reminder>>>` |
| `categoriesProvider` / `categoryIndexProvider` | `StreamProvider` |
| `reminderProvider(id)` | `StreamProviderFamily<Reminder?, String>` |
| `voiceCaptureProvider` | `AutoDisposeNotifierProvider<VoiceCaptureController, VoiceCaptureState>` |
