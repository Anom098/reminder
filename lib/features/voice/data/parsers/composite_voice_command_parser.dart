/// Chains parsers so a richer one can be added without touching call sites.
library;

import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';
import 'package:voice_reminder/features/voice/domain/services/voice_command_parser.dart';

/// Tries [primary] first and falls back to [fallback].
///
/// This is the seam a language-model parser plugs into. The fallback is the
/// rule-based parser, which is always available, so voice capture keeps working
/// offline and while a model is downloading, unavailable or simply worse than
/// the rules for a given phrasing.
///
/// The fallback is used when the primary is unavailable, fails outright, or
/// returns a draft below [confidenceFloor] — a low-confidence model answer is
/// not obviously better than a deterministic one.
final class CompositeVoiceCommandParser implements VoiceCommandParser {
  /// Creates a composite parser.
  const CompositeVoiceCommandParser({
    required VoiceCommandParser primary,
    required VoiceCommandParser fallback,
    required AppLogger logger,
    this.confidenceFloor = 0.4,
  })  : _primary = primary,
        _fallback = fallback,
        _log = logger;

  /// Builds a composite from configuration.
  ///
  /// With [VoiceParserStrategy.ruleBased] the primary *is* the fallback, so the
  /// composite collapses to a single parser with no extra indirection at
  /// runtime.
  factory CompositeVoiceCommandParser.fromConfig({
    required AppConfig config,
    required VoiceCommandParser ruleBased,
    required AppLogger logger,
    VoiceCommandParser? llm,
  }) {
    final VoiceCommandParser primary =
        config.voiceParser == VoiceParserStrategy.llm && llm != null
            ? llm
            : ruleBased;

    return CompositeVoiceCommandParser(
      primary: primary,
      fallback: ruleBased,
      logger: logger.forContext('VoiceParser'),
    );
  }

  final VoiceCommandParser _primary;
  final VoiceCommandParser _fallback;
  final AppLogger _log;

  /// Confidence below which the fallback's answer is preferred.
  final double confidenceFloor;

  @override
  Future<bool> isAvailable() async =>
      await _primary.isAvailable() || await _fallback.isAvailable();

  @override
  Future<Result<ParsedReminderDraft>> parse(
    String transcript, {
    required DateTime reference,
  }) async {
    if (identical(_primary, _fallback)) {
      return _primary.parse(transcript, reference: reference);
    }

    if (await _primary.isAvailable()) {
      final Result<ParsedReminderDraft> result =
          await _primary.parse(transcript, reference: reference);

      switch (result) {
        case Success<ParsedReminderDraft>(value: final ParsedReminderDraft d)
            when d.confidence >= confidenceFloor:
          return result;
        case Success<ParsedReminderDraft>(value: final ParsedReminderDraft d):
          _log.debug(
            'Primary parser returned ${d.confidence.toStringAsFixed(2)} '
            'confidence; trying the fallback.',
          );
        case Failure<ParsedReminderDraft>():
          _log.debug('Primary parser failed; trying the fallback.');
      }
    }

    return _fallback.parse(transcript, reference: reference);
  }
}
