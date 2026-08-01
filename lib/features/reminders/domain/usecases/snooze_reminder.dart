/// Pushes a reminder back by a chosen duration.
library;

import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Snoozes a reminder.
///
/// Like [CompleteReminder][], this runs from the notification background
/// isolate as well as from the UI.
///
/// [CompleteReminder]: package:voice_reminder/features/reminders/domain/usecases/complete_reminder.dart
final class SnoozeReminder {
  /// Creates the use case.
  const SnoozeReminder({
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
  /// The duration is clamped by [Reminder.snooze] to the supported range, so a
  /// malformed notification payload cannot schedule a reminder years out.
  Future<Result<Reminder?>> call(String id, Duration duration) async {
    final Result<Reminder> found = await _repository.getReminder(id);

    switch (found) {
      case Failure<Reminder>(failure: final NotFoundFailure _):
        return const Success<Reminder?>(null);
      case Failure<Reminder>(failure: final AppFailure failure):
        return Failure<Reminder?>(failure);
      case Success<Reminder>(value: final Reminder reminder):
        final Reminder snoozed = reminder.snooze(
          duration: duration,
          now: _clock.now(),
        );
        final Result<Reminder> saved = await _repository.update(snoozed);

        switch (saved) {
          case Failure<Reminder>(failure: final AppFailure failure):
            return Failure<Reminder?>(failure);
          case Success<Reminder>(value: final Reminder value):
            await _scheduler.schedule(value);
            return Success<Reminder?>(value);
        }
    }
  }
}
