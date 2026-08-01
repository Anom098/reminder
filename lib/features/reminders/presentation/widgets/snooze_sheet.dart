/// Snooze duration picker.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';

/// Asks the user how long to snooze for.
///
/// Returns the chosen duration, or `null` if the sheet was dismissed.
Future<Duration?> showSnoozeSheet(
  BuildContext context, {
  required Duration defaultSnooze,
}) {
  return showModalBottomSheet<Duration>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _SnoozeSheet(
      defaultSnooze: defaultSnooze,
    ),
  );
}

class _SnoozeSheet extends StatelessWidget {
  const _SnoozeSheet({required this.defaultSnooze});

  final Duration defaultSnooze;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The user's default is always offered first, even when it is not one of
    // the presets, so the most likely choice is the closest to the thumb.
    final List<Duration> options = <Duration>[
      defaultSnooze,
      ...AppConstants.snoozePresets.where(
        (Duration preset) => preset != defaultSnooze,
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          0,
          Insets.lg,
          Insets.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Snooze for', style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.lg),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: <Widget>[
                for (final Duration option in options)
                  ActionChip(
                    label: Text(Formatters.duration(option)),
                    onPressed: () =>
                        Navigator.of(context).pop<Duration>(option),
                  ),
              ],
            ),
            const SizedBox(height: Insets.md),
            OutlinedButton.icon(
              onPressed: () async {
                final Duration? custom = await _pickCustom(context);
                if (custom != null && context.mounted) {
                  Navigator.of(context).pop<Duration>(custom);
                }
              },
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Choose a different time'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Duration?> _pickCustom(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 1, minute: 0),
      helpText: 'Snooze for how long?',
      // The picker is used as a duration input here, so a 24-hour dial avoids
      // an AM/PM control that would make no sense for a length of time.
      builder: (BuildContext dialogContext, Widget? child) => MediaQuery(
        data:
            MediaQuery.of(dialogContext).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) {
      return null;
    }
    final Duration duration =
        Duration(hours: picked.hour, minutes: picked.minute);
    return duration < AppConstants.minSnooze
        ? AppConstants.minSnooze
        : duration;
  }
}
