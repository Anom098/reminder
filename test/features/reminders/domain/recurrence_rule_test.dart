import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';

void main() {
  // A Saturday, so weekday/weekend rules are exercised from a non-Monday
  // starting point.
  final DateTime anchor = DateTime(2026, 8, 1, 9);

  group('RecurrenceRule.occurrences', () {
    test('once yields exactly the anchor', () {
      const RecurrenceRule rule = RecurrenceRule.once();

      expect(
        rule.occurrences(anchor: anchor).toList(),
        <DateTime>[anchor],
      );
    });

    test('daily advances by whole calendar days, preserving the time', () {
      const RecurrenceRule rule = RecurrenceRule.daily();

      expect(
        rule.occurrences(anchor: anchor, limit: 3).toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 2, 9),
          DateTime(2026, 8, 3, 9),
        ],
      );
    });

    test('interval multiplies the step', () {
      const RecurrenceRule rule = RecurrenceRule.daily(interval: 3);

      expect(
        rule.occurrences(anchor: anchor, limit: 3).toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 4, 9),
          DateTime(2026, 8, 7, 9),
        ],
      );
    });

    test('hourly and custom minute intervals step by duration', () {
      expect(
        const RecurrenceRule.hourly(interval: 2)
            .occurrences(anchor: anchor, limit: 3)
            .toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 1, 11),
          DateTime(2026, 8, 1, 13),
        ],
      );

      expect(
        const RecurrenceRule.everyMinutes(20)
            .occurrences(anchor: anchor, limit: 3)
            .toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 1, 9, 20),
          DateTime(2026, 8, 1, 9, 40),
        ],
      );
    });

    test('weekly with no weekdays repeats on the anchor\'s own weekday', () {
      const RecurrenceRule rule = RecurrenceRule.weekly();

      expect(
        rule.occurrences(anchor: anchor, limit: 3).toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 8, 9),
          DateTime(2026, 8, 15, 9),
        ],
      );
    });

    test('weekly expands every selected weekday within each week', () {
      final RecurrenceRule rule = RecurrenceRule.weekdaysOnly();

      // The anchor is Saturday 1 August, so the first weekday occurrence is
      // Monday 3 August — occurrences before the anchor are never produced.
      expect(
        rule.occurrences(anchor: anchor, limit: 6).toList(),
        <DateTime>[
          DateTime(2026, 8, 3, 9),
          DateTime(2026, 8, 4, 9),
          DateTime(2026, 8, 5, 9),
          DateTime(2026, 8, 6, 9),
          DateTime(2026, 8, 7, 9),
          DateTime(2026, 8, 10, 9),
        ],
      );
    });

    test('weekly honours a multi-week interval', () {
      const RecurrenceRule rule = RecurrenceRule.weekly(
        weekdays: <int>{DateTime.monday},
        interval: 2,
      );

      expect(
        rule.occurrences(anchor: anchor, limit: 3).toList(),
        <DateTime>[
          DateTime(2026, 8, 3, 9),
          DateTime(2026, 8, 17, 9),
          DateTime(2026, 8, 31, 9),
        ],
      );
    });

    test('monthly clamps to the last day of shorter months', () {
      const RecurrenceRule rule = RecurrenceRule.monthly();
      final DateTime endOfJanuary = DateTime(2026, 1, 31, 8);

      expect(
        rule.occurrences(anchor: endOfJanuary, limit: 3).toList(),
        <DateTime>[
          DateTime(2026, 1, 31, 8),
          DateTime(2026, 2, 28, 8),
          DateTime(2026, 3, 31, 8),
        ],
        reason: '31 January + 1 month must not roll over into March',
      );
    });

    test('yearly clamps 29 February in non-leap years', () {
      const RecurrenceRule rule = RecurrenceRule.yearly();
      final DateTime leapDay = DateTime(2028, 2, 29, 8);

      expect(
        rule.occurrences(anchor: leapDay, limit: 2).toList(),
        <DateTime>[
          DateTime(2028, 2, 29, 8),
          DateTime(2029, 2, 28, 8),
        ],
      );
    });

    test('maxOccurrences bounds the sequence', () {
      const RecurrenceRule rule = RecurrenceRule.daily(maxOccurrences: 2);

      expect(rule.occurrences(anchor: anchor).length, 2);
    });

    test('until bounds the sequence inclusively', () {
      final RecurrenceRule rule = RecurrenceRule.daily(
        until: DateTime(2026, 8, 3, 9),
      );

      expect(
        rule.occurrences(anchor: anchor).toList(),
        <DateTime>[
          DateTime(2026, 8, 1, 9),
          DateTime(2026, 8, 2, 9),
          DateTime(2026, 8, 3, 9),
        ],
      );
    });

    test('an unbounded rule is still capped, so it cannot hang a caller', () {
      const RecurrenceRule rule = RecurrenceRule.hourly();

      expect(rule.occurrences(anchor: anchor).length, lessThanOrEqualTo(5000));
    });
  });

  group('RecurrenceRule.nextOccurrence', () {
    test('returns the first occurrence strictly after the reference', () {
      const RecurrenceRule rule = RecurrenceRule.daily();

      expect(
        rule.nextOccurrence(anchor: anchor, after: DateTime(2026, 8, 2, 9)),
        DateTime(2026, 8, 3, 9),
        reason: 'an occurrence equal to the reference is not "after" it',
      );
    });

    test('returns null once the rule is exhausted', () {
      final RecurrenceRule rule = RecurrenceRule.daily(
        until: DateTime(2026, 8, 2, 9),
      );

      expect(
        rule.nextOccurrence(anchor: anchor, after: DateTime(2026, 8, 2, 9)),
        isNull,
      );
    });
  });

  group('RecurrenceRule serialisation', () {
    test('round-trips through JSON', () {
      final RecurrenceRule rule = RecurrenceRule.weekly(
        weekdays: <int>{DateTime.monday, DateTime.thursday},
        interval: 2,
        until: DateTime(2027, 1, 1),
      );

      expect(RecurrenceRule.fromJson(rule.toJson()), rule);
    });

    test('degrades to `once` rather than throwing on malformed input', () {
      expect(
        RecurrenceRule.fromJson(<String, dynamic>{'frequency': 'nonsense'}),
        const RecurrenceRule.once(),
      );
      expect(
        RecurrenceRule.fromJson(<String, dynamic>{}),
        const RecurrenceRule.once(),
      );
    });

    test('rejects out-of-range weekday values', () {
      final RecurrenceRule rule = RecurrenceRule.fromJson(
        <String, dynamic>{
          'frequency': 'weekly',
          'weekdays': <dynamic>[1, 99, 'x', 5],
        },
      );

      expect(rule.weekdays, <int>{1, 5});
    });
  });

  group('RecurrenceRule.describe', () {
    test('names the common cadences in plain English', () {
      expect(const RecurrenceRule.once().describe(), 'Does not repeat');
      expect(const RecurrenceRule.daily().describe(), 'Every day');
      expect(
        const RecurrenceRule.daily(interval: 3).describe(),
        'Every 3 days',
      );
      expect(RecurrenceRule.weekdaysOnly().describe(), 'Every weekday');
      expect(RecurrenceRule.weekendsOnly().describe(), 'Every weekend');
      expect(
        const RecurrenceRule.weekly(
          weekdays: <int>{DateTime.monday, DateTime.wednesday},
        ).describe(),
        'Every week on Mon, Wed',
      );
    });
  });

  group('DateTimeExtensions', () {
    test('addDays preserves the wall-clock time', () {
      expect(
        DateTime(2026, 3, 28, 9, 30).addDays(2),
        DateTime(2026, 3, 30, 9, 30),
      );
    });

    test('startOfWeek lands on Monday', () {
      expect(
        DateTime(2026, 8, 1, 9).startOfWeek,
        DateTime(2026, 7, 27),
      );
    });

    test('nextWeekday can include today', () {
      final DateTime saturday = DateTime(2026, 8, 1, 9);

      expect(
        saturday.nextWeekday(DateTime.saturday, inclusive: true),
        saturday,
      );
      expect(
        saturday.nextWeekday(DateTime.saturday),
        DateTime(2026, 8, 8, 9),
      );
    });
  });
}
