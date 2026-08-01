/// Tests for completing an incomplete voice draft.
///
/// `ParsedReminderDraft` documents that a draft is *allowed* to be incomplete
/// and that the UI asks a targeted follow-up. That follow-up did not exist:
/// "remind me to call Mom" produced a draft the sheet displayed, then disabled
/// its own Save button because `dueAt` was null, leaving the user with nothing
/// but "Try again". These tests pin the completion path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';

/// Mirrors what the sheet does once the user answers the date/time question.
ParsedReminderDraft completeWith(ParsedReminderDraft draft, DateTime dueAt) =>
    draft.copyWith(
      dueAt: dueAt,
      missingFields: draft.missingFields
          .where(
            (ParsedField field) =>
                field != ParsedField.date && field != ParsedField.time,
          )
          .toSet(),
    );

void main() {
  ParsedReminderDraft timelessDraft() => const ParsedReminderDraft(
        transcript: 'remind me to call Mom',
        title: 'Call Mom',
        confidence: 0.7,
        missingFields: <ParsedField>{ParsedField.date, ParsedField.time},
      );

  group('an incomplete draft', () {
    test('is not complete and cannot be saved as-is', () {
      final ParsedReminderDraft draft = timelessDraft();

      expect(draft.isComplete, isFalse);
      expect(draft.dueAt, isNull);
    });

    test('asks a targeted question rather than failing', () {
      expect(timelessDraft().clarificationPrompt, 'When should I remind you?');
    });

    test('asks only about the field that is missing', () {
      final ParsedReminderDraft dateOnly = timelessDraft().copyWith(
        missingFields: <ParsedField>{ParsedField.time},
      );

      expect(dateOnly.clarificationPrompt, 'What time should this be at?');
    });
  });

  group('completing the draft', () {
    test('becomes saveable once a time is supplied', () {
      final ParsedReminderDraft completed =
          completeWith(timelessDraft(), DateTime(2026, 8, 2, 19));

      expect(completed.isComplete, isTrue);
      expect(completed.dueAt, DateTime(2026, 8, 2, 19));
    });

    test('clears the fields the answer resolved', () {
      final ParsedReminderDraft completed =
          completeWith(timelessDraft(), DateTime(2026, 8, 2, 19));

      // Leaving these in place keeps `isComplete` false and re-disables Save,
      // which is precisely the dead end this path exists to remove.
      expect(completed.missingFields, isEmpty);
    });

    test('leaves unrelated missing fields alone', () {
      final ParsedReminderDraft draft = timelessDraft().copyWith(
        missingFields: <ParsedField>{
          ParsedField.date,
          ParsedField.time,
          ParsedField.title,
        },
      );

      final ParsedReminderDraft completed =
          completeWith(draft, DateTime(2026, 8, 2, 19));

      expect(completed.missingFields, <ParsedField>{ParsedField.title});
      expect(completed.isComplete, isFalse);
    });

    test('preserves everything the parser did understand', () {
      final ParsedReminderDraft draft = timelessDraft().copyWith(
        recurrence: const RecurrenceRule.daily(),
        categoryId: 'family',
      );

      final ParsedReminderDraft completed =
          completeWith(draft, DateTime(2026, 8, 2, 19));

      expect(completed.title, 'Call Mom');
      expect(completed.recurrence.isRepeating, isTrue);
      expect(completed.categoryId, 'family');
      expect(completed.transcript, 'remind me to call Mom');
    });
  });
}
