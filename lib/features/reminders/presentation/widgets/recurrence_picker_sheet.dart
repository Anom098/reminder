/// Recurrence editor.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';

/// Opens the recurrence editor, returning the chosen rule.
///
/// Returns `null` when dismissed without a change.
Future<RecurrenceRule?> showRecurrencePicker(
  BuildContext context, {
  required RecurrenceRule initial,
  required DateTime anchor,
}) {
  return showModalBottomSheet<RecurrenceRule>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _RecurrencePicker(
      initial: initial,
      anchor: anchor,
    ),
  );
}

class _RecurrencePicker extends StatefulWidget {
  const _RecurrencePicker({required this.initial, required this.anchor});

  final RecurrenceRule initial;
  final DateTime anchor;

  @override
  State<_RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<_RecurrencePicker> {
  late RecurrenceRule _rule = widget.initial;
  late final TextEditingController _interval =
      TextEditingController(text: '${widget.initial.interval}');

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Repeat', style: theme.textTheme.titleMedium),
              const SizedBox(height: Insets.md),
              Text(
                _rule.describe(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final RecurrenceFrequency frequency
                      in RecurrenceFrequency.values)
                    ChoiceChip(
                      label: Text(frequency.label),
                      selected: _rule.frequency == frequency,
                      onSelected: (_) => setState(() {
                        _rule = _rule.copyWith(
                          frequency: frequency,
                          // Switching away from weekly clears the weekday
                          // selection so a stale set cannot resurface later.
                          weekdays: frequency == RecurrenceFrequency.weekly
                              ? _rule.weekdays
                              : const <int>{},
                        );
                      }),
                    ),
                ],
              ),
              if (_rule.isRepeating) ...<Widget>[
                const SizedBox(height: Insets.xl),
                _IntervalField(
                  controller: _interval,
                  unitLabel: _unitLabel(_rule.frequency),
                  onChanged: (int value) => setState(
                    () => _rule = _rule.copyWith(interval: value),
                  ),
                ),
              ],
              if (_rule.frequency == RecurrenceFrequency.weekly) ...<Widget>[
                const SizedBox(height: Insets.lg),
                _WeekdaySelector(
                  selected: _rule.weekdays,
                  onChanged: (Set<int> days) =>
                      setState(() => _rule = _rule.copyWith(weekdays: days)),
                ),
              ],
              if (_rule.isRepeating) ...<Widget>[
                const SizedBox(height: Insets.lg),
                _EndCondition(
                  rule: _rule,
                  anchor: widget.anchor,
                  onChanged: (RecurrenceRule rule) =>
                      setState(() => _rule = rule),
                ),
              ],
              const SizedBox(height: Insets.xl),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop<RecurrenceRule>(_rule),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _unitLabel(RecurrenceFrequency frequency) =>
      switch (frequency) {
        RecurrenceFrequency.customInterval => 'minutes',
        RecurrenceFrequency.hourly => 'hours',
        RecurrenceFrequency.daily => 'days',
        RecurrenceFrequency.weekly => 'weeks',
        RecurrenceFrequency.monthly => 'months',
        RecurrenceFrequency.yearly => 'years',
        RecurrenceFrequency.once => '',
      };
}

class _IntervalField extends StatelessWidget {
  const _IntervalField({
    required this.controller,
    required this.unitLabel,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String unitLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Text('Every'),
        const SizedBox(width: Insets.md),
        SizedBox(
          width: 88,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (String value) {
              final int? parsed = int.tryParse(value);
              // Ignore transient invalid states while typing rather than
              // fighting the user's cursor with a forced correction.
              if (parsed != null && parsed >= 1) {
                onChanged(parsed);
              }
            },
          ),
        ),
        const SizedBox(width: Insets.md),
        Text(unitLabel),
      ],
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: <Widget>[
        for (int weekday = DateTime.monday;
            weekday <= DateTime.sunday;
            weekday++)
          FilterChip(
            label: Text(Formatters.weekdayAbbreviation(weekday)),
            selected: selected.contains(weekday),
            onSelected: (bool isSelected) {
              final Set<int> next = Set<int>.of(selected);
              if (isSelected) {
                next.add(weekday);
              } else {
                next.remove(weekday);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _EndCondition extends StatelessWidget {
  const _EndCondition({
    required this.rule,
    required this.anchor,
    required this.onChanged,
  });

  final RecurrenceRule rule;
  final DateTime anchor;
  final ValueChanged<RecurrenceRule> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Ends', style: theme.textTheme.labelLarge),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Never'),
              selected: !rule.hasEnd,
              onSelected: (_) => onChanged(
                rule.copyWith(clearUntil: true, clearMaxOccurrences: true),
              ),
            ),
            ChoiceChip(
              label: Text(
                rule.until == null
                    ? 'On a date'
                    : 'Until ${Formatters.shortDate(rule.until!)}',
              ),
              selected: rule.until != null,
              onSelected: (_) async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: rule.until ??
                      anchor.add(
                        const Duration(days: 30),
                      ),
                  firstDate: anchor,
                  lastDate: anchor.add(const Duration(days: 365 * 10)),
                );
                if (picked != null) {
                  onChanged(
                    rule.copyWith(
                      until: picked,
                      clearMaxOccurrences: true,
                    ),
                  );
                }
              },
            ),
            ChoiceChip(
              label: Text(
                rule.maxOccurrences == null
                    ? 'After N times'
                    : 'After ${rule.maxOccurrences} times',
              ),
              selected: rule.maxOccurrences != null,
              onSelected: (_) async {
                final int? count = await _askOccurrenceCount(
                  context,
                  initial: rule.maxOccurrences ?? 10,
                );
                if (count != null) {
                  onChanged(
                    rule.copyWith(maxOccurrences: count, clearUntil: true),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<int?> _askOccurrenceCount(
    BuildContext context, {
    required int initial,
  }) {
    final TextEditingController controller =
        TextEditingController(text: '$initial');

    return showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('How many times?'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Occurrences'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final int? parsed = int.tryParse(controller.text);
              Navigator.of(dialogContext).pop(
                parsed != null && parsed > 0 ? parsed : null,
              );
            },
            child: const Text('Set'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
