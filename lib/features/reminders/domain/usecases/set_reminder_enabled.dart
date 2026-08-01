/// Turns a reminder on or off without deleting it.
library;

import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Enables or disables a reminder.
final class SetReminderEnabled {
  /// Creates the use case.
  const SetReminderEnabled({
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
  /// Re-enabling a reminder whose time has passed moves it to its next
  /// occurrence, so flipping the switch never fires an alert immediately. See
  /// [Reminder.setEnabled].
  Future<Result<Reminder>> call(String id, {required bool enabled}) async {
    final Result<Reminder> found = await _repository.getReminder(id);
    if (found case Failure<Reminder>(failure: final AppFailure failure)) {
      return Failure<Reminder>(failure);
    }

    final Reminder reminder = (found as Success<Reminder>).value;
    final Reminder toggled = reminder.setEnabled(
      enabled: enabled,
      now: _clock.now(),
    );
    if (toggled == reminder) {
      return Success<Reminder>(reminder);
    }

    final Result<Reminder> saved = await _repository.update(toggled);
    if (saved case Success<Reminder>(value: final Reminder value)) {
      if (enabled) {
        await _scheduler.schedule(value);
      } else {
        await _scheduler.cancel(value);
      }
    }
    return saved;
  }
}
