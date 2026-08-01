/// Backup, restore, export and import contract.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// File format of an export.
enum BackupFormat {
  /// Loss-free JSON. The only format [BackupService.import] accepts.
  json('JSON', 'json', 'application/json'),

  /// Flat CSV of reminders, for spreadsheets. Lossy — recurrence rules are
  /// flattened to their human-readable description.
  csv('CSV', 'csv', 'text/csv'),

  /// A byte copy of the SQLite database, for support and migration.
  sqlite('SQLite database', 'sqlite', 'application/vnd.sqlite3');

  const BackupFormat(this.label, this.extension, this.mimeType);

  /// User-facing name.
  final String label;

  /// Filename extension, without the dot.
  final String extension;

  /// MIME type used when sharing.
  final String mimeType;

  /// Whether [BackupService.import] can read this format.
  bool get isImportable => this == BackupFormat.json;
}

/// The outcome of a completed export.
final class BackupArtifact extends Equatable {
  /// Creates an artifact descriptor.
  const BackupArtifact({
    required this.path,
    required this.format,
    required this.sizeInBytes,
    required this.createdAt,
    required this.reminderCount,
  });

  /// Absolute path of the written file.
  final String path;

  /// Format it was written in.
  final BackupFormat format;

  /// Size on disk.
  final int sizeInBytes;

  /// When it was produced.
  final DateTime createdAt;

  /// How many reminders it contains.
  final int reminderCount;

  /// Filename without directories.
  String get fileName => path.split(RegExp(r'[/\\]')).last;

  @override
  List<Object?> get props =>
      <Object?>[path, format, sizeInBytes, createdAt, reminderCount];
}

/// How an import merges with existing data.
enum ImportStrategy {
  /// Delete everything first, then import. The backup becomes the truth.
  replace('Replace everything'),

  /// Keep existing reminders; add those whose ids are not already present.
  merge('Merge, keep existing'),

  /// Add everything under fresh ids, keeping duplicates side by side.
  ///
  /// The safe choice when importing someone else's backup, where colliding ids
  /// would otherwise silently drop rows.
  duplicate('Add as copies');

  const ImportStrategy(this.label);

  /// User-facing name.
  final String label;
}

/// A summary of what an import did.
final class ImportSummary extends Equatable {
  /// Creates a summary.
  const ImportSummary({
    required this.remindersImported,
    required this.remindersSkipped,
    required this.categoriesImported,
    this.settingsRestored = false,
    this.warnings = const <String>[],
  });

  /// Reminders written.
  final int remindersImported;

  /// Reminders skipped because they already existed.
  final int remindersSkipped;

  /// Categories written.
  final int categoriesImported;

  /// Whether settings were restored from the payload.
  final bool settingsRestored;

  /// Non-fatal problems, e.g. rows dropped because they were malformed.
  final List<String> warnings;

  @override
  List<Object?> get props => <Object?>[
        remindersImported,
        remindersSkipped,
        categoriesImported,
        settingsRestored,
        warnings,
      ];
}

/// Writes and reads backup files.
abstract interface class BackupService {
  /// Writes an export in [format] and returns where it landed.
  ///
  /// The file is placed in a directory the platform lets other apps read from a
  /// share sheet; it is not automatically shared.
  Future<Result<BackupArtifact>> export({
    BackupFormat format = BackupFormat.json,
    bool includeSettings = true,
    bool includeCompleted = true,
  });

  /// Opens the system share sheet for a previously exported [artifact].
  Future<Result<void>> share(BackupArtifact artifact);

  /// Reads the JSON backup at [path] and applies it using [strategy].
  ///
  /// Fails with a `SerializationFailure` when the payload is malformed or was
  /// written by a newer version of the app.
  Future<Result<ImportSummary>> import(
    String path, {
    ImportStrategy strategy = ImportStrategy.merge,
    bool restoreSettings = false,
  });

  /// Lists exports previously written by this app, newest first.
  Future<Result<List<BackupArtifact>>> listLocalBackups();

  /// Deletes a local export.
  Future<Result<void>> deleteLocalBackup(String path);
}
