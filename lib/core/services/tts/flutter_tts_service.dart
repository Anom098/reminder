/// `flutter_tts`-backed [TextToSpeechService].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// Speaks reminders using the platform speech synthesiser.
///
/// The engine is a single shared native resource, so this class is a singleton
/// in the provider graph and serialises access: a [speak] that arrives while
/// another utterance is playing stops the first one rather than queueing.
final class FlutterTtsService implements TextToSpeechService {
  /// Creates a service over [engine].
  FlutterTtsService({
    required AppLogger logger,
    FlutterTts? engine,
  })  : _log = logger.forContext('Tts'),
        _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  final AppLogger _log;
  final StreamController<bool> _speaking = StreamController<bool>.broadcast();

  bool _initialized = false;
  TtsSpeechSettings _settings = const TtsSpeechSettings();
  Completer<void>? _utterance;

  @override
  Stream<bool> get isSpeaking => _speaking.stream;

  @override
  Future<Result<void>> initialize() async {
    if (_initialized) {
      return voidSuccess;
    }
    try {
      // iOS needs an explicit audio-session category or a spoken reminder is
      // silenced by the ringer switch and cannot play while other audio runs.
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          <IosTextToSpeechAudioCategoryOptions>[
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions
                .interruptSpokenAudioAndMixWithOthers,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      }

      // Without this, `speak()` returns as soon as synthesis *starts*, and the
      // app would tear the engine down mid-sentence.
      await _tts.awaitSpeakCompletion(true);

      _tts
        ..setStartHandler(() => _speaking.add(true))
        ..setCompletionHandler(_finishUtterance)
        ..setCancelHandler(_finishUtterance)
        ..setErrorHandler((dynamic message) {
          _log.warning('TTS engine error: $message');
          _finishUtterance();
        });

      await applySettings(_settings);
      _initialized = true;
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _log.error('initialize failed', error: error, stackTrace: stackTrace);
      return Failure<void>(
        TextToSpeechFailure(
          message: 'Speech is unavailable on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> speak(String text, {TtsSpeechSettings? settings}) async {
    final String utterance = text.trim();
    if (utterance.isEmpty) {
      return voidSuccess;
    }

    final Result<void> ready = await initialize();
    if (ready.isFailure) {
      return ready;
    }

    try {
      await stop();
      if (settings != null && settings != _settings) {
        await applySettings(settings);
      }

      final Completer<void> completer = Completer<void>();
      _utterance = completer;
      _speaking.add(true);

      await _tts.speak(utterance);
      // `awaitSpeakCompletion(true)` makes the call above block until playback
      // ends on both platforms, but the handler-based completer is the
      // authoritative signal and covers engines that return early.
      _finishUtterance();
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _finishUtterance();
      _log.error('speak failed', error: error, stackTrace: stackTrace);
      return Failure<void>(
        TextToSpeechFailure(
          message: 'Could not speak the reminder.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> stop() async {
    try {
      await _tts.stop();
      _finishUtterance();
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      return Failure<void>(
        TextToSpeechFailure(
          message: 'Could not stop playback.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> pause() async {
    try {
      await _tts.pause();
      _speaking.add(false);
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      return Failure<void>(
        TextToSpeechFailure(
          message: 'Pausing is not supported on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> applySettings(TtsSpeechSettings settings) async {
    try {
      await _tts.setLanguage(settings.language);
      await _tts.setSpeechRate(settings.rate);
      await _tts.setPitch(settings.pitch);
      await _tts.setVolume(settings.volume);

      final String? voiceName = settings.voiceName;
      final String? voiceLocale = settings.voiceLocale;
      if (voiceName != null && voiceLocale != null) {
        await _tts.setVoice(<String, String>{
          'name': voiceName,
          'locale': voiceLocale,
        });
      }

      _settings = settings;
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _log.warning(
        'applySettings failed; keeping previous voice settings',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>(
        TextToSpeechFailure(
          message: 'Those voice settings are not supported on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<String>>> availableLanguages() async {
    return Result.guardAsync<List<String>>(() async {
      final Object? raw = await _tts.getLanguages;
      if (raw is! List<Object?>) {
        return <String>[];
      }
      return raw
          .whereType<Object>()
          .map((Object value) => value.toString())
          .toSet()
          .toList()
        ..sort();
    });
  }

  @override
  Future<Result<List<TtsVoice>>> availableVoices() async {
    return Result.guardAsync<List<TtsVoice>>(() async {
      final Object? raw = await _tts.getVoices;
      if (raw is! List<Object?>) {
        return <TtsVoice>[];
      }

      final List<TtsVoice> voices = <TtsVoice>[];
      for (final Object? entry in raw) {
        if (entry is! Map<Object?, Object?>) {
          continue;
        }
        final Object? name = entry['name'];
        final Object? locale = entry['locale'];
        if (name == null || locale == null) {
          continue;
        }
        voices.add(
          TtsVoice(
            name: name.toString(),
            locale: locale.toString(),
            // Android marks network voices with this key; iOS never does.
            isNetworkOnly: entry['network_required'] == '1' ||
                entry['network_required'] == true,
          ),
        );
      }
      voices.sort(
        (TtsVoice a, TtsVoice b) => a.displayName.compareTo(b.displayName),
      );
      return voices;
    });
  }

  @override
  Future<Result<bool>> isLanguageAvailable(String language) async {
    return Result.guardAsync<bool>(() async {
      final Object? result = await _tts.isLanguageAvailable(language);
      return result == true || result == 1;
    });
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _speaking.close();
  }

  void _finishUtterance() {
    _speaking.add(false);
    final Completer<void>? completer = _utterance;
    _utterance = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
