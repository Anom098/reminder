/// Manage reminder categories.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/category_icons.dart';
import 'package:voice_reminder/shared/widgets/confirm_dialog.dart';

/// Lists categories and allows adding, editing, hiding and deleting them.
class CategoriesScreen extends ConsumerWidget {
  /// Creates the categories screen.
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ReminderCategory>> categories =
        ref.watch(_allCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: AsyncValueView<List<ReminderCategory>>(
        value: categories,
        onRetry: () => ref.invalidate(_allCategoriesProvider),
        builder: (BuildContext context, List<ReminderCategory> data) =>
            ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: Insets.sm),
          itemCount: data.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) => _CategoryTile(
            category: data[index],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_editCategory(context, ref, null)),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final ReminderCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(category.colorValue).withValues(alpha: 0.16),
        child: Icon(
          CategoryIcons.resolve(category.iconCodePoint),
          color: Color(category.colorValue),
        ),
      ),
      title: Text(category.name),
      subtitle: Text(
        category.isBuiltIn ? 'Built in' : 'Custom',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: category.isHidden ? 'Show' : 'Hide',
            icon: Icon(
              category.isHidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => unawaited(
              _setHidden(ref, category, hidden: !category.isHidden),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => unawaited(_editCategory(context, ref, category)),
          ),
          if (!category.isBuiltIn)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_delete(context, ref, category)),
            ),
        ],
      ),
    );
  }
}

Future<void> _setHidden(
  WidgetRef ref,
  ReminderCategory category, {
  required bool hidden,
}) async {
  await ref
      .read(categoryRepositoryProvider)
      .update(category.copyWith(isHidden: hidden));
  ref.invalidate(_allCategoriesProvider);
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  ReminderCategory category,
) async {
  final bool confirmed = await showConfirmDialog(
    context,
    title: 'Delete "${category.name}"?',
    message: 'Reminders in this category are kept, but become uncategorised.',
    confirmLabel: 'Delete',
    isDestructive: true,
  );
  if (!confirmed) {
    return;
  }

  final Result<void> result =
      await ref.read(categoryRepositoryProvider).delete(category.id);
  ref.invalidate(_allCategoriesProvider);

  if (!context.mounted) {
    return;
  }
  if (result case Failure<void>(failure: final AppFailure failure)) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

Future<void> _editCategory(
  BuildContext context,
  WidgetRef ref,
  ReminderCategory? existing,
) async {
  final ReminderCategory? edited = await showModalBottomSheet<ReminderCategory>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _CategoryEditor(existing: existing),
  );
  if (edited == null) {
    return;
  }

  final Result<ReminderCategory> result = existing == null
      ? await ref.read(categoryRepositoryProvider).create(edited)
      : await ref.read(categoryRepositoryProvider).update(edited);

  ref.invalidate(_allCategoriesProvider);

  if (!context.mounted) {
    return;
  }
  if (result case Failure<ReminderCategory>(failure: final AppFailure f)) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(f.message)));
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.existing});

  final ReminderCategory? existing;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late int _colorValue =
      widget.existing?.colorValue ?? AppTheme.seedPalette.first.toARGB32();
  late int _iconCodePoint =
      widget.existing?.iconCodePoint ?? CategoryIcons.palette.first.codePoint;

  @override
  void initState() {
    super.initState();
    // The Save button is disabled until a name is typed, so the button has to
    // rebuild as the field changes.
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Insets.lg,
          right: Insets.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.existing == null ? 'New category' : 'Edit category',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: AppConstants.maxCategoryNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Insets.md),
              Text('Colour', style: theme.textTheme.labelLarge),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final Color color in AppTheme.seedPalette)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _colorValue = color.toARGB32()),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorValue == color.toARGB32()
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Text('Icon', style: theme.textTheme.labelLarge),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: <Widget>[
                  for (final IconData icon in CategoryIcons.palette)
                    IconButton(
                      isSelected: _iconCodePoint == icon.codePoint,
                      onPressed: () =>
                          setState(() => _iconCodePoint = icon.codePoint),
                      icon: Icon(icon),
                      style: IconButton.styleFrom(
                        backgroundColor: _iconCodePoint == icon.codePoint
                            ? Color(_colorValue).withValues(alpha: 0.16)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _submit,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    final ReminderCategory? existing = widget.existing;

    Navigator.of(context).pop<ReminderCategory>(
      existing == null
          ? ReminderCategory(
              id: const Uuid().v4(),
              name: name,
              colorValue: _colorValue,
              iconCodePoint: _iconCodePoint,
              // New categories sort after the built-ins.
              sortOrder: 100,
            )
          : existing.copyWith(
              name: name,
              colorValue: _colorValue,
              iconCodePoint: _iconCodePoint,
            ),
    );
  }
}

/// Every category, including hidden ones, for the management screen.
final AutoDisposeStreamProvider<List<ReminderCategory>> _allCategoriesProvider =
    StreamProvider.autoDispose<List<ReminderCategory>>(
  (Ref ref) => ref
      .watch(categoryRepositoryProvider)
      .watchCategories(includeHidden: true),
);
