/// Vocabulary used by the rule-based parser.
///
/// Kept apart from the parsing logic so the two can be reviewed — and
/// localised — independently. Every entry is lowercase; the parser lowercases
/// its input before matching.
library;

import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';

/// Word lists and lookup tables for English command parsing.
abstract final class ParserLexicon {
  /// Phrases that introduce a command and carry no meaning themselves.
  ///
  /// Ordered longest-first so that "remind me to" is stripped before
  /// "remind me".
  static const List<String> leadIns = <String>[
    'can you please remind me to',
    'can you please remind me',
    'could you please remind me to',
    'please could you remind me to',
    'can you remind me to',
    'could you remind me to',
    'i want you to remind me to',
    'i need you to remind me to',
    'set up a reminder to',
    'set up a reminder for',
    'create a reminder to',
    'create a reminder for',
    'add a reminder to',
    'add a reminder for',
    'set a reminder to',
    'set a reminder for',
    'make a reminder to',
    'remind me that i need to',
    'remind me that i have to',
    'remind me to',
    'remind me about',
    'remind me',
    'reminder to',
    'reminder for',
    'reminder',
    "don't forget to",
    'dont forget to',
    'do not forget to',
    'i need to',
    'i have to',
    'i must',
    'wake me up',
    'wake me',
    'alert me to',
    'alert me',
    'notify me to',
    'notify me',
    'ping me to',
    'ping me',
    'please',
  ];

  /// Filler words removed from the extracted title.
  static const Set<String> titleNoise = <String>{
    'to',
    'the',
    'a',
    'an',
    'please',
    'and',
    'that',
    'i',
  };

  /// Spelled-out numbers the parser understands, including informal forms.
  static const Map<String, int> numberWords = <String, int>{
    'zero': 0,
    'one': 1,
    'won': 1,
    'two': 2,
    'to': 2,
    'too': 2,
    'three': 3,
    'four': 4,
    'for': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'ate': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'ninety': 90,
    'hundred': 100,
  };

  /// Weekday names and common abbreviations.
  static const Map<String, int> weekdayNames = <String, int>{
    'monday': DateTime.monday,
    'mon': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'tues': DateTime.tuesday,
    'tue': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'weds': DateTime.wednesday,
    'wed': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'thurs': DateTime.thursday,
    'thur': DateTime.thursday,
    'thu': DateTime.thursday,
    'friday': DateTime.friday,
    'fri': DateTime.friday,
    'saturday': DateTime.saturday,
    'sat': DateTime.saturday,
    'sunday': DateTime.sunday,
    'sun': DateTime.sunday,
  };

  /// Month names and abbreviations.
  static const Map<String, int> monthNames = <String, int>{
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  /// Named times of day, as (hour, minute) pairs.
  ///
  /// These are the defaults applied when a day is given without a clock time —
  /// "remind me tomorrow morning".
  static const Map<String, (int, int)> namedTimes = <String, (int, int)>{
    'midnight': (0, 0),
    'early morning': (6, 0),
    'morning': (9, 0),
    'noon': (12, 0),
    'midday': (12, 0),
    'lunchtime': (12, 30),
    'lunch': (12, 30),
    'afternoon': (15, 0),
    'evening': (18, 30),
    'dinner': (19, 0),
    'dinnertime': (19, 0),
    'tonight': (20, 0),
    'night': (21, 0),
    'bedtime': (22, 0),
  };

  /// Words implying an elevated priority.
  static const Map<String, ReminderPriority> priorityWords =
      <String, ReminderPriority>{
    'urgent': ReminderPriority.urgent,
    'urgently': ReminderPriority.urgent,
    'asap': ReminderPriority.urgent,
    'critical': ReminderPriority.urgent,
    'emergency': ReminderPriority.urgent,
    'important': ReminderPriority.high,
    'importantly': ReminderPriority.high,
    'high priority': ReminderPriority.high,
    'must': ReminderPriority.high,
    'whenever': ReminderPriority.low,
    'sometime': ReminderPriority.low,
    'low priority': ReminderPriority.low,
    'no rush': ReminderPriority.low,
  };

  /// Keywords that map an utterance onto a built-in category.
  ///
  /// First match wins, so more specific words are listed first within each
  /// category's entry.
  static const Map<BuiltInCategory, List<String>> categoryKeywords =
      <BuiltInCategory, List<String>>{
    BuiltInCategory.medicine: <String>[
      'medicine',
      'medication',
      'tablet',
      'tablets',
      'pill',
      'pills',
      'dose',
      'insulin',
      'inhaler',
      'vitamin',
      'vitamins',
      'doctor',
      'dentist',
      'appointment',
      'prescription',
      'antibiotic',
    ],
    BuiltInCategory.bills: <String>[
      'bill',
      'bills',
      'rent',
      'mortgage',
      'invoice',
      'payment',
      'pay ',
      'subscription',
      'renew',
      'renewal',
      'insurance',
      'tax',
      'taxes',
      'electricity',
      'broadband',
    ],
    BuiltInCategory.workout: <String>[
      'workout',
      'exercise',
      'gym',
      'run',
      'running',
      'jog',
      'yoga',
      'stretch',
      'walk',
      'steps',
      'training',
      'swim',
      'cycle',
    ],
    BuiltInCategory.study: <String>[
      'study',
      'revise',
      'revision',
      'homework',
      'assignment',
      'exam',
      'lecture',
      'course',
      'read chapter',
      'practice',
      'flashcards',
    ],
    BuiltInCategory.office: <String>[
      'meeting',
      'standup',
      'stand-up',
      'deadline',
      'report',
      'email',
      'client',
      'presentation',
      'interview',
      'review',
      'timesheet',
      'invoice client',
    ],
    BuiltInCategory.family: <String>[
      'mom',
      'mum',
      'mother',
      'dad',
      'father',
      'grandma',
      'grandpa',
      'granny',
      'wife',
      'husband',
      'son',
      'daughter',
      'kids',
      'school run',
      'birthday',
      'anniversary',
    ],
    BuiltInCategory.shopping: <String>[
      'buy',
      'shopping',
      'groceries',
      'grocery',
      'supermarket',
      'order',
      'milk',
      'bread',
      'pick up',
      'collect',
    ],
    BuiltInCategory.travel: <String>[
      'flight',
      'train',
      'bus',
      'airport',
      'station',
      'check in',
      'check-in',
      'passport',
      'visa',
      'hotel',
      'booking',
      'taxi',
      'pack',
    ],
    BuiltInCategory.personal: <String>[
      'water',
      'drink',
      'hydrate',
      'meditate',
      'meditation',
      'journal',
      'call',
      'text',
      'message',
      'haircut',
    ],
  };

  /// Converts a spelled-out number to a digit, or `null` when unrecognised.
  ///
  /// Handles the compound forms speech recognisers produce for clock times,
  /// e.g. `twenty five`.
  static int? parseNumberWords(String input) {
    final List<String> tokens = input
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty && token != 'and')
        .toList();

    if (tokens.isEmpty) {
      return null;
    }

    int total = 0;
    bool matched = false;
    for (final String token in tokens) {
      final int? value = numberWords[token];
      if (value == null) {
        return null;
      }
      matched = true;
      if (value == 100) {
        total = (total == 0 ? 1 : total) * 100;
      } else {
        total += value;
      }
    }
    return matched ? total : null;
  }
}
