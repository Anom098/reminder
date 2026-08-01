/// Create and edit a reminder.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/create_reminder.dart';
import 'package:voice_reminder/features/reminders/presentation/controllers/reminder_list_controller.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/recurrence_picker_sheet.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/category_icons.dart';
import 'package:voice_reminder/shared/widgets/confirm_dialog.dart';

/// Creates a reminder, or edits the one identified by [reminderId].
class ReminderEditorScreen extends ConsumerWidget {
  /// Creates the editor.
  const ReminderEditorScreen({this.reminderId, super.key});

  /// The reminder being edited, or `null` when creating a new one.
  final String? reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? id = reminderId;
    if (id == null) {
      return const _EditorForm(existing: null);
    }

    return AsyncValueView<Reminder?>(
      value: ref.watch(reminderProvider(id)),
      onRetry: () => ref.invalidate(reminderProvider(id)),
      builder: (BuildContext context, Reminder? reminder) {
        if (reminder == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('That reminder no longer exists.'),
            ),
          );
        }
        return _EditorForm(existing: reminder);
      },
    );
  }
}

class _EditorForm extends ConsumerStatefulWidget {
  const _EditorForm({required this.existing});

  final Reminder? existing;

  @override
  ConsumerState<_EditorForm> createState() => _EditorFormState();
}

class _EditorFormState extends ConsumerState<_EditorForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _spokenOverride;

  late DateTime _dueAt;
  late RecurrenceRule _recurrence;
  late ReminderPriority _priority;
  late bool _isSpoken;
  String? _categoryId;
  int? _colorValue;
  bool _saving = false;
  bool _dirty = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Reminder? existing = widget.existing;
    final DateTime now = ref.read(clockProvider).now();

    _title = TextEditingController(text: existing?.title ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _spokenOverride =
        TextEditingController(text: existing?.spokenTextOverride ?? '');

    // A new reminder defaults to the next round hour, which is both a sensible
    // guess and always safely in the future.
    _dueAt =
        existing?.dueAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    _recurrence = existing?.recurrence ?? const RecurrenceRule.once();
    _priority = existing?.priority ?? ReminderPriority.normal;
    _isSpoken = existing?.isSpoken ?? true;
    _categoryId = existing?.categoryId;
    _colorValue = existing?.colorValue;

    for (final TextEditingController controller in <TextEditingController>[
      _title,
      _notes,
      _spokenOverride,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _spokenOverride.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = ref.watch(clockProvider).now();
    final List<ReminderCategory> categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ReminderCategory>[];

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool discard = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: 'Your edits will not be saved.',
          confirmLabel: 'Discard',
          isDestructive: true,
        );
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit reminder' : 'New reminder'),
          actions: <Widget>[
            TextButton(
              onPressed: _saving ? null : () => unawaited(_save()),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(Insets.lg),
            children: <Widget>[
              TextFormField(
                controller: _title,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                maxLength: AppConstants.maxTitleLength,
                decoration: const InputDecoration(
                  labelText: 'What should I remind you about?',
                  hintText: 'Call Mom',
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Give the reminder a title.'
                        : null,
              ),
              const SizedBox(height: Insets.lg),
              _WhenCard(
                dueAt: _dueAt,
                now: now,
                recurrence: _recurrence,
                onPickDate: _pickDate,
                onPickTime: _pickTime,
                onPickRecurrence: _pickRecurrence,
              ),
              const SizedBox(height: Insets.lg),
              _PrioritySelector(
                value: _priority,
                onChanged: (ReminderPriority value) => setState(() {
                  _priority = value;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: Insets.lg),
              _CategorySelector(
                categories: categories,
                selectedId: _categoryId,
                onChanged: (String? id) => setState(() {
                  _categoryId = id;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: Insets.lg),
              _ColorSelector(
                value: _colorValue,
                onChanged: (int? value) => setState(() {
                  _colorValue = value;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: Insets.lg),
              TextFormField(
                controller: _notes,
                maxLines: 4,
                minLines: 2,
                maxLength: AppConstants.maxNotesLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Anything else worth remembering',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: Insets.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isSpoken,
                onChanged: (bool value) => setState(() {
                  _isSpoken = value;
                  _dirty = true;
                }),
                title: const Text('Speak this reminder aloud'),
                subtitle: Text(
                  _isSpoken
                      ? 'Announced when it is due.'
                      : 'Notification only, no speech.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (_isSpoken) ...<Widget>[
                const SizedBox(height: Insets.sm),
                TextFormField(
                  controller: _spokenOverride,
                  maxLength: AppConstants.maxTitleLength,
                  decoration: InputDecoration(
                    labelText: 'What to say (optional)',
                    hintText: _previewSpokenText(),
                    helperText:
                        'Leave empty to announce the title automatically.',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_previewSpeech()),
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Preview'),
                  ),
                ),
              ],
              const SizedBox(height: Insets.xxl),
            ],
          ),
        ),
      ),
    );
  }

  String _previewSpokenText() {
    final String title = _title.text.trim();
    return title.isEmpty ? 'Reminder.' : 'Reminder. $title.';
  }

  Future<void> _previewSpeech() async {
    final String override = _spokenOverride.text.trim();
    await ref.read(textToSpeechServiceProvider).speak(
          override.isEmpty ? _previewSpokenText() : override,
        );
  }

  Future<void> _pickDate() async {
    final DateTime now = ref.read(clockProvider).now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueAt.isBefore(now) ? now : _dueAt,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 10)),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dueAt.hour,
        _dueAt.minute,
      );
      _dirty = true;
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        _dueAt.year,
        _dueAt.month,
        _dueAt.day,
        picked.hour,
        picked.minute,
      );
      _dirty = true;
    });
  }

  Future<void> _pickRecurrence() async {
    final RecurrenceRule? picked = await showRecurrencePicker(
      context,
      initial: _recurrence,
      anchor: _dueAt,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _recurrence = picked;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _saving = true);

    final String? notes =
        _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final String? override = _spokenOverride.text.trim().isEmpty
        ? null
        : _spokenOverride.text.trim();

    final Reminder? existing = widget.existing;
    final Result<Reminder> result = existing == null
        ? await ref.read(createReminderProvider).call(
              CreateReminderInput(
                title: _title.text,
                dueAt: _dueAt,
                notes: notes,
                categoryId: _categoryId,
                priority: _priority,
                recurrence: _recurrence,
                colorValue: _colorValue,
                isSpoken: _isSpoken,
                spokenTextOverride: override,
              ),
            )
        : await ref.read(updateReminderProvider).call(
              existing.copyWith(
                title: _title.text.trim(),
                dueAt: _dueAt,
                notes: notes,
                categoryId: _categoryId,
                priority: _priority,
                recurrence: _recurrence,
                colorValue: _colorValue,
                isSpoken: _isSpoken,
                spokenTextOverride: override,
                clearNotes: notes == null,
                clearCategoryId: _categoryId == null,
                clearColorValue: _colorValue == null,
                clearSpokenTextOverride: override == null,
              ),
            );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    switch (result) {
      case Success<Reminder>(value: final Reminder reminder):
        _dirty = false;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Reminder set for '
                '${Formatters.dateAndTime(reminder.dueAt)}',
              ),
            ),
          );
      case Failure<Reminder>(failure: final AppFailure failure):
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _WhenCard extends StatelessWidget {
  const _WhenCard({
    required this.dueAt,
    required this.now,
    required this.recurrence,
    required this.onPickDate,
    required this.onPickTime,
    required this.onPickRecurrence,
  });

  final DateTime dueAt;
  final DateTime now;
  final RecurrenceRule recurrence;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickTime;
  final Future<void> Function() onPickRecurrence;

  @override
  Widget build(BuildContext context) {
    final bool inPast = dueAt.isBefore(now);
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Date'),
            subtitle: Text(Formatters.longDate(dueAt)),
            onTap: () => unawaited(onPickDate()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Time'),
            subtitle: Text(Formatters.time(dueAt)),
            onTap: () => unawaited(onPickTime()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Repeat'),
            subtitle: Text(recurrence.describe()),
            onTap: () => unawaited(onPickRecurrence()),
          ),
          if (inPast)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                0,
                Insets.lg,
                Insets.md,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      'That time has already passed — pick a future one.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  const _PrioritySelector({required this.value, required this.onChanged});

  final ReminderPriority value;
  final ValueChanged<ReminderPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReminderPriority>(
      segments: <ButtonSegment<ReminderPriority>>[
        for (final ReminderPriority priority in ReminderPriority.values)
          ButtonSegment<ReminderPriority>(
            value: priority,
            label: Text(priority.label),
          ),
      ],
      selected: <ReminderPriority>{value},
      showSelectedIcon: false,
      onSelectionChanged: (Set<ReminderPriority> selection) =>
          onChanged(selection.first),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  final List<ReminderCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: <Widget>[
        ChoiceChip(
          label: const Text('No category'),
          selected: selectedId == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final ReminderCategory category in categories)
          ChoiceChip(
            avatar: Icon(
              CategoryIcons.resolve(category.iconCodePoint),
              size: 18,
              color: Color(category.colorValue),
            ),
            label: Text(category.name),
            selected: selectedId == category.id,
            onSelected: (_) => onChanged(category.id),
          ),
      ],
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: Insets.md),
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _Swatch(
                  color: null,
                  selected: value == null,
                  onTap: () => onChanged(null),
                ),
                for (final Color color in AppTheme.seedPalette)
                  _Swatch(
                    color: color,
                    selected: value == color.toARGB32(),
                    onTap: () => onChanged(color.toARGB32()),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: Insets.sm),
      child: Semantics(
        selected: selected,
        button: true,
        label: color == null ? 'Use the category colour' : 'Custom colour',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? scheme.surfaceContainerHighest,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: color == null
                ? Icon(Icons.block, size: 18, color: scheme.onSurfaceVariant)
                : null,
          ),
        ),
      ),
    );
  }
}
