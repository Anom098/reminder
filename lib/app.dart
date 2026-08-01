/// The application widget and its start-up side effects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/presentation/controllers/settings_controller.dart';
import 'package:voice_reminder/shared/startup/app_bootstrap.dart';

/// Root widget.
class VoiceReminderApp extends ConsumerWidget {
  /// Creates the application widget.
  const VoiceReminderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final GoRouter router = ref.watch(appRouterProvider);
    final AppConfig config = ref.watch(appConfigProvider);

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(settings),
      darkTheme: AppTheme.dark(settings),
      themeMode: AppTheme.themeModeFor(settings.themeMode),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        final double? override = settings.textScaleOverride;

        return MediaQuery(
          data: media.copyWith(
            // Respect the system text scale by default. When the user has set
            // an in-app override, clamp it so that the layout stays usable at
            // the extremes rather than allowing unbounded growth.
            textScaler: override == null
                ? media.textScaler
                : TextScaler.linear(override.clamp(0.8, 2.0)),
          ),
          child: AppBootstrap(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
