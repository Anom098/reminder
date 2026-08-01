/// State machine for the voice capture flow.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/services/speech/speech_recognition_service.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';

/// Where the capture flow currently is.
sealed class VoiceCaptureState {
  const VoiceCaptureState();
}

/// Nothing is happening; the microphone button is idle.
final class VoiceCaptureIdle extends VoiceCaptureState {
  /// Creates the idle state.
  const VoiceCaptureIdle();
}

/// Waiting for the microphone permission decision.
final class VoiceCaptureRequestingPermission extends VoiceCaptureState {
  /// Creates the permission-request state.
  const VoiceCaptureRequestingPermission();
}

/// Actively capturing audio.
final class VoiceCaptureListening extends VoiceCaptureState {
  /// Creates the listening state.
  const VoiceCaptureListening({this.transcript = '', this.soundLevel = 0});

  /// Words recognised so far.
  final String transcript;

  /// Latest sound level, for the waveform.
  final double soundLevel;
}

/// Interpreting the final transcript.
final class VoiceCaptureParsing extends VoiceCaptureState {
  /// Creates the parsing state.
  const VoiceCaptureParsing(this.transcript);

  /// The text being interpreted.
  final String transcript;
}

/// A draft is ready for review.
final class VoiceCaptureDraftReady extends VoiceCaptureState {
  /// Creates the draft-ready state.
  const VoiceCaptureDraftReady({
    required this.draft,
    required this.needsConfirmation,
  });

  /// The interpreted reminder.
  final ParsedReminderDraft draft;

  /// Whether the user should confirm before it is saved.
  final bool needsConfirmation;
}

/// Something went wrong.
final class VoiceCaptureFailed extends VoiceCaptureState {
  /// Creates the failed state.
  const VoiceCaptureFailed(this.failure);

  /// What went wrong.
  final AppFailure failure;
}

/// Drives microphone capture and command parsing.
///
/// Owns exactly one listening session at a time and always tears it down —
/// leaving the recogniser running holds the microphone open and drains the
/// battery, which users notice long before they notice a missing reminder.
final class VoiceCaptureController
    extends AutoDisposeNotifier<VoiceCaptureState> {
  StreamSubscription<SpeechTranscript>? _transcripts;
  StreamSubscription<double>? _levels;
  String _latestTranscript = '';

  @override
  VoiceCaptureState build() {
    // Captured now rather than read inside the callback: by the time disposal
    // runs, reading from the container is no longer allowed, and the
    // microphone would be left open.
    final SpeechRecognitionService recogniser =
        ref.read(speechRecognitionServiceProvider);
    ref.onDispose(() {
      unawaited(_transcripts?.cancel());
      unawaited(_levels?.cancel());
      unawaited(recogniser.cancel());
    });
    return const VoiceCaptureIdle();
  }

  /// Requests permission if needed, then starts listening.
  Future<void> start() async {
    if (state is VoiceCaptureListening) {
      return;
    }

    state = const VoiceCaptureRequestingPermission();

    final PermissionService permissions = ref.read(permissionServiceProvider);
    final Result<PermissionState> microphone =
        await permissions.request(AppPermission.microphone);

    final PermissionState micState =
        microphone.getOrElse(PermissionState.denied);
    if (!micState.isUsable) {
      state = VoiceCaptureFailed(
        PermissionFailure(
          message: micState.requiresSettings
              ? 'Microphone access is turned off. Enable it in Settings to '
                  'create reminders by voice.'
              : 'Microphone access is needed to create reminders by voice.',
          permission: 'microphone',
          isPermanentlyDenied: micState.requiresSettings,
        ),
      );
      return;
    }

    // iOS additionally gates the recogniser itself; on Android this resolves
    // to `notApplicable` and passes straight through.
    final Result<PermissionState> speech =
        await permissions.request(AppPermission.speechRecognition);
    final PermissionState speechState =
        speech.getOrElse(PermissionState.denied);
    if (!speechState.isUsable) {
      state = VoiceCaptureFailed(
        PermissionFailure(
          message: 'Speech recognition access is needed to understand what '
              'you say.',
          permission: 'speechRecognition',
          isPermanentlyDenied: speechState.requiresSettings,
        ),
      );
      return;
    }

    _latestTranscript = '';
    state = const VoiceCaptureListening();

    final SpeechRecognitionService recogniser =
        ref.read(speechRecognitionServiceProvider);

    _levels = recogniser.soundLevel.listen((double level) {
      if (state case VoiceCaptureListening(:final String transcript)) {
        state = VoiceCaptureListening(
          transcript: transcript,
          soundLevel: level,
        );
      }
    });

    _transcripts = recogniser
        .listen(localeId: ref.read(settingsSpeechLocaleProvider))
        .listen(
      (SpeechTranscript transcript) {
        _latestTranscript = transcript.text;
        if (transcript.isFinal) {
          unawaited(_interpret(transcript.text));
        } else {
          state = VoiceCaptureListening(transcript: transcript.text);
        }
      },
      onError: (Object error) {
        // Android's recogniser reports `error_no_match` / `error_speech_timeout`
        // when its pause timeout elapses — including at the natural end of a
        // *successful* dictation, once the user simply stops talking. Partial
        // results have already delivered the words, so discarding them here
        // turned a finished sentence into "I didn't catch that", and the only
        // way to succeed was to press "Done speaking" before the timeout.
        //
        // Anything we actually heard wins over the recogniser's verdict.
        if (_latestTranscript.trim().isNotEmpty) {
          unawaited(_interpret(_latestTranscript));
          return;
        }
        state = VoiceCaptureFailed(
          error is AppFailure
              ? error
              : const SpeechRecognitionFailure(
                  message: 'Listening failed. Please try again.',
                ),
        );
      },
      onDone: () {
        // The recogniser can also close without a final result. Same rule:
        // interpret whatever was heard rather than hanging or failing.
        if (state is VoiceCaptureListening) {
          unawaited(_interpret(_latestTranscript));
        }
      },
    );
  }

  /// Stops listening and interprets what was heard.
  Future<void> stop() async {
    await ref.read(speechRecognitionServiceProvider).stop();
    if (state is VoiceCaptureListening) {
      await _interpret(_latestTranscript);
    }
  }

  /// Abandons the capture without interpreting anything.
  Future<void> cancel() async {
    await _transcripts?.cancel();
    await _levels?.cancel();
    _transcripts = null;
    _levels = null;
    await ref.read(speechRecognitionServiceProvider).cancel();
    state = const VoiceCaptureIdle();
  }

  /// Interprets typed text, bypassing the microphone entirely.
  ///
  /// The same parser is used for typed and spoken input, so "remind me
  /// tomorrow at 7" behaves identically whichever way it arrives.
  Future<void> interpretText(String text) => _interpret(text);

  /// Replaces the current draft, e.g. after the user edits a field in the
  /// confirmation sheet.
  void updateDraft(ParsedReminderDraft draft) {
    state = VoiceCaptureDraftReady(
      draft: draft,
      needsConfirmation: !draft.isComplete,
    );
  }

  /// Returns to the idle state, ready for another attempt.
  void reset() => state = const VoiceCaptureIdle();

  Future<void> _interpret(String transcript) async {
    await _transcripts?.cancel();
    await _levels?.cancel();
    _transcripts = null;
    _levels = null;

    final String text = transcript.trim();
    if (text.isEmpty) {
      state = const VoiceCaptureFailed(
        SpeechRecognitionFailure(
          message: "I didn't catch that. Tap the microphone and try again.",
          reason: SpeechFailureReason.noSpeechDetected,
        ),
      );
      return;
    }

    state = VoiceCaptureParsing(text);

    final AppConfig config = ref.read(appConfigProvider);
    // Deliberately omits the transcript and title: they are user content and
    // this goes to the device log. The shape of the parse is what makes a
    // failure diagnosable, and it carries nothing personal.
    final AppLogger log = ref.read(appLoggerProvider).forContext('VoiceCapture')
      ..info('Interpreting ${text.length} characters.');

    final Result<ParsedReminderDraft> parsed =
        await ref.read(voiceCommandParserProvider).parse(
              text,
              reference: ref.read(clockProvider).now(),
            );

    state = switch (parsed) {
      Success<ParsedReminderDraft>(value: final ParsedReminderDraft draft) =>
        () {
          final bool confirm = draft.needsConfirmation(
            config.voiceParserConfidenceThreshold,
          );
          log.info(
            'Parsed: hasTitle=${draft.title.trim().isNotEmpty}, '
            'hasDueAt=${draft.dueAt != null}, '
            'repeat=${draft.recurrence.frequency.name}, '
            'confidence=${draft.confidence.toStringAsFixed(2)} '
            '(threshold ${config.voiceParserConfidenceThreshold}), '
            'missing=[${draft.missingFields.map((ParsedField f) => f.name).join(',')}], '
            'needsConfirmation=$confirm',
          );
          return VoiceCaptureDraftReady(
            draft: draft,
            needsConfirmation: confirm,
          );
        }(),
      Failure<ParsedReminderDraft>(failure: final AppFailure failure) => () {
          log.warning('Parse failed: ${failure.code} — ${failure.message}');
          return VoiceCaptureFailed(failure);
        }(),
    };
  }
}

/// The voice capture state machine.
final AutoDisposeNotifierProvider<VoiceCaptureController, VoiceCaptureState>
    voiceCaptureProvider =
    AutoDisposeNotifierProvider<VoiceCaptureController, VoiceCaptureState>(
  VoiceCaptureController.new,
  name: 'voiceCapture',
);

/// The recogniser locale the user selected, or `null` for the device default.
final Provider<String?> settingsSpeechLocaleProvider = Provider<String?>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).current.speechLocaleId,
  name: 'settingsSpeechLocale',
);
