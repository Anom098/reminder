/// Handles notification button presses that arrive while the app is not in the
/// foreground.
///
/// This code runs in a **separate isolate** with no access to the app's
/// provider graph, widget tree or in-memory state. It therefore builds the
/// minimum it needs — a database connection and a scheduler — does its work,
/// and tears everything down again.
///
/// The entry point must stay top-level and annotated with
/// `@pragma('vm:entry-point')`, otherwise tree shaking removes it from release
/// builds and every background action silently does nothing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/constants/notification_constants.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/logging/console_logger.dart';
import 'package:voice_reminder/core/services/notifications/local_notification_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_reminder_repository.dart';
import 'package:voice_reminder/features/reminders/data/services/notification_reminder_scheduler.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/complete_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/snooze_reminder.dart';

/// Entry point invoked by `flutter_local_notifications` in the background
/// isolate.
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Fire-and-forget: the plugin's callback signature is synchronous, but the
  // isolate stays alive long enough for a short database write.
  unawaited(
    handleNotificationActionInBackground(
      actionId: response.actionId,
      payload: response.payload,
    ),
  );
}

/// Applies a notification action without any UI.
///
/// Exposed separately from the plugin callback so it can be unit-tested and
/// re-used by the foreground handler.
Future<void> handleNotificationActionInBackground({
  required String? actionId,
  required String? payload,
}) async {
  // Required before any plugin can be used from a background isolate.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final AppLogger log =
      ConsoleLogger(level: LogLevel.warning).forContext('BackgroundAction');

  final Map<String, Object?> data = decodeNotificationPayload(payload);
  final String? reminderId =
      data[NotificationConstants.payloadReminderId] as String?;

  if (reminderId == null) {
    log.warning('Background action $actionId had no reminder id; ignoring.');
    return;
  }
  if (actionId == NotificationConstants.actionDismiss) {
    // Dismissing is purely a UI gesture: the reminder keeps its schedule so
    // that a repeating reminder still fires next time.
    return;
  }

  final AppDatabase database = AppDatabase();
  try {
    final LocalNotificationService notifications =
        LocalNotificationService(logger: log);
    await notifications.initialize();

    final ReminderRepository repository = DriftReminderRepository(
      database: database,
      logger: log,
    );
    final NotificationReminderScheduler scheduler =
        NotificationReminderScheduler(
      repository: repository,
      notifications: notifications,
      logger: log,
      clock: const SystemClock(),
      horizonOccurrences: 4,
    );

    switch (actionId) {
      case NotificationConstants.actionComplete:
        await CompleteReminder(
          repository: repository,
          scheduler: scheduler,
          clock: const SystemClock(),
        ).call(reminderId);

      case NotificationConstants.actionSnooze:
        await SnoozeReminder(
          repository: repository,
          scheduler: scheduler,
          clock: const SystemClock(),
        ).call(reminderId, await _defaultSnooze());

      default:
        // A body tap with no action id: the app is being brought to the
        // foreground and the main isolate handles routing.
        return;
    }
  } on Object catch (error, stackTrace) {
    log.error(
      'Background action $actionId failed',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    // The isolate is about to be torn down; leaving the connection open leaks
    // a file handle and can leave the WAL un-checkpointed.
    await database.close();
  }
}

/// Reads the user's configured snooze duration from shared preferences.
///
/// Read directly rather than through the settings repository because this
/// isolate has no provider graph to resolve one from.
Future<Duration> _defaultSnooze() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? minutes = prefs.getInt(StorageKeys.defaultSnoozeMinutes);
    if (minutes != null && minutes > 0) {
      return Duration(minutes: minutes);
    }
  } on Object {
    // Fall through to the default below.
  }
  return const Duration(minutes: 10);
}

/// Encodes a notification payload map into the opaque string the OS carries.
///
/// Kept beside `decodeNotificationPayload` so the two cannot drift apart.
String encodeNotificationPayload(Map<String, Object?> payload) =>
    jsonEncode(payload);
