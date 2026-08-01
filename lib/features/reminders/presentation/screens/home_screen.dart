/// The reminder list.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/presentation/controllers/reminder_list_controller.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_actions.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_card.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_filter_sheet.dart';
import 'package:voice_reminder/features/voice/presentation/widgets/voice_capture_sheet.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/empty_state.dart';

/// Shows reminders grouped into overdue, today, tomorrow, upcoming and later.
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Reminder>> reminders =
        ref.watch(reminderListProvider);
    final ReminderListQuery query = ref.watch(reminderListQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: <Widget>[
          IconButton(
            onPressed: context.goToSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Search reminders',
          ),
          _FilterButton(activeCount: query.activeFilterCount),
          IconButton(
            onPressed: context.goToSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: AsyncValueView<List<Reminder>>(
        value: reminders,
        onRetry: () => ref.invalidate(reminderListProvider),
        builder: (BuildContext context, List<Reminder> data) =>
            const _HomeBody(),
      ),
      floatingActionButton: const _HomeActions(),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<ReminderBucket, List<Reminder>> buckets =
        ref.watch(bucketedRemindersProvider);
    final ReminderListQuery query = ref.watch(reminderListQueryProvider);

    if (buckets.isEmpty) {
      return query.hasActiveFilters || query.filter.normalisedSearchTerm != null
          ? EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing matches those filters',
              message: 'Try widening your search or clearing the filters.',
              action: ref.read(reminderListQueryProvider.notifier).clearFilters,
              actionLabel: 'Clear filters',
            )
          : EmptyState(
              icon: Icons.notifications_none,
              title: 'No reminders yet',
              message:
                  'Tap the microphone and say something like "remind me to '
                  'call Mom tomorrow at 7 PM".',
              action: () => unawaited(showVoiceCaptureSheet(context)),
              actionLabel: 'Add by voice',
            );
    }

    final Map<String, ReminderCategory> categories =
        ref.watch(categoryIndexProvider).valueOrNull ??
            const <String, ReminderCategory>{};
    final DateTime now = ref.watch(clockProvider).now();

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(reminderListProvider),
      child: CustomScrollView(
        // A physics override is needed for pull-to-refresh to work on a list
        // that is shorter than the viewport.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          for (final MapEntry<ReminderBucket, List<Reminder>> entry
              in buckets.entries) ...<Widget>[
            SliverToBoxAdapter(
              child: _SectionHeader(
                bucket: entry.key,
                count: entry.value.length,
              ),
            ),
            SliverList.separated(
              itemCount: entry.value.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: Insets.sm),
              itemBuilder: (BuildContext context, int index) {
                final Reminder reminder = entry.value[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                  ),
                  child: ReminderCard(
                    reminder: reminder,
                    now: now,
                    category: reminder.categoryId == null
                        ? null
                        : categories[reminder.categoryId],
                    onTap: () => context.goToReminder(reminder.id),
                    onComplete: () => unawaited(
                      ref.reminderActions(context).complete(reminder),
                    ),
                    onSnooze: () => unawaited(
                      ref.reminderActions(context).snooze(reminder),
                    ),
                    onDelete: () => unawaited(
                      ref.reminderActions(context).delete(reminder),
                    ),
                    onToggleEnabled: (bool enabled) => unawaited(
                      ref
                          .reminderActions(context)
                          .setEnabled(reminder, enabled: enabled),
                    ),
                  ),
                );
              },
            ),
          ],
          // Clearance for the floating action buttons.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.bucket, required this.count});

  final ReminderBucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool urgent = bucket == ReminderBucket.overdue;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xl,
        Insets.lg,
        Insets.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            bucket.label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: urgent
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: Insets.sm),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Filter and sort',
      onPressed: () => unawaited(showReminderFilterSheet(context)),
      icon: Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: const Icon(Icons.tune),
      ),
    );
  }
}

class _HomeActions extends StatelessWidget {
  const _HomeActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        FloatingActionButton.small(
          heroTag: 'quick-add',
          onPressed: context.goToCreateReminder,
          tooltip: 'Add a reminder',
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: Insets.md),
        FloatingActionButton.extended(
          heroTag: 'voice-add',
          onPressed: () => unawaited(showVoiceCaptureSheet(context)),
          icon: const Icon(Icons.mic),
          label: const Text('Speak'),
        ),
      ],
    );
  }
}
