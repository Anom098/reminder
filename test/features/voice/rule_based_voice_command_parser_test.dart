import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/voice/data/parsers/rule_based_voice_command_parser.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';

void main() {
  const RuleBasedVoiceCommandParser parser = RuleBasedVoiceCommandParser();

  // Friday 31 July 2026, 14:00. A mid-afternoon weekday reference exercises
  // both the "already passed today" and "still to come today" branches.
  final DateTime reference = DateTime(2026, 7, 31, 14);

  Future<ParsedReminderDraft> parse(String transcript) async {
    final Result<ParsedReminderDraft> result =
        await parser.parse(transcript, reference: reference);
    expect(result.isSuccess, isTrue, reason: 'parsing "$transcript" failed');
    return (result as Success<ParsedReminderDraft>).value;
  }

  group('title extraction', () {
    test('strips the lead-in and keeps original capitalisation', () async {
      final ParsedReminderDraft draft =
          await parse('Remind me to call Mom tomorrow at 7 PM');

      expect(draft.title, 'Call Mom');
    });

    test('strips stacked lead-ins', () async {
      final ParsedReminderDraft draft =
          await parse('Please remind me to water the plants tomorrow');

      expect(draft.title, 'Water the plants');
    });

    test('removes filler left behind by masking', () async {
      final ParsedReminderDraft draft =
          await parse('remind me in 20 minutes to check the oven');

      expect(draft.title, 'Check the oven');
    });

    test('derives a title from a lead-in that is itself the task', () async {
      final ParsedReminderDraft draft =
          await parse('wake me up tomorrow at six');

      expect(draft.title, 'Wake up');
      expect(draft.dueAt, DateTime(2026, 8, 1, 6));
    });
  });

  group('absolute times', () {
    test('resolves "tomorrow at 7 PM"', () async {
      final ParsedReminderDraft draft =
          await parse('Remind me to call Mom tomorrow at 7 PM');

      expect(draft.dueAt, DateTime(2026, 8, 1, 19));
      expect(draft.recurrence, const RecurrenceRule.once());
      expect(draft.isComplete, isTrue);
    });

    test('resolves a 24-hour time', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to join the standup tomorrow at 09:15');

      expect(draft.dueAt, DateTime(2026, 8, 1, 9, 15));
    });

    test('rolls a time that has already passed today into tomorrow', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to stretch at 9 am');

      expect(draft.dueAt, DateTime(2026, 8, 1, 9));
      expect(
        draft.interpretationNotes.join(),
        contains('already passed'),
      );
    });

    test('a bare hour resolves to whichever reading comes next', () async {
      // 10 AM has passed at 14:00, so "at 10" means 10 PM today.
      final ParsedReminderDraft draft = await parse('remind me to read at 10');

      expect(draft.dueAt, DateTime(2026, 7, 31, 22));

      // 5 PM is still ahead, so "at 5" means 17:00 rather than tomorrow.
      final ParsedReminderDraft later = await parse('remind me to leave at 5');
      expect(later.dueAt, DateTime(2026, 7, 31, 17));
    });

    test('resolves "half past seven"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to leave at half past seven');

      expect(draft.dueAt, DateTime(2026, 7, 31, 19, 30));
    });

    test('resolves a named time of day', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to take the bins out tomorrow morning');

      expect(draft.dueAt, DateTime(2026, 8, 1, 9));
    });

    test('resolves a calendar date', () async {
      final ParsedReminderDraft draft =
          await parse('remind me about the dentist on 12 August at 9:30');

      expect(draft.dueAt, DateTime(2026, 8, 12, 9, 30));
      expect(draft.title, 'Dentist');
    });

    test('resolves "next Monday"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to send the report next Monday at 10 am');

      expect(draft.dueAt, DateTime(2026, 8, 3, 10));
    });
  });

  group('relative offsets', () {
    test('resolves "in 20 minutes"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me in 20 minutes to check the oven');

      expect(draft.dueAt, DateTime(2026, 7, 31, 14, 20));
    });

    test('resolves a spelled-out offset', () async {
      final ParsedReminderDraft draft =
          await parse('remind me in two hours to call the plumber');

      expect(draft.dueAt, DateTime(2026, 7, 31, 16));
    });
  });

  group('recurrence', () {
    test('recognises "every hour"', () async {
      final ParsedReminderDraft draft =
          await parse('Remind me to drink water every hour');

      expect(draft.recurrence.frequency, RecurrenceFrequency.hourly);
      expect(draft.title, 'Drink water');
      // With no time given, a repeating reminder starts an hour from now.
      expect(draft.dueAt, DateTime(2026, 7, 31, 15));
    });

    test('recognises "every day at 8 am"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to take my tablets every day at 8 am');

      expect(draft.recurrence.frequency, RecurrenceFrequency.daily);
      expect(draft.dueAt, DateTime(2026, 8, 1, 8));
      expect(draft.title, 'Take my tablets');
    });

    test('recognises a custom minute interval', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to stand up every 30 minutes');

      expect(
        draft.recurrence.frequency,
        RecurrenceFrequency.customInterval,
      );
      expect(draft.recurrence.interval, 30);
    });

    test('recognises "every other week"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to put the bins out every other week');

      expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
      expect(draft.recurrence.interval, 2);
    });

    test('recognises named weekdays and snaps the first occurrence', () async {
      final ParsedReminderDraft draft =
          await parse('remind me every Monday at 10 to water the plants');

      expect(draft.recurrence.frequency, RecurrenceFrequency.weekly);
      expect(draft.recurrence.weekdays, <int>{DateTime.monday});
      expect(
        draft.dueAt,
        DateTime(2026, 8, 3, 10),
        reason: 'the first occurrence must land on the named weekday',
      );
      expect(draft.title, 'Water the plants');
    });

    test('recognises "every weekday"', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to log my hours every weekday at 5 pm');

      expect(draft.recurrence.weekdays.length, 5);
      expect(draft.recurrence.weekdays.contains(DateTime.saturday), isFalse);
    });

    test('recognises bare adverbs', () async {
      expect(
        (await parse('remind me to pay rent monthly')).recurrence.frequency,
        RecurrenceFrequency.monthly,
      );
      expect(
        (await parse('remind me to renew insurance annually'))
            .recurrence
            .frequency,
        RecurrenceFrequency.yearly,
      );
    });
  });

  group('priority and category', () {
    test('infers urgency from wording', () async {
      final ParsedReminderDraft draft =
          await parse('remind me urgently to pay the electricity bill at 5 pm');

      expect(draft.priority, ReminderPriority.urgent);
      expect(draft.categoryId, 'bills');
    });

    test('infers a category from keywords', () async {
      expect(
          (await parse('remind me to call Mom tomorrow')).categoryId, 'family');
      expect(
        (await parse('remind me to take my tablets at 8 pm')).categoryId,
        'medicine',
      );
      expect(
        (await parse('remind me to book a flight tomorrow')).categoryId,
        'travel',
      );
    });

    test('leaves priority unset when nothing implies it', () async {
      expect((await parse('remind me to read at 8 pm')).priority, isNull);
    });
  });

  group('incomplete input', () {
    test('reports the missing time rather than inventing one', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to call the bank');

      expect(draft.dueAt, isNull);
      expect(draft.isComplete, isFalse);
      expect(
        draft.missingFields,
        containsAll(<ParsedField>[ParsedField.date, ParsedField.time]),
      );
      expect(draft.clarificationPrompt, 'When should I remind you?');
    });

    test('defaults to 9 AM when only a day is given', () async {
      final ParsedReminderDraft draft =
          await parse('remind me to file the report on Wednesday');

      expect(draft.dueAt, DateTime(2026, 8, 5, 9));
      expect(draft.interpretationNotes.join(), contains('9:00 AM'));
    });

    test('fails outright on an empty transcript', () async {
      final Result<ParsedReminderDraft> result =
          await parser.parse('   ', reference: reference);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ParsingFailure>());
    });
  });

  group('confidence', () {
    test('is higher when a time was stated explicitly', () async {
      final ParsedReminderDraft precise =
          await parse('remind me to call Mom tomorrow at 7 pm');
      final ParsedReminderDraft vague = await parse('remind me to call Mom');

      expect(precise.confidence, greaterThan(vague.confidence));
      expect(precise.needsConfirmation(0.6), isFalse);
      expect(vague.needsConfirmation(0.6), isTrue);
    });
  });

  test('does not mistake an ordinary number for a time', () async {
    final ParsedReminderDraft draft =
        await parse('remind me to buy 3 bottles of milk tomorrow');

    expect(draft.title, contains('3 bottles'));
    // No clock time was given, so the 9 AM default applies rather than 03:00.
    expect(draft.dueAt, DateTime(2026, 8, 1, 9));
  });
}
