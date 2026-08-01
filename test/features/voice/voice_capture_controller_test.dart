/// Tests for [VoiceCaptureController]'s handling of the recogniser's verdict.
///
/// The case that matters here is the one a user actually hit: they finished
/// speaking and simply waited instead of pressing "Done speaking". Android's
/// recogniser then reported `error_no_match` once its pause timeout elapsed,
/// and the controller discarded a complete, correct transcript to show
/// "I didn't catch that."
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/services/speech/speech_recognition_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';
import 'package:voice_reminder/features/voice/domain/services/voice_command_parser.dart';
import 'package:voice_reminder/features/voice/presentation/controllers/voice_capture_controller.dart';

/// A recogniser whose transcript stream this test drives by hand.
final class ScriptedSpeechService implements SpeechRecognitionService {
  final StreamController<SpeechTranscript> _transcripts =
      StreamController<SpeechTranscript>();
  final StreamController<double> _levels = StreamController<double>.broadcast();
  final StreamController<SpeechRecognitionState> _state =
      StreamController<SpeechRecognitionState>.broadcast();

  /// Emits a partial result, as the recogniser does while the user speaks.
  void emitPartial(String text) =>
      _transcripts.add(SpeechTranscript(text: text, isFinal: false));

  /// Emits the error Android raises when its pause timeout elapses.
  void emitError(AppFailure failure) => _transcripts.addError(failure);

  /// Closes the session without ever sending a final result.
  Future<void> close() => _transcripts.close();

  @override
  Stream<SpeechTranscript> listen({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  }) =>
      _transcripts.stream;

  @override
  Stream<SpeechRecognitionState> get state => _state.stream;

  @override
  Stream<double> get soundLevel => _levels.stream;

  @override
  Future<Result<bool>> isAvailable() async => const Success<bool>(true);

  @override
  Future<Result<void>> initialize() async => voidSuccess;

  @override
  Future<Result<void>> stop() async => voidSuccess;

  @override
  Future<Result<void>> cancel() async => voidSuccess;

  @override
  Future<Result<List<SpeechLocale>>> availableLocales() async =>
      const Success<List<SpeechLocale>>(<SpeechLocale>[]);

  @override
  Future<void> dispose() async {
    await _levels.close();
    await _state.close();
  }
}

/// Grants everything.
final class AllowingPermissionService implements PermissionService {
  @override
  Future<Result<PermissionState>> status(AppPermission permission) async =>
      const Success<PermissionState>(PermissionState.granted);

  @override
  Future<Result<PermissionState>> request(AppPermission permission) async =>
      const Success<PermissionState>(PermissionState.granted);

  @override
  Future<Result<Map<AppPermission, PermissionState>>> statuses() async =>
      const Success<Map<AppPermission, PermissionState>>(
        <AppPermission, PermissionState>{},
      );

  @override
  Future<Result<Map<AppPermission, PermissionState>>> requestAll(
    List<AppPermission> permissions,
  ) async =>
      const Success<Map<AppPermission, PermissionState>>(
        <AppPermission, PermissionState>{},
      );

  @override
  Future<Result<bool>> openSettings() async => const Success<bool>(true);

  @override
  Future<Result<bool>> openPermissionSettings(AppPermission permission) async =>
      const Success<bool>(true);
}

/// Records what it was asked to parse and returns a fixed draft.
final class RecordingParser implements VoiceCommandParser {
  final List<String> parsed = <String>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Result<ParsedReminderDraft>> parse(
    String transcript, {
    required DateTime reference,
  }) async {
    parsed.add(transcript);
    return Success<ParsedReminderDraft>(
      ParsedReminderDraft(
        transcript: transcript,
        title: 'Call Mom',
        confidence: 0.9,
        dueAt: reference.add(const Duration(hours: 1)),
      ),
    );
  }
}

void main() {
  late ScriptedSpeechService speech;
  late RecordingParser parser;
  late ProviderContainer container;

  setUp(() {
    speech = ScriptedSpeechService();
    parser = RecordingParser();
    container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(const AppConfig()),
        appLoggerProvider.overrideWithValue(const NoopLogger()),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1, 9))),
        permissionServiceProvider
            .overrideWithValue(AllowingPermissionService()),
        speechRecognitionServiceProvider.overrideWithValue(speech),
        voiceCommandParserProvider.overrideWithValue(parser),
        settingsSpeechLocaleProvider.overrideWithValue(null),
      ],
    )
      // The provider is autoDispose: without a listener it is torn down
      // between reads and every assertion would see a fresh VoiceCaptureIdle.
      ..listen<VoiceCaptureState>(
        voiceCaptureProvider,
        (_, __) {},
        fireImmediately: true,
      );
  });

  tearDown(() {
    container.dispose();
    speech.dispose();
  });

  /// Lets the controller's pending futures settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a recogniser error after real speech still creates a draft', () async {
    final VoiceCaptureController controller =
        container.read(voiceCaptureProvider.notifier);

    await controller.start();
    speech.emitPartial('remind me to call Mom at 7 pm');
    await settle();

    // Exactly what Android sends when the user stops talking and waits.
    speech.emitError(
      const SpeechRecognitionFailure(
        message: "I didn't catch that. Tap the microphone and try again.",
        reason: SpeechFailureReason.noSpeechDetected,
      ),
    );
    await settle();

    expect(
      container.read(voiceCaptureProvider),
      isA<VoiceCaptureDraftReady>(),
      reason: 'words were heard, so the recogniser verdict must not win',
    );
    expect(parser.parsed, <String>['remind me to call Mom at 7 pm']);
  });

  test('a recogniser error with nothing heard still fails', () async {
    final VoiceCaptureController controller =
        container.read(voiceCaptureProvider.notifier);

    await controller.start();
    speech.emitError(
      const SpeechRecognitionFailure(
        message: "I didn't catch that. Tap the microphone and try again.",
        reason: SpeechFailureReason.noSpeechDetected,
      ),
    );
    await settle();

    // The message is correct when it is actually true.
    expect(container.read(voiceCaptureProvider), isA<VoiceCaptureFailed>());
    expect(parser.parsed, isEmpty);
  });

  test('the stream closing after speech interprets what was heard', () async {
    final VoiceCaptureController controller =
        container.read(voiceCaptureProvider.notifier);

    await controller.start();
    speech.emitPartial('buy milk tomorrow');
    await settle();
    await speech.close();
    await settle();

    expect(container.read(voiceCaptureProvider), isA<VoiceCaptureDraftReady>());
    expect(parser.parsed, <String>['buy milk tomorrow']);
  });

  test('pressing "Done speaking" still works', () async {
    final VoiceCaptureController controller =
        container.read(voiceCaptureProvider.notifier);

    await controller.start();
    speech.emitPartial('call the dentist');
    await settle();
    await controller.stop();
    await settle();

    expect(container.read(voiceCaptureProvider), isA<VoiceCaptureDraftReady>());
    expect(parser.parsed, <String>['call the dentist']);
  });

  test('the transcript is interpreted once, not twice', () async {
    final VoiceCaptureController controller =
        container.read(voiceCaptureProvider.notifier);

    await controller.start();
    speech.emitPartial('water the plants');
    await settle();

    // Android often sends the error and *then* closes the stream.
    speech.emitError(
      const SpeechRecognitionFailure(
        message: 'no match',
        reason: SpeechFailureReason.noSpeechDetected,
      ),
    );
    await settle();
    await speech.close();
    await settle();

    expect(parser.parsed, hasLength(1));
  });
}
