/// Persistence contract for reminders.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';

/// Stores and retrieves [Reminder]s.
///
/// Implementations never throw: every method returns a [Result]. Streams are
/// the primary read path so that the UI stays in sync when a reminder is
/// completed from a notification while a list is on screen.
abstract interface class ReminderRepository {
  /// Emits the reminders matching [filter], ordered by [sort].
  ///
  /// The stream emits immediately with the current contents and again on every
  /// relevant write. It does not close until the subscription is cancelled.
  Stream<List<Reminder>> watchReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  });

  /// Emits the reminder with [id], or `null` once it is deleted.
  Stream<Reminder?> watchReminder(String id);

  /// One-shot read of the reminders matching [filter].
  Future<Result<List<Reminder>>> getReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  });

  /// Reads a single reminder.
  ///
  /// Fails with `NotFoundFailure` when no such reminder exists.
  Future<Result<Reminder>> getReminder(String id);

  /// Reads every reminder that is scheduled or snoozed and due at or before
  /// [horizon].
  ///
  /// Used by the scheduler to decide which reminders need OS notification
  /// slots.
  Future<Result<List<Reminder>>> getDueBefore(DateTime horizon);

  /// Reads every active reminder, regardless of due date.
  ///
  /// Used by the post-boot rescheduling pass.
  Future<Result<List<Reminder>>> getActive();

  /// Inserts a new reminder.
  Future<Result<Reminder>> create(Reminder reminder);

  /// Replaces an existing reminder.
  Future<Result<Reminder>> update(Reminder reminder);

  /// Applies [reminders] in a single transaction.
  ///
  /// Used by catch-up and restore, where dozens of rows change at once and a
  /// partial write would leave the schedule inconsistent.
  Future<Result<void>> updateAll(List<Reminder> reminders);

  /// Deletes the reminder with [id].
  ///
  /// Succeeds even when the row is already gone: deletion is idempotent so that
  /// a duplicate notification action cannot fail.
  Future<Result<void>> delete(String id);

  /// Deletes every reminder matching [filter] and returns how many were
  /// removed.
  Future<Result<int>> deleteWhere(ReminderFilter filter);

  /// Removes every reminder. Used by "restore from backup" before importing.
  Future<Result<void>> deleteAll();

  /// Counts the reminders matching [filter].
  Future<Result<int>> count({ReminderFilter filter = ReminderFilter.none});
}
