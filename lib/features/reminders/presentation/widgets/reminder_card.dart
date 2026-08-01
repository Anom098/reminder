/// A single reminder in a list.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/shared/widgets/category_icons.dart';

/// Renders a reminder as a tappable card with swipe actions.
///
/// The card is the densest surface in the app, so everything on it earns its
/// place: title, due time, category, and the two state signals a user scans
/// for — overdue and muted.
class ReminderCard extends StatelessWidget {
  /// Creates a card.
  const ReminderCard({
    required this.reminder,
    required this.now,
    required this.onTap,
    this.category,
    this.onComplete,
    this.onSnooze,
    this.onDelete,
    this.onToggleEnabled,
    super.key,
  });

  /// The reminder to display.
  final Reminder reminder;

  /// The current time, injected so the "overdue" styling is testable.
  final DateTime now;

  /// The reminder's category, when it has one.
  final ReminderCategory? category;

  /// Opens the reminder.
  final VoidCallback onTap;

  /// Marks it complete. Bound to a swipe from the left.
  final VoidCallback? onComplete;

  /// Opens the snooze options. Bound to a long press.
  final VoidCallback? onSnooze;

  /// Deletes it.
  final VoidCallback? onDelete;

  /// Enables or disables it.
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool overdue = reminder.isOverdue(now);
    final bool inactive = reminder.isDisabled || reminder.status.isTerminal;

    final Color accent = Color(
      reminder.colorValue ?? category?.colorValue ?? scheme.primary.toARGB32(),
    );

    final Widget card = Card(
      child: InkWell(
        onTap: onTap,
        // Long-press is the quickest route to snooze without opening the
        // reminder; swiping is already spoken for by done and delete.
        onLongPress: onSnooze,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Leading(
                accent: accent,
                icon: category == null
                    ? Icons.notifications_none
                    : CategoryIcons.resolve(category!.iconCodePoint),
                dimmed: inactive,
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      reminder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: reminder.status == ReminderStatus.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: inactive ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: Insets.xs),
                    _Subtitle(
                      reminder: reminder,
                      now: now,
                      overdue: overdue,
                      category: category,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.sm),
              _Trailing(
                reminder: reminder,
                onToggleEnabled: onToggleEnabled,
              ),
            ],
          ),
        ),
      ),
    );

    if (onComplete == null && onDelete == null) {
      return card;
    }

    return Dismissible(
      key: ValueKey<String>('reminder-${reminder.id}'),
      // Confirmation is required in both directions: an accidental swipe on a
      // list the user is scrolling must not silently destroy or complete a
      // reminder.
      confirmDismiss: (DismissDirection direction) async {
        if (direction == DismissDirection.startToEnd) {
          onComplete?.call();
        } else {
          onDelete?.call();
        }
        // Always false: the list rebuilds from the database, so letting
        // Dismissible remove the row itself would double-remove it.
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        icon: Icons.check_circle_outline,
        label: 'Done',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.delete_outline,
        label: 'Delete',
      ),
      child: card,
    );
  }
}

class _Leading extends StatelessWidget {
  const _Leading({
    required this.accent,
    required this.icon,
    required this.dimmed,
  });

  final Color accent;
  final IconData icon;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final Color color = dimmed ? accent.withValues(alpha: 0.4) : accent;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.reminder,
    required this.now,
    required this.overdue,
    required this.category,
  });

  final Reminder reminder;
  final DateTime now;
  final bool overdue;
  final ReminderCategory? category;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<Widget> chips = <Widget>[
      _MetaChip(
        icon: overdue ? Icons.warning_amber_rounded : Icons.schedule,
        label: Formatters.dueLabel(reminder.dueAt, now),
        color: overdue ? scheme.error : scheme.onSurfaceVariant,
        emphasised: overdue,
      ),
      if (reminder.recurrence.isRepeating)
        _MetaChip(
          icon: Icons.repeat,
          label: reminder.recurrence.describe(),
          color: scheme.onSurfaceVariant,
        ),
      if (reminder.isSnoozed)
        _MetaChip(
          icon: Icons.snooze,
          label: 'Snoozed',
          color: scheme.tertiary,
        ),
      if (!reminder.isSpoken)
        _MetaChip(
          icon: Icons.volume_off_outlined,
          label: 'Silent',
          color: scheme.onSurfaceVariant,
        ),
      if (reminder.priority != ReminderPriority.normal)
        _MetaChip(
          icon: Icons.flag_outlined,
          label: reminder.priority.label,
          color: reminder.priority == ReminderPriority.low
              ? scheme.onSurfaceVariant
              : scheme.error,
        ),
      if (category != null)
        _MetaChip(
          icon: Icons.folder_outlined,
          label: category!.name,
          color: scheme.onSurfaceVariant,
        ),
    ];

    return Wrap(
      spacing: Insets.md,
      runSpacing: Insets.xs,
      children: chips,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: Insets.xs),
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: color,
            fontWeight: emphasised ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.reminder, required this.onToggleEnabled});

  final Reminder reminder;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    if (onToggleEnabled == null || reminder.status.isTerminal) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: '${reminder.title} reminder',
      child: Switch(
        value: !reminder.isDisabled,
        onChanged: onToggleEnabled,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: foreground),
          const SizedBox(width: Insets.sm),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
