/// Material 3 theming.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';

/// Builds the light and dark [ThemeData] for the application.
///
/// Both themes are derived from a single seed colour so the palette stays
/// coherent when the user picks a different accent, and component overrides are
/// kept to the few places where the Material defaults genuinely do not suit a
/// reminder list.
abstract final class AppTheme {
  /// Accent colours offered in settings.
  static const List<Color> seedPalette = <Color>[
    Color(0xFF4F46E5), // Indigo
    Color(0xFF0D9488), // Teal
    Color(0xFF2563EB), // Blue
    Color(0xFF7C3AED), // Violet
    Color(0xFFDB2777), // Pink
    Color(0xFFEA580C), // Orange
    Color(0xFF16A34A), // Green
    Color(0xFF475569), // Slate
  ];

  /// The light theme.
  static ThemeData light(AppSettings settings) => _build(
        settings: settings,
        brightness: Brightness.light,
      );

  /// The dark theme.
  static ThemeData dark(AppSettings settings) => _build(
        settings: settings,
        brightness: Brightness.dark,
      );

  /// Maps the domain preference onto Flutter's [ThemeMode].
  static ThemeMode themeModeFor(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static ThemeData _build({
    required AppSettings settings,
    required Brightness brightness,
  }) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: Color(settings.seedColorValue),
      brightness: brightness,
      // High contrast raises the minimum contrast ratio the algorithm targets,
      // which is a genuine accessibility affordance rather than a filter.
      contrastLevel: settings.useHighContrast ? 1.0 : 0.0,
    );

    final ThemeData base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        // Reminder rows carry two lines plus a trailing control; the default
        // padding makes them feel cramped at large text sizes.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48dp is the minimum comfortable touch target, and this app is used
          // one-handed and in a hurry.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        backgroundColor: scheme.surfaceContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Spacing scale used throughout the UI.
///
/// A named scale rather than ad-hoc numbers, so that density can be adjusted in
/// one place and reviewers can spot inconsistent padding at a glance.
abstract final class Insets {
  /// 4dp.
  static const double xs = 4;

  /// 8dp.
  static const double sm = 8;

  /// 12dp.
  static const double md = 12;

  /// 16dp — the default screen gutter.
  static const double lg = 16;

  /// 24dp.
  static const double xl = 24;

  /// 32dp.
  static const double xxl = 32;
}

/// Breakpoints for the adaptive layout.
abstract final class Breakpoints {
  /// Below this the layout is a single column.
  static const double compact = 600;

  /// At or above this a two-pane list/detail layout is used.
  static const double medium = 840;

  /// Wide tablets and desktop-class windows.
  static const double expanded = 1200;

  /// Whether [width] should use the two-pane layout.
  static bool isTwoPane(double width) => width >= medium;
}
