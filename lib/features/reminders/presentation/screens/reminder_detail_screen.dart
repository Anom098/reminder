/// A single reminder, with its actions.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/presentation/controllers/reminder_list_controller.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_actions.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/category_icons.dart';
import 'package:voice_reminder/shared/widgets/empty_state.dart';

/// Shows everything about one reminder.
class ReminderDetailScreen extends ConsumerWidget {
  /// Creates the detail screen for [reminderId].
  const ReminderDetailScreen({required this.reminderId, super.key});

  /// Which reminder to show.
  final String reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<Reminder?>(
      value: ref.watch(reminderProvider(reminderId)),
      onRetry: () => ref.invalidate(reminderProvider(reminderId)),
      builder: (BuildContext context, Reminder? reminder) {
        if (reminder == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.search_off,
              title: 'This reminder is gone',
              message: 'It was deleted, or the link is out of date.',
              action: () => Navigator.of(context).pop(),
              actionLabel: 'Go back',
            ),
          );
        }
        return _DetailBody(reminder: reminder);
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = ref.watch(clockProvider).now();
    final ReminderCategory? category = reminder.categoryId == null
        ? null
        : ref.watch(categoryIndexProvider).valueOrNull?[reminder.categoryId];
    final ReminderActions actions = ref.reminderActions(context);

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            tooltip: 'Edit',
            onPressed: () => context.goToEditReminder(reminder.id),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_DetailMenuAction>(
            onSelected: (_DetailMenuAction action) => unawaited(
              _handleMenu(context, ref, action),
            ),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_DetailMenuAction>>[
              const PopupMenuItem<_DetailMenuAction>(
                value: _DetailMenuAction.duplicate,
                child: ListTile(
                  leading: Icon(Icons.copy_outlined),
                  title: Text('Duplicate'),
                ),
              ),
              const PopupMenuItem<_DetailMenuAction>(
                value: _DetailMenuAction.preview,
                child: ListTile(
                  leading: Icon(Icons.volume_up_outlined),
                  title: Text('Hear it'),
                ),
              ),
              const PopupMenuItem<_DetailMenuAction>(
                value: _DetailMenuAction.share,
                child: ListTile(
                  leading: Icon(Icons.share_outlined),
                  title: Text('Share'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<_DetailMenuAction>(
                value: _DetailMenuAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Insets.lg),
        children: <Widget>[
          Text(reminder.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Insets.lg),
          Card(
            child: Column(
              children: <Widget>[
                _DetailTile(
                  icon: reminder.isOverdue(now)
                      ? Icons.warning_amber_rounded
                      : Icons.event,
                  label: 'Due',
                  value: '${Formatters.longDate(reminder.dueAt)}\n'
                      '${Formatters.time(reminder.dueAt)}',
                  emphasised: reminder.isOverdue(now),
                ),
                const Divider(height: 1),
                _DetailTile(
                  icon: Icons.repeat,
                  label: 'Repeat',
                  value: reminder.recurrence.describe(),
                ),
                const Divider(height: 1),
                _DetailTile(
                  icon: Icons.flag_outlined,
                  label: 'Priority',
                  value: reminder.priority.label,
                ),
                if (category != null) ...<Widget>[
                  const Divider(height: 1),
                  _DetailTile(
                    icon: CategoryIcons.resolve(category.iconCodePoint),
                    label: 'Category',
                    value: category.name,
                  ),
                ],
                const Divider(height: 1),
                _DetailTile(
                  icon: reminder.isSpoken
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                  label: 'Spoken',
                  value: reminder.isSpoken
                      ? '"${reminder.spokenText}"'
                      : 'Notification only',
                ),
                const Divider(height: 1),
                _DetailTile(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: reminder.status.label,
                ),
              ],
            ),
          ),
          if (reminder.notes != null) ...<Widget>[
            const SizedBox(height: Insets.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Notes', style: theme.textTheme.labelLarge),
                    const SizedBox(height: Insets.sm),
                    Text(reminder.notes!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Insets.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: reminder.isActive
                      ? () => unawaited(actions.snooze(reminder))
                      : null,
                  icon: const Icon(Icons.snooze),
                  label: const Text('Snooze'),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: reminder.status.isTerminal
                      ? null
                      : () => unawaited(actions.complete(reminder)),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          SwitchListTile(
            value: !reminder.isDisabled,
            onChanged: (bool enabled) => unawaited(
              actions.setEnabled(reminder, enabled: enabled),
            ),
            title: const Text('Reminder is on'),
            subtitle: Text(
              reminder.isDisabled
                  ? 'It will not alert you until you turn it back on.'
                  : 'It will alert you at the time above.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    _DetailMenuAction action,
  ) async {
    final ReminderActions actions = ref.reminderActions(context);
    switch (action) {
      case _DetailMenuAction.duplicate:
        await actions.duplicate(reminder);
      case _DetailMenuAction.preview:
        await actions.preview(reminder);
      case _DetailMenuAction.share:
        await Share.share(
          '${reminder.title}\n'
          '${Formatters.dateAndTime(reminder.dueAt)}'
          '${reminder.recurrence.isRepeating ? '\n${reminder.recurrence.describe()}' : ''}'
          '${reminder.notes == null ? '' : '\n\n${reminder.notes}'}',
          subject: reminder.title,
        );
      case _DetailMenuAction.delete:
        await actions.delete(reminder);
        // The reminder is gone, so this screen has nothing left to show.
        if (context.mounted) {
          Navigator.of(context).pop();
        }
    }
  }
}

enum _DetailMenuAction { duplicate, preview, share, delete }

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: emphasised ? theme.colorScheme.error : null,
      ),
      title: Text(label, style: theme.textTheme.labelMedium),
      subtitle: Text(
        value,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: emphasised ? theme.colorScheme.error : null,
        ),
      ),
    );
  }
}
