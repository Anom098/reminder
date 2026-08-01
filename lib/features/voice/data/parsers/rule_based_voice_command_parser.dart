/// Deterministic, fully offline natural-language command parser.
///
/// ### How it works
///
/// The transcript is matched against an ordered set of patterns. Each match
/// contributes a piece of structure (a recurrence, a date, a time, a priority)
/// and *masks out* the characters it consumed. Whatever survives the masking is
/// the reminder's title.
///
/// Masking rather than deleting is what lets the title keep its original
/// capitalisation and word order: "Remind me to call Mom tomorrow at 7 PM"
/// yields the title `call Mom`, not `call mom`.
///
/// Order matters. Recurrence is extracted before dates, because "every Monday"
/// must not be consumed by the "next Monday" date rule; relative offsets ("in
/// 20 minutes") are extracted before clock times, because they contain numbers
/// that a time pattern would otherwise claim.
library;

import 'package:collection/collection.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/voice/data/parsers/parser_lexicon.dart';
import 'package:voice_reminder/features/voice/data/parsers/text_mask.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';
import 'package:voice_reminder/features/voice/domain/services/voice_command_parser.dart';

/// Parses English reminder commands using hand-written rules.
final class RuleBasedVoiceCommandParser implements VoiceCommandParser {
  /// Creates a parser.
  const RuleBasedVoiceCommandParser();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Result<ParsedReminderDraft>> parse(
    String transcript, {
    required DateTime reference,
  }) async {
    final String trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      return Failure<ParsedReminderDraft>(
        ParsingFailure(
          message: "I didn't catch anything. Try saying it again.",
          transcript: transcript,
          missingFields: const <ParsedField>{
            ParsedField.title,
            ParsedField.date,
            ParsedField.time,
          },
          clarificationPrompt: 'What would you like to be reminded about?',
        ),
      );
    }

    final TextMask mask = TextMask(trimmed);
    final List<String> notes = <String>[];

    final String? leadIn = _stripLeadIns(mask);
    final ReminderPriority? priority = _extractPriority(mask);
    final RecurrenceRule recurrence = _extractRecurrence(mask, reference);
    final _RelativeOffset? offset = _extractRelativeOffset(mask);
    final _DatePart? date =
        offset == null ? _extractDate(mask, reference) : null;
    final _TimePart? time = offset == null ? _extractTime(mask) : null;

    final String title = _buildTitle(mask, leadIn: leadIn);
    final Set<ParsedField> missing = <ParsedField>{};

    final DateTime? dueAt = _composeDueAt(
      reference: reference,
      offset: offset,
      date: date,
      time: time,
      recurrence: recurrence,
      missing: missing,
      notes: notes,
    );

    if (title.isEmpty) {
      missing.add(ParsedField.title);
    }

    final ParsedReminderDraft draft = ParsedReminderDraft(
      transcript: trimmed,
      title: title,
      dueAt: dueAt,
      recurrence: recurrence,
      priority: priority,
      categoryId: _inferCategory(trimmed),
      confidence: _score(
        hasTitle: title.isNotEmpty,
        hasExplicitTime: time != null || offset != null,
        hasExplicitDate: date != null || offset != null,
        hasRecurrence: recurrence.isRepeating,
      ),
      missingFields: missing,
      interpretationNotes: notes,
    );

    return Success<ParsedReminderDraft>(draft);
  }

  // -- lead-ins -----------------------------------------------------------

  /// Removes command lead-ins, returning the first one that matched.
  ///
  /// The phrase is returned because some lead-ins carry the task themselves:
  /// "wake me up at seven" has no words left once "wake me up" is stripped, and
  /// the resulting reminder needs a title.
  String? _stripLeadIns(TextMask mask) {
    String? first;
    // Several may be stacked ("please remind me to"), so keep going until
    // nothing matches. Longest first, and anchored to the start, so
    // "remind me to call" does not lose the "me" from the middle of a sentence.
    bool matchedThisPass = true;
    while (matchedThisPass) {
      matchedThisPass = false;
      for (final String phrase in ParserLexicon.leadIns) {
        final RegExp pattern = RegExp(
          '^\\s*${RegExp.escape(phrase)}\\b',
          caseSensitive: false,
        );
        if (mask.maskFirst(pattern)) {
          first ??= phrase;
          matchedThisPass = true;
          break;
        }
      }
    }
    return first;
  }

  // -- priority -----------------------------------------------------------

  ReminderPriority? _extractPriority(TextMask mask) {
    for (final MapEntry<String, ReminderPriority> entry
        in ParserLexicon.priorityWords.entries) {
      final RegExp pattern = RegExp(
        '\\b${RegExp.escape(entry.key)}\\b',
        caseSensitive: false,
      );
      if (mask.maskFirst(pattern)) {
        return entry.value;
      }
    }
    return null;
  }

  // -- recurrence ---------------------------------------------------------

  RecurrenceRule _extractRecurrence(TextMask mask, DateTime reference) {
    // "every weekday" / "on weekdays"
    if (mask.maskFirst(
      RegExp(r'\b(every|each|on)\s+week\s?days?\b', caseSensitive: false),
    )) {
      return RecurrenceRule.weekdaysOnly();
    }
    if (mask.maskFirst(
      RegExp(r'\b(every|each|on|at)\s+weekends?\b', caseSensitive: false),
    )) {
      return RecurrenceRule.weekendsOnly();
    }

    // "every other <unit>"
    final RegExpMatch? otherMatch = mask.firstMatch(
      RegExp(
        r'\b(?:every|each)\s+other\s+(minute|hour|day|week|month|year)s?\b',
        caseSensitive: false,
      ),
    );
    if (otherMatch != null) {
      mask.maskMatch(otherMatch);
      return _ruleFor(unit: otherMatch.group(1)!, interval: 2);
    }

    // "every N <unit>" with the count as digits or words
    final RegExpMatch? intervalMatch = mask.firstMatch(
      RegExp(
        r'\b(?:every|each)\s+([\w\s-]{1,20}?)\s*'
        r'(minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)\b',
        caseSensitive: false,
      ),
    );
    if (intervalMatch != null) {
      final String rawCount = intervalMatch.group(1)!.trim();
      final int? count = rawCount.isEmpty
          ? 1
          : int.tryParse(rawCount) ?? ParserLexicon.parseNumberWords(rawCount);
      if (count != null && count > 0) {
        mask.maskMatch(intervalMatch);
        return _ruleFor(unit: intervalMatch.group(2)!, interval: count);
      }
    }

    // "every <weekday>" / "every Monday and Thursday"
    final RegExpMatch? weekdayMatch = mask.firstMatch(
      RegExp(
        r'\b(?:every|each)\s+((?:'
        r'monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
        r'mon|tues|tue|weds|wed|thurs|thur|thu|fri|sat|sun'
        r')(?:\s*(?:,|and|&)\s*(?:'
        r'monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
        r'mon|tues|tue|weds|wed|thurs|thur|thu|fri|sat|sun'
        r'))*)\b',
        caseSensitive: false,
      ),
    );
    if (weekdayMatch != null) {
      final Set<int> days = _weekdaysIn(weekdayMatch.group(1)!);
      if (days.isNotEmpty) {
        mask.maskMatch(weekdayMatch);
        return RecurrenceRule.weekly(weekdays: days);
      }
    }

    // Bare adverbs: "daily", "hourly", "weekly", "monthly", "yearly".
    const Map<String, RecurrenceFrequency> adverbs =
        <String, RecurrenceFrequency>{
      'hourly': RecurrenceFrequency.hourly,
      'daily': RecurrenceFrequency.daily,
      'weekly': RecurrenceFrequency.weekly,
      'fortnightly': RecurrenceFrequency.weekly,
      'monthly': RecurrenceFrequency.monthly,
      'yearly': RecurrenceFrequency.yearly,
      'annually': RecurrenceFrequency.yearly,
    };
    for (final MapEntry<String, RecurrenceFrequency> entry in adverbs.entries) {
      if (mask.maskFirst(
        RegExp('\\b${entry.key}\\b', caseSensitive: false),
      )) {
        final int interval = entry.key == 'fortnightly' ? 2 : 1;
        return RecurrenceRule(frequency: entry.value, interval: interval);
      }
    }

    // "every day" / "every morning" — the time-of-day word is left in place so
    // the time extractor can still use it.
    if (mask.maskFirst(
      RegExp(r'\b(?:every|each)\s+day\b', caseSensitive: false),
    )) {
      return const RecurrenceRule.daily();
    }
    if (mask.maskFirst(
        RegExp(r'\b(?:every|each)\s+hour\b', caseSensitive: false))) {
      return const RecurrenceRule.hourly();
    }
    if (mask.firstMatch(
          RegExp(
            r'\b(?:every|each)\s+(?:morning|afternoon|evening|night)\b',
            caseSensitive: false,
          ),
        ) !=
        null) {
      mask.maskFirst(RegExp(r'\b(?:every|each)\s+', caseSensitive: false));
      return const RecurrenceRule.daily();
    }

    return const RecurrenceRule.once();
  }

  RecurrenceRule _ruleFor({required String unit, required int interval}) {
    final String normalised =
        unit.toLowerCase().endsWith('s') && unit.length > 3
            ? unit.toLowerCase().substring(0, unit.length - 1)
            : unit.toLowerCase();

    return switch (normalised) {
      'minute' => RecurrenceRule.everyMinutes(interval),
      'hour' => RecurrenceRule.hourly(interval: interval),
      'day' => RecurrenceRule.daily(interval: interval),
      'week' => RecurrenceRule.weekly(interval: interval),
      'month' => RecurrenceRule.monthly(interval: interval),
      'year' => RecurrenceRule.yearly(interval: interval),
      _ => const RecurrenceRule.once(),
    };
  }

  Set<int> _weekdaysIn(String text) {
    final Set<int> days = <int>{};
    for (final RegExpMatch match
        in RegExp(r'[a-z]+', caseSensitive: false).allMatches(text)) {
      final int? weekday =
          ParserLexicon.weekdayNames[match.group(0)!.toLowerCase()];
      if (weekday != null) {
        days.add(weekday);
      }
    }
    return days;
  }

  // -- relative offsets ---------------------------------------------------

  _RelativeOffset? _extractRelativeOffset(TextMask mask) {
    final RegExpMatch? match = mask.firstMatch(
      RegExp(
        r'\bin\s+(?:(\d{1,4})|([a-z\s-]{1,20}?))\s*'
        r'(minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks)\b',
        caseSensitive: false,
      ),
    );
    if (match == null) {
      return null;
    }

    final String? digits = match.group(1);
    final int? amount = digits != null
        ? int.tryParse(digits)
        : ParserLexicon.parseNumberWords(match.group(2) ?? '');
    if (amount == null || amount <= 0) {
      return null;
    }

    mask.maskMatch(match);
    final String unit = match.group(3)!.toLowerCase();
    return _RelativeOffset(
      switch (unit) {
        'minute' || 'minutes' || 'min' || 'mins' => Duration(minutes: amount),
        'hour' || 'hours' || 'hr' || 'hrs' => Duration(hours: amount),
        'day' || 'days' => Duration(days: amount),
        _ => Duration(days: amount * 7),
      },
    );
  }

  // -- dates --------------------------------------------------------------

  _DatePart? _extractDate(TextMask mask, DateTime reference) {
    if (mask.maskFirst(
      RegExp(r'\bday\s+after\s+tomorrow\b', caseSensitive: false),
    )) {
      return _DatePart(reference.addDays(2));
    }
    if (mask.maskFirst(RegExp(r'\btomorrow\b', caseSensitive: false))) {
      return _DatePart(reference.addDays(1));
    }
    if (mask.maskFirst(RegExp(r'\byesterday\b', caseSensitive: false))) {
      // Accepted so the word does not leak into the title; the composer will
      // report it as unusable because reminders cannot be created in the past.
      return _DatePart(reference.addDays(-1));
    }
    if (mask.maskFirst(
      RegExp(r'\b(today|this\s+(?:morning|afternoon|evening))\b',
          caseSensitive: false),
    )) {
      return _DatePart(reference);
    }
    if (mask.maskFirst(RegExp(r'\btonight\b', caseSensitive: false))) {
      return _DatePart(reference, impliedTime: const (20, 0));
    }

    // "next Monday" / "this Friday" / "on Wednesday"
    final RegExpMatch? weekdayMatch = mask.firstMatch(
      RegExp(
        r'\b(?:(next|this|coming|on)\s+)?('
        r'monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
        r'mon|tues|tue|weds|wed|thurs|thur|thu|fri|sat|sun'
        r')\b',
        caseSensitive: false,
      ),
    );
    if (weekdayMatch != null) {
      final int? weekday =
          ParserLexicon.weekdayNames[weekdayMatch.group(2)!.toLowerCase()];
      if (weekday != null) {
        mask.maskMatch(weekdayMatch);
        final String qualifier = weekdayMatch.group(1)?.toLowerCase() ?? '';
        // "this Friday" can mean today when today *is* Friday; "next Friday"
        // never does.
        final bool inclusive =
            qualifier == 'this' || qualifier == 'on' || qualifier.isEmpty;
        return _DatePart(
          reference.nextWeekday(weekday, inclusive: inclusive),
        );
      }
    }

    // "next week" / "next month" / "next year"
    final RegExpMatch? nextUnit = mask.firstMatch(
      RegExp(r'\bnext\s+(week|month|year)\b', caseSensitive: false),
    );
    if (nextUnit != null) {
      mask.maskMatch(nextUnit);
      return _DatePart(
        switch (nextUnit.group(1)!.toLowerCase()) {
          'week' => reference.addWeeks(1),
          'month' => reference.addMonths(1),
          _ => reference.addYears(1),
        },
      );
    }

    // "on 5 August" / "on August 5th" / "on the 5th"
    final RegExpMatch? dayMonth = mask.firstMatch(
          RegExp(
            r'\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+of\s+'
            r'(january|february|march|april|may|june|july|august|september|'
            r'october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|'
            r'oct|nov|dec)\b',
            caseSensitive: false,
          ),
        ) ??
        mask.firstMatch(
          RegExp(
            r'\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+'
            r'(january|february|march|april|may|june|july|august|september|'
            r'october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|'
            r'oct|nov|dec)\b',
            caseSensitive: false,
          ),
        );
    if (dayMonth != null) {
      final int day = int.parse(dayMonth.group(1)!);
      final int? month =
          ParserLexicon.monthNames[dayMonth.group(2)!.toLowerCase()];
      if (month != null) {
        mask.maskMatch(dayMonth);
        return _DatePart(_resolveCalendarDate(reference, month, day));
      }
    }

    final RegExpMatch? monthDay = mask.firstMatch(
      RegExp(
        r'\b(?:on\s+)?'
        r'(january|february|march|april|may|june|july|august|september|'
        r'october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|'
        r'oct|nov|dec)\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\b',
        caseSensitive: false,
      ),
    );
    if (monthDay != null) {
      final int? month =
          ParserLexicon.monthNames[monthDay.group(1)!.toLowerCase()];
      final int day = int.parse(monthDay.group(2)!);
      if (month != null) {
        mask.maskMatch(monthDay);
        return _DatePart(_resolveCalendarDate(reference, month, day));
      }
    }

    // "on the 5th" — day of the current or next month.
    final RegExpMatch? dayOnly = mask.firstMatch(
      RegExp(r'\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b', caseSensitive: false),
    );
    if (dayOnly != null) {
      final int day = int.parse(dayOnly.group(1)!);
      if (day >= 1 && day <= 31) {
        mask.maskMatch(dayOnly);
        return _DatePart(
          _resolveCalendarDate(reference, reference.month, day),
        );
      }
    }

    return null;
  }

  /// Resolves a month/day pair to the next such date at or after [reference].
  DateTime _resolveCalendarDate(DateTime reference, int month, int day) {
    final int clampedDay =
        day.clamp(1, DateTime(reference.year, month + 1, 0).day);
    final DateTime candidate = DateTime(reference.year, month, clampedDay);
    if (!candidate.startOfDay.isBefore(reference.startOfDay)) {
      return candidate;
    }
    // The date has passed this year, so the user means next year.
    final int nextYearDay =
        day.clamp(1, DateTime(reference.year + 1, month + 1, 0).day);
    return DateTime(reference.year + 1, month, nextYearDay);
  }

  // -- times --------------------------------------------------------------

  _TimePart? _extractTime(TextMask mask) {
    // "at half past seven" / "at quarter to eight"
    final RegExpMatch? fractional = mask.firstMatch(
      RegExp(
        r'\b(?:at\s+)?(half|quarter)\s+(past|to)\s+'
        r'(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
        r'twelve)\b',
        caseSensitive: false,
      ),
    );
    if (fractional != null) {
      final int? base = int.tryParse(fractional.group(3)!) ??
          ParserLexicon.parseNumberWords(fractional.group(3)!);
      if (base != null && base >= 1 && base <= 12) {
        mask.maskMatch(fractional);
        final int minutes =
            fractional.group(1)!.toLowerCase() == 'half' ? 30 : 15;
        final bool past = fractional.group(2)!.toLowerCase() == 'past';
        final int hour = past ? base : (base - 1 + 12) % 12;
        return _TimePart(
          hour: hour,
          minute: past ? minutes : 60 - minutes,
          meridiemKnown: false,
        );
      }
    }

    // "at 7:30 pm", "at 7 pm", "at 19:00", "7.30am"
    final RegExpMatch? clock = mask.firstMatch(
      RegExp(
        r'\b(?:at|@)?\s*(\d{1,2})(?:[:.](\d{2}))?\s*'
        r'(a\.?m\.?|p\.?m\.?|o\W?clock)?\b',
        caseSensitive: false,
      ),
    );
    if (clock != null && _looksLikeTime(clock)) {
      mask.maskMatch(clock);
      final int rawHour = int.parse(clock.group(1)!);
      final int minute = int.tryParse(clock.group(2) ?? '') ?? 0;
      final String suffix = (clock.group(3) ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^apm]'), '');

      if (suffix.startsWith('p')) {
        return _TimePart(
          hour: rawHour == 12 ? 12 : rawHour + 12,
          minute: minute,
          meridiemKnown: true,
        );
      }
      if (suffix.startsWith('a')) {
        return _TimePart(
          hour: rawHour == 12 ? 0 : rawHour,
          minute: minute,
          meridiemKnown: true,
        );
      }
      return _TimePart(
        hour: rawHour,
        minute: minute,
        // A bare "at 7" is ambiguous; the composer resolves it to whichever of
        // 07:00 / 19:00 comes next.
        meridiemKnown: rawHour == 0 || rawHour > 12,
      );
    }

    // "at seven", "at seven thirty"
    final RegExpMatch? spelled = mask.firstMatch(
      RegExp(
        r'\bat\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
        r'twelve)(?:\s+(thirty|fifteen|forty[\s-]?five|o\W?clock))?\s*'
        r'(a\.?m\.?|p\.?m\.?)?\b',
        caseSensitive: false,
      ),
    );
    if (spelled != null) {
      final int? hour = ParserLexicon.parseNumberWords(spelled.group(1)!);
      if (hour != null) {
        mask.maskMatch(spelled);
        final String modifier = (spelled.group(2) ?? '').toLowerCase();
        final int minute = switch (modifier.replaceAll(RegExp(r'[\s-]'), '')) {
          'thirty' => 30,
          'fifteen' => 15,
          'fortyfive' => 45,
          _ => 0,
        };
        final String suffix = (spelled.group(3) ?? '').toLowerCase();
        if (suffix.startsWith('p')) {
          return _TimePart(
            hour: hour == 12 ? 12 : hour + 12,
            minute: minute,
            meridiemKnown: true,
          );
        }
        if (suffix.startsWith('a')) {
          return _TimePart(
            hour: hour == 12 ? 0 : hour,
            minute: minute,
            meridiemKnown: true,
          );
        }
        return _TimePart(hour: hour, minute: minute, meridiemKnown: false);
      }
    }

    // Named times: "in the morning", "at lunchtime", "tonight".
    for (final MapEntry<String, (int, int)> entry
        in ParserLexicon.namedTimes.entries) {
      final RegExp pattern = RegExp(
        '\\b(?:in\\s+the\\s+|at\\s+|this\\s+)?${RegExp.escape(entry.key)}\\b',
        caseSensitive: false,
      );
      if (mask.maskFirst(pattern)) {
        return _TimePart(
          hour: entry.value.$1,
          minute: entry.value.$2,
          meridiemKnown: true,
          isApproximate: true,
        );
      }
    }

    return null;
  }

  /// Rejects numbers that are obviously not clock times.
  ///
  /// Without this, "buy 3 bottles of milk" would be read as 03:00.
  bool _looksLikeTime(RegExpMatch match) {
    final int hour = int.tryParse(match.group(1) ?? '') ?? -1;
    final bool hasMinutes = match.group(2) != null;
    final bool hasSuffix = (match.group(3) ?? '').isNotEmpty;
    final bool hasAtPrefix =
        match.group(0)!.trimLeft().toLowerCase().startsWith(RegExp('at|@'));

    if (hour < 0 || hour > 23) {
      return false;
    }
    if (hasMinutes) {
      final int minute = int.tryParse(match.group(2)!) ?? 60;
      if (minute > 59) {
        return false;
      }
      return true;
    }
    // A bare number only counts as a time when something marks it as one.
    return hasSuffix || hasAtPrefix;
  }

  // -- composition --------------------------------------------------------

  DateTime? _composeDueAt({
    required DateTime reference,
    required _RelativeOffset? offset,
    required _DatePart? date,
    required _TimePart? time,
    required RecurrenceRule recurrence,
    required Set<ParsedField> missing,
    required List<String> notes,
  }) {
    if (offset != null) {
      return reference.add(offset.duration).truncatedToMinute;
    }

    // A recurrence with no date and no time still needs a first occurrence.
    if (date == null && time == null) {
      if (recurrence.isRepeating) {
        notes.add(
          'No time was given, so this starts one hour from now and repeats '
          '${recurrence.describe().toLowerCase()}.',
        );
        return reference.add(const Duration(hours: 1)).truncatedToMinute;
      }
      missing
        ..add(ParsedField.date)
        ..add(ParsedField.time);
      return null;
    }

    final DateTime day = date?.value ?? reference;
    final (int, int)? implied = date?.impliedTime;

    if (time == null && implied == null) {
      // A day with no time: default to 9 am, which is what a user who says
      // "remind me on Friday" almost always means.
      notes.add('No time was given, so 9:00 AM was used.');
      final DateTime candidate = day.withTime(hour: 9, minute: 0);
      return candidate.isAfter(reference) ? candidate : candidate.addDays(1);
    }

    final int hour = time?.hour ?? implied!.$1;
    final int minute = time?.minute ?? implied!.$2;
    DateTime candidate = day.withTime(hour: hour, minute: minute);

    if (time?.isApproximate ?? false) {
      notes.add('"${_formatHour(hour)}" was used for that time of day.');
    }

    // "Every Monday at 10" names the day through the recurrence, not the date,
    // so the first occurrence must be snapped onto a selected weekday. Doing
    // this before the AM/PM fallback also stops "at 10" being pushed to 10 PM
    // merely because 10 AM has already passed *today*.
    final bool weeklyByWeekday =
        recurrence.frequency == RecurrenceFrequency.weekly &&
            recurrence.weekdays.isNotEmpty;
    if (weeklyByWeekday && date == null) {
      final DateTime snapped =
          recurrence.occurrences(anchor: candidate, limit: 1).firstOrNull ??
              candidate;
      return snapped.truncatedToMinute;
    }

    // Resolve an ambiguous bare hour ("at 7") to whichever reading is next.
    if (time != null && !time.meridiemKnown && hour >= 1 && hour <= 12) {
      final DateTime morning = day.withTime(hour: hour, minute: minute);
      final DateTime evening = day.withTime(hour: hour + 12, minute: minute);
      if (morning.isAfter(reference)) {
        candidate = morning;
      } else if (evening.isAfter(reference)) {
        candidate = evening;
        notes.add(
          'Assumed ${_formatHour(hour + 12)} because '
          '${_formatHour(hour)} has already passed today.',
        );
      } else {
        candidate = morning.addDays(1);
        notes.add('Assumed tomorrow because that time has already passed.');
      }
      return candidate.truncatedToMinute;
    }

    if (!candidate.isAfter(reference)) {
      if (date != null) {
        // The user named a specific day that has passed. Do not silently move
        // it; ask instead.
        notes.add('That date and time have already passed.');
        missing.add(ParsedField.date);
        return null;
      }
      candidate = candidate.addDays(1);
      notes.add('Assumed tomorrow because that time has already passed today.');
    }

    return candidate.truncatedToMinute;
  }

  static String _formatHour(int hour24) {
    final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12${hour24 >= 12 ? ' PM' : ' AM'}';
  }

  // -- title & category ---------------------------------------------------

  String _buildTitle(TextMask mask, {String? leadIn}) {
    final String remainder = mask.remainder();
    final List<String> words = remainder
        .split(RegExp(r'\s+'))
        .map((String word) => word.trim())
        .where((String word) => word.isNotEmpty)
        .toList();

    // Trailing/leading filler left behind by masking ("to", "the", "and").
    while (words.isNotEmpty &&
        ParserLexicon.titleNoise.contains(words.first.toLowerCase())) {
      words.removeAt(0);
    }
    while (words.isNotEmpty &&
        ParserLexicon.titleNoise.contains(words.last.toLowerCase())) {
      words.removeLast();
    }

    final String title = words
        .join(' ')
        .replaceAll(RegExp(r'\s+([,.!?])'), r'$1')
        .replaceAll(RegExp(r'[,\s]+$'), '')
        .trim();

    if (title.isEmpty) {
      // Some lead-ins are the task: "wake me up at seven" leaves nothing behind
      // once the phrase is stripped, but the user's intent is perfectly clear.
      final String? implied = _titleFromLeadIn(leadIn);
      return implied ?? '';
    }
    // Capitalise the first letter without touching the rest, so proper nouns
    // recognised by the speech engine keep their capitals.
    return title[0].toUpperCase() + title.substring(1);
  }

  /// A title implied by the lead-in alone, or `null` when it implies nothing.
  static String? _titleFromLeadIn(String? leadIn) {
    if (leadIn == null) {
      return null;
    }
    if (leadIn.startsWith('wake me')) {
      return 'Wake up';
    }
    return null;
  }

  String? _inferCategory(String transcript) {
    final String haystack = ' ${transcript.toLowerCase()} ';
    for (final MapEntry<BuiltInCategory, List<String>> entry
        in ParserLexicon.categoryKeywords.entries) {
      for (final String keyword in entry.value) {
        if (haystack.contains(' $keyword') || haystack.contains('$keyword ')) {
          return entry.key.id;
        }
      }
    }
    return null;
  }

  // -- confidence ---------------------------------------------------------

  /// Heuristic confidence score.
  ///
  /// Weighted towards the *time*, because a reminder with the wrong title is a
  /// nuisance the user can fix, whereas one with the wrong time simply fails to
  /// do its job.
  double _score({
    required bool hasTitle,
    required bool hasExplicitTime,
    required bool hasExplicitDate,
    required bool hasRecurrence,
  }) {
    double score = 0.35;
    if (hasTitle) {
      score += 0.20;
    }
    if (hasExplicitTime) {
      score += 0.28;
    }
    if (hasExplicitDate) {
      score += 0.12;
    }
    if (hasRecurrence) {
      score += 0.05;
    }
    return score.clamp(0.0, 1.0);
  }
}

/// A duration offset extracted from "in N units".
final class _RelativeOffset {
  const _RelativeOffset(this.duration);

  final Duration duration;
}

/// A calendar day extracted from the transcript.
final class _DatePart {
  const _DatePart(this.value, {this.impliedTime});

  /// The resolved day; only its date components are meaningful.
  final DateTime value;

  /// A time the date phrase implies on its own, e.g. "tonight" → 20:00.
  final (int, int)? impliedTime;
}

/// A clock time extracted from the transcript.
final class _TimePart {
  const _TimePart({
    required this.hour,
    required this.minute,
    required this.meridiemKnown,
    this.isApproximate = false,
  });

  /// Hour in 24-hour form, or 1–12 when [meridiemKnown] is false.
  final int hour;

  /// Minute past the hour.
  final int minute;

  /// Whether AM/PM was stated or implied unambiguously.
  final bool meridiemKnown;

  /// Whether the time came from a vague phrase such as "in the morning".
  final bool isApproximate;
}
