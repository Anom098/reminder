# Contributing

## Getting set up

```bash
bash tool/bootstrap.sh          # or: pwsh tool/bootstrap.ps1
flutter run
```

The bootstrap script fills in the generated platform files and runs
`build_runner`. It never overwrites a file that already exists, so the curated
platform configuration is safe.

---

## Before you open a pull request

```bash
dart format lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

CI runs exactly these, plus an Android and an iOS build. All four must pass.

---

## Coding standards

The linter is strict and enforced (`analysis_options.yaml`). Beyond what it can
check:

### Documentation

Every public member carries a doc comment — `public_member_api_docs` is a
warning, and warnings fail CI. Write comments that explain **why**, not what:

```dart
// Bad: restates the code.
/// Adds days to the date.

// Good: explains a decision the reader cannot infer.
/// Uses the [DateTime] constructor rather than `add(Duration(days:))` so that a
/// daylight-saving transition does not shift the wall-clock time.
```

### Errors

Never throw across a layer boundary. Return `Result<T>` with an `AppFailure`.
`AppFailure.message` is shown to users, so write it for them: say what failed
and what they can do about it. Never put an exception's `toString()` in it.

### Time

Never call `DateTime.now()` outside the composition root. Take a `Clock`.
Anything that computes an occurrence must be testable with a `FixedClock`.

### The domain layer imports nothing

`features/*/domain/` may import `dart:*` and `package:equatable` only. No
Flutter, no Drift, no plugins. If a domain type seems to need `Color` or
`IconData`, store an `int` and resolve it in the presentation layer — see
`CategoryIcons`.

### Widgets

Keep them small and composable. A `build` method longer than about 60 lines
wants extracting into private widgets in the same file. Prefer private
`StatelessWidget` classes over `_buildX()` helper methods: they get their own
element, so Flutter can skip rebuilding them.

### Cross-isolate identifiers

Values in `NotificationConstants` are persisted by the OS inside pending
notifications. **Changing one orphans every notification already scheduled on a
user's device.** Add new values; never repurpose old ones.

---

## Testing expectations

| Change | Tests expected |
| --- | --- |
| Domain logic | Unit tests, including edge cases (month ends, DST, exhausted rules) |
| Repository / SQL | Tests against an in-memory database, not mocks |
| Parser | A case in `rule_based_voice_command_parser_test.dart` for every new phrasing |
| Widget | A widget test, plus a large-text-scale check for anything in a list |
| Scheduling | A test asserting what ended up scheduled, using `RecordingScheduler` |

Prefer hand-written fakes (`test/helpers/test_doubles.dart`) over generated
mocks. Assert on outcomes, not on call sequences.

Name tests as behaviour, and use `reason:` where an assertion encodes a
decision:

```dart
test('a repeating reminder rolls forward and stays scheduled', () { … });

expect(
  repository.rows,
  hasLength(1),
  reason: 'an orphaned notification would alert about a deleted reminder',
);
```

---

## Database changes

1. Edit `core/database/tables/reminder_rows.dart`.
2. Bump `AppConstants.databaseSchemaVersion`.
3. Add an `if (from < N) { … }` block to `AppDatabase.migration.onUpgrade`.
4. Add a migration test.
5. Regenerate: `dart run build_runner build --delete-conflicting-outputs`.

A schema change without a migration step will lose user data on upgrade.

---

## Commits and pull requests

- One logical change per commit; imperative subject line
  (`Add weekly recurrence snapping`).
- Explain **why** in the body when it is not obvious from the diff.
- PR description: what changed, why, how it was verified, and anything a
  reviewer should look at especially closely.
- Update `TODO.md` when you complete or discover work.

---

## Adding a platform capability

Because every platform edge is behind an interface, adding one follows the same
shape each time:

1. Define or extend the contract in `domain/` (or `core/services/*`).
2. Implement it in `data/` (or `core/services/*/`).
3. Register it in `core/di/app_providers.dart`.
4. Write a fake in `test/helpers/` and test the callers against it.
5. Document the platform asymmetry if the two behave differently — do not paper
   over it with a lowest-common-denominator abstraction.
