/// User-controlled application settings.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';

/// Which colour scheme the app follows.
enum AppThemeMode {
  /// Follow the OS setting.
  system('System'),

  /// Always light.
  light('Light'),

  /// Always dark.
  dark('Dark');

  const AppThemeMode(this.label);

  /// User-facing name.
  final String label;

  /// Parses a stored name, defaulting to [AppThemeMode.system].
  static AppThemeMode parse(String? raw) {
    for (final AppThemeMode value in AppThemeMode.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return AppThemeMode.system;
  }
}

/// Complete, immutable settings snapshot.
///
/// Held as one value rather than a bag of independent keys so that a settings
/// screen rebuild is a single provider read, and so that export/import round
/// trips are total.
final class AppSettings extends Equatable {
  /// Creates a settings snapshot.
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seedColorValue = _defaultSeedColor,
    this.useHighContrast = false,
    this.textScaleOverride,
    this.speech = const TtsSpeechSettings(),
    this.speakReminders = true,
    this.speakRepeatCount = 1,
    this.speakInSilentMode = false,
    this.notificationVibration = true,
    this.defaultSnooze = const Duration(minutes: 10),
    this.speechLocaleId,
    this.onboardingComplete = false,
    this.lastBackupAt,
  });

  /// Default Material 3 seed colour (indigo).
  static const int _defaultSeedColor = 0xFF4F46E5;

  /// Colour scheme preference.
  final AppThemeMode themeMode;

  /// ARGB seed colour for the Material 3 palette.
  final int seedColorValue;

  /// Whether to force a high-contrast palette.
  final bool useHighContrast;

  /// Explicit text scale, or `null` to follow the system setting.
  ///
  /// Overriding the system scale is an accessibility escape hatch for users
  /// whose global setting is too small for this app specifically; the default
  /// is deliberately `null`.
  final double? textScaleOverride;

  /// Voice, rate, pitch and volume used for spoken reminders.
  final TtsSpeechSettings speech;

  /// Whether reminders are announced aloud at all.
  final bool speakReminders;

  /// How many times each announcement is repeated.
  ///
  /// One utterance is easy to miss from another room or half-asleep, which is
  /// exactly when a reminder matters most. Always within
  /// [minSpeakRepeatCount]–[maxSpeakRepeatCount]: values arriving from
  /// preferences or an imported backup are clamped rather than trusted, so a
  /// corrupt file cannot make the app talk indefinitely.
  final int speakRepeatCount;

  /// Fewest times an announcement may be spoken.
  static const int minSpeakRepeatCount = 1;

  /// Most times an announcement may be spoken.
  static const int maxSpeakRepeatCount = 5;

  /// Pause inserted between repeats.
  ///
  /// Without a gap the repeats run together into one long sentence and stop
  /// reading as a repetition at all.
  static const Duration speakRepeatGap = Duration(milliseconds: 900);

  /// Constrains [value] to the supported range.
  static int clampSpeakRepeatCount(int value) =>
      value.clamp(minSpeakRepeatCount, maxSpeakRepeatCount);

  /// Whether to speak even when the device is in silent mode.
  final bool speakInSilentMode;

  /// Whether reminder notifications vibrate.
  final bool notificationVibration;

  /// Duration applied by the notification's Snooze button.
  final Duration defaultSnooze;

  /// Locale id used by the speech recogniser, or `null` for the device
  /// default.
  final String? speechLocaleId;

  /// Whether first-run onboarding has been completed.
  final bool onboardingComplete;

  /// When the last successful backup was written.
  final DateTime? lastBackupAt;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? seedColorValue,
    bool? useHighContrast,
    double? textScaleOverride,
    TtsSpeechSettings? speech,
    bool? speakReminders,
    int? speakRepeatCount,
    bool? speakInSilentMode,
    bool? notificationVibration,
    Duration? defaultSnooze,
    String? speechLocaleId,
    bool? onboardingComplete,
    DateTime? lastBackupAt,
    bool clearTextScaleOverride = false,
    bool clearSpeechLocaleId = false,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        seedColorValue: seedColorValue ?? this.seedColorValue,
        useHighContrast: useHighContrast ?? this.useHighContrast,
        textScaleOverride: clearTextScaleOverride
            ? null
            : (textScaleOverride ?? this.textScaleOverride),
        speech: speech ?? this.speech,
        speakReminders: speakReminders ?? this.speakReminders,
        speakRepeatCount:
            clampSpeakRepeatCount(speakRepeatCount ?? this.speakRepeatCount),
        speakInSilentMode: speakInSilentMode ?? this.speakInSilentMode,
        notificationVibration:
            notificationVibration ?? this.notificationVibration,
        defaultSnooze: defaultSnooze ?? this.defaultSnooze,
        speechLocaleId: clearSpeechLocaleId
            ? null
            : (speechLocaleId ?? this.speechLocaleId),
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      );

  @override
  List<Object?> get props => <Object?>[
        themeMode,
        seedColorValue,
        useHighContrast,
        textScaleOverride,
        speech,
        speakReminders,
        speakRepeatCount,
        speakInSilentMode,
        notificationVibration,
        defaultSnooze,
        speechLocaleId,
        onboardingComplete,
        lastBackupAt,
      ];
}
