/// Presentation-layer state for user settings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/domain/repositories/settings_repository.dart';

/// Exposes [AppSettings] to the widget tree and applies edits.
///
/// State is seeded synchronously from the repository's cached value, so the
/// first frame already has the user's theme. Writes are optimistic: the new
/// value is published immediately and rolled back only if persistence fails,
/// which keeps toggles from feeling laggy.
final class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final SettingsRepository repository = ref.watch(settingsRepositoryProvider);

    // Keep in sync with writes made outside this controller — a restore from
    // backup, or the reset action.
    final ProviderSubscription<AsyncValue<AppSettings>> subscription =
        ref.listen<AsyncValue<AppSettings>>(
      _settingsStreamProvider,
      (AsyncValue<AppSettings>? previous, AsyncValue<AppSettings> next) {
        final AppSettings? value = next.valueOrNull;
        if (value != null && value != state) {
          state = value;
        }
      },
    );
    ref.onDispose(subscription.close);

    return repository.current;
  }

  /// Persists [settings], reverting on failure.
  Future<Result<AppSettings>> _persist(AppSettings settings) async {
    final AppSettings previous = state;
    state = settings;

    final Result<AppSettings> saved =
        await ref.read(settingsRepositoryProvider).save(settings);

    if (saved.isFailure) {
      state = previous;
    }
    return saved;
  }

  /// Changes the colour scheme preference.
  Future<Result<AppSettings>> setThemeMode(AppThemeMode mode) =>
      _persist(state.copyWith(themeMode: mode));

  /// Changes the accent colour.
  Future<Result<AppSettings>> setSeedColor(int colorValue) =>
      _persist(state.copyWith(seedColorValue: colorValue));

  /// Turns high contrast on or off.
  Future<Result<AppSettings>> setHighContrast({required bool enabled}) =>
      _persist(state.copyWith(useHighContrast: enabled));

  /// Overrides the text scale, or clears the override when [scale] is `null`.
  Future<Result<AppSettings>> setTextScale(double? scale) => _persist(
        scale == null
            ? state.copyWith(clearTextScaleOverride: true)
            : state.copyWith(textScaleOverride: scale),
      );

  /// Replaces the speech settings and applies them to the engine immediately,
  /// so the preview the user hears matches what was just chosen.
  Future<Result<AppSettings>> setSpeech(TtsSpeechSettings speech) async {
    final Result<AppSettings> saved =
        await _persist(state.copyWith(speech: speech));
    if (saved.isSuccess) {
      await ref.read(textToSpeechServiceProvider).applySettings(speech);
    }
    return saved;
  }

  /// Turns spoken reminders on or off.
  Future<Result<AppSettings>> setSpeakReminders({required bool enabled}) =>
      _persist(state.copyWith(speakReminders: enabled));

  /// Sets how many times each announcement is repeated.
  ///
  /// Out-of-range values are clamped by [AppSettings.copyWith] rather than
  /// rejected, so a caller cannot put the app into a state where it talks
  /// forever.
  Future<Result<AppSettings>> setSpeakRepeatCount(int count) =>
      _persist(state.copyWith(speakRepeatCount: count));

  /// Sets the pause between repeats of an announcement.
  ///
  /// Out-of-range values are clamped by [AppSettings.copyWith] rather than
  /// rejected.
  Future<Result<AppSettings>> setSpeakRepeatInterval(Duration interval) =>
      _persist(state.copyWith(speakRepeatInterval: interval));

  /// Controls whether reminders are spoken in silent mode.
  Future<Result<AppSettings>> setSpeakInSilentMode({required bool enabled}) =>
      _persist(state.copyWith(speakInSilentMode: enabled));

  /// Turns notification vibration on or off.
  Future<Result<AppSettings>> setNotificationVibration({
    required bool enabled,
  }) =>
      _persist(state.copyWith(notificationVibration: enabled));

  /// Sets the duration used by the notification's Snooze button.
  Future<Result<AppSettings>> setDefaultSnooze(Duration duration) =>
      _persist(state.copyWith(defaultSnooze: duration));

  /// Sets the recogniser locale, or clears it to follow the device.
  Future<Result<AppSettings>> setSpeechLocale(String? localeId) => _persist(
        localeId == null
            ? state.copyWith(clearSpeechLocaleId: true)
            : state.copyWith(speechLocaleId: localeId),
      );

  /// Marks onboarding as done.
  Future<Result<AppSettings>> completeOnboarding() =>
      _persist(state.copyWith(onboardingComplete: true));

  /// Restores every setting to its default.
  Future<Result<AppSettings>> resetToDefaults() async {
    final Result<AppSettings> reset =
        await ref.read(settingsRepositoryProvider).reset();
    if (reset case Success<AppSettings>(value: final AppSettings value)) {
      state = value;
    }
    return reset;
  }
}

/// The settings, kept in sync with persistence.
final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
  name: 'settings',
);

/// Internal stream used to observe writes made outside the controller.
final StreamProvider<AppSettings> _settingsStreamProvider =
    StreamProvider<AppSettings>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).watch(),
  name: 'settingsStream',
);
