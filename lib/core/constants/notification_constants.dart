/// Identifiers shared between the app isolate and the notification background
/// isolate.
///
/// These strings cross an isolate boundary and are persisted by the OS inside
/// pending notifications. Changing a value silently orphans every notification
/// already scheduled on a user's device, so treat them as a wire format: add
/// new values, never repurpose old ones.
library;

/// Android notification channel definitions and action identifiers.
abstract final class NotificationConstants {
  /// Channel for reminders that are due now. High importance, heads-up.
  static const String reminderChannelId = 'voice_reminder.reminders.v1';

  /// User-visible name of the reminder channel.
  static const String reminderChannelName = 'Reminders';

  /// User-visible description of the reminder channel.
  static const String reminderChannelDescription =
      'Alerts for reminders that are due, announced aloud when enabled.';

  /// Channel for silent status notifications (backup complete, and similar).
  static const String statusChannelId = 'voice_reminder.status.v1';

  /// User-visible name of the status channel.
  static const String statusChannelName = 'Status';

  /// User-visible description of the status channel.
  static const String statusChannelDescription =
      'Quiet confirmations such as completed backups.';

  /// Action group identifier used by iOS to attach buttons to a notification.
  static const String iosReminderCategoryId = 'VOICE_REMINDER_DUE';

  /// Action id: mark the reminder complete.
  static const String actionComplete = 'action.complete';

  /// Action id: snooze by the user's default duration.
  static const String actionSnooze = 'action.snooze';

  /// Action id: dismiss without completing.
  static const String actionDismiss = 'action.dismiss';

  /// Payload key holding the reminder identifier.
  static const String payloadReminderId = 'reminderId';

  /// Payload key holding the scheduled occurrence timestamp.
  static const String payloadOccurrenceAt = 'occurrenceAt';

  /// Payload key holding the text to speak.
  static const String payloadSpokenText = 'spokenText';

  /// Payload key marking a notification produced by a snooze.
  static const String payloadIsSnoozed = 'isSnoozed';

  /// Drawable resource used as the small icon on Android.
  ///
  /// `@mipmap/ic_launcher` is used rather than a dedicated silhouette so that
  /// the project has no binary assets to check in; ship a proper monochrome
  /// `@drawable/ic_notification` before release.
  static const String androidSmallIcon = '@mipmap/ic_launcher';

  /// Unique name of the periodic WorkManager job that tops up the schedule.
  static const String scheduleRefreshTaskName =
      'voice_reminder.schedule_refresh';

  /// Unique name of the one-shot WorkManager job that reschedules after boot.
  static const String bootRescheduleTaskName = 'voice_reminder.boot_reschedule';
}
