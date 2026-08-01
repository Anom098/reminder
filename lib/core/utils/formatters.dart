/// Presentation-layer formatting of dates, times and durations.
///
/// Every helper takes an explicit [Clock] or reference instant rather than
/// calling `DateTime.now()`, so that "Today" / "Tomorrow" labels are testable
/// and stay correct across a midnight rollover while a screen is open.
library;

import 'package:intl/intl.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';

/// Formats domain values for display.
abstract final class Formatters {
  /// `Mon, 4 Aug` — a compact date without the year.
  static String shortDate(DateTime value, {String? locale}) =>
      DateFormat('EEE, d MMM', locale).format(value);

  /// `Monday, 4 August 2026` — a full, screen-reader friendly date.
  static String longDate(DateTime value, {String? locale}) =>
      DateFormat.yMMMMEEEEd(locale).format(value);

  /// `7:00 PM` or `19:00`, following the locale's convention.
  static String time(DateTime value, {String? locale}) =>
      DateFormat.jm(locale).format(value);

  /// `Mon, 4 Aug · 7:00 PM`.
  static String dateAndTime(DateTime value, {String? locale}) =>
      '${shortDate(value, locale: locale)} · ${time(value, locale: locale)}';

  /// A date label relative to [now]: `Today`, `Tomorrow`, `Yesterday`, or a
  /// short date for anything further away.
  static String relativeDate(
    DateTime value,
    DateTime now, {
    String? locale,
  }) {
    final DateTime today = now.startOfDay;
    final int dayDelta = value.startOfDay.difference(today).inDays;

    return switch (dayDelta) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      // Within the coming week the weekday alone is unambiguous and reads
      // better than a date.
      > 1 && < 7 => DateFormat.EEEE(locale).format(value),
      _ => value.year == now.year
          ? DateFormat('d MMM', locale).format(value)
          : DateFormat('d MMM y', locale).format(value),
    };
  }

  /// A due-time label such as `Today · 7:00 PM` or `in 20 minutes`.
  ///
  /// Within the next hour a countdown is far more useful than a clock time,
  /// which is why the two forms are mixed.
  static String dueLabel(DateTime due, DateTime now, {String? locale}) {
    final Duration delta = due.difference(now);

    if (delta.isNegative) {
      return '${relativeDate(due, now, locale: locale)} · '
          '${time(due, locale: locale)}';
    }
    if (delta < const Duration(minutes: 1)) {
      return 'in less than a minute';
    }
    if (delta < const Duration(hours: 1)) {
      return 'in ${plural(delta.inMinutes, 'minute')}';
    }
    return '${relativeDate(due, now, locale: locale)} · '
        '${time(due, locale: locale)}';
  }

  /// A compact duration such as `5 min`, `1 h 30 min` or `2 days`.
  static String duration(Duration value) {
    if (value.inMinutes < 60) {
      return '${value.inMinutes} min';
    }
    if (value.inHours < 24) {
      final int minutes = value.inMinutes.remainder(60);
      return minutes == 0
          ? '${value.inHours} h'
          : '${value.inHours} h $minutes min';
    }
    return plural(value.inDays, 'day');
  }

  /// `1 minute` / `5 minutes` — naive English pluralisation.
  ///
  /// Adequate for the fixed vocabulary used here (minute, hour, day, reminder).
  /// Replace with ICU messages when the app is localised.
  static String plural(int count, String singular, {String? pluralForm}) =>
      count == 1
          ? '$count $singular'
          : '$count ${pluralForm ?? '${singular}s'}';

  /// `mon`, `tue`, … for the compact weekday selector.
  static String weekdayAbbreviation(int weekday, {String? locale}) {
    // 2024-01-01 was a Monday, so this maps 1..7 onto the right dates.
    final DateTime reference = DateTime(2024, 1, weekday);
    return DateFormat.E(locale).format(reference);
  }

  /// Filename-safe timestamp, e.g. `20260804-190000`.
  static String fileTimestamp(DateTime value) =>
      DateFormat('yyyyMMdd-HHmmss').format(value);
}
