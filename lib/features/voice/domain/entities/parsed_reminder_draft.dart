/// The structured result of interpreting a spoken or typed command.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';

/// A candidate reminder extracted from natural language.
///
/// A draft is explicitly allowed to be *incomplete*: "remind me to call Mom"
/// has a title but no time. The UI inspects [missingFields] and asks a targeted
/// follow-up rather than rejecting the utterance.
final class ParsedReminderDraft extends Equatable {
  /// Creates a draft.
  const ParsedReminderDraft({
    required this.transcript,
    required this.title,
    required this.confidence,
    this.dueAt,
    this.recurrence = const RecurrenceRule.once(),
    this.priority,
    this.categoryId,
    this.missingFields = const <ParsedField>{},
    this.interpretationNotes = const <String>[],
  }) : assert(
          confidence >= 0 && confidence <= 1,
          'confidence must be within 0.0..1.0',
        );

  /// The text that was interpreted.
  final String transcript;

  /// The extracted task, with time and command words removed.
  final String title;

  /// When the reminder should fire, if a time could be resolved.
  final DateTime? dueAt;

  /// The recurrence detected, or [RecurrenceRule.once].
  final RecurrenceRule recurrence;

  /// Priority inferred from urgency words, or `null` when none were present.
  final ReminderPriority? priority;

  /// Category inferred from keywords, or `null`.
  final String? categoryId;

  /// Overall confidence in `0.0`–`1.0`.
  ///
  /// Compared against `AppConfig.voiceParserConfidenceThreshold` to decide
  /// between saving directly and showing a confirmation sheet.
  final double confidence;

  /// Fields that could not be resolved.
  final Set<ParsedField> missingFields;

  /// Human-readable notes about assumptions the parser made, e.g.
  /// `Assumed tomorrow because 7 PM has already passed today.`
  ///
  /// Surfaced in the confirmation sheet so the user can see *why* the app chose
  /// a particular time.
  final List<String> interpretationNotes;

  /// Whether the draft has everything needed to create a reminder.
  bool get isComplete =>
      title.trim().isNotEmpty && dueAt != null && missingFields.isEmpty;

  /// Whether the draft should be confirmed by the user before saving.
  bool needsConfirmation(double threshold) =>
      !isComplete || confidence < threshold;

  /// A question to put to the user about the first unresolved field.
  ///
  /// Returns `null` when nothing needs clarifying.
  String? get clarificationPrompt {
    if (title.trim().isEmpty) {
      return 'What should the reminder say?';
    }
    if (missingFields.contains(ParsedField.date) &&
        missingFields.contains(ParsedField.time)) {
      return 'When should I remind you?';
    }
    if (missingFields.contains(ParsedField.date)) {
      return 'Which day should this be on?';
    }
    if (missingFields.contains(ParsedField.time)) {
      return 'What time should this be at?';
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  ParsedReminderDraft copyWith({
    String? transcript,
    String? title,
    DateTime? dueAt,
    RecurrenceRule? recurrence,
    ReminderPriority? priority,
    String? categoryId,
    double? confidence,
    Set<ParsedField>? missingFields,
    List<String>? interpretationNotes,
    bool clearDueAt = false,
    bool clearPriority = false,
    bool clearCategoryId = false,
  }) =>
      ParsedReminderDraft(
        transcript: transcript ?? this.transcript,
        title: title ?? this.title,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        recurrence: recurrence ?? this.recurrence,
        priority: clearPriority ? null : (priority ?? this.priority),
        categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
        confidence: confidence ?? this.confidence,
        missingFields: missingFields ?? this.missingFields,
        interpretationNotes: interpretationNotes ?? this.interpretationNotes,
      );

  @override
  List<Object?> get props => <Object?>[
        transcript,
        title,
        dueAt,
        recurrence,
        priority,
        categoryId,
        confidence,
        (missingFields.map((ParsedField f) => f.name).toList()..sort())
            .join(','),
      ];

  @override
  String toString() => 'ParsedReminderDraft("$title", due: $dueAt, '
      'repeat: ${recurrence.frequency.name}, '
      'confidence: ${confidence.toStringAsFixed(2)})';
}
