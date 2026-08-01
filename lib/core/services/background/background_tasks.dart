/// Background execution entry points.
///
/// Everything in this file runs in an isolate with no widget tree and no
/// provider graph. Each entry point builds what it needs, does one job, and
/// tears down.
///
/// Two distinct mechanisms are used, for two distinct jobs:
///
/// * **`android_alarm_manager_plus`** delivers the *spoken* announcement. A
///   notification alone cannot run Dart, so an exact alarm is registered
///   alongside each occurrence; its callback wakes the device and speaks.
/// * **`workmanager`** performs the periodic *top-up*, re-expanding repeating
///   reminders into fresh OS notification slots long before the window drains.
///
/// iOS has no equivalent of either. There, the notification itself alerts the
/// user, and the announcement is spoken when the app next comes to the
/// foreground. This asymmetry is deliberate and documented rather than hidden
/// behind a lowest-common-denominator abstraction.
library;

import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/constants/notification_constants.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/logging/console_logger.dart';
import 'package:voice_reminder/core/services/notifications/local_notification_service.dart';
import 'package:voice_reminder/core/services/tts/flutter_tts_service.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_reminder_repository.dart';
import 'package:voice_reminder/features/reminders/data/services/notification_reminder_scheduler.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:workmanager/workmanager.dart';

/// Alarm id used for the recurring "speak what is due now" sweep.
///
/// A single rolling alarm rather than one per reminder: Android caps the number
/// of exact alarms an app may hold, and a sweep is resilient to the schedule
/// changing between registration and firing.
const int kSpeakSweepAlarmId = 90_001;

/// Registers the periodic schedule top-up task.
///
/// A no-op on iOS, where periodic background execution is not guaranteed.
Future<void> registerBackgroundRefresh({
  Duration frequency = const Duration(hours: 6),
}) async {
  if (!Platform.isAndroid) {
    return;
  }
  await Workmanager().registerPeriodicTask(
    NotificationConstants.scheduleRefreshTaskName,
    NotificationConstants.scheduleRefreshTaskName,
    frequency: frequency,
    // `keep` rather than `replace`: re-registering on every launch must not
    // reset the periodic schedule, or the top-up would never actually run on a
    // device the user opens often.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
    backoffPolicy: BackoffPolicy.linear,
    initialDelay: const Duration(minutes: 15),
  );
}

/// Initialises the background execution plugins.
///
/// Called once during app start-up, before any scheduling happens.
///
/// Returns whether the alarm subsystem — the half that speaks reminders aloud —
/// came up. `AndroidAlarmManager.initialize` reports failure by returning
/// `false` rather than throwing, which happens when the plugin's callback
/// dispatcher cannot be resolved to a handle. Discarding that value makes a
/// dead speech subsystem indistinguishable from a healthy one: alarms still
/// register, they simply never reach Dart.
Future<bool> initializeBackgroundExecution({AppLogger? logger}) async {
  if (!Platform.isAndroid) {
    return false;
  }
  final AppLogger log = (logger ?? ConsoleLogger()).forContext('Background');

  await Workmanager().initialize(workManagerDispatcher);

  final bool alarmsReady = await AndroidAlarmManager.initialize();
  if (!alarmsReady) {
    log.error(
      'AndroidAlarmManager.initialize() returned false: the background isolate '
      'that speaks reminders will never start. Notifications are unaffected.',
    );
  } else {
    log.info('Alarm subsystem initialised.');
  }
  return alarmsReady;
}

/// Schedules the next spoken-announcement sweep at [at].
///
/// Registering the same [kSpeakSweepAlarmId] replaces any previous alarm, so
/// the sweep always points at the soonest upcoming reminder.
Future<void> scheduleSpeakSweep(DateTime at) async {
  if (!Platform.isAndroid) {
    return;
  }
  await AndroidAlarmManager.oneShotAt(
    at,
    kSpeakSweepAlarmId,
    speakDueRemindersCallback,
    exact: true,
    wakeup: true,
    alarmClock: true,
    rescheduleOnReboot: true,
  );
}

/// WorkManager entry point.
@pragma('vm:entry-point')
void workManagerDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final AppLogger log =
        ConsoleLogger(level: LogLevel.info).forContext('BackgroundTask');

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
      );

      await scheduler.reconcileMissed();
      await scheduler.rescheduleAll();
      await scheduleNextSpeakSweep(repository);
      return true;
    } on Object catch (error, stackTrace) {
      log.error('Task $task failed', error: error, stackTrace: stackTrace);
      // Returning false asks WorkManager to retry with backoff.
      return false;
    } finally {
      await database.close();
    }
  });
}

/// Alarm callback that speaks whatever is due right now.
@pragma('vm:entry-point')
Future<void> speakDueRemindersCallback(int alarmId) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Info rather than warning. This isolate cannot be attached to a debugger and
  // leaves no UI trace, so "it ran and decided to do nothing" has to be
  // distinguishable from "it never ran" in a logcat capture.
  final AppLogger log =
      ConsoleLogger(level: LogLevel.info).forContext('SpeakAlarm');

  final AppDatabase database = AppDatabase();
  final FlutterTtsService tts = FlutterTtsService(logger: log);
  try {
    log.info('Sweep alarm $alarmId fired.');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(StorageKeys.speakReminders) ?? true)) {
      log.info('Spoken reminders are switched off; nothing to announce.');
      return;
    }

    final ReminderRepository repository = DriftReminderRepository(
      database: database,
      logger: log,
    );

    final DateTime now = DateTime.now();
    final Result<List<Reminder>> due = await repository.getDueBefore(
      now.add(AppConstants.reminderFireTolerance),
    );

    final List<Reminder> speakable = due
        .getOrElse(const <Reminder>[])
        .where(
          (Reminder reminder) =>
              reminder.isSpoken &&
              now.difference(reminder.dueAt).abs() <=
                  AppConstants.reminderFireTolerance,
        )
        .toList();

    if (speakable.isEmpty) {
      // Distinguishes "the alarm was pointed at the wrong instant" from "the
      // alarm never fired" — the two failures look identical from outside.
      log.info(
        'Nothing to announce: ${due.getOrElse(const <Reminder>[]).length} '
        'reminder(s) due within tolerance, none spoken and in range of $now.',
      );
      return;
    }

    final int repeats = AppSettings.clampSpeakRepeatCount(
      prefs.getInt(StorageKeys.speakRepeatCount) ?? 1,
    );

    log.info('Announcing ${speakable.length} reminder(s), $repeats time(s).');
    await tts.applySettings(_speechSettingsFrom(prefs));
    for (final Reminder reminder in speakable) {
      for (int pass = 0; pass < repeats; pass++) {
        if (pass > 0) {
          // `speak` only returns once playback has finished, so this is a
          // genuine pause between utterances rather than an overlap guard.
          await Future<void>.delayed(AppSettings.speakRepeatGap);
        }
        final Result<void> spoken = await tts.speak(reminder.spokenText);
        if (spoken case Failure<void>(failure: final AppFailure f)) {
          log.error('Could not speak ${reminder.id}: ${f.message}');
          // Repeating a failing utterance just multiplies the failure.
          break;
        }
      }
    }

    await scheduleNextSpeakSweep(repository);
  } on Object catch (error, stackTrace) {
    log.error('Speak sweep failed', error: error, stackTrace: stackTrace);
  } finally {
    await tts.dispose();
    await database.close();
  }
}

/// Points the rolling sweep alarm at the soonest upcoming spoken reminder.
///
/// Must be called whenever the reminder set changes, not only from the
/// background isolates. The alarm is what actually speaks; a reminder saved
/// while no alarm is armed would show its notification and stay silent.
Future<void> scheduleNextSpeakSweep(ReminderRepository repository) async {
  final Result<List<Reminder>> active = await repository.getActive();
  final List<Reminder> reminders = active.getOrElse(const <Reminder>[]);

  final DateTime now = DateTime.now();
  DateTime? soonest;
  for (final Reminder reminder in reminders) {
    if (!reminder.isSpoken || !reminder.dueAt.isAfter(now)) {
      continue;
    }
    if (soonest == null || reminder.dueAt.isBefore(soonest)) {
      soonest = reminder.dueAt;
    }
  }

  if (soonest != null) {
    await scheduleSpeakSweep(soonest);
  }
}

/// Rebuilds speech settings from raw preferences.
///
/// The settings repository is not available in a background isolate, so the
/// keys are read directly. Keys live in [StorageKeys] precisely so the two
/// readers cannot disagree.
TtsSpeechSettings _speechSettingsFrom(SharedPreferences prefs) {
  const TtsSpeechSettings defaults = TtsSpeechSettings();
  return TtsSpeechSettings(
    language: prefs.getString(StorageKeys.ttsLanguage) ?? defaults.language,
    voiceName: prefs.getString(StorageKeys.ttsVoiceName),
    voiceLocale: prefs.getString(StorageKeys.ttsVoiceLocale),
    rate: prefs.getDouble(StorageKeys.ttsRate) ?? defaults.rate,
    pitch: prefs.getDouble(StorageKeys.ttsPitch) ?? defaults.pitch,
    volume: prefs.getDouble(StorageKeys.ttsVolume) ?? defaults.volume,
  );
}
