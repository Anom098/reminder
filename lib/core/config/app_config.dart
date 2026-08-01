/// Typed, immutable runtime configuration.
///
/// Values originate from the bundled `.env` asset, but the app is offline-first
/// and must boot even if that asset is missing or malformed: every field has a
/// production-safe default, and parsing never throws.
library;

import 'package:voice_reminder/core/services/logging/app_logger.dart';

/// Which build flavour the app is running as.
enum AppEnvironment {
  /// Local development. Verbose logging, no data minimisation.
  development,

  /// Pre-release testing.
  staging,

  /// Shipping build.
  production;

  /// Parses an environment name, defaulting to [AppEnvironment.production].
  ///
  /// Defaulting to production is deliberate: an unrecognised value must never
  /// accidentally enable development behaviour in a shipped build.
  static AppEnvironment parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'development':
      case 'dev':
      case 'debug':
        return AppEnvironment.development;
      case 'staging':
      case 'stage':
      case 'beta':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.production;
    }
  }

  /// Whether this is a non-production environment.
  bool get isDevelopmentLike => this != AppEnvironment.production;
}

/// Strategy used to turn a spoken sentence into a structured reminder.
enum VoiceParserStrategy {
  /// Deterministic, fully offline grammar-based parser.
  ruleBased,

  /// Language-model parser, with [ruleBased] as fallback when unavailable.
  llm;

  /// Parses a strategy name, defaulting to [VoiceParserStrategy.ruleBased].
  static VoiceParserStrategy parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'llm' => VoiceParserStrategy.llm,
        _ => VoiceParserStrategy.ruleBased,
      };
}

/// Speech-to-text backend selection.
enum SpeechEngineKind {
  /// The recogniser supplied by Android / iOS.
  platform,

  /// A bundled Whisper model. Reserved for a future release.
  whisper;

  /// Parses an engine name, defaulting to [SpeechEngineKind.platform].
  static SpeechEngineKind parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'whisper' => SpeechEngineKind.whisper,
        _ => SpeechEngineKind.platform,
      };
}

/// Immutable snapshot of application configuration.
final class AppConfig {
  /// Creates a configuration with explicit values.
  ///
  /// Prefer [AppConfig.fromMap] outside of tests.
  const AppConfig({
    this.appName = 'Voice Reminder',
    this.environment = AppEnvironment.production,
    this.logLevel = LogLevel.info,
    this.voiceParser = VoiceParserStrategy.ruleBased,
    this.voiceParserConfidenceThreshold = 0.6,
    this.speechEngine = SpeechEngineKind.platform,
    this.speechListenTimeout = const Duration(seconds: 30),
    this.speechPauseTimeout = const Duration(seconds: 3),
    this.ttsDefaultLanguage = 'en-US',
    this.ttsDefaultRate = 0.5,
    this.ttsDefaultPitch = 1.0,
    this.ttsDefaultVolume = 1.0,
    this.schedulingHorizonOccurrences = 12,
    this.schedulingRefreshInterval = const Duration(hours: 6),
  })  : assert(
          voiceParserConfidenceThreshold >= 0 &&
              voiceParserConfidenceThreshold <= 1,
          'confidence threshold must be within 0.0..1.0',
        ),
        assert(
          schedulingHorizonOccurrences > 0,
          'at least one occurrence must be scheduled',
        );

  /// Builds a configuration from raw string values, ignoring unknown keys.
  ///
  /// Malformed entries fall back to the corresponding default rather than
  /// failing the boot sequence.
  factory AppConfig.fromMap(Map<String, String> values) {
    return AppConfig(
      appName: _string(values, 'APP_NAME', 'Voice Reminder'),
      environment: AppEnvironment.parse(values['APP_ENV']),
      logLevel: LogLevel.parse(values['LOG_LEVEL']),
      voiceParser: VoiceParserStrategy.parse(values['VOICE_PARSER']),
      voiceParserConfidenceThreshold: _double(
        values,
        'VOICE_PARSER_CONFIDENCE_THRESHOLD',
        0.6,
        min: 0,
        max: 1,
      ),
      speechEngine: SpeechEngineKind.parse(values['SPEECH_ENGINE']),
      speechListenTimeout: Duration(
        seconds:
            _int(values, 'SPEECH_LISTEN_TIMEOUT_SECONDS', 30, min: 5, max: 120),
      ),
      speechPauseTimeout: Duration(
        seconds:
            _int(values, 'SPEECH_PAUSE_TIMEOUT_SECONDS', 3, min: 1, max: 30),
      ),
      ttsDefaultLanguage: _string(values, 'TTS_DEFAULT_LANGUAGE', 'en-US'),
      ttsDefaultRate: _double(values, 'TTS_DEFAULT_RATE', 0.5, min: 0, max: 1),
      ttsDefaultPitch:
          _double(values, 'TTS_DEFAULT_PITCH', 1, min: 0.5, max: 2),
      ttsDefaultVolume:
          _double(values, 'TTS_DEFAULT_VOLUME', 1, min: 0, max: 1),
      schedulingHorizonOccurrences: _int(
        values,
        'SCHEDULING_HORIZON_OCCURRENCES',
        12,
        min: 1,
        max: 60,
      ),
      schedulingRefreshInterval: Duration(
        hours: _int(values, 'SCHEDULING_REFRESH_INTERVAL_HOURS', 6,
            min: 1, max: 24),
      ),
    );
  }

  /// Display name of the application.
  final String appName;

  /// Build flavour.
  final AppEnvironment environment;

  /// Minimum severity that is logged.
  final LogLevel logLevel;

  /// Which natural-language parser to use.
  final VoiceParserStrategy voiceParser;

  /// Confidence below which the user is asked to confirm a parsed reminder.
  final double voiceParserConfidenceThreshold;

  /// Which speech-to-text backend to use.
  final SpeechEngineKind speechEngine;

  /// Maximum duration of a single listening session.
  final Duration speechListenTimeout;

  /// Silence after which listening stops automatically.
  final Duration speechPauseTimeout;

  /// BCP-47 language tag used for spoken reminders by default.
  final String ttsDefaultLanguage;

  /// Default speech rate, `0.0`–`1.0`.
  final double ttsDefaultRate;

  /// Default voice pitch, `0.5`–`2.0`.
  final double ttsDefaultPitch;

  /// Default playback volume, `0.0`–`1.0`.
  final double ttsDefaultVolume;

  /// How many future occurrences of a repeating reminder are handed to the OS.
  ///
  /// iOS allows at most 64 pending notifications per app, so repeating
  /// reminders are materialised in windows and topped up by a background task
  /// rather than scheduled indefinitely.
  final int schedulingHorizonOccurrences;

  /// How often the background worker tops up the OS schedule.
  final Duration schedulingRefreshInterval;

  static String _string(
    Map<String, String> values,
    String key,
    String fallback,
  ) {
    final String? raw = values[key]?.trim();
    return (raw == null || raw.isEmpty) ? fallback : raw;
  }

  static int _int(
    Map<String, String> values,
    String key,
    int fallback, {
    required int min,
    required int max,
  }) {
    final int? parsed = int.tryParse(values[key]?.trim() ?? '');
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  static double _double(
    Map<String, String> values,
    String key,
    double fallback, {
    required double min,
    required double max,
  }) {
    final double? parsed = double.tryParse(values[key]?.trim() ?? '');
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  @override
  String toString() =>
      'AppConfig(env: ${environment.name}, logLevel: ${logLevel.name}, '
      'parser: ${voiceParser.name}, speech: ${speechEngine.name})';
}
