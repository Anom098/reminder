/// Application entry point.
///
/// Start-up is deliberately split in two. Everything that *must* happen before
/// the first frame — configuration, preferences, background plugin
/// registration — happens here. Everything else (notifications, scheduling,
/// catch-up) happens after the first frame, inside `AppBootstrap`, so the UI
/// appears immediately even on a cold start.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/app.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/config/config_loader.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/services/background/background_tasks.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/logging/console_logger.dart';

/// Boots the application.
Future<void> main() async {
  // `runZonedGuarded` is not used: Flutter's own error handling already
  // reports framework errors, and a guarded zone swallows the stack traces
  // that make platform-channel failures diagnosable.
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config = await ConfigLoader.load();
  final AppLogger logger = ConsoleLogger(level: config.logLevel);

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      details.summary.toString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final SharedPreferences preferences = await SharedPreferences.getInstance();

  // Registering the background isolates is cheap and must happen before any
  // scheduling call, so it stays on the critical path.
  try {
    await initializeBackgroundExecution(logger: logger);
  } on Object catch (error, stackTrace) {
    logger.error(
      'Background execution could not be initialised; reminders will still '
      'notify but may not be spoken while the app is closed.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const VoiceReminderApp(),
    ),
  );
}
