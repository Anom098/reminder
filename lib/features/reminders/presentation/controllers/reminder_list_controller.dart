/// Presentation state for reminder lists.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';

/// The filter and sort currently applied to the home list.
///
/// Held as a single value so a screen rebuild reads one provider, and so
/// "clear all filters" is a single assignment rather than several.
final class ReminderListQuery {
  /// Creates a query.
  const ReminderListQuery({
    this.filter = ReminderFilter.none,
    this.sort = ReminderSort.dueDateAscending,
    this.showCompleted = false,
  });

  /// Active criteria.
  final ReminderFilter filter;

  /// Ordering.
  final ReminderSort sort;

  /// Whether completed and finished reminders appear in the list.
  final bool showCompleted;

  /// Whether anything is narrowing the list.
  bool get hasActiveFilters =>
      filter.categoryIds.isNotEmpty ||
      filter.priorities.isNotEmpty ||
      filter.dueRange != null ||
      showCompleted;

  /// How many filter dimensions are active, for the badge on the filter button.
  int get activeFilterCount =>
      (filter.categoryIds.isEmpty ? 0 : 1) +
      (filter.priorities.isEmpty ? 0 : 1) +
      (filter.dueRange == null ? 0 : 1);

  /// Returns a copy with the given fields replaced.
  ReminderListQuery copyWith({
    ReminderFilter? filter,
    ReminderSort? sort,
    bool? showCompleted,
  }) =>
      ReminderListQuery(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        showCompleted: showCompleted ?? this.showCompleted,
      );
}

/// Owns the home screen's filter and sort.
final class ReminderListController extends Notifier<ReminderListQuery> {
  @override
  ReminderListQuery build() => const ReminderListQuery();

  /// Replaces the free-text search term.
  void setSearchTerm(String? term) {
    final String? trimmed = term?.trim();
    state = state.copyWith(
      filter: (trimmed == null || trimmed.isEmpty)
          ? state.filter.copyWith(clearSearchTerm: true)
          : state.filter.copyWith(searchTerm: trimmed),
    );
  }

  /// Replaces the ordering.
  void setSort(ReminderSort sort) => state = state.copyWith(sort: sort);

  /// Adds or removes [categoryId] from the category filter.
  void toggleCategory(String categoryId) {
    final Set<String> next = Set<String>.of(state.filter.categoryIds);
    if (!next.remove(categoryId)) {
      next.add(categoryId);
    }
    state = state.copyWith(filter: state.filter.copyWith(categoryIds: next));
  }

  /// Replaces the priority filter.
  void setPriorities(Set<ReminderPriority> priorities) => state =
      state.copyWith(filter: state.filter.copyWith(priorities: priorities));

  /// Restricts the list to reminders due within [range], or clears the
  /// restriction when [range] is `null`.
  void setDueRange(DateRange? range) => state = state.copyWith(
        filter: range == null
            ? state.filter.copyWith(clearDueRange: true)
            : state.filter.copyWith(dueRange: range),
      );

  /// Shows or hides completed reminders.
  void setShowCompleted({required bool show}) =>
      state = state.copyWith(showCompleted: show);

  /// Clears every filter, keeping the sort and the search term.
  void clearFilters() => state = ReminderListQuery(
        sort: state.sort,
        filter: ReminderFilter(searchTerm: state.filter.searchTerm),
      );
}

/// The home list's query.
final NotifierProvider<ReminderListController, ReminderListQuery>
    reminderListQueryProvider =
    NotifierProvider<ReminderListController, ReminderListQuery>(
  ReminderListController.new,
  name: 'reminderListQuery',
);

/// Reminders matching the current query, kept live.
///
/// Completed reminders are fetched regardless of `showCompleted` and filtered
/// out during bucketing. That keeps the "Completed" section a pure display
/// toggle, with no round trip to the database when it is flipped.
final StreamProvider<List<Reminder>> reminderListProvider =
    StreamProvider<List<Reminder>>(
  (Ref ref) {
    final ReminderListQuery query = ref.watch(reminderListQueryProvider);
    return ref.watch(reminderRepositoryProvider).watchReminders(
          filter: query.filter,
          sort: query.sort,
        );
  },
  name: 'reminderList',
);

/// Reminders grouped into the home screen's time buckets.
///
/// Grouping happens here rather than in the widget so the screen stays
/// declarative and the bucketing is unit-testable.
final Provider<Map<ReminderBucket, List<Reminder>>> bucketedRemindersProvider =
    Provider<Map<ReminderBucket, List<Reminder>>>(
  (Ref ref) {
    final List<Reminder> reminders =
        ref.watch(reminderListProvider).valueOrNull ?? const <Reminder>[];
    final Clock clock = ref.watch(clockProvider);
    final DateTime now = clock.now();
    final bool showCompleted =
        ref.watch(reminderListQueryProvider).showCompleted;

    final Map<ReminderBucket, List<Reminder>> grouped =
        <ReminderBucket, List<Reminder>>{};

    for (final Reminder reminder in reminders) {
      final ReminderBucket bucket = ReminderBucket.of(reminder, now);
      if (bucket == ReminderBucket.done && !showCompleted) {
        continue;
      }
      grouped.putIfAbsent(bucket, () => <Reminder>[]).add(reminder);
    }

    // Preserve the enum's declaration order so sections always appear in the
    // same sequence regardless of which ones happen to be populated.
    return <ReminderBucket, List<Reminder>>{
      for (final ReminderBucket bucket in ReminderBucket.values)
        if (grouped[bucket]?.isNotEmpty ?? false) bucket: grouped[bucket]!,
    };
  },
  name: 'bucketedReminders',
);

/// Every selectable category, hidden ones excluded.
final StreamProvider<List<ReminderCategory>> categoriesProvider =
    StreamProvider<List<ReminderCategory>>(
  (Ref ref) => ref.watch(categoryRepositoryProvider).watchCategories(),
  name: 'categories',
);

/// Category lookup by id, including hidden categories.
final StreamProvider<Map<String, ReminderCategory>> categoryIndexProvider =
    StreamProvider<Map<String, ReminderCategory>>(
  (Ref ref) => ref
      .watch(categoryRepositoryProvider)
      .watchCategories(includeHidden: true)
      .map(
        (List<ReminderCategory> categories) => <String, ReminderCategory>{
          for (final ReminderCategory category in categories)
            category.id: category,
        },
      ),
  name: 'categoryIndex',
);

/// A single reminder, kept live.
final StreamProviderFamily<Reminder?, String> reminderProvider =
    StreamProvider.family<Reminder?, String>(
  (Ref ref, String id) =>
      ref.watch(reminderRepositoryProvider).watchReminder(id),
  name: 'reminder',
);
