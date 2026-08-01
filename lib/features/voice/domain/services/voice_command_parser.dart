/// Natural-language command parsing contract.
///
/// Two implementations are anticipated. The shipping one is a deterministic
/// rule-based parser that runs entirely offline. A language-model parser can be
/// added later behind the same interface; `CompositeVoiceCommandParser` in the
/// data layer already handles falling back from one to the other.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';

/// Turns a sentence into a [ParsedReminderDraft].
abstract interface class VoiceCommandParser {
  /// Whether this parser can run right now.
  ///
  /// A model-backed parser reports `false` when its model is not downloaded, so
  /// the composite can fall through to the rule-based one without a round trip.
  Future<bool> isAvailable();

  /// Interprets [transcript] relative to [reference].
  ///
  /// [reference] is "now" as far as relative expressions are concerned —
  /// "tomorrow", "in 20 minutes", "next Monday" all resolve against it. It is
  /// passed in rather than read from a clock so that parsing is deterministic
  /// and testable.
  ///
  /// Returns a [ParsedReminderDraft] even when fields are missing; a
  /// `ParsingFailure` is reserved for input that yields nothing usable at all.
  Future<Result<ParsedReminderDraft>> parse(
    String transcript, {
    required DateTime reference,
  });
}
