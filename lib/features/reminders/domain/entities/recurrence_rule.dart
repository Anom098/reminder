/// Recurrence model and expansion.
///
/// A [RecurrenceRule] is a *pure value*: given an anchor instant it can
/// enumerate future occurrences without touching the database, the clock or the
/// OS scheduler. That purity is what makes the scheduling behaviour of this app
/// exhaustively testable.
///
/// All arithmetic happens in local wall-clock time via
/// `DateTimeExtensions`, so a daily 09:00 reminder stays at 09:00 across
/// daylight-saving transitions instead of drifting by an hour.
library;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';

/// How often a reminder repeats.
enum RecurrenceFrequency {
  /// Fires exactly once.
  once('Once'),

  /// Repeats every `interval` hours.
  hourly('Hourly'),

  /// Repeats every `interval` days.
  daily('Daily'),

  /// Repeats every `interval` weeks on the selected weekdays.
  weekly('Weekly'),

  /// Repeats every `interval` months on the same day of month.
  monthly('Monthly'),

  /// Repeats every `interval` years on the same date.
  yearly('Yearly'),

  /// Repeats every `interval` minutes.
  ///
  /// Backs the "custom interval" option, which is also how sub-hourly
  /// reminders such as "every 20 minutes" are expressed.
  customInterval('Custom interval');

  const RecurrenceFrequency(this.label);

  /// User-facing name.
  final String label;

  /// Whether this frequency produces more than one occurrence.
  bool get isRepeating => this != RecurrenceFrequency.once;
}

/// An immutable recurrence specification.
///
/// Construct through the named constructors rather than the primary one: they
/// enforce the invariants each frequency requires (for example, that a weekly
/// rule always has at least one selected weekday).
final class RecurrenceRule extends Equatable {
  /// Creates a rule from its raw components.
  ///
  /// Prefer [RecurrenceRule.once], [RecurrenceRule.daily],
  /// [RecurrenceRule.weekly], [RecurrenceRule.monthly],
  /// [RecurrenceRule.yearly], [RecurrenceRule.hourly] or
  /// [RecurrenceRule.everyMinutes].
  const RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const <int>{},
    this.until,
    this.maxOccurrences,
  })  : assert(interval >= 1, 'interval must be at least 1'),
        assert(
          maxOccurrences == null || maxOccurrences > 0,
          'maxOccurrences must be positive when set',
        );

  /// A rule that never repeats.
  const RecurrenceRule.once()
      : frequency = RecurrenceFrequency.once,
        interval = 1,
        weekdays = const <int>{},
        until = null,
        maxOccurrences = null;

  /// Repeats every [interval] days.
  const RecurrenceRule.daily({
    this.interval = 1,
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.daily,
        weekdays = const <int>{},
        assert(interval >= 1, 'interval must be at least 1');

  /// Repeats every [interval] hours.
  const RecurrenceRule.hourly({
    this.interval = 1,
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.hourly,
        weekdays = const <int>{},
        assert(interval >= 1, 'interval must be at least 1');

  /// Repeats every [interval] minutes.
  const RecurrenceRule.everyMinutes(
    this.interval, {
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.customInterval,
        weekdays = const <int>{},
        assert(interval >= 1, 'interval must be at least 1');

  /// Repeats on the given [weekdays], every [interval] weeks.
  ///
  /// An empty [weekdays] set means "the same weekday as the reminder's start".
  const RecurrenceRule.weekly({
    this.weekdays = const <int>{},
    this.interval = 1,
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.weekly,
        assert(interval >= 1, 'interval must be at least 1');

  /// Repeats every [interval] months on the anchor's day of month.
  const RecurrenceRule.monthly({
    this.interval = 1,
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.monthly,
        weekdays = const <int>{},
        assert(interval >= 1, 'interval must be at least 1');

  /// Repeats every [interval] years on the anchor's date.
  const RecurrenceRule.yearly({
    this.interval = 1,
    this.until,
    this.maxOccurrences,
  })  : frequency = RecurrenceFrequency.yearly,
        weekdays = const <int>{},
        assert(interval >= 1, 'interval must be at least 1');

  /// Every weekday, Monday through Friday.
  factory RecurrenceRule.weekdaysOnly({
    DateTime? until,
    int? maxOccurrences,
  }) =>
      RecurrenceRule.weekly(
        weekdays: Weekdays.weekdays,
        until: until,
        maxOccurrences: maxOccurrences,
      );

  /// Saturdays and Sundays.
  factory RecurrenceRule.weekendsOnly({
    DateTime? until,
    int? maxOccurrences,
  }) =>
      RecurrenceRule.weekly(
        weekdays: Weekdays.weekend,
        until: until,
        maxOccurrences: maxOccurrences,
      );

  /// Restores a rule from its [toJson] representation.
  ///
  /// Unknown or malformed input degrades to [RecurrenceRule.once] rather than
  /// throwing: a corrupt recurrence must not make an existing reminder
  /// unopenable.
  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    final String? frequencyName = json['frequency'] as String?;
    final RecurrenceFrequency frequency = RecurrenceFrequency.values
            .where((RecurrenceFrequency f) => f.name == frequencyName)
            .firstOrNull ??
        RecurrenceFrequency.once;

    final int interval = switch (json['interval']) {
      final int value when value >= 1 => value,
      _ => 1,
    };

    final Set<int> weekdays = switch (json['weekdays']) {
      final List<dynamic> raw => raw
          .whereType<int>()
          .where((int day) => day >= DateTime.monday && day <= DateTime.sunday)
          .toSet(),
      _ => const <int>{},
    };

    final DateTime? until = switch (json['until']) {
      final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
      _ => null,
    };

    final int? maxOccurrences = switch (json['maxOccurrences']) {
      final int value when value > 0 => value,
      _ => null,
    };

    return RecurrenceRule(
      frequency: frequency,
      interval: interval,
      weekdays: weekdays,
      until: until,
      maxOccurrences: maxOccurrences,
    );
  }

  /// How the reminder repeats.
  final RecurrenceFrequency frequency;

  /// Multiplier on [frequency]; `2` with [RecurrenceFrequency.weekly] means
  /// every other week.
  final int interval;

  /// Selected weekdays (`DateTime.monday`..`DateTime.sunday`).
  ///
  /// Only meaningful for [RecurrenceFrequency.weekly]. Empty means "the
  /// anchor's own weekday".
  final Set<int> weekdays;

  /// Inclusive end date; occurrences after this instant are not produced.
  final DateTime? until;

  /// Total number of occurrences to produce, counting the anchor itself.
  final int? maxOccurrences;

  /// Whether this rule produces more than one occurrence.
  bool get isRepeating => frequency.isRepeating;

  /// Whether the rule stops on its own.
  bool get hasEnd => until != null || maxOccurrences != null;

  /// The next occurrence strictly after [after], or `null` when exhausted.
  ///
  /// [anchor] is the reminder's original due instant; it defines the
  /// wall-clock time and, for monthly/yearly rules, the day of the month that
  /// every occurrence inherits.
  DateTime? nextOccurrence({
    required DateTime anchor,
    required DateTime after,
  }) {
    for (final DateTime occurrence in occurrences(anchor: anchor)) {
      if (occurrence.isAfter(after)) {
        return occurrence;
      }
    }
    return null;
  }

  /// Lazily enumerates occurrences starting at [anchor], in ascending order.
  ///
  /// The sequence terminates when [until] or [maxOccurrences] is reached. For
  /// an unbounded rule it is infinite, so callers **must** limit it — with
  /// `take`, or by passing [limit].
  Iterable<DateTime> occurrences({
    required DateTime anchor,
    int? limit,
  }) sync* {
    final int cap = <int>[
      if (limit != null) limit,
      if (maxOccurrences != null) maxOccurrences!,
    ].fold<int>(_hardIterationCap, (int a, int b) => a < b ? a : b);

    if (cap <= 0) {
      return;
    }

    if (frequency == RecurrenceFrequency.once) {
      yield anchor;
      return;
    }

    if (frequency == RecurrenceFrequency.weekly) {
      yield* _weeklyOccurrences(anchor: anchor, cap: cap);
      return;
    }

    // Each occurrence is computed from the anchor with a step count, never by
    // advancing the previous one. Iterating would compound the month-length
    // clamp: 31 Jan → 28 Feb → 28 Mar, losing the 31st permanently. Computing
    // from the anchor gives 31 Jan → 28 Feb → 31 Mar, which is what a monthly
    // reminder set on the 31st should do.
    int step = 0;
    while (step < cap) {
      final DateTime current = _advance(anchor, steps: step);
      if (until != null && current.isAfter(until!)) {
        return;
      }
      yield current;
      step++;
    }
  }

  /// Weekly expansion has to walk day-by-day within each selected week rather
  /// than simply adding `interval` weeks, because a single rule can select
  /// several weekdays.
  Iterable<DateTime> _weeklyOccurrences({
    required DateTime anchor,
    required int cap,
  }) sync* {
    final List<int> selected =
        (weekdays.isEmpty ? <int>{anchor.weekday} : weekdays).toList()..sort();

    // The rule is phased on its *first* occurrence, not on the anchor's
    // calendar week. "Every 2 weeks on Monday" created on a Saturday must start
    // on the following Monday and then skip a fortnight — not skip the Monday
    // that is two days away because it happens to fall outside week zero.
    DateTime weekStart = anchor.startOfWeek;
    final bool anchorWeekHasCandidate = selected.any(
      (int weekday) => !weekStart
          .addDays(weekday - DateTime.monday)
          .withTime(
              hour: anchor.hour, minute: anchor.minute, second: anchor.second)
          .isBefore(anchor),
    );
    if (!anchorWeekHasCandidate) {
      weekStart = weekStart.addWeeks(1);
    }

    int emitted = 0;

    while (emitted < cap) {
      for (final int weekday in selected) {
        final DateTime candidate = weekStart
            .addDays(weekday - DateTime.monday)
            .withTime(
                hour: anchor.hour,
                minute: anchor.minute,
                second: anchor.second);

        if (candidate.isBefore(anchor)) {
          continue;
        }
        if (until != null && candidate.isAfter(until!)) {
          return;
        }
        yield candidate;
        emitted++;
        if (emitted >= cap) {
          return;
        }
      }
      weekStart = weekStart.addWeeks(interval);
    }
  }

  /// Advances [from] by [steps] repetitions of this rule.
  DateTime _advance(DateTime from, {required int steps}) {
    final int amount = interval * steps;
    return switch (frequency) {
      RecurrenceFrequency.once => from,
      RecurrenceFrequency.customInterval => from.add(Duration(minutes: amount)),
      RecurrenceFrequency.hourly => from.add(Duration(hours: amount)),
      RecurrenceFrequency.daily => from.addDays(amount),
      RecurrenceFrequency.weekly => from.addWeeks(amount),
      RecurrenceFrequency.monthly => from.addMonths(amount),
      RecurrenceFrequency.yearly => from.addYears(amount),
    };
  }

  /// Human-readable summary, e.g. `Every 2 weeks on Mon, Wed`.
  String describe() {
    final String base = switch (frequency) {
      RecurrenceFrequency.once => 'Does not repeat',
      RecurrenceFrequency.customInterval =>
        interval == 1 ? 'Every minute' : 'Every $interval minutes',
      RecurrenceFrequency.hourly =>
        interval == 1 ? 'Every hour' : 'Every $interval hours',
      RecurrenceFrequency.daily =>
        interval == 1 ? 'Every day' : 'Every $interval days',
      RecurrenceFrequency.weekly => _describeWeekly(),
      RecurrenceFrequency.monthly =>
        interval == 1 ? 'Every month' : 'Every $interval months',
      RecurrenceFrequency.yearly =>
        interval == 1 ? 'Every year' : 'Every $interval years',
    };

    if (frequency == RecurrenceFrequency.once) {
      return base;
    }
    if (maxOccurrences != null) {
      return '$base, $maxOccurrences times';
    }
    if (until != null) {
      return '$base, until ${until!.day}/${until!.month}/${until!.year}';
    }
    return base;
  }

  String _describeWeekly() {
    final String cadence =
        interval == 1 ? 'Every week' : 'Every $interval weeks';
    if (weekdays.isEmpty) {
      return cadence;
    }
    if (_setEquals(weekdays, Weekdays.weekdays)) {
      return interval == 1 ? 'Every weekday' : '$cadence on weekdays';
    }
    if (_setEquals(weekdays, Weekdays.weekend)) {
      return interval == 1 ? 'Every weekend' : '$cadence at weekends';
    }
    final List<int> sorted = weekdays.toList()..sort();
    final String days = sorted.map(_weekdayShortName).join(', ');
    return '$cadence on $days';
  }

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  static String _weekdayShortName(int weekday) => switch (weekday) {
        DateTime.monday => 'Mon',
        DateTime.tuesday => 'Tue',
        DateTime.wednesday => 'Wed',
        DateTime.thursday => 'Thu',
        DateTime.friday => 'Fri',
        DateTime.saturday => 'Sat',
        DateTime.sunday => 'Sun',
        _ => '?',
      };

  /// Returns a copy with the given fields replaced.
  ///
  /// [until] and [maxOccurrences] are nullable, so explicit `clear` flags are
  /// used to distinguish "leave unchanged" from "set to null".
  RecurrenceRule copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    Set<int>? weekdays,
    DateTime? until,
    int? maxOccurrences,
    bool clearUntil = false,
    bool clearMaxOccurrences = false,
  }) =>
      RecurrenceRule(
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        until: clearUntil ? null : (until ?? this.until),
        maxOccurrences: clearMaxOccurrences
            ? null
            : (maxOccurrences ?? this.maxOccurrences),
      );

  /// Serialises this rule for storage in the reminder row.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'frequency': frequency.name,
        'interval': interval,
        if (weekdays.isNotEmpty) 'weekdays': (weekdays.toList()..sort()),
        if (until != null) 'until': until!.millisecondsSinceEpoch,
        if (maxOccurrences != null) 'maxOccurrences': maxOccurrences,
      };

  /// Safety valve so that a bug in a caller cannot spin forever inside the
  /// generator. No legitimate call site needs more occurrences than this.
  static const int _hardIterationCap = 5000;

  @override
  List<Object?> get props => <Object?>[
        frequency,
        interval,
        // Sets compare unordered under Equatable only if normalised.
        (weekdays.toList()..sort()).join(','),
        until,
        maxOccurrences,
      ];

  @override
  String toString() => 'RecurrenceRule(${describe()})';
}
