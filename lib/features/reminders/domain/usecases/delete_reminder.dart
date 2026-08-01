/// Deletes a reminder and releases its OS notification slots.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Removes a reminder permanently.
final class DeleteReminder {
  /// Creates the use case.
  const DeleteReminder({
    required ReminderRepository repository,
    required ReminderScheduler scheduler,
  })  : _repository = repository,
        _scheduler = scheduler;

  final ReminderRepository _repository;
  final ReminderScheduler _scheduler;

  /// Runs the use case.
  ///
  /// Notifications are cancelled *before* the row is removed. If cancellation
  /// failed after deletion, the app would have no way to find the orphaned
  /// notification id again and the user would be alerted about a reminder that
  /// no longer exists.
  Future<Result<void>> call(String id) async {
    final Result<void> cancelled = await _scheduler.cancelById(id);
    if (cancelled.isFailure) {
      return cancelled;
    }
    return _repository.delete(id);
  }
}
