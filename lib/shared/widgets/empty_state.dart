/// Placeholder shown when a list has nothing to display.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';

/// An illustration, a headline and an optional call to action.
///
/// Empty states name the *action that fills them*, rather than simply stating
/// that a list is empty — a blank screen with "No reminders" tells the user
/// nothing they did not already know.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.actionLabel,
    super.key,
  }) : assert(
          (action == null) == (actionLabel == null),
          'action and actionLabel must be provided together',
        );

  /// Large leading icon.
  final IconData icon;

  /// Headline.
  final String title;

  /// Supporting sentence.
  final String? message;

  /// Primary action.
  final VoidCallback? action;

  /// Label for [action].
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(Insets.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.xl),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: Insets.xl),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
