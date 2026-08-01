/// Domain-level error descriptors.
///
/// Nothing in this application throws across a layer boundary. Operations that
/// can fail return a [Result][], and the failure arm carries an [AppFailure]
/// describing *what* went wrong in terms the presentation layer can act on —
/// never a raw platform exception.
///
/// [Result]: package:voice_reminder/core/utils/result.dart
library;

import 'package:equatable/equatable.dart';

/// Base type for every recoverable error surfaced to the domain layer.
///
/// Implementations are exhaustive and sealed, so `switch` statements over an
/// [AppFailure] are checked by the compiler. Add a new subtype only when the UI
/// genuinely needs to react differently; otherwise reuse an existing one.
sealed class AppFailure extends Equatable {
  /// Creates a failure with a user-presentable [message].
  const AppFailure({
    required this.message,
    this.cause,
    this.stackTrace,
  });

  /// Human-readable explanation, safe to show in the UI.
  ///
  /// Messages are written for end users: they say what failed and what the user
  /// can do about it, and never contain stack traces or internal identifiers.
  final String message;

  /// The originating error, retained for logging. Never shown to users.
  final Object? cause;

  /// Stack trace captured at the point of failure, retained for logging.
  final StackTrace? stackTrace;

  /// Whether retrying the identical operation could plausibly succeed.
  ///
  /// The UI uses this to decide whether to offer a "Try again" action.
  bool get isRetryable => false;

  /// Short machine-readable discriminator, used in logs and analytics.
  String get code;

  @override
  List<Object?> get props => <Object?>[code, message];

  @override
  String toString() => '$code: $message';
}

/// A read or write against the local database failed.
final class DatabaseFailure extends AppFailure {
  /// Creates a database failure.
  const DatabaseFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  bool get isRetryable => true;

  @override
  String get code => 'database_failure';
}

/// The requested record does not exist.
///
/// Distinct from [DatabaseFailure] because "not found" is an expected outcome
/// (a reminder deleted on another screen, a stale notification payload) rather
/// than a malfunction.
final class NotFoundFailure extends AppFailure {
  /// Creates a not-found failure for the entity identified by [entityId].
  const NotFoundFailure({
    required super.message,
    required this.entityId,
    super.cause,
    super.stackTrace,
  });

  /// Identifier that could not be resolved.
  final String entityId;

  @override
  String get code => 'not_found';

  @override
  List<Object?> get props => <Object?>[code, message, entityId];
}

/// User input did not satisfy a domain invariant.
final class ValidationFailure extends AppFailure {
  /// Creates a validation failure, optionally attributing errors to fields.
  const ValidationFailure({
    required super.message,
    this.fieldErrors = const <String, String>{},
    super.cause,
    super.stackTrace,
  });

  /// Field name to error message, for inline form errors.
  final Map<String, String> fieldErrors;

  @override
  String get code => 'validation_failure';

  @override
  List<Object?> get props => <Object?>[code, message, fieldErrors];
}

/// An OS permission the feature depends on was refused.
final class PermissionFailure extends AppFailure {
  /// Creates a permission failure for [permission].
  const PermissionFailure({
    required super.message,
    required this.permission,
    this.isPermanentlyDenied = false,
    super.cause,
    super.stackTrace,
  });

  /// Name of the permission, e.g. `microphone` or `notifications`.
  final String permission;

  /// Whether the OS will no longer show a prompt.
  ///
  /// When true the UI must deep-link to system settings rather than re-asking,
  /// because a second request would be silently denied.
  final bool isPermanentlyDenied;

  @override
  bool get isRetryable => !isPermanentlyDenied;

  @override
  String get code => 'permission_denied';

  @override
  List<Object?> get props =>
      <Object?>[code, message, permission, isPermanentlyDenied];
}

/// Speech-to-text capture failed or produced nothing usable.
final class SpeechRecognitionFailure extends AppFailure {
  /// Creates a speech recognition failure.
  const SpeechRecognitionFailure({
    required super.message,
    this.reason = SpeechFailureReason.unknown,
    super.cause,
    super.stackTrace,
  });

  /// Why recognition failed, so the UI can tailor its guidance.
  final SpeechFailureReason reason;

  @override
  bool get isRetryable => reason != SpeechFailureReason.unavailable;

  @override
  String get code => 'speech_recognition_failure';

  @override
  List<Object?> get props => <Object?>[code, message, reason];
}

/// Why a speech recognition attempt did not yield a transcript.
enum SpeechFailureReason {
  /// No recogniser is installed or the platform does not support one.
  unavailable,

  /// The user said nothing within the listening window.
  noSpeechDetected,

  /// Audio was captured but no words could be recognised.
  noMatch,

  /// Recognition exceeded the configured timeout.
  timeout,

  /// The recogniser could not open the microphone.
  audioError,

  /// Recognition was cancelled by the user or the app.
  cancelled,

  /// Unclassified recogniser error.
  unknown,
}

/// Text-to-speech synthesis or playback failed.
final class TextToSpeechFailure extends AppFailure {
  /// Creates a text-to-speech failure.
  const TextToSpeechFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  bool get isRetryable => true;

  @override
  String get code => 'text_to_speech_failure';
}

/// A natural-language command could not be turned into a reminder.
///
/// Carries the ambiguity back to the UI so it can ask a targeted follow-up
/// question ("Which day did you mean?") instead of a generic error.
final class ParsingFailure extends AppFailure {
  /// Creates a parsing failure describing what could not be resolved.
  const ParsingFailure({
    required super.message,
    required this.transcript,
    this.missingFields = const <ParsedField>{},
    this.clarificationPrompt,
    super.cause,
    super.stackTrace,
  });

  /// The raw text that was being parsed.
  final String transcript;

  /// Fields the parser could not extract with sufficient confidence.
  final Set<ParsedField> missingFields;

  /// A question to put to the user, when one can be phrased.
  final String? clarificationPrompt;

  @override
  bool get isRetryable => true;

  @override
  String get code => 'parsing_failure';

  @override
  List<Object?> get props =>
      <Object?>[code, message, transcript, missingFields];
}

/// Components a natural-language command can specify.
enum ParsedField {
  /// What the reminder is about.
  title,

  /// Calendar day the reminder falls on.
  date,

  /// Clock time within the day.
  time,

  /// Recurrence rule.
  repeat,
}

/// Posting, updating or cancelling an OS notification failed.
final class NotificationFailure extends AppFailure {
  /// Creates a notification failure.
  const NotificationFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  bool get isRetryable => true;

  @override
  String get code => 'notification_failure';
}

/// A reminder could not be placed on the OS schedule.
final class SchedulingFailure extends AppFailure {
  /// Creates a scheduling failure.
  const SchedulingFailure({
    required super.message,
    this.requiresExactAlarmPermission = false,
    super.cause,
    super.stackTrace,
  });

  /// Whether the failure is due to the missing exact-alarm capability.
  ///
  /// Android 12+ withholds exact alarms unless granted; when true the UI should
  /// route the user to the corresponding system settings page.
  final bool requiresExactAlarmPermission;

  @override
  bool get isRetryable => true;

  @override
  String get code => 'scheduling_failure';

  @override
  List<Object?> get props =>
      <Object?>[code, message, requiresExactAlarmPermission];
}

/// Reading or writing a file (backup, export, import) failed.
final class StorageFailure extends AppFailure {
  /// Creates a storage failure.
  const StorageFailure({
    required super.message,
    this.path,
    super.cause,
    super.stackTrace,
  });

  /// Filesystem path involved, when known.
  final String? path;

  @override
  bool get isRetryable => true;

  @override
  String get code => 'storage_failure';

  @override
  List<Object?> get props => <Object?>[code, message, path];
}

/// A backup or import payload was malformed or of an unsupported version.
final class SerializationFailure extends AppFailure {
  /// Creates a serialization failure.
  const SerializationFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  String get code => 'serialization_failure';
}

/// An error no other subtype describes.
///
/// Always logged with its [cause] and [stackTrace]; treated as a bug.
final class UnexpectedFailure extends AppFailure {
  /// Creates an unexpected failure.
  ///
  /// [message] defaults to a generic apology because, by definition, nothing
  /// specific can be said about the cause without leaking internals.
  const UnexpectedFailure({
    String message = 'Something went wrong. Please try again.',
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message: message, cause: cause, stackTrace: stackTrace);

  @override
  bool get isRetryable => true;

  @override
  String get code => 'unexpected_failure';
}
