/// OS notification contract.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';

/// A notification the app asks the OS to deliver at a future instant.
final class ScheduledNotification extends Equatable {
  /// Creates a scheduled notification request.
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.scheduledAt,
    required this.payload,
    this.body,
    this.priority = ReminderPriority.normal,
    this.withActions = true,
    this.allowWhileIdle = true,
  });

  /// Platform notification id. Must be stable for cancellation to work.
  final int id;

  /// Notification title, shown in bold.
  final String title;

  /// Secondary line.
  final String? body;

  /// When the notification should be delivered, in device-local time.
  final DateTime scheduledAt;

  /// Data handed back when the user interacts with the notification.
  ///
  /// Encoded as a JSON string by the implementation, because both platforms
  /// only carry an opaque string across the process boundary.
  final Map<String, Object?> payload;

  /// Drives channel importance and Do Not Disturb bypass.
  final ReminderPriority priority;

  /// Whether Complete / Snooze / Dismiss buttons are attached.
  final bool withActions;

  /// Whether to fire during Doze on Android.
  ///
  /// Requires the exact-alarm capability; the implementation degrades to an
  /// inexact alarm when it is unavailable rather than failing to schedule.
  final bool allowWhileIdle;

  @override
  List<Object?> get props => <Object?>[id, title, body, scheduledAt, priority];
}

/// A user interaction with a delivered notification.
final class NotificationAction extends Equatable {
  /// Creates an action event.
  const NotificationAction({
    required this.notificationId,
    required this.payload,
    this.actionId,
  });

  /// Id of the notification that was acted on.
  final int notificationId;

  /// The payload originally supplied in [ScheduledNotification.payload].
  final Map<String, Object?> payload;

  /// Which button was pressed, or `null` when the body itself was tapped.
  final String? actionId;

  /// The reminder this action refers to, if the payload carries one.
  String? get reminderId => payload['reminderId'] as String?;

  @override
  List<Object?> get props => <Object?>[notificationId, actionId, payload];
}

/// Posts, schedules and cancels OS notifications.
abstract interface class NotificationService {
  /// Emits every user interaction with a reminder notification.
  ///
  /// Includes the interaction that launched the app from a cold start, which is
  /// replayed to the first subscriber so it is not lost while the app boots.
  Stream<NotificationAction> get actions;

  /// Creates channels, wires callbacks and configures time zones.
  Future<Result<void>> initialize();

  /// Requests notification permission, returning whether it was granted.
  Future<Result<bool>> requestPermission();

  /// Whether the app may currently post notifications.
  Future<Result<bool>> hasPermission();

  /// Whether the OS will honour exact alarm timing.
  ///
  /// Always true on iOS; on Android 12+ it reflects the exact-alarm grant.
  Future<Result<bool>> canScheduleExactAlarms();

  /// Schedules [notification].
  ///
  /// A request whose [ScheduledNotification.scheduledAt] is in the past is
  /// rejected with a `SchedulingFailure` rather than delivered immediately —
  /// firing a stale reminder is more confusing than dropping it.
  Future<Result<void>> schedule(ScheduledNotification notification);

  /// Schedules several notifications, continuing past individual failures.
  ///
  /// Returns the ids that could not be scheduled, so the caller can retry or
  /// report a partial result. Repeating reminders occupy many slots and one bad
  /// occurrence must not abort the rest.
  Future<Result<List<int>>> scheduleAll(
    List<ScheduledNotification> notifications,
  );

  /// Displays a notification immediately.
  Future<Result<void>> showNow(ScheduledNotification notification);

  /// Cancels the notification with [id].
  Future<Result<void>> cancel(int id);

  /// Cancels several notifications.
  Future<Result<void>> cancelMany(Iterable<int> ids);

  /// Cancels every pending notification.
  Future<Result<void>> cancelAll();

  /// Ids of notifications the OS has accepted but not yet delivered.
  Future<Result<List<int>>> pendingIds();

  /// The action that launched the app, when it was started from a
  /// notification.
  Future<Result<NotificationAction?>> launchAction();
}
