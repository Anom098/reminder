/// Saves edits to an existing reminder and re-schedules it.
library;

import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Validates and persists an edited reminder.
final class UpdateReminder {
  /// Creates the use case.
  const UpdateReminder({
    required ReminderRepository repository,
    required ReminderScheduler scheduler,
    required Clock clock,
  })  : _repository = repository,
        _scheduler = scheduler,
        _clock = clock;

  final ReminderRepository _repository;
  final ReminderScheduler _scheduler;
  final Clock _clock;

  /// Runs the use case.
  ///
  /// When the due time moves, [Reminder.anchorAt] moves with it and the
  /// occurrence counter resets: editing "every day at 9" to "every day at 10"
  /// must produce a schedule anchored at 10, not one that still remembers 9.
  Future<Result<Reminder>> call(Reminder reminder) async {
    final Map<String, String> errors = reminder.validate();
    if (errors.isNotEmpty) {
      return Failure<Reminder>(
        ValidationFailure(message: errors.values.first, fieldErrors: errors),
      );
    }

    final DateTime now = _clock.now();
    final Result<Reminder> existing = await _repository.getReminder(
      reminder.id,
    );
    if (existing case Failure<Reminder>(failure: final AppFailure failure)) {
      return Failure<Reminder>(failure);
    }

    final Reminder previous = (existing as Success<Reminder>).value;
    final bool timingChanged = previous.dueAt != reminder.dueAt ||
        previous.recurrence != reminder.recurrence;

    final Reminder updated = timingChanged
        ? reminder.copyWith(
            anchorAt: reminder.dueAt,
            occurrenceCount: 0,
            updatedAt: now,
            clearSnoozedFrom: true,
            status: reminder.status == ReminderStatus.disabled
                ? ReminderStatus.disabled
                : ReminderStatus.scheduled,
          )
        : reminder.copyWith(updatedAt: now);

    final Result<Reminder> saved = await _repository.update(updated);
    if (saved case Success<Reminder>(value: final Reminder value)) {
      await _scheduler.schedule(value);
    }
    return saved;
  }
}
