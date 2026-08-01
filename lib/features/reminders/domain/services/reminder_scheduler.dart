/// Scheduling contract.
///
/// Sits between the reminder repository and the OS notification layer. It owns
/// the translation from "a reminder with a recurrence rule" into "a bounded set
/// of pending OS notifications", including the windowing that keeps the app
/// under iOS's 64-notification limit.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';

/// Places reminders on, and removes them from, the OS schedule.
abstract interface class ReminderScheduler {
  /// Schedules the next occurrences of [reminder].
  ///
  /// Cancels any notifications already registered for it first, so the method
  /// is safe to call after every edit. A disabled or terminal reminder is
  /// cancelled and not re-scheduled.
  Future<Result<void>> schedule(Reminder reminder);

  /// Removes every pending notification belonging to [reminder].
  Future<Result<void>> cancel(Reminder reminder);

  /// Removes every pending notification belonging to the reminder with [id].
  ///
  /// Used after deletion, when the entity is no longer available to pass.
  Future<Result<void>> cancelById(String id);

  /// Rebuilds the entire OS schedule from the database.
  ///
  /// Run after boot, after a restore, after a time-zone change and whenever the
  /// background top-up task fires. Idempotent by design: it cancels everything
  /// and re-derives, rather than attempting an incremental diff that could
  /// silently drift out of sync with the OS.
  Future<Result<int>> rescheduleAll();

  /// Moves reminders whose time passed while the device was asleep.
  ///
  /// Repeating reminders roll forward to their next future occurrence; one-shot
  /// reminders older than the missed threshold are marked missed. Returns how
  /// many reminders changed.
  Future<Result<int>> reconcileMissed();

  /// Ensures the periodic background top-up task is registered.
  Future<Result<void>> ensureBackgroundRefreshScheduled();
}
