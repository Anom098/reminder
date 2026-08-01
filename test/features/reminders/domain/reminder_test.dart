import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';

import '../../../helpers/test_doubles.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 1, 9, 30);

  group('Reminder.complete', () {
    test('a one-shot reminder becomes completed', () {
      final Reminder reminder = buildReminder(dueAt: DateTime(2026, 8, 1, 9));

      final Reminder completed = reminder.complete(firedAt: now);

      expect(completed.status, ReminderStatus.completed);
      expect(completed.completedAt, now);
      expect(completed.occurrenceCount, 1);
    });

    test('a repeating reminder rolls forward and stays scheduled', () {
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: const RecurrenceRule.daily(),
      );

      final Reminder completed = reminder.complete(firedAt: now);

      expect(completed.status, ReminderStatus.scheduled);
      expect(completed.dueAt, DateTime(2026, 8, 2, 9));
      expect(completed.occurrenceCount, 1);
      expect(completed.completedAt, isNull);
    });

    test('a repeating reminder that has run out becomes finished', () {
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: const RecurrenceRule.daily(maxOccurrences: 1),
      );

      final Reminder completed = reminder.complete(firedAt: now);

      expect(completed.status, ReminderStatus.finished);
      expect(completed.status.isTerminal, isTrue);
    });

    test('recurrence is computed from the anchor, so it does not drift', () {
      // Completed 3 hours late; the next occurrence must still be 09:00.
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: const RecurrenceRule.daily(),
      );

      final Reminder completed =
          reminder.complete(firedAt: DateTime(2026, 8, 1, 12));

      expect(completed.dueAt, DateTime(2026, 8, 2, 9));
    });
  });

  group('Reminder.snooze', () {
    test('moves the due time and remembers the original', () {
      final Reminder reminder = buildReminder(dueAt: DateTime(2026, 8, 1, 9));

      final Reminder snoozed =
          reminder.snooze(duration: const Duration(minutes: 10), now: now);

      expect(snoozed.status, ReminderStatus.snoozed);
      expect(snoozed.dueAt, DateTime(2026, 8, 1, 9, 40));
      expect(snoozed.snoozedFrom, DateTime(2026, 8, 1, 9));
    });

    test('a second snooze keeps the original due time', () {
      final Reminder reminder = buildReminder(dueAt: DateTime(2026, 8, 1, 9));

      final Reminder twice = reminder
          .snooze(duration: const Duration(minutes: 10), now: now)
          .snooze(
            duration: const Duration(minutes: 10),
            now: DateTime(2026, 8, 1, 9, 40),
          );

      expect(twice.snoozedFrom, DateTime(2026, 8, 1, 9));
    });

    test('clamps an absurd duration rather than trusting the caller', () {
      final Reminder reminder = buildReminder(dueAt: DateTime(2026, 8, 1, 9));

      final Reminder snoozed = reminder.snooze(
        duration: const Duration(days: 400),
        now: now,
      );

      expect(
        snoozed.dueAt.difference(now).inDays,
        lessThanOrEqualTo(7),
        reason: 'a malformed payload must not schedule a reminder years out',
      );
    });
  });

  group('Reminder.setEnabled', () {
    test('disabling keeps the configuration', () {
      final Reminder reminder = buildReminder();

      final Reminder disabled = reminder.setEnabled(enabled: false, now: now);

      expect(disabled.status, ReminderStatus.disabled);
      expect(disabled.dueAt, reminder.dueAt);
      expect(disabled.recurrence, reminder.recurrence);
    });

    test('re-enabling a past repeating reminder moves it forward', () {
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 7, 20, 9),
        anchorAt: DateTime(2026, 7, 20, 9),
        recurrence: const RecurrenceRule.daily(),
        status: ReminderStatus.disabled,
      );

      final Reminder enabled = reminder.setEnabled(enabled: true, now: now);

      expect(enabled.status, ReminderStatus.scheduled);
      expect(enabled.dueAt.isAfter(now), isTrue);
    });

    test('is a no-op when the state already matches', () {
      final Reminder reminder = buildReminder();

      expect(reminder.setEnabled(enabled: true, now: now), same(reminder));
    });
  });

  group('Reminder derived state', () {
    test('isOverdue applies the fire tolerance', () {
      final Reminder reminder = buildReminder(dueAt: DateTime(2026, 8, 1, 9));

      expect(reminder.isOverdue(DateTime(2026, 8, 1, 9, 1)), isFalse);
      expect(reminder.isOverdue(DateTime(2026, 8, 1, 9, 5)), isTrue);
    });

    test('spokenText composes a sentence and honours an override', () {
      expect(
        buildReminder(title: 'Call Mom').spokenText,
        'Reminder. Call Mom.',
      );
      expect(
        buildReminder(title: 'Call Mom')
            .copyWith(spokenTextOverride: 'Time to ring your mother')
            .spokenText,
        'Time to ring your mother',
      );
    });

    test('notificationId is stable and non-negative', () {
      final Reminder a = buildReminder(id: 'abc');
      final Reminder b = buildReminder(id: 'abc', title: 'Different');

      expect(a.notificationId, b.notificationId);
      expect(a.notificationId, greaterThanOrEqualTo(0));
    });
  });

  group('Reminder.validate', () {
    test('rejects an empty title', () {
      expect(buildReminder(title: '   ').validate(), contains('title'));
    });

    test('rejects an end date before the first occurrence', () {
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: RecurrenceRule.daily(until: DateTime(2026, 7, 1)),
      );

      expect(reminder.validate(), contains('recurrence'));
    });

    test('accepts a well-formed reminder', () {
      expect(buildReminder().validate(), isEmpty);
    });
  });

  group('ReminderBucket', () {
    test('classifies by due time relative to now', () {
      expect(
        ReminderBucket.of(
          buildReminder(dueAt: DateTime(2026, 8, 1, 8)),
          now,
        ),
        ReminderBucket.overdue,
      );
      expect(
        ReminderBucket.of(
          buildReminder(dueAt: DateTime(2026, 8, 1, 18)),
          now,
        ),
        ReminderBucket.today,
      );
      expect(
        ReminderBucket.of(
          buildReminder(dueAt: DateTime(2026, 8, 2, 9)),
          now,
        ),
        ReminderBucket.tomorrow,
      );
      expect(
        ReminderBucket.of(
          buildReminder(dueAt: DateTime(2026, 9, 2, 9)),
          now,
        ),
        ReminderBucket.later,
      );
      expect(
        ReminderBucket.of(
          buildReminder(status: ReminderStatus.completed),
          now,
        ),
        ReminderBucket.done,
      );
    });
  });

  group('ReminderFilter', () {
    test('an empty filter matches everything', () {
      expect(ReminderFilter.none.matches(buildReminder()), isTrue);
    });

    test('searches title, notes and category name', () {
      final Reminder reminder = buildReminder(
        title: 'Take tablets',
        notes: 'The blue ones',
        categoryId: 'medicine',
      );

      expect(
        const ReminderFilter(searchTerm: 'blue').matches(reminder),
        isTrue,
      );
      expect(
        const ReminderFilter(searchTerm: 'Medicine').matches(
          reminder,
          categoryNameLookup: (String id) => 'Medicine',
        ),
        isTrue,
      );
      expect(
        const ReminderFilter(searchTerm: 'zebra').matches(reminder),
        isFalse,
      );
    });

    test('excludes disabled reminders when asked', () {
      final Reminder disabled = buildReminder(status: ReminderStatus.disabled);

      expect(ReminderFilter.active.matches(disabled), isFalse);
      expect(ReminderFilter.none.matches(disabled), isTrue);
    });
  });
}
