/// Root of the dependency-injection graph.
///
/// Every provider in the application ultimately resolves through this file.
/// Providers that need a value only available after asynchronous start-up —
/// the parsed [AppConfig], the opened database — throw when read without an
/// override, which turns a missing bootstrap step into an immediate, obvious
/// error rather than silent misbehaviour.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/logging/console_logger.dart';
import 'package:voice_reminder/core/utils/clock.dart';

/// Runtime configuration.
///
/// Overridden in `main()` with the value produced by `ConfigLoader.load()`.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (Ref ref) => throw UnimplementedError(
    'appConfigProvider must be overridden in ProviderScope during bootstrap.',
  ),
  name: 'appConfig',
);

/// Application-wide logger, configured from [appConfigProvider].
final Provider<AppLogger> appLoggerProvider = Provider<AppLogger>(
  (Ref ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    return ConsoleLogger(level: config.logLevel);
  },
  name: 'appLogger',
);

/// Source of the current time. Overridden with a [FixedClock] in tests.
final Provider<Clock> clockProvider = Provider<Clock>(
  (Ref ref) => const SystemClock(),
  name: 'clock',
);

/// Key–value store for user settings.
///
/// Overridden in `main()` with the resolved instance so that widgets can read
/// settings synchronously on first frame instead of flashing defaults.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope '
    'during bootstrap.',
  ),
  name: 'sharedPreferences',
);

/// Returns a logger tagged with [context].
///
/// Use from other providers: `ref.watch(scopedLoggerProvider('Scheduler'))`.
final ProviderFamily<AppLogger, String> scopedLoggerProvider =
    Provider.family<AppLogger, String>(
  (Ref ref, String context) => ref.watch(appLoggerProvider).forContext(context),
  name: 'scopedLogger',
);
