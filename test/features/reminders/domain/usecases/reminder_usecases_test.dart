import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/complete_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/create_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/delete_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/duplicate_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/set_reminder_enabled.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/snooze_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/update_reminder.dart';

import '../../../../helpers/test_doubles.dart';

void main() {
  late FakeReminderRepository repository;
  late RecordingScheduler scheduler;
  late FixedClock clock;

  setUp(() {
    repository = FakeReminderRepository();
    scheduler = RecordingScheduler();
    clock = FixedClock(DateTime(2026, 8, 1, 10));
  });

  tearDown(() => repository.dispose());

  group('CreateReminder', () {
    CreateReminder build() => CreateReminder(
          repository: repository,
          scheduler: scheduler,
          clock: clock,
        );

    test('persists and schedules a valid reminder', () async {
      final Result<Reminder> result = await build().call(
        CreateReminderInput(
          title: '  Call Mom  ',
          dueAt: DateTime(2026, 8, 1, 19),
        ),
      );

      expect(result.isSuccess, isTrue);
      final Reminder created = (result as Success<Reminder>).value;

      expect(created.title, 'Call Mom', reason: 'the title is trimmed');
      expect(created.anchorAt, created.dueAt);
      expect(repository.rows, hasLength(1));
      expect(scheduler.scheduled.single.id, created.id);
    });

    test('rejects a due time in the past', () async {
      final Result<Reminder> result = await build().call(
        CreateReminderInput(
          title: 'Too late',
          dueAt: DateTime(2026, 8, 1, 9),
        ),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repository.rows, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    test('rejects an empty title', () async {
      final Result<Reminder> result = await build().call(
        CreateReminderInput(title: '   ', dueAt: DateTime(2026, 8, 1, 19)),
      );

      final AppFailure? failure = result.failureOrNull;
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).fieldErrors, contains('title'));
    });

    test('still succeeds when scheduling fails', () async {
      scheduler.failWith = const SchedulingFailure(message: 'no slots');

      final Result<Reminder> result = await build().call(
        CreateReminderInput(
          title: 'Call Mom',
          dueAt: DateTime(2026, 8, 1, 19),
        ),
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: 'losing the user\'s input is worse than a missing OS slot; '
            'the background top-up retries',
      );
      expect(repository.rows, hasLength(1));
    });
  });

  group('UpdateReminder', () {
    test('re-anchors and resets the counter when the timing changes', () async {
      final Reminder original = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: const RecurrenceRule.daily(),
        occurrenceCount: 5,
      );
      await repository.create(original);

      final Result<Reminder> result = await UpdateReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call(original.copyWith(dueAt: DateTime(2026, 8, 1, 20)));

      final Reminder updated = (result as Success<Reminder>).value;
      expect(updated.anchorAt, DateTime(2026, 8, 1, 20));
      expect(updated.occurrenceCount, 0);
      expect(scheduler.scheduled, hasLength(1));
    });

    test('leaves the anchor alone when only the title changes', () async {
      final Reminder original = buildReminder(occurrenceCount: 5);
      await repository.create(original);

      final Result<Reminder> result = await UpdateReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call(original.copyWith(title: 'Renamed'));

      final Reminder updated = (result as Success<Reminder>).value;
      expect(updated.anchorAt, original.anchorAt);
      expect(updated.occurrenceCount, 5);
    });
  });

  group('DeleteReminder', () {
    test('cancels notifications before removing the row', () async {
      await repository.create(buildReminder());

      final Result<void> result = await DeleteReminder(
        repository: repository,
        scheduler: scheduler,
      ).call('reminder-1');

      expect(result.isSuccess, isTrue);
      expect(scheduler.cancelled, <String>['reminder-1']);
      expect(repository.rows, isEmpty);
    });

    test('does not delete when cancellation fails', () async {
      await repository.create(buildReminder());
      scheduler.failWith = const NotificationFailure(message: 'nope');

      final Result<void> result = await DeleteReminder(
        repository: repository,
        scheduler: scheduler,
      ).call('reminder-1');

      expect(result.isFailure, isTrue);
      expect(
        repository.rows,
        hasLength(1),
        reason: 'an orphaned notification would alert about a deleted reminder',
      );
    });
  });

  group('CompleteReminder', () {
    test('completes and re-schedules', () async {
      await repository.create(
        buildReminder(
          dueAt: DateTime(2026, 8, 1, 9),
          recurrence: const RecurrenceRule.daily(),
        ),
      );

      final Result<Reminder?> result = await CompleteReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call('reminder-1');

      final Reminder? completed = (result as Success<Reminder?>).value;
      expect(completed?.dueAt, DateTime(2026, 8, 2, 9));
      expect(scheduler.scheduled, hasLength(1));
    });

    test('succeeds quietly when the reminder is already gone', () async {
      final Result<Reminder?> result = await CompleteReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call('missing');

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });
  });

  group('SnoozeReminder', () {
    test('moves the due time and re-schedules', () async {
      await repository.create(buildReminder(dueAt: DateTime(2026, 8, 1, 9)));

      final Result<Reminder?> result = await SnoozeReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call('reminder-1', const Duration(minutes: 15));

      final Reminder? snoozed = (result as Success<Reminder?>).value;
      expect(snoozed?.status, ReminderStatus.snoozed);
      expect(snoozed?.dueAt, DateTime(2026, 8, 1, 10, 15));
      expect(scheduler.scheduled, hasLength(1));
    });
  });

  group('SetReminderEnabled', () {
    test('cancels when disabling and schedules when enabling', () async {
      await repository.create(buildReminder(dueAt: DateTime(2026, 8, 2, 9)));

      final SetReminderEnabled usecase = SetReminderEnabled(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      );

      await usecase.call('reminder-1', enabled: false);
      expect(scheduler.cancelled, contains('reminder-1'));

      await usecase.call('reminder-1', enabled: true);
      expect(scheduler.scheduled, hasLength(1));
    });
  });

  group('DuplicateReminder', () {
    test('creates an independent copy with fresh history', () async {
      await repository.create(
        buildReminder(
          dueAt: DateTime(2026, 8, 2, 9),
          occurrenceCount: 3,
          status: ReminderStatus.completed,
        ),
      );

      final Result<Reminder> result = await DuplicateReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call('reminder-1');

      final Reminder copy = (result as Success<Reminder>).value;
      expect(copy.id, isNot('reminder-1'));
      expect(copy.title, endsWith('(copy)'));
      expect(copy.occurrenceCount, 0);
      expect(copy.status, ReminderStatus.scheduled);
      expect(repository.rows, hasLength(2));
    });

    test('moves a copy of a past reminder into the future', () async {
      await repository.create(buildReminder(dueAt: DateTime(2026, 7, 1, 9)));

      final Result<Reminder> result = await DuplicateReminder(
        repository: repository,
        scheduler: scheduler,
        clock: clock,
      ).call('reminder-1');

      final Reminder copy = (result as Success<Reminder>).value;
      expect(copy.dueAt.isAfter(clock.now()), isTrue);
    });
  });
}
