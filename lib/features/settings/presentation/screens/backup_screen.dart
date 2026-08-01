/// Backup, restore, export and import.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/settings/domain/services/backup_service.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/confirm_dialog.dart';

/// Exports the database and restores it from a file.
class BackupScreen extends ConsumerStatefulWidget {
  /// Creates the backup screen.
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Text(
              'Backups are written to this device. Nothing is uploaded '
              'anywhere — share a backup yourself to move it to another '
              'phone or to keep a copy.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final BackupFormat format in BackupFormat.values)
            ListTile(
              enabled: !_busy,
              leading: Icon(_iconFor(format)),
              title: Text('Export as ${format.label}'),
              subtitle: Text(_descriptionFor(format)),
              onTap: () => unawaited(_export(format)),
            ),
          const Divider(),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import a backup'),
            subtitle: const Text('Restores reminders from a JSON backup'),
            onTap: () => unawaited(_import()),
          ),
          const Divider(),
          const _SectionHeading('Backups on this device'),
          const _LocalBackupList(),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }

  static IconData _iconFor(BackupFormat format) => switch (format) {
        BackupFormat.json => Icons.data_object,
        BackupFormat.csv => Icons.table_chart_outlined,
        BackupFormat.sqlite => Icons.storage_outlined,
      };

  static String _descriptionFor(BackupFormat format) => switch (format) {
        BackupFormat.json =>
          'Complete and restorable. Use this one for real backups.',
        BackupFormat.csv =>
          'For spreadsheets. Repeat rules are flattened to text and cannot '
              'be imported back.',
        BackupFormat.sqlite =>
          'A raw copy of the database, for support and diagnostics.',
      };

  Future<void> _export(BackupFormat format) async {
    setState(() => _busy = true);

    final Result<BackupArtifact> result =
        await ref.read(backupServiceProvider).export(format: format);

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    ref.invalidate(_localBackupsProvider);

    switch (result) {
      case Success<BackupArtifact>(value: final BackupArtifact artifact):
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Exported ${artifact.reminderCount} reminders to '
                '${artifact.fileName}',
              ),
              action: SnackBarAction(
                label: 'Share',
                onPressed: () => unawaited(
                  ref.read(backupServiceProvider).share(artifact),
                ),
              ),
            ),
          );
      case Failure<BackupArtifact>(failure: final AppFailure failure):
        _showError(failure);
    }
  }

  Future<void> _import() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      withData: false,
    );

    final List<PlatformFile> files = picked?.files ?? const <PlatformFile>[];
    final String? path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) {
      return;
    }

    final ImportStrategy? strategy = await _askStrategy();
    if (strategy == null || !mounted) {
      return;
    }

    if (strategy == ImportStrategy.replace) {
      final bool confirmed = await showConfirmDialog(
        context,
        title: 'Replace everything?',
        message: 'Every reminder currently on this device is deleted first, '
            'then the backup is restored. This cannot be undone.',
        confirmLabel: 'Replace',
        isDestructive: true,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() => _busy = true);

    final Result<ImportSummary> result =
        await ref.read(backupServiceProvider).import(path, strategy: strategy);

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    switch (result) {
      case Success<ImportSummary>(value: final ImportSummary summary):
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Imported ${summary.remindersImported} reminders'
                '${summary.remindersSkipped > 0 ? ', '
                    '${summary.remindersSkipped} already existed' : ''}.',
              ),
            ),
          );
      case Failure<ImportSummary>(failure: final AppFailure failure):
        _showError(failure);
    }
  }

  Future<ImportStrategy?> _askStrategy() {
    return showModalBottomSheet<ImportStrategy>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final ImportStrategy strategy in ImportStrategy.values)
              ListTile(
                title: Text(strategy.label),
                subtitle: Text(_strategyDescription(strategy)),
                onTap: () => Navigator.of(sheetContext).pop(strategy),
              ),
          ],
        ),
      ),
    );
  }

  static String _strategyDescription(ImportStrategy strategy) =>
      switch (strategy) {
        ImportStrategy.replace =>
          'Delete everything here first, then restore the backup.',
        ImportStrategy.merge =>
          'Add reminders that are missing; leave existing ones untouched.',
        ImportStrategy.duplicate =>
          'Add everything as new copies, keeping duplicates side by side.',
      };

  void _showError(AppFailure failure) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

class _LocalBackupList extends ConsumerWidget {
  const _LocalBackupList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BackupArtifact>> backups =
        ref.watch(_localBackupsProvider);

    return AsyncValueView<List<BackupArtifact>>(
      value: backups,
      onRetry: () => ref.invalidate(_localBackupsProvider),
      loading: const Padding(
        padding: EdgeInsets.all(Insets.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      builder: (BuildContext context, List<BackupArtifact> data) {
        if (data.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(Insets.lg),
            child: Text('No backups yet.'),
          );
        }
        return Column(
          children: <Widget>[
            for (final BackupArtifact artifact in data)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(artifact.fileName),
                subtitle: Text(
                  '${Formatters.dateAndTime(artifact.createdAt)} · '
                  '${(artifact.sizeInBytes / 1024).toStringAsFixed(1)} KB',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => unawaited(
                        ref.read(backupServiceProvider).share(artifact),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref
                            .read(backupServiceProvider)
                            .deleteLocalBackup(artifact.path);
                        ref.invalidate(_localBackupsProvider);
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Backups already written to this device.
final AutoDisposeFutureProvider<List<BackupArtifact>> _localBackupsProvider =
    FutureProvider.autoDispose<List<BackupArtifact>>((Ref ref) async {
  final Result<List<BackupArtifact>> result =
      await ref.watch(backupServiceProvider).listLocalBackups();
  return result.getOrElse(const <BackupArtifact>[]);
});
