# Architecture

## Goals that shaped this design

1. **A reminder must fire.** Everything else is secondary. Where a trade-off
   exists between elegance and delivery reliability, delivery wins.
2. **Offline first, with no backend.** There is no server to blame and no
   network to wait for.
3. **Testable time.** The app is almost entirely time-dependent logic, so time
   is injected everywhere.
4. **Swappable platform edges.** Speech, synthesis, notifications and parsing
   are all behind interfaces, because each has a plausible replacement.

---

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation                                                 │
│   screens · widgets · Riverpod controllers                   │
│   Knows: domain entities, use cases, provider graph          │
└───────────────────────────┬──────────────────────────────────┘
                            │ depends on
┌───────────────────────────▼──────────────────────────────────┐
│ Domain                          ← the stable centre           │
│   entities   Reminder, RecurrenceRule, ReminderCategory       │
│   contracts  ReminderRepository, ReminderScheduler,           │
│              VoiceCommandParser, BackupService                │
│   use cases  CreateReminder, CompleteReminder, …              │
│                                                               │
│   Imports NO Flutter, NO Drift, NO plugins.                   │
└───────────────────────────▲──────────────────────────────────┘
                            │ implements
┌───────────────────────────┴──────────────────────────────────┐
│ Data + platform services                                     │
│   DriftReminderRepository · NotificationReminderScheduler    │
│   FlutterTtsService · PlatformSpeechRecognitionService       │
│   RuleBasedVoiceCommandParser · FileBackupService           │
└──────────────────────────────────────────────────────────────┘
```

The dependency rule points inward. `domain/` has no imports outside `dart:` and
`package:equatable`, which is what lets the entire recurrence engine and every
use case be tested without a Flutter binding, a database or a device.

### Where the code lives

Feature-first, layered within each feature:

```
features/reminders/
  data/        implementations       (Drift, scheduler, mappers)
  domain/      contracts + entities  (no dependencies)
  presentation/ UI + controllers
```

Cross-cutting infrastructure lives in `core/`. A thing belongs in `core/` when
more than one feature needs it *and* it has no domain meaning — logging,
theming, routing, the `Result` type. Reminder scheduling is in
`features/reminders/`, not `core/`, because it is meaningless without reminders.

---

## Key decisions

### `Result<T>` instead of exceptions

**Decision.** Nothing throws across a layer boundary. Fallible operations return
`sealed class Result<T>` = `Success<T>` | `Failure<T>(AppFailure)`.

**Why.** Exceptions are invisible in a signature. In an app whose entire value
is "the reminder fired", a silently swallowed exception on a scheduling path is
the worst possible bug. Sealing the type means `switch` is exhaustiveness-checked
and adding a failure mode breaks the build at every site that must handle it.

**Cost.** More ceremony at call sites, and `guard`/`guardAsync` are needed at the
edges where third-party code still throws.

### Two instants per reminder

**Decision.** `anchorAt` (immutable original) and `dueAt` (next occurrence).

**Why.** Computing the next occurrence from the *last fire time* accumulates
error: a daily reminder delivered 90 seconds late every day drifts by three
quarters of an hour in a month. Anchoring removes drift by construction.

It also makes snooze correct. Snoozing sets `dueAt` and records `snoozedFrom`;
once the snooze fires, recurrence resumes from `anchorAt` rather than from the
snoozed time, so "snooze the 9 AM daily reminder by 10 minutes" does not
permanently move it to 9:10.

### Local wall-clock arithmetic, not `Duration`

**Decision.** `addDays`, `addMonths` and `addYears` rebuild a `DateTime` from
components rather than adding a `Duration`.

**Why.** `add(Duration(days: 1))` adds exactly 24 hours. Across a daylight-saving
boundary that shifts a 09:00 reminder to 08:00 or 10:00. Rebuilding from
components keeps the wall-clock time fixed, which is what a user means by
"every day at nine".

Monthly and yearly rules additionally **clamp**: 31 January plus one month is 28
or 29 February, never 3 March.

### Windowed OS scheduling

**Decision.** Materialise at most N future occurrences per reminder into
notification slots, in a contiguous 64-id block derived from the reminder UUID,
topped up by a periodic background task.

**Why.** iOS caps an app at 64 pending notifications; an unbounded repeating
reminder cannot be expressed. Deriving ids from the UUID means no mapping table
is needed and ids survive a restore. Reserving a fixed block means cancellation
can clear it without knowing how many slots were actually used.

**Cost.** A device that is off for longer than the window drains it. The
start-up and resume passes rebuild it, and the horizon is sized so this only
matters after weeks of non-use.

### Full rebuild instead of incremental scheduling

**Decision.** `rescheduleAll()` cancels every pending notification and
re-derives from the database.

**Why.** The OS schedule is state the app does not own. A reboot, a force-stop,
a restore or an OS-initiated cleanup can desynchronise it in ways nothing
observes. Diffing propagates that desynchronisation; rebuilding erases it. The
operation is cheap (tens of reminders) and runs at moments the user is not
waiting on it.

### Text masking in the parser

**Decision.** Patterns *mask* the characters they consume from a lowercase view
that stays index-aligned with the original string; whatever survives is the
title.

**Why.** Deleting matched substrings loses the original capitalisation, so
"call Mom" becomes "call mom". Masking preserves it. Blanking the consumed span
in the matching view also prevents a later pattern from re-claiming digits that
an earlier one already used — "in 20 minutes" cannot subsequently be read as
"20:00".

Pattern order encodes precedence: recurrence before dates (so "every Monday" is
not eaten by the "next Monday" rule), relative offsets before clock times.

### Sealed capture state instead of booleans

**Decision.** `VoiceCaptureState` is a sealed hierarchy, not a struct of flags.

**Why.** `isListening && !isParsing && draft == null` is a state machine written
in the least checkable way available. A sealed type makes the illegal
combinations unrepresentable and the `switch` in the UI exhaustive.

### Hand-written providers

**Decision.** Riverpod providers are written by hand; `build_runner` is
responsible for Drift alone.

**Why.** The graph is small enough that generation adds build time without
removing meaningful boilerplate, and keeping one generator in the project makes
the codegen step easier to reason about.

---

## Cross-isolate concerns

Three isolates run app code:

| Isolate | Entry point | What it does |
| --- | --- | --- |
| Main | `main()` | Everything the user sees |
| Notification action | `onDidReceiveBackgroundNotificationResponse` | Applies Done / Snooze while the app is closed |
| Background work | `workManagerDispatcher`, `speakDueRemindersCallback` | Schedule top-up; spoken announcements on Android |

Background isolates have **no provider graph and no widget tree**. They build
exactly what they need — a database connection, a scheduler — do one job, and
close the connection. This is why every class below the presentation layer takes
plain constructor arguments rather than a `Ref`.

Two consequences worth remembering:

- **SQLite runs in WAL mode** so a write from the notification isolate does not
  block a read on the UI isolate.
- **Identifiers that cross the boundary are a wire format.** The strings in
  `NotificationConstants` are persisted by the OS inside pending notifications.
  Changing one orphans every notification already on a user's device. Add new
  values; never repurpose old ones.

---

## Data model

```
category_rows                     reminder_rows
─────────────                     ─────────────
id            TEXT PK ◄────┐      id                 TEXT PK
name          TEXT         │      title              TEXT
color_value   INT          └──────category_id        TEXT NULL
icon_code_point INT                                  ON DELETE SET NULL
is_built_in   BOOL                priority           TEXT
sort_order    INT                 anchor_at          DATETIME
is_hidden     BOOL                due_at             DATETIME  ◄ indexed
                                  recurrence         TEXT (JSON)
                                  status             TEXT      ◄ indexed
                                  color_value        INT NULL
                                  is_spoken          BOOL
                                  spoken_text_override TEXT NULL
                                  snoozed_from       DATETIME NULL
                                  completed_at       DATETIME NULL
                                  last_fired_at      DATETIME NULL
                                  occurrence_count   INT
                                  attachment_path    TEXT NULL
                                  time_zone_id       TEXT NULL
                                  created_at         DATETIME
                                  updated_at         DATETIME
```

- Enums are stored as **text**, so a database opened by hand is readable and
  reordering an enum cannot silently reinterpret existing rows.
- Recurrence is stored as **JSON** in one column. It is never queried on, only
  read whole, so normalising it into its own table would buy nothing and cost a
  join on the hottest read path.
- `ON DELETE SET NULL` — deleting a category must not delete the reminders filed
  under it. This requires `PRAGMA foreign_keys = ON`, set in `beforeOpen`.
- `due_at` and `status` are indexed because every list query and the scheduler
  filter and order on them.

---

## Extension points

| I want to… | Do this |
| --- | --- |
| Add an LLM parser | Implement `VoiceCommandParser`, pass it as `llm:` to `CompositeVoiceCommandParser.fromConfig`, set `VOICE_PARSER=llm` |
| Swap in Whisper | Implement `SpeechRecognitionService`, override `speechRecognitionServiceProvider` |
| Add cloud sync | Implement `ReminderRepository` as a decorator over the Drift one; nothing above the contract changes |
| Add a notification style | Extend `ScheduledNotification` and `LocalNotificationService._detailsFor` |
| Change the schedule window | `SCHEDULING_HORIZON_OCCURRENCES` in `.env` |
| Add a language | Localise `ParserLexicon`, add ICU messages for `Formatters` |

---

## Known limitations

These are design consequences, not oversights. Each is a deliberate trade.

- **iOS cannot speak in the background.** The notification alerts; speech
  happens on next foreground. No API allows otherwise.
- **Repeating reminders have a finite scheduled horizon.** Mitigated by the
  background top-up and by rebuilding at start-up and on resume.
- **Search treats `%` and `_` as wildcards.** SQLite's `LIKE` has no `ESCAPE`
  clause available through Drift's typed API. A harmless superset of the
  expected behaviour for a search box.
- **The SQLite export can miss un-checkpointed WAL data.** The JSON export is
  the supported backup; the SQLite copy is a diagnostic aid, and says so.
- **The parser is English-only.** The vocabulary is isolated in
  `ParserLexicon` specifically so a translation is a data change.
