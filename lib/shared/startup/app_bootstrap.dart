/// Start-up side effects that need a live widget tree.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/constants/notification_constants.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/notifications/notification_service.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/presentation/controllers/settings_controller.dart';

/// Runs one-time start-up work and keeps the schedule healthy.
///
/// Wraps the router's content rather than replacing it, so the UI is
/// interactive immediately and none of this work blocks the first frame.
///
/// Responsibilities:
///
/// * initialise the notification stack and seed the built-in categories;
/// * reconcile reminders whose time passed while the app was not running;
/// * rebuild the OS schedule, which self-heals after a reboot or a restore;
/// * route notification taps to the reminder they refer to;
/// * speak a reminder that came due while the app was in the foreground, which
///   is also the iOS announcement path.
class AppBootstrap extends ConsumerStatefulWidget {
  /// Wraps [child].
  const AppBootstrap({required this.child, super.key});

  /// The application content.
  final Widget child;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationAction>? _actions;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deferred to after the first frame: providers must not be read during
    // build, and the user should see the UI before any I/O happens.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_actions?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground is the cheapest reliable moment to catch up:
    // the device may have been asleep, rebooted, or had its time zone changed.
    if (state == AppLifecycleState.resumed && _started) {
      unawaited(_reconcile());
    }
  }

  Future<void> _start() async {
    if (_started) {
      return;
    }
    _started = true;

    final AppLogger log = ref.read(uiLoggerProvider).forContext('Bootstrap');

    try {
      await ref.read(notificationServiceProvider).initialize();
      await ref.read(categoryRepositoryProvider).seedBuiltIns();

      _actions = ref
          .read(notificationServiceProvider)
          .actions
          .listen(_handleNotificationAction);

      final ReminderScheduler scheduler = ref.read(reminderSchedulerProvider);
      await scheduler.reconcileMissed();
      await scheduler.rescheduleAll();
      await scheduler.ensureBackgroundRefreshScheduled();
    } on Object catch (error, stackTrace) {
      // Start-up must never crash the app. A failure here degrades scheduling,
      // which the periodic background task and the next resume will retry.
      log.error('Start-up failed', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _reconcile() async {
    final ReminderScheduler scheduler = ref.read(reminderSchedulerProvider);
    await scheduler.reconcileMissed();
    await scheduler.rescheduleAll();
  }

  Future<void> _handleNotificationAction(NotificationAction action) async {
    final String? reminderId = action.reminderId;
    if (reminderId == null) {
      return;
    }

    switch (action.actionId) {
      case NotificationConstants.actionComplete:
        await ref.read(completeReminderProvider).call(reminderId);
      case NotificationConstants.actionSnooze:
        final AppSettings settings = ref.read(settingsProvider);
        await ref
            .read(snoozeReminderProvider)
            .call(reminderId, settings.defaultSnooze);
      case NotificationConstants.actionDismiss:
        // Dismissal is a UI gesture only; the schedule is unchanged.
        break;
      case null:
        // The notification body itself was tapped: speak it, then open it.
        await _speak(action);
        if (mounted) {
          context.goToReminder(reminderId);
        }
      default:
        break;
    }
  }

  /// Speaks the reminder that a notification refers to.
  ///
  /// This is the announcement path on iOS, where no background isolate can run
  /// at the scheduled instant, and a redundant-but-harmless one on Android.
  Future<void> _speak(NotificationAction action) async {
    final AppSettings settings = ref.read(settingsProvider);
    if (!settings.speakReminders) {
      return;
    }
    final Object? text =
        action.payload[NotificationConstants.payloadSpokenText];
    if (text is! String || text.trim().isEmpty) {
      return;
    }
    final TextToSpeechService tts = ref.read(textToSpeechServiceProvider);
    for (int pass = 0; pass < settings.speakRepeatCount; pass++) {
      if (pass > 0) {
        await Future<void>.delayed(settings.speakRepeatInterval);
      }
      final Result<void> spoken =
          await tts.speak(text, settings: settings.speech);
      if (spoken.isFailure) {
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
