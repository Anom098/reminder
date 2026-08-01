/// Calendar arithmetic used by recurrence expansion and the home screen
/// buckets.
///
/// All helpers operate on *local* time and preserve the receiver's UTC flag.
/// Recurrence must be computed in local time so that a "9:00 daily" reminder
/// stays at 9:00 across a daylight-saving transition.
library;

/// Calendar helpers on [DateTime].
extension DateTimeExtensions on DateTime {
  /// Midnight at the start of this date.
  DateTime get startOfDay =>
      isUtc ? DateTime.utc(year, month, day) : DateTime(year, month, day);

  /// The last representable instant of this date.
  DateTime get endOfDay => isUtc
      ? DateTime.utc(year, month, day, 23, 59, 59, 999, 999)
      : DateTime(year, month, day, 23, 59, 59, 999, 999);

  /// Midnight at the start of the following day.
  DateTime get startOfNextDay => startOfDay.addDays(1);

  /// Midnight on the Monday of this week.
  ///
  /// ISO-8601 week semantics: weeks begin on Monday.
  DateTime get startOfWeek => startOfDay.addDays(-(weekday - DateTime.monday));

  /// Midnight on the first day of this month.
  DateTime get startOfMonth =>
      isUtc ? DateTime.utc(year, month) : DateTime(year, month);

  /// The number of days in this date's month.
  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// The time-of-day component, as a duration since midnight.
  Duration get timeOfDay => Duration(
        hours: hour,
        minutes: minute,
        seconds: second,
        milliseconds: millisecond,
        microseconds: microsecond,
      );

  /// Whether this instant falls on the same calendar day as [other].
  bool isSameDayAs(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  /// Whether this instant falls in the same calendar month as [other].
  bool isSameMonthAs(DateTime other) =>
      year == other.year && month == other.month;

  /// Whether this instant is within `[start, end)`.
  bool isInRange(DateTime start, DateTime end) =>
      !isBefore(start) && isBefore(end);

  /// Adds [days] using calendar arithmetic.
  ///
  /// Uses the [DateTime] constructor rather than `add(Duration(days:))` so that
  /// a daylight-saving transition does not shift the wall-clock time. Adding one
  /// day to 09:00 always yields 09:00, not 08:00 or 10:00.
  DateTime addDays(int days) => _rebuild(
        year: year,
        month: month,
        day: day + days,
      );

  /// Adds [weeks], preserving wall-clock time.
  DateTime addWeeks(int weeks) => addDays(weeks * 7);

  /// Adds [months], clamping the day to the length of the target month.
  ///
  /// 31 January plus one month yields 28/29 February rather than rolling over
  /// into March, which is what users expect from a monthly reminder.
  DateTime addMonths(int months) {
    final int totalMonths = (year * 12 + (month - 1)) + months;
    final int targetYear = totalMonths ~/ 12;
    final int targetMonth = totalMonths % 12 + 1;
    final int lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
    return _rebuild(
      year: targetYear,
      month: targetMonth,
      day: day < lastDay ? day : lastDay,
    );
  }

  /// Adds [years], clamping 29 February to 28 February in non-leap years.
  DateTime addYears(int years) {
    final int targetYear = year + years;
    final int lastDay = DateTime(targetYear, month + 1, 0).day;
    return _rebuild(
      year: targetYear,
      month: month,
      day: day < lastDay ? day : lastDay,
    );
  }

  /// Returns this date with its time-of-day replaced.
  DateTime withTime({
    required int hour,
    required int minute,
    int second = 0,
  }) =>
      _rebuild(
        hour: hour,
        minute: minute,
        second: second,
        millisecond: 0,
        microsecond: 0,
      );

  /// The next occurrence of [weekday] strictly after this instant's date.
  ///
  /// When [inclusive] is true and this instant already falls on [weekday], the
  /// same date is returned.
  DateTime nextWeekday(int weekday, {bool inclusive = false}) {
    assert(
      weekday >= DateTime.monday && weekday <= DateTime.sunday,
      'weekday must be DateTime.monday..DateTime.sunday',
    );
    // Dart's `%` on positive divisors always yields a non-negative result, so
    // this lands in 0..6 regardless of which day the receiver falls on.
    int delta = (weekday - this.weekday) % 7;
    if (delta == 0 && !inclusive) {
      delta = 7;
    }
    return addDays(delta);
  }

  /// Drops sub-minute precision, which the OS schedulers ignore anyway.
  DateTime get truncatedToMinute => _rebuild(
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );

  /// Rebuilds this instant, defaulting every unspecified component to the
  /// receiver's own value and preserving its UTC flag.
  ///
  /// Out-of-range components are normalised by the [DateTime] constructor,
  /// which is what makes `day: day + n` correct across month boundaries.
  DateTime _rebuild({
    int? year,
    int? month,
    int? day,
    int? hour,
    int? minute,
    int? second,
    int? millisecond,
    int? microsecond,
  }) {
    final int y = year ?? this.year;
    final int mo = month ?? this.month;
    final int d = day ?? this.day;
    final int h = hour ?? this.hour;
    final int mi = minute ?? this.minute;
    final int s = second ?? this.second;
    final int ms = millisecond ?? this.millisecond;
    final int us = microsecond ?? this.microsecond;
    return isUtc
        ? DateTime.utc(y, mo, d, h, mi, s, ms, us)
        : DateTime(y, mo, d, h, mi, s, ms, us);
  }
}

/// Weekday helpers shared by the recurrence editor and the parser.
abstract final class Weekdays {
  /// Monday through Friday.
  static const Set<int> weekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  /// Saturday and Sunday.
  static const Set<int> weekend = <int>{DateTime.saturday, DateTime.sunday};

  /// All seven days.
  static const Set<int> all = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  };
}
