/// `speech_to_text`-backed [SpeechRecognitionService].
library;

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/speech/speech_recognition_service.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// Captures speech using the recogniser built into Android and iOS.
///
/// The plugin is callback-based and single-session; this class adapts it to a
/// stream and guarantees that exactly one session is active at a time, because
/// starting a second one while the first is live silently drops audio on
/// Android.
final class PlatformSpeechRecognitionService
    implements SpeechRecognitionService {
  /// Creates a service.
  PlatformSpeechRecognitionService({
    required AppConfig config,
    required AppLogger logger,
    stt.SpeechToText? engine,
  })  : _config = config,
        _log = logger.forContext('Speech'),
        _speech = engine ?? stt.SpeechToText();

  final stt.SpeechToText _speech;
  final AppConfig _config;
  final AppLogger _log;

  final StreamController<SpeechRecognitionState> _state =
      StreamController<SpeechRecognitionState>.broadcast();
  final StreamController<double> _levels = StreamController<double>.broadcast();

  bool _initialized = false;
  StreamController<SpeechTranscript>? _session;

  @override
  Stream<SpeechRecognitionState> get state => _state.stream;

  @override
  Stream<double> get soundLevel => _levels.stream;

  @override
  Future<Result<bool>> isAvailable() async {
    final Result<void> initialised = await initialize();
    return initialised.fold(
      (_) => Success<bool>(_speech.isAvailable),
      Failure<bool>.new,
    );
  }

  @override
  Future<Result<void>> initialize() async {
    if (_initialized) {
      return voidSuccess;
    }
    try {
      final bool available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: false,
      );

      if (!available) {
        _state.add(SpeechRecognitionState.unavailable);
        return const Failure<void>(
          SpeechRecognitionFailure(
            message: 'Speech recognition is not available on this device.',
            reason: SpeechFailureReason.unavailable,
          ),
        );
      }

      _initialized = true;
      _state.add(SpeechRecognitionState.ready);
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _log.error('initialize failed', error: error, stackTrace: stackTrace);
      _state.add(SpeechRecognitionState.unavailable);
      return Failure<void>(
        SpeechRecognitionFailure(
          message: 'Speech recognition could not start.',
          reason: SpeechFailureReason.unavailable,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Stream<SpeechTranscript> listen({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  }) {
    // A session already in flight is cancelled rather than rejected: the user
    // tapped the mic again, and their latest intent wins.
    unawaited(_closeSession());

    final StreamController<SpeechTranscript> controller =
        StreamController<SpeechTranscript>(
      onCancel: () async {
        await _speech.cancel();
      },
    );
    _session = controller;

    unawaited(_startSession(controller, localeId, listenFor, pauseFor));
    return controller.stream;
  }

  Future<void> _startSession(
    StreamController<SpeechTranscript> controller,
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  ) async {
    final Result<void> ready = await initialize();
    if (ready case Failure<void>(failure: final AppFailure failure)) {
      controller
        ..addError(failure)
        ..close().ignore();
      return;
    }

    try {
      _state.add(SpeechRecognitionState.listening);
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (controller.isClosed) {
            return;
          }
          controller.add(
            SpeechTranscript(
              text: result.recognizedWords,
              isFinal: result.finalResult,
              confidence: result.hasConfidenceRating ? result.confidence : null,
              alternatives: result.alternates
                  .map((SpeechRecognitionWords words) => words.recognizedWords)
                  .where((String words) => words != result.recognizedWords)
                  .toList(growable: false),
            ),
          );
          if (result.finalResult) {
            controller.close().ignore();
            _state.add(SpeechRecognitionState.ready);
          }
        },
        onSoundLevelChange: (double level) {
          if (!_levels.isClosed) {
            _levels.add(level);
          }
        },
        // Every tuning knob lives on SpeechListenOptions; the top-level
        // localeId / listenFor / pauseFor parameters are deprecated.
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          // Partial results drive the live transcript in the capture sheet.
          partialResults: true,
          // Reminder text is personal; opting out of on-server logging is the
          // right default for an offline-first app.
          onDevice: false,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          listenFor: listenFor ?? _config.speechListenTimeout,
          pauseFor: pauseFor ?? _config.speechPauseTimeout,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('listen failed', error: error, stackTrace: stackTrace);
      if (!controller.isClosed) {
        controller
          ..addError(
            SpeechRecognitionFailure(
              message: 'Could not start listening.',
              reason: SpeechFailureReason.audioError,
              cause: error,
              stackTrace: stackTrace,
            ),
          )
          ..close().ignore();
      }
      _state.add(SpeechRecognitionState.ready);
    }
  }

  @override
  Future<Result<void>> stop() async {
    return Result.guardAsync<void>(() async {
      await _speech.stop();
      _state.add(SpeechRecognitionState.processing);
    });
  }

  @override
  Future<Result<void>> cancel() async {
    return Result.guardAsync<void>(() async {
      await _speech.cancel();
      await _closeSession();
      _state.add(SpeechRecognitionState.ready);
    });
  }

  @override
  Future<Result<List<SpeechLocale>>> availableLocales() async {
    final Result<void> ready = await initialize();
    if (ready case Failure<void>(failure: final AppFailure failure)) {
      return Failure<List<SpeechLocale>>(failure);
    }
    return Result.guardAsync<List<SpeechLocale>>(() async {
      final List<stt.LocaleName> locales = await _speech.locales();
      return locales
          .map(
            (stt.LocaleName locale) =>
                SpeechLocale(id: locale.localeId, name: locale.name),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<void> dispose() async {
    await _closeSession();
    await _speech.cancel();
    await _state.close();
    await _levels.close();
  }

  void _handleStatus(String status) {
    _log.trace('Recogniser status: $status');
    switch (status) {
      case 'listening':
        _state.add(SpeechRecognitionState.listening);
      case 'notListening':
        _state.add(SpeechRecognitionState.processing);
      case 'done':
        _state.add(SpeechRecognitionState.ready);
        // `done` without a final result means the user said nothing.
        final StreamController<SpeechTranscript>? session = _session;
        if (session != null && !session.isClosed) {
          session.close().ignore();
          _session = null;
        }
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _log.warning('Recogniser error: ${error.errorMsg}');
    final StreamController<SpeechTranscript>? session = _session;
    if (session == null || session.isClosed) {
      return;
    }
    session
      ..addError(
        SpeechRecognitionFailure(
          message: _messageFor(error.errorMsg),
          reason: _reasonFor(error.errorMsg),
        ),
      )
      ..close().ignore();
    _session = null;
    _state.add(SpeechRecognitionState.ready);
  }

  Future<void> _closeSession() async {
    final StreamController<SpeechTranscript>? session = _session;
    _session = null;
    if (session != null && !session.isClosed) {
      await session.close();
    }
  }

  static SpeechFailureReason _reasonFor(String code) => switch (code) {
        'error_speech_timeout' ||
        'error_no_match' =>
          SpeechFailureReason.noSpeechDetected,
        'error_network_timeout' => SpeechFailureReason.timeout,
        'error_audio' || 'error_audio_error' => SpeechFailureReason.audioError,
        'error_client' => SpeechFailureReason.cancelled,
        _ => SpeechFailureReason.unknown,
      };

  static String _messageFor(String code) => switch (_reasonFor(code)) {
        SpeechFailureReason.noSpeechDetected =>
          "I didn't catch that. Tap the microphone and try again.",
        SpeechFailureReason.audioError =>
          'The microphone is unavailable. Close other apps using it and '
              'try again.',
        SpeechFailureReason.timeout =>
          'Listening timed out. Tap the microphone to try again.',
        SpeechFailureReason.cancelled => 'Listening was cancelled.',
        _ => 'Something went wrong while listening. Please try again.',
      };
}
