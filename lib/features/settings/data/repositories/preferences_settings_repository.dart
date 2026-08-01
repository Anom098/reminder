/// `SharedPreferences`-backed [SettingsRepository].
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/domain/repositories/settings_repository.dart';

/// Persists settings as individual preference keys.
///
/// Individual keys rather than one JSON blob, so that a value added in a future
/// release simply reads as absent for existing users instead of invalidating
/// everything they had configured.
///
/// The current value is cached in memory and refreshed on every write, which is
/// what lets [current] be synchronous.
final class PreferencesSettingsRepository implements SettingsRepository {
  /// Creates a repository over [preferences].
  PreferencesSettingsRepository({
    required SharedPreferences preferences,
    required AppLogger logger,
  })  : _prefs = preferences,
        _log = logger.forContext('SettingsRepository') {
    _cached = _read();
    _controller = StreamController<AppSettings>.broadcast(
      onListen: () => _controller.add(_cached),
    );
  }

  final SharedPreferences _prefs;
  final AppLogger _log;

  late AppSettings _cached;
  late final StreamController<AppSettings> _controller;

  @override
  AppSettings get current => _cached;

  @override
  Stream<AppSettings> watch() => _controller.stream;

  @override
  Future<Result<AppSettings>> save(AppSettings settings) async {
    try {
      await Future.wait<bool>(<Future<bool>>[
        _prefs.setString(StorageKeys.themeMode, settings.themeMode.name),
        _prefs.setInt(StorageKeys.themeSeed, settings.seedColorValue),
        _prefs.setBool(StorageKeys.highContrast, settings.useHighContrast),
        _prefs.setString(StorageKeys.ttsLanguage, settings.speech.language),
        _prefs.setDouble(StorageKeys.ttsRate, settings.speech.rate),
        _prefs.setDouble(StorageKeys.ttsPitch, settings.speech.pitch),
        _prefs.setDouble(StorageKeys.ttsVolume, settings.speech.volume),
        _prefs.setBool(StorageKeys.speakReminders, settings.speakReminders),
        _prefs.setInt(
          StorageKeys.speakRepeatCount,
          settings.speakRepeatCount,
        ),
        _prefs.setInt(
          StorageKeys.speakRepeatIntervalSeconds,
          settings.speakRepeatInterval.inSeconds,
        ),
        _prefs.setBool(
          StorageKeys.speakInSilentMode,
          settings.speakInSilentMode,
        ),
        _prefs.setBool(
          StorageKeys.notificationVibration,
          settings.notificationVibration,
        ),
        _prefs.setInt(
          StorageKeys.defaultSnoozeMinutes,
          settings.defaultSnooze.inMinutes,
        ),
        _prefs.setBool(
          StorageKeys.onboardingComplete,
          settings.onboardingComplete,
        ),
      ]);

      await _writeNullable(
        StorageKeys.textScale,
        settings.textScaleOverride,
        _prefs.setDouble,
      );
      await _writeNullable(
        StorageKeys.ttsVoiceName,
        settings.speech.voiceName,
        _prefs.setString,
      );
      await _writeNullable(
        StorageKeys.ttsVoiceLocale,
        settings.speech.voiceLocale,
        _prefs.setString,
      );
      await _writeNullable(
        StorageKeys.speechLocale,
        settings.speechLocaleId,
        _prefs.setString,
      );
      await _writeNullable(
        StorageKeys.lastBackupAt,
        settings.lastBackupAt?.millisecondsSinceEpoch,
        _prefs.setInt,
      );

      _cached = settings;
      _controller.add(settings);
      return Success<AppSettings>(settings);
    } on Object catch (error, stackTrace) {
      _log.error('save failed', error: error, stackTrace: stackTrace);
      return Failure<AppSettings>(
        StorageFailure(
          message: 'Could not save your settings. Please try again.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<AppSettings>> reset() async {
    try {
      for (final String key in _ownedKeys) {
        await _prefs.remove(key);
      }
      _cached = const AppSettings();
      _controller.add(_cached);
      return Success<AppSettings>(_cached);
    } on Object catch (error, stackTrace) {
      _log.error('reset failed', error: error, stackTrace: stackTrace);
      return Failure<AppSettings>(
        StorageFailure(
          message: 'Could not reset your settings.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Releases the broadcast controller.
  Future<void> dispose() => _controller.close();

  AppSettings _read() {
    const AppSettings defaults = AppSettings();

    final int? backupMillis = _prefs.getInt(StorageKeys.lastBackupAt);

    return AppSettings(
      themeMode: AppThemeMode.parse(_prefs.getString(StorageKeys.themeMode)),
      seedColorValue:
          _prefs.getInt(StorageKeys.themeSeed) ?? defaults.seedColorValue,
      useHighContrast: _prefs.getBool(StorageKeys.highContrast) ?? false,
      textScaleOverride: _prefs.getDouble(StorageKeys.textScale),
      speech: TtsSpeechSettings(
        language: _prefs.getString(StorageKeys.ttsLanguage) ??
            defaults.speech.language,
        voiceName: _prefs.getString(StorageKeys.ttsVoiceName),
        voiceLocale: _prefs.getString(StorageKeys.ttsVoiceLocale),
        rate: _prefs.getDouble(StorageKeys.ttsRate) ?? defaults.speech.rate,
        pitch: _prefs.getDouble(StorageKeys.ttsPitch) ?? defaults.speech.pitch,
        volume:
            _prefs.getDouble(StorageKeys.ttsVolume) ?? defaults.speech.volume,
      ),
      speakReminders: _prefs.getBool(StorageKeys.speakReminders) ?? true,
      // Clamped on read as well as on write: preferences survive downgrades and
      // hand-edited backups, so a stored value is not automatically valid.
      speakRepeatCount: AppSettings.clampSpeakRepeatCount(
        _prefs.getInt(StorageKeys.speakRepeatCount) ??
            defaults.speakRepeatCount,
      ),
      speakRepeatInterval: AppSettings.clampSpeakRepeatInterval(
        Duration(
          seconds: _prefs.getInt(StorageKeys.speakRepeatIntervalSeconds) ??
              defaults.speakRepeatInterval.inSeconds,
        ),
      ),
      speakInSilentMode: _prefs.getBool(StorageKeys.speakInSilentMode) ?? false,
      notificationVibration:
          _prefs.getBool(StorageKeys.notificationVibration) ?? true,
      defaultSnooze: Duration(
        minutes: _prefs.getInt(StorageKeys.defaultSnoozeMinutes) ??
            defaults.defaultSnooze.inMinutes,
      ),
      speechLocaleId: _prefs.getString(StorageKeys.speechLocale),
      onboardingComplete:
          _prefs.getBool(StorageKeys.onboardingComplete) ?? false,
      lastBackupAt: backupMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(backupMillis),
    );
  }

  /// Writes [value], or removes the key when it is `null`.
  ///
  /// Removing rather than writing a sentinel keeps "unset" distinguishable from
  /// "explicitly set to the default".
  Future<void> _writeNullable<T>(
    String key,
    T? value,
    Future<bool> Function(String key, T value) write,
  ) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await write(key, value);
    }
  }

  static const List<String> _ownedKeys = <String>[
    StorageKeys.themeMode,
    StorageKeys.themeSeed,
    StorageKeys.highContrast,
    StorageKeys.textScale,
    StorageKeys.ttsLanguage,
    StorageKeys.ttsVoiceName,
    StorageKeys.ttsVoiceLocale,
    StorageKeys.ttsRate,
    StorageKeys.ttsPitch,
    StorageKeys.ttsVolume,
    StorageKeys.speakReminders,
    StorageKeys.speakRepeatCount,
    StorageKeys.speakRepeatIntervalSeconds,
    StorageKeys.speakInSilentMode,
    StorageKeys.notificationVibration,
    StorageKeys.defaultSnoozeMinutes,
    StorageKeys.speechLocale,
    StorageKeys.onboardingComplete,
    StorageKeys.lastBackupAt,
  ];
}
