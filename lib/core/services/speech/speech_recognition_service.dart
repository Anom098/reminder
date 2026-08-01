/// Speech-to-text contract.
///
/// Two implementations are anticipated: the platform recogniser (shipping) and
/// a bundled Whisper model (future). Call sites depend only on this interface,
/// so swapping engines is a provider override.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// A partial or final transcription.
final class SpeechTranscript extends Equatable {
  /// Creates a transcript.
  const SpeechTranscript({
    required this.text,
    required this.isFinal,
    this.confidence,
    this.alternatives = const <String>[],
  });

  /// An empty, non-final transcript.
  static const SpeechTranscript empty =
      SpeechTranscript(text: '', isFinal: false);

  /// Recognised words.
  final String text;

  /// Whether the recogniser considers this its final answer.
  final bool isFinal;

  /// Recogniser confidence in `0.0`–`1.0`, when reported.
  ///
  /// iOS frequently reports `null`, so nothing may depend on this being
  /// present.
  final double? confidence;

  /// Lower-ranked hypotheses, best first.
  ///
  /// Retained so the parser can retry against an alternative when the top
  /// hypothesis yields no date or time.
  final List<String> alternatives;

  /// Whether any words were recognised.
  bool get hasText => text.trim().isNotEmpty;

  @override
  List<Object?> get props => <Object?>[text, isFinal, confidence, alternatives];
}

/// The recogniser's current state.
enum SpeechRecognitionState {
  /// Not initialised, or initialisation failed.
  unavailable,

  /// Ready to listen.
  ready,

  /// Capturing audio.
  listening,

  /// Finishing up after listening stopped.
  processing,
}

/// A locale the recogniser supports.
final class SpeechLocale extends Equatable {
  /// Creates a locale descriptor.
  const SpeechLocale({required this.id, required this.name});

  /// Platform identifier, e.g. `en_GB`.
  final String id;

  /// Display name, e.g. `English (United Kingdom)`.
  final String name;

  @override
  List<Object?> get props => <Object?>[id, name];
}

/// Converts speech to text.
abstract interface class SpeechRecognitionService {
  /// The recogniser's state.
  Stream<SpeechRecognitionState> get state;

  /// Live sound level in decibels, for the waveform animation.
  ///
  /// Emits nothing on platforms that do not report levels; the UI must degrade
  /// to a non-reactive animation rather than assuming values arrive.
  Stream<double> get soundLevel;

  /// Whether the device has a usable recogniser.
  Future<Result<bool>> isAvailable();

  /// Prepares the recogniser and requests permission if needed.
  Future<Result<void>> initialize();

  /// Captures a single utterance.
  ///
  /// Emits partial transcripts as the user speaks and a final one when they
  /// stop. The stream closes after the final transcript, or on error. Listening
  /// stops automatically after [listenFor], or after [pauseFor] of silence.
  Stream<SpeechTranscript> listen({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  });

  /// Stops listening and keeps whatever was recognised.
  Future<Result<void>> stop();

  /// Stops listening and discards the result.
  Future<Result<void>> cancel();

  /// Lists supported locales.
  Future<Result<List<SpeechLocale>>> availableLocales();

  /// Releases recogniser resources.
  Future<void> dispose();
}
