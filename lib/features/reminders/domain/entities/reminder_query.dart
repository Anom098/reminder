/// Query, filter and sort descriptors for reminder lists.
///
/// These are domain values, not SQL. The Drift repository translates them into
/// a query; an in-memory repository (used by widget tests) applies them with
/// [ReminderFilter.matches] and [ReminderSort.comparator]. Keeping both paths
/// driven by the same descriptor is what stops the two implementations from
/// diverging.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';

/// Ordering applied to a reminder list.
enum ReminderSort {
  /// Soonest first. The default for every forward-looking list.
  dueDateAscending('Due date (soonest first)'),

  /// Latest first.
  dueDateDescending('Due date (latest first)'),

  /// Most important first, then by due date.
  priorityDescending('Priority (highest first)'),

  /// Alphabetical.
  titleAscending('Title (A–Z)'),

  /// Most recently created first.
  createdDescending('Recently created');

  const ReminderSort(this.label);

  /// User-facing name.
  final String label;

  /// The comparator implementing this ordering.
  ///
  /// Every ordering falls back to due date and then to id, so that the sort is
  /// total and list positions do not jitter between rebuilds.
  Comparator<Reminder> get comparator => switch (this) {
        ReminderSort.dueDateAscending => _byDueDateAscending,
        ReminderSort.dueDateDescending => _byDueDateDescending,
        ReminderSort.priorityDescending => _byPriority,
        ReminderSort.titleAscending => _byTitle,
        ReminderSort.createdDescending => _byCreated,
      };

  static int _byDueDateAscending(Reminder a, Reminder b) {
    final int result = a.dueAt.compareTo(b.dueAt);
    return result != 0 ? result : a.id.compareTo(b.id);
  }

  static int _byDueDateDescending(Reminder a, Reminder b) =>
      -_byDueDateAscending(a, b);

  static int _byPriority(Reminder a, Reminder b) {
    final int result = b.priority.weight.compareTo(a.priority.weight);
    return result != 0 ? result : _byDueDateAscending(a, b);
  }

  static int _byTitle(Reminder a, Reminder b) {
    final int result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return result != 0 ? result : _byDueDateAscending(a, b);
  }

  static int _byCreated(Reminder a, Reminder b) {
    final int result = b.createdAt.compareTo(a.createdAt);
    return result != 0 ? result : a.id.compareTo(b.id);
  }
}

/// A half-open date range, `[start, end)`.
final class DateRange extends Equatable {
  /// Creates a range.
  const DateRange({required this.start, required this.end});

  /// A range covering the whole calendar day containing [day].
  factory DateRange.day(DateTime day) =>
      DateRange(start: day.startOfDay, end: day.startOfNextDay);

  /// A range covering [days] days starting at [from]'s midnight.
  factory DateRange.fromDays(DateTime from, int days) => DateRange(
        start: from.startOfDay,
        end: from.startOfDay.addDays(days),
      );

  /// Inclusive lower bound.
  final DateTime start;

  /// Exclusive upper bound.
  final DateTime end;

  /// Whether [value] falls inside the range.
  bool contains(DateTime value) => value.isInRange(start, end);

  @override
  List<Object?> get props => <Object?>[start, end];
}

/// Criteria narrowing a reminder list.
///
/// An empty collection means "do not filter on this dimension", which is why
/// the defaults are empty sets rather than "all values".
final class ReminderFilter extends Equatable {
  /// Creates a filter.
  const ReminderFilter({
    this.statuses = const <ReminderStatus>{},
    this.categoryIds = const <String>{},
    this.priorities = const <ReminderPriority>{},
    this.dueRange,
    this.searchTerm,
    this.includeDisabled = true,
  });

  /// No filtering at all.
  static const ReminderFilter none = ReminderFilter();

  /// Only reminders that are scheduled or snoozed.
  static const ReminderFilter active = ReminderFilter(
    statuses: <ReminderStatus>{
      ReminderStatus.scheduled,
      ReminderStatus.snoozed,
    },
    includeDisabled: false,
  );

  /// Statuses to include; empty means all.
  final Set<ReminderStatus> statuses;

  /// Category ids to include; empty means all.
  final Set<String> categoryIds;

  /// Priorities to include; empty means all.
  final Set<ReminderPriority> priorities;

  /// Restricts results to reminders due within this range.
  final DateRange? dueRange;

  /// Free-text search across title, notes and category.
  final String? searchTerm;

  /// Whether disabled reminders appear in the results.
  final bool includeDisabled;

  /// Whether any criterion is set.
  bool get isEmpty =>
      statuses.isEmpty &&
      categoryIds.isEmpty &&
      priorities.isEmpty &&
      dueRange == null &&
      (searchTerm?.trim().isEmpty ?? true) &&
      includeDisabled;

  /// The normalised search term, or `null` when blank.
  String? get normalisedSearchTerm {
    final String? trimmed = searchTerm?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Whether [reminder] satisfies every criterion.
  ///
  /// [categoryNameLookup] resolves a category id to its display name so that a
  /// search for "medicine" matches reminders in the Medicine category.
  bool matches(
    Reminder reminder, {
    String? Function(String id)? categoryNameLookup,
  }) {
    if (!includeDisabled && reminder.isDisabled) {
      return false;
    }
    if (statuses.isNotEmpty && !statuses.contains(reminder.status)) {
      return false;
    }
    if (priorities.isNotEmpty && !priorities.contains(reminder.priority)) {
      return false;
    }
    if (categoryIds.isNotEmpty &&
        (reminder.categoryId == null ||
            !categoryIds.contains(reminder.categoryId))) {
      return false;
    }
    if (dueRange != null && !dueRange!.contains(reminder.dueAt)) {
      return false;
    }

    final String? term = normalisedSearchTerm;
    if (term == null) {
      return true;
    }

    if (reminder.title.toLowerCase().contains(term)) {
      return true;
    }
    if (reminder.notes?.toLowerCase().contains(term) ?? false) {
      return true;
    }
    final String? categoryId = reminder.categoryId;
    if (categoryId != null && categoryNameLookup != null) {
      final String? categoryName = categoryNameLookup(categoryId);
      if (categoryName != null && categoryName.toLowerCase().contains(term)) {
        return true;
      }
    }
    return false;
  }

  /// Returns a copy with the given fields replaced.
  ReminderFilter copyWith({
    Set<ReminderStatus>? statuses,
    Set<String>? categoryIds,
    Set<ReminderPriority>? priorities,
    DateRange? dueRange,
    String? searchTerm,
    bool? includeDisabled,
    bool clearDueRange = false,
    bool clearSearchTerm = false,
  }) =>
      ReminderFilter(
        statuses: statuses ?? this.statuses,
        categoryIds: categoryIds ?? this.categoryIds,
        priorities: priorities ?? this.priorities,
        dueRange: clearDueRange ? null : (dueRange ?? this.dueRange),
        searchTerm: clearSearchTerm ? null : (searchTerm ?? this.searchTerm),
        includeDisabled: includeDisabled ?? this.includeDisabled,
      );

  @override
  List<Object?> get props => <Object?>[
        (statuses.map((ReminderStatus s) => s.name).toList()..sort()).join(','),
        (categoryIds.toList()..sort()).join(','),
        (priorities.map((ReminderPriority p) => p.name).toList()..sort())
            .join(','),
        dueRange,
        searchTerm,
        includeDisabled,
      ];
}

/// Time-based grouping used by the home screen.
enum ReminderBucket {
  /// Active and already past due.
  overdue('Overdue'),

  /// Due later today.
  today('Today'),

  /// Due tomorrow.
  tomorrow('Tomorrow'),

  /// Due within the next week.
  upcoming('Upcoming'),

  /// Due beyond the upcoming window.
  later('Later'),

  /// Completed, finished or missed.
  done('Completed');

  const ReminderBucket(this.label);

  /// Section heading shown in the UI.
  final String label;

  /// Classifies [reminder] relative to [now].
  static ReminderBucket of(Reminder reminder, DateTime now) {
    if (reminder.status.isTerminal ||
        reminder.status == ReminderStatus.missed) {
      return ReminderBucket.done;
    }
    if (reminder.isOverdue(now)) {
      return ReminderBucket.overdue;
    }
    if (reminder.dueAt.isSameDayAs(now)) {
      return ReminderBucket.today;
    }
    if (reminder.dueAt.isSameDayAs(now.addDays(1))) {
      return ReminderBucket.tomorrow;
    }
    if (reminder.dueAt.isBefore(now.startOfDay.addDays(7))) {
      return ReminderBucket.upcoming;
    }
    return ReminderBucket.later;
  }
}
