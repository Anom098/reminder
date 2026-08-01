/// Translates reminders into OS notification slots.
library;

import 'dart:io';

import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/constants/notification_constants.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/notifications/notification_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Keeps the OS schedule in sync with the reminder database.
///
/// ### Why occurrences are windowed
///
/// iOS allows an app at most 64 pending local notifications, and Android
/// degrades badly past a few hundred alarms. A reminder that repeats every hour
/// forever cannot be handed to the OS in full, so each reminder is materialised
/// as at most [horizonOccurrences] upcoming notifications. A periodic
/// background task re-runs [rescheduleAll] to top the window up long before it
/// drains.
final class NotificationReminderScheduler implements ReminderScheduler {
  /// Creates a scheduler.
  NotificationReminderScheduler({
    required ReminderRepository repository,
    required NotificationService notifications,
    required AppLogger logger,
    required Clock clock,
    int horizonOccurrences = 12,
    Future<void> Function()? registerBackgroundRefresh,
    Future<void> Function()? armSpokenAnnouncement,
  })  : _repository = repository,
        _notifications = notifications,
        _log = logger.forContext('Scheduler'),
        _clock = clock,
        _horizon = horizonOccurrences,
        _registerBackgroundRefresh = registerBackgroundRefresh,
        _armSpokenAnnouncement = armSpokenAnnouncement,
        assert(
          horizonOccurrences > 0 && horizonOccurrences <= _maxSlotsPerReminder,
          'horizonOccurrences must be within 1..$_maxSlotsPerReminder',
        );

  /// Upper bound on notification ids reserved per reminder.
  ///
  /// Ids are allocated as a contiguous block starting at the reminder's own
  /// derived id, so cancellation can clear the whole block without knowing how
  /// many slots were actually used.
  static const int _maxSlotsPerReminder = 64;

  final ReminderRepository _repository;
  final NotificationService _notifications;
  final AppLogger _log;
  final Clock _clock;
  final int _horizon;
  final Future<void> Function()? _registerBackgroundRefresh;

  /// Re-points the alarm that delivers spoken announcements.
  ///
  /// A notification cannot run Dart, so the speech is driven by a separate
  /// exact alarm. That alarm has to be re-armed every time the schedule changes
  /// — otherwise a reminder saved while no alarm is pending shows its
  /// notification and stays silent, with nothing to arm the alarm later.
  final Future<void> Function()? _armSpokenAnnouncement;

  @override
  Future<Result<void>> schedule(Reminder reminder) async {
    // A failed cancel is logged and stepped over rather than returned. Slot ids
    // are derived from the reminder id, so re-scheduling overwrites the same
    // slots anyway; the worst case is a few stale ones beyond the new count.
    // Aborting here instead means the reminder is never scheduled at all, which
    // is how a plugin-level cancel failure once silenced the entire app.
    final Result<void> cleared = await _cancelSlots(reminder.id);
    if (cleared case Failure<void>(failure: final AppFailure f)) {
      _log.warning('Could not clear slots for ${reminder.id}: ${f.message}');
    }

    // Armed on every path below, including the early returns: disabling or
    // completing the current soonest reminder changes which one the speech
    // alarm should point at just as much as adding one does.
    await _armSpokenSweep();

    if (!reminder.isActive) {
      return voidSuccess;
    }

    final List<ScheduledNotification> requests = _buildRequests(reminder);
    if (requests.isEmpty) {
      _log.debug('Reminder ${reminder.id} has no future occurrences.');
      return voidSuccess;
    }

    final Result<List<int>> scheduled =
        await _notifications.scheduleAll(requests);

    return scheduled.fold<Result<void>>(
      (List<int> failedIds) {
        if (failedIds.isEmpty) {
          return voidSuccess;
        }
        // Partial success is still success: the earliest occurrences are what
        // matter, and the background top-up retries the rest.
        _log.warning(
          '${failedIds.length}/${requests.length} occurrences of '
          '${reminder.id} could not be scheduled.',
        );
        return voidSuccess;
      },
      Failure<void>.new,
    );
  }

  @override
  Future<Result<void>> cancel(Reminder reminder) => cancelById(reminder.id);

  @override
  Future<Result<void>> cancelById(String id) async {
    final Result<void> cleared = await _cancelSlots(id);
    await _armSpokenSweep();
    return cleared;
  }

  /// Clears a reminder's notification block without touching the speech alarm.
  ///
  /// Split out so that [schedule] can cancel and re-schedule while arming the
  /// speech alarm exactly once, rather than once per half of the operation.
  Future<Result<void>> _cancelSlots(String id) {
    // The whole reserved block is cancelled, not just the slots believed to be
    // in use: the previous schedule may have used more of them, and cancelling
    // an id that was never scheduled is a no-op on both platforms.
    final int base = _baseIdFor(id);
    return _notifications.cancelMany(
      List<int>.generate(
        _maxSlotsPerReminder,
        (int index) => _slotId(base, index),
        growable: false,
      ),
    );
  }

  @override
  Future<Result<int>> rescheduleAll() async {
    final Result<List<Reminder>> active = await _repository.getActive();
    if (active case Failure<List<Reminder>>(failure: final AppFailure f)) {
      return Failure<int>(f);
    }

    // Cancel everything first rather than diffing. An incremental update can
    // drift out of sync with the OS (a reboot, a restore, a killed process) in
    // ways that are invisible until a reminder fails to fire.
    // As in `schedule`: rebuilding on top of a stale schedule is recoverable,
    // rebuilding nothing is not.
    final Result<void> cleared = await _notifications.cancelAll();
    if (cleared case Failure<void>(failure: final AppFailure f)) {
      _log.warning('Could not clear the existing schedule: ${f.message}');
    }

    final List<Reminder> reminders = (active as Success<List<Reminder>>).value;
    int scheduled = 0;
    for (final Reminder reminder in reminders) {
      final List<ScheduledNotification> requests = _buildRequests(reminder);
      if (requests.isEmpty) {
        continue;
      }
      final Result<List<int>> result =
          await _notifications.scheduleAll(requests);
      scheduled += result.fold(
        (List<int> failed) => requests.length - failed.length,
        (_) => 0,
      );
    }

    await _armSpokenSweep();

    _log.info('Rescheduled $scheduled notifications for '
        '${reminders.length} reminders.');
    return Success<int>(scheduled);
  }

  @override
  Future<Result<int>> reconcileMissed() async {
    final DateTime now = _clock.now();
    final Result<List<Reminder>> active = await _repository.getActive();
    if (active case Failure<List<Reminder>>(failure: final AppFailure f)) {
      return Failure<int>(f);
    }

    final List<Reminder> changed = <Reminder>[];
    for (final Reminder reminder in (active as Success<List<Reminder>>).value) {
      if (!reminder.isOverdue(now)) {
        continue;
      }

      if (reminder.recurrence.isRepeating) {
        // Do not fire a burst of alerts for every occurrence the device slept
        // through; move to the next future one.
        changed.add(reminder.advanceToNextOccurrence(now: now));
        continue;
      }

      final Duration lateBy = now.difference(reminder.dueAt);
      if (lateBy > AppConstants.missedThreshold) {
        changed.add(reminder.markMissed(now: now));
      }
      // Recently overdue one-shot reminders are left alone: they still show as
      // overdue in the UI and the user can act on them.
    }

    if (changed.isEmpty) {
      return const Success<int>(0);
    }

    final Result<void> saved = await _repository.updateAll(changed);
    if (saved case Failure<void>(failure: final AppFailure f)) {
      return Failure<int>(f);
    }

    _log.info('Reconciled ${changed.length} missed reminders.');
    return Success<int>(changed.length);
  }

  @override
  Future<Result<void>> ensureBackgroundRefreshScheduled() async {
    final Future<void> Function()? register = _registerBackgroundRefresh;
    if (register == null) {
      return voidSuccess;
    }
    return Result.guardAsync<void>(register);
  }

  /// Re-points the spoken-announcement alarm, swallowing any failure.
  ///
  /// Deliberately does not surface an error: the announcement is an enhancement
  /// over the notification, and failing a save because the alarm could not be
  /// armed would trade a missing voice for a missing reminder.
  Future<void> _armSpokenSweep() async {
    final Future<void> Function()? arm = _armSpokenAnnouncement;
    if (arm == null) {
      return;
    }
    final Result<void> armed = await Result.guardAsync<void>(arm);
    if (armed case Failure<void>(failure: final AppFailure f)) {
      _log.warning('Could not arm the spoken-announcement alarm: ${f.message}');
    }
  }

  /// Builds the notification requests for [reminder]'s next occurrences.
  List<ScheduledNotification> _buildRequests(Reminder reminder) {
    if (!reminder.isActive) {
      return const <ScheduledNotification>[];
    }

    final DateTime now = _clock.now();
    final int base = _baseIdFor(reminder.id);
    final List<ScheduledNotification> requests = <ScheduledNotification>[];

    for (final DateTime occurrence in _futureOccurrences(reminder, now)) {
      requests.add(
        ScheduledNotification(
          id: _slotId(base, requests.length),
          title: reminder.title,
          body: _bodyFor(reminder),
          scheduledAt: occurrence,
          priority: reminder.priority,
          payload: <String, Object?>{
            NotificationConstants.payloadReminderId: reminder.id,
            NotificationConstants.payloadOccurrenceAt:
                occurrence.millisecondsSinceEpoch,
            NotificationConstants.payloadSpokenText:
                reminder.isSpoken ? reminder.spokenText : null,
            NotificationConstants.payloadIsSnoozed: reminder.isSnoozed,
          },
          // Exact, wake-the-device alarms are the point of a reminder app; the
          // notification service degrades to inexact if the grant is missing.
          allowWhileIdle: true,
        ),
      );
      if (requests.length >= _horizon) {
        break;
      }
    }

    return requests;
  }

  /// The upcoming occurrences of [reminder] that are still in the future.
  ///
  /// A snoozed reminder contributes exactly its snoozed instant: its recurrence
  /// continues from the original anchor once the snooze fires, so expanding the
  /// rule here would double-book the next occurrence.
  Iterable<DateTime> _futureOccurrences(Reminder reminder, DateTime now) sync* {
    if (reminder.isSnoozed) {
      if (reminder.dueAt.isAfter(now)) {
        yield reminder.dueAt;
      }
      return;
    }

    if (!reminder.recurrence.isRepeating) {
      if (reminder.dueAt.isAfter(now)) {
        yield reminder.dueAt;
      }
      return;
    }

    int emitted = 0;
    for (final DateTime occurrence in reminder.recurrence.occurrences(
      anchor: reminder.anchorAt,
      // Ask for more than the horizon because leading occurrences in the past
      // are filtered out below.
      limit: _horizon * 4,
    )) {
      if (!occurrence.isAfter(now)) {
        continue;
      }
      yield occurrence;
      emitted++;
      if (emitted >= _horizon) {
        return;
      }
    }
  }

  String? _bodyFor(Reminder reminder) {
    final String? notes = reminder.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      return notes;
    }
    return reminder.recurrence.isRepeating
        ? reminder.recurrence.describe()
        : null;
  }

  /// Deterministic base notification id for a reminder id.
  ///
  /// Slots are spaced [_maxSlotsPerReminder] apart so that two reminders whose
  /// hashes land close together cannot overlap blocks.
  static int _baseIdFor(String reminderId) =>
      (reminderId.hashCode & 0x7fffffff) ~/
      _maxSlotsPerReminder *
      _maxSlotsPerReminder;

  static int _slotId(int base, int index) => (base + index) & 0x7fffffff;

  /// Whether this platform supports registering periodic background work.
  ///
  /// iOS background execution is opportunistic and cannot be relied on, which
  /// is why the horizon is sized to survive without it.
  static bool get supportsPeriodicBackgroundWork => Platform.isAndroid;
}
