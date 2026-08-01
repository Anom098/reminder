/// The application's dependency graph.
///
/// Providers are declared top-down: infrastructure first, then repositories,
/// then services, then use cases. Nothing below the presentation layer knows
/// Riverpod exists — providers only *construct* plain objects, so every class
/// here is equally usable from a background isolate or a unit test.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/services/background/background_tasks.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/notifications/local_notification_service.dart';
import 'package:voice_reminder/core/services/notifications/notification_service.dart';
import 'package:voice_reminder/core/services/permissions/permission_handler_service.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/services/speech/platform_speech_recognition_service.dart';
import 'package:voice_reminder/core/services/speech/speech_recognition_service.dart';
import 'package:voice_reminder/core/services/tts/flutter_tts_service.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_category_repository.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_reminder_repository.dart';
import 'package:voice_reminder/features/reminders/data/services/notification_reminder_scheduler.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/category_repository.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/complete_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/create_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/delete_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/duplicate_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/set_reminder_enabled.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/snooze_reminder.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/update_reminder.dart';
import 'package:voice_reminder/features/settings/data/repositories/preferences_settings_repository.dart';
import 'package:voice_reminder/features/settings/data/services/file_backup_service.dart';
import 'package:voice_reminder/features/settings/domain/repositories/settings_repository.dart';
import 'package:voice_reminder/features/settings/domain/services/backup_service.dart';
import 'package:voice_reminder/features/voice/data/parsers/composite_voice_command_parser.dart';
import 'package:voice_reminder/features/voice/data/parsers/rule_based_voice_command_parser.dart';
import 'package:voice_reminder/features/voice/domain/services/voice_command_parser.dart';

// -- infrastructure ---------------------------------------------------------

/// The Drift database. Closed when the provider container is disposed.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (Ref ref) {
    final AppDatabase database = AppDatabase();
    ref.onDispose(database.close);
    return database;
  },
  name: 'appDatabase',
);

// -- repositories -----------------------------------------------------------

/// Reminder persistence.
final Provider<ReminderRepository> reminderRepositoryProvider =
    Provider<ReminderRepository>(
  (Ref ref) => DriftReminderRepository(
    database: ref.watch(appDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
  name: 'reminderRepository',
);

/// Category persistence.
final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
  (Ref ref) => DriftCategoryRepository(
    database: ref.watch(appDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  ),
  name: 'categoryRepository',
);

/// Settings persistence.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) {
    final PreferencesSettingsRepository repository =
        PreferencesSettingsRepository(
      preferences: ref.watch(sharedPreferencesProvider),
      logger: ref.watch(appLoggerProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  },
  name: 'settingsRepository',
);

// -- platform services ------------------------------------------------------

/// OS notifications.
final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>(
  (Ref ref) {
    final LocalNotificationService service =
        LocalNotificationService(logger: ref.watch(appLoggerProvider));
    ref.onDispose(service.dispose);
    return service;
  },
  name: 'notificationService',
);

/// Speech synthesis.
final Provider<TextToSpeechService> textToSpeechServiceProvider =
    Provider<TextToSpeechService>(
  (Ref ref) {
    final FlutterTtsService service =
        FlutterTtsService(logger: ref.watch(appLoggerProvider));
    ref.onDispose(service.dispose);
    return service;
  },
  name: 'textToSpeechService',
);

/// Speech recognition.
final Provider<SpeechRecognitionService> speechRecognitionServiceProvider =
    Provider<SpeechRecognitionService>(
  (Ref ref) {
    final PlatformSpeechRecognitionService service =
        PlatformSpeechRecognitionService(
      config: ref.watch(appConfigProvider),
      logger: ref.watch(appLoggerProvider),
    );
    ref.onDispose(service.dispose);
    return service;
  },
  name: 'speechRecognitionService',
);

/// Runtime permissions.
final Provider<PermissionService> permissionServiceProvider =
    Provider<PermissionService>(
  (Ref ref) => PermissionHandlerService(logger: ref.watch(appLoggerProvider)),
  name: 'permissionService',
);

/// Reminder scheduling.
final Provider<ReminderScheduler> reminderSchedulerProvider =
    Provider<ReminderScheduler>(
  (Ref ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    final ReminderRepository reminders = ref.watch(reminderRepositoryProvider);
    return NotificationReminderScheduler(
      repository: reminders,
      notifications: ref.watch(notificationServiceProvider),
      logger: ref.watch(appLoggerProvider),
      clock: ref.watch(clockProvider),
      horizonOccurrences: config.schedulingHorizonOccurrences,
      registerBackgroundRefresh: () => registerBackgroundRefresh(
        frequency: config.schedulingRefreshInterval,
      ),
      // Without this the speech alarm is only ever armed from inside the
      // background isolates, so a reminder created in the foreground would
      // never be announced.
      armSpokenAnnouncement: () => scheduleNextSpeakSweep(reminders),
    );
  },
  name: 'reminderScheduler',
);

/// Backup, restore, export and import.
final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (Ref ref) => FileBackupService(
    reminders: ref.watch(reminderRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    logger: ref.watch(appLoggerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'backupService',
);

/// Natural-language command parsing.
final Provider<VoiceCommandParser> voiceCommandParserProvider =
    Provider<VoiceCommandParser>(
  (Ref ref) => CompositeVoiceCommandParser.fromConfig(
    config: ref.watch(appConfigProvider),
    ruleBased: const RuleBasedVoiceCommandParser(),
    logger: ref.watch(appLoggerProvider),
  ),
  name: 'voiceCommandParser',
);

// -- use cases --------------------------------------------------------------

/// Creates a reminder.
final Provider<CreateReminder> createReminderProvider =
    Provider<CreateReminder>(
  (Ref ref) => CreateReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'createReminder',
);

/// Saves edits to a reminder.
final Provider<UpdateReminder> updateReminderProvider =
    Provider<UpdateReminder>(
  (Ref ref) => UpdateReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'updateReminder',
);

/// Deletes a reminder.
final Provider<DeleteReminder> deleteReminderProvider =
    Provider<DeleteReminder>(
  (Ref ref) => DeleteReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
  ),
  name: 'deleteReminder',
);

/// Copies a reminder.
final Provider<DuplicateReminder> duplicateReminderProvider =
    Provider<DuplicateReminder>(
  (Ref ref) => DuplicateReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'duplicateReminder',
);

/// Marks a reminder complete.
final Provider<CompleteReminder> completeReminderProvider =
    Provider<CompleteReminder>(
  (Ref ref) => CompleteReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'completeReminder',
);

/// Snoozes a reminder.
final Provider<SnoozeReminder> snoozeReminderProvider =
    Provider<SnoozeReminder>(
  (Ref ref) => SnoozeReminder(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'snoozeReminder',
);

/// Enables or disables a reminder.
final Provider<SetReminderEnabled> setReminderEnabledProvider =
    Provider<SetReminderEnabled>(
  (Ref ref) => SetReminderEnabled(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'setReminderEnabled',
);

/// A logger tagged for presentation-layer use.
final Provider<AppLogger> uiLoggerProvider = Provider<AppLogger>(
  (Ref ref) => ref.watch(appLoggerProvider).forContext('UI'),
  name: 'uiLogger',
);

/// The clock, re-exported for widgets that need "now" without importing core.
final Provider<Clock> uiClockProvider = Provider<Clock>(
  (Ref ref) => ref.watch(clockProvider),
  name: 'uiClock',
);
