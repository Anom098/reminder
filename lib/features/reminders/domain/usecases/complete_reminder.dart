/// Marks a reminder acknowledged.
library;

import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Completes a reminder, rolling repeating ones forward.
///
/// Reachable from the notification action handler in a background isolate, so
/// it must not touch the widget tree or any UI-scoped provider.
final class CompleteReminder {
  /// Creates the use case.
  const CompleteReminder({
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
  /// A reminder that no longer exists completes successfully rather than
  /// failing: the user tapped "Done" on a notification for something they had
  /// already deleted, and there is nothing to report.
  Future<Result<Reminder?>> call(String id) async {
    final Result<Reminder> found = await _repository.getReminder(id);

    switch (found) {
      case Failure<Reminder>(failure: final NotFoundFailure _):
        return const Success<Reminder?>(null);
      case Failure<Reminder>(failure: final AppFailure failure):
        return Failure<Reminder?>(failure);
      case Success<Reminder>(value: final Reminder reminder):
        final Reminder completed = reminder.complete(firedAt: _clock.now());
        final Result<Reminder> saved = await _repository.update(completed);

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
