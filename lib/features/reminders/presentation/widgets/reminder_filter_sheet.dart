/// Filter and sort controls for the reminder list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/presentation/controllers/reminder_list_controller.dart';
import 'package:voice_reminder/shared/widgets/category_icons.dart';

/// Opens the filter and sort sheet.
Future<void> showReminderFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ReminderListQuery query = ref.watch(reminderListQueryProvider);
    final ReminderListController controller =
        ref.read(reminderListQueryProvider.notifier);
    final List<ReminderCategory> categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ReminderCategory>[];

    return SafeArea(
      child: ConstrainedBox(
        // Cap the height so the sheet never covers the whole screen on a
        // phone, and stays scrollable when the category list is long.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Filter and sort',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (query.hasActiveFilters)
                    TextButton(
                      onPressed: controller.clearFilters,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              const _SectionLabel('Sort by'),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final ReminderSort sort in ReminderSort.values)
                    ChoiceChip(
                      label: Text(sort.label),
                      selected: query.sort == sort,
                      onSelected: (_) => controller.setSort(sort),
                    ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              const _SectionLabel('Priority'),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final ReminderPriority priority
                      in ReminderPriority.values)
                    FilterChip(
                      label: Text(priority.label),
                      selected: query.filter.priorities.contains(priority),
                      onSelected: (bool selected) {
                        final Set<ReminderPriority> next =
                            Set<ReminderPriority>.of(query.filter.priorities);
                        if (selected) {
                          next.add(priority);
                        } else {
                          next.remove(priority);
                        }
                        controller.setPriorities(next);
                      },
                    ),
                ],
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: Insets.xl),
                const _SectionLabel('Category'),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: <Widget>[
                    for (final ReminderCategory category in categories)
                      FilterChip(
                        avatar: Icon(
                          CategoryIcons.resolve(category.iconCodePoint),
                          size: 18,
                          color: Color(category.colorValue),
                        ),
                        label: Text(category.name),
                        selected:
                            query.filter.categoryIds.contains(category.id),
                        onSelected: (_) =>
                            controller.toggleCategory(category.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Insets.xl),
              const _SectionLabel('When'),
              const SizedBox(height: Insets.sm),
              const _DueRangeChips(),
              const SizedBox(height: Insets.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: query.showCompleted,
                onChanged: (bool value) =>
                    controller.setShowCompleted(show: value),
                title: const Text('Show completed'),
                subtitle: const Text(
                  'Includes reminders that are done, finished or missed.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueRangeChips extends ConsumerWidget {
  const _DueRangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReminderListQuery query = ref.watch(reminderListQueryProvider);
    final ReminderListController controller =
        ref.read(reminderListQueryProvider.notifier);
    final DateTime now = ref.watch(clockProvider).now();

    final Map<String, DateRange?> options = <String, DateRange?>{
      'Any time': null,
      'Today': DateRange.day(now),
      'Next 7 days': DateRange.fromDays(now, 7),
      'Next 30 days': DateRange.fromDays(now, 30),
    };

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: <Widget>[
        for (final MapEntry<String, DateRange?> option in options.entries)
          ChoiceChip(
            label: Text(option.key),
            selected: query.filter.dueRange == option.value,
            onSelected: (_) => controller.setDueRange(option.value),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
