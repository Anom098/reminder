/// Application-wide constants that are not user-configurable.
///
/// Anything a user or a build flavour can change belongs in `AppConfig` or the
/// settings store instead.
library;

/// Non-configurable application constants.
abstract final class AppConstants {
  /// Filename of the on-device Drift database.
  static const String databaseFileName = 'voice_reminder.sqlite';

  /// Current Drift schema version. Bump alongside a migration step.
  static const int databaseSchemaVersion = 1;

  /// Version stamped into exported backup files.
  ///
  /// Import refuses payloads newer than this, because a future version may
  /// contain fields this build would silently drop.
  static const int backupFormatVersion = 1;

  /// Prefix for exported backup filenames.
  static const String backupFilePrefix = 'voice_reminder_backup';

  /// Maximum length of a reminder title.
  static const int maxTitleLength = 120;

  /// Maximum length of the free-form notes field.
  static const int maxNotesLength = 2000;

  /// Maximum length of a user-defined category name.
  static const int maxCategoryNameLength = 40;

  /// Page size used by the paginated reminder list.
  static const int reminderPageSize = 40;

  /// Debounce applied to the search field before querying the database.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Grace period after a reminder's due time during which firing it is still
  /// considered on-time rather than missed.
  ///
  /// Absorbs OS scheduling jitter and doze-mode wake-up delay.
  static const Duration reminderFireTolerance = Duration(minutes: 2);

  /// How long a reminder may remain unacknowledged before it is marked missed.
  static const Duration missedThreshold = Duration(hours: 12);

  /// Snooze durations offered in the notification and the UI.
  static const List<Duration> snoozePresets = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  /// Bounds accepted for a custom snooze duration.
  static const Duration minSnooze = Duration(minutes: 1);

  /// Upper bound for a custom snooze duration.
  static const Duration maxSnooze = Duration(days: 7);

  /// How far ahead the "upcoming" bucket on the home screen looks.
  static const Duration upcomingWindow = Duration(days: 7);
}

/// Keys used with `SharedPreferences` and the secure storage wrapper.
///
/// Centralised so that a typo cannot silently create a second, empty setting.
abstract final class StorageKeys {
  /// Selected theme mode (`system` / `light` / `dark`).
  static const String themeMode = 'settings.theme_mode';

  /// Selected seed colour index for the Material 3 palette.
  static const String themeSeed = 'settings.theme_seed';

  /// Whether high-contrast mode is forced on.
  static const String highContrast = 'settings.high_contrast';

  /// User text-scale override, or absent to follow the system.
  static const String textScale = 'settings.text_scale';

  /// BCP-47 language tag for spoken reminders.
  static const String ttsLanguage = 'settings.tts_language';

  /// Identifier of the selected TTS voice.
  static const String ttsVoiceName = 'settings.tts_voice_name';

  /// Locale of the selected TTS voice.
  static const String ttsVoiceLocale = 'settings.tts_voice_locale';

  /// Speech rate override.
  static const String ttsRate = 'settings.tts_rate';

  /// Pitch override.
  static const String ttsPitch = 'settings.tts_pitch';

  /// Volume override.
  static const String ttsVolume = 'settings.tts_volume';

  /// Whether reminders are spoken aloud at all.
  static const String speakReminders = 'settings.speak_reminders';

  /// How many times each spoken reminder is repeated.
  ///
  /// Read directly by the background isolate, which has no access to the
  /// settings repository — the key lives here so the two readers cannot drift.
  static const String speakRepeatCount = 'settings.speak_repeat_count';

  /// Seconds between repeats of a spoken reminder.
  ///
  /// Read directly by the background isolate and by the iOS locked-screen
  /// sound baker, neither of which has access to the settings repository —
  /// the key lives here so all readers cannot drift.
  static const String speakRepeatIntervalSeconds =
      'settings.speak_repeat_interval_seconds';

  /// Whether reminders are spoken when the device is in silent mode.
  static const String speakInSilentMode = 'settings.speak_in_silent_mode';

  /// Whether notifications vibrate.
  static const String notificationVibration = 'settings.notification_vibration';

  /// Default snooze duration in minutes.
  static const String defaultSnoozeMinutes = 'settings.default_snooze_minutes';

  /// Locale used by the speech recogniser.
  static const String speechLocale = 'settings.speech_locale';

  /// Whether the first-run onboarding has been completed.
  static const String onboardingComplete = 'settings.onboarding_complete';

  /// Timestamp of the most recent successful backup.
  static const String lastBackupAt = 'settings.last_backup_at';

  /// Whether the user has been told about battery optimisation.
  static const String batteryOptimisationPrompted =
      'settings.battery_optimisation_prompted';
}
