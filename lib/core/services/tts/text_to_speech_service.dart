/// Text-to-speech contract.
///
/// Deliberately narrow so it can be satisfied by `flutter_tts` today and by a
/// bundled neural voice later without touching call sites.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// A voice offered by the platform speech synthesiser.
final class TtsVoice extends Equatable {
  /// Creates a voice descriptor.
  const TtsVoice({
    required this.name,
    required this.locale,
    this.isNetworkOnly = false,
  });

  /// Engine-specific identifier, e.g. `en-gb-x-gba-network`.
  final String name;

  /// BCP-47 locale tag, e.g. `en-GB`.
  final String locale;

  /// Whether the voice requires connectivity.
  ///
  /// Surfaced in the UI because this app is offline-first: a network-only voice
  /// silently fails to speak a reminder on a plane.
  final bool isNetworkOnly;

  /// Locale-qualified display label.
  String get displayName => '$name ($locale)';

  @override
  List<Object?> get props => <Object?>[name, locale, isNetworkOnly];
}

/// Playback parameters applied to synthesised speech.
final class TtsSpeechSettings extends Equatable {
  /// Creates speech settings.
  const TtsSpeechSettings({
    this.language = 'en-US',
    this.voiceName,
    this.voiceLocale,
    this.rate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
  });

  /// BCP-47 language tag.
  final String language;

  /// Selected voice name, or `null` for the platform default.
  final String? voiceName;

  /// Locale of the selected voice; required alongside [voiceName] on Android.
  final String? voiceLocale;

  /// Speech rate, `0.0`–`1.0`.
  ///
  /// The scale is engine-defined and deliberately not normalised here: `0.5` is
  /// the natural speaking rate on both platforms.
  final double rate;

  /// Voice pitch, `0.5`–`2.0`, where `1.0` is unmodified.
  final double pitch;

  /// Playback volume, `0.0`–`1.0`.
  final double volume;

  /// Returns a copy with the given fields replaced.
  TtsSpeechSettings copyWith({
    String? language,
    String? voiceName,
    String? voiceLocale,
    double? rate,
    double? pitch,
    double? volume,
    bool clearVoice = false,
  }) =>
      TtsSpeechSettings(
        language: language ?? this.language,
        voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
        voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
        rate: rate ?? this.rate,
        pitch: pitch ?? this.pitch,
        volume: volume ?? this.volume,
      );

  @override
  List<Object?> get props =>
      <Object?>[language, voiceName, voiceLocale, rate, pitch, volume];
}

/// Speaks text aloud.
abstract interface class TextToSpeechService {
  /// Whether the engine is currently speaking.
  Stream<bool> get isSpeaking;

  /// Prepares the engine. Safe to call more than once.
  Future<Result<void>> initialize();

  /// Speaks [text] using [settings].
  ///
  /// Completes when playback finishes. Any in-progress utterance is stopped
  /// first, so a second reminder firing during the first one interrupts rather
  /// than queues — reminders are time-sensitive and a stale queue is worse than
  /// a truncated announcement.
  Future<Result<void>> speak(String text, {TtsSpeechSettings? settings});

  /// Stops playback immediately.
  Future<Result<void>> stop();

  /// Pauses playback, where the platform supports it.
  Future<Result<void>> pause();

  /// Applies [settings] as the default for subsequent [speak] calls.
  Future<Result<void>> applySettings(TtsSpeechSettings settings);

  /// Lists the language tags the engine can synthesise.
  Future<Result<List<String>>> availableLanguages();

  /// Lists the installed voices.
  Future<Result<List<TtsVoice>>> availableVoices();

  /// Whether [language] is available on this device.
  Future<Result<bool>> isLanguageAvailable(String language);

  /// Releases engine resources.
  Future<void> dispose();
}
