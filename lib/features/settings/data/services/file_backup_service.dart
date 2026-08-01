/// Filesystem-backed [BackupService].
library;

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/category_repository.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/domain/repositories/settings_repository.dart';
import 'package:voice_reminder/features/settings/domain/services/backup_service.dart';

/// Reads and writes backups in the app's documents directory.
///
/// JSON is the canonical format and the only one that can be imported. CSV and
/// SQLite are export-only conveniences, and say so in the UI.
final class FileBackupService implements BackupService {
  /// Creates a service.
  FileBackupService({
    required ReminderRepository reminders,
    required CategoryRepository categories,
    required SettingsRepository settings,
    required ReminderScheduler scheduler,
    required AppLogger logger,
    required Clock clock,
    Uuid uuid = const Uuid(),
  })  : _reminders = reminders,
        _categories = categories,
        _settings = settings,
        _scheduler = scheduler,
        _log = logger.forContext('Backup'),
        _clock = clock,
        _uuid = uuid;

  final ReminderRepository _reminders;
  final CategoryRepository _categories;
  final SettingsRepository _settings;
  final ReminderScheduler _scheduler;
  final AppLogger _log;
  final Clock _clock;
  final Uuid _uuid;

  @override
  Future<Result<BackupArtifact>> export({
    BackupFormat format = BackupFormat.json,
    bool includeSettings = true,
    bool includeCompleted = true,
  }) async {
    try {
      final ReminderFilter filter = includeCompleted
          ? ReminderFilter.none
          : const ReminderFilter(
              statuses: <ReminderStatus>{
                ReminderStatus.scheduled,
                ReminderStatus.snoozed,
                ReminderStatus.disabled,
                ReminderStatus.missed,
              },
            );

      final Result<List<Reminder>> reminders =
          await _reminders.getReminders(filter: filter);
      if (reminders
          case Failure<List<Reminder>>(
            failure: final AppFailure failure,
          )) {
        return Failure<BackupArtifact>(failure);
      }

      final Result<List<ReminderCategory>> categories =
          await _categories.getCategories();
      if (categories
          case Failure<List<ReminderCategory>>(
            failure: final AppFailure failure,
          )) {
        return Failure<BackupArtifact>(failure);
      }

      final List<Reminder> rows = (reminders as Success<List<Reminder>>).value;
      final List<ReminderCategory> categoryRows =
          (categories as Success<List<ReminderCategory>>).value;

      final DateTime now = _clock.now();
      final Directory directory = await _backupDirectory();
      final File file = File(
        p.join(
          directory.path,
          '${AppConstants.backupFilePrefix}-'
          '${Formatters.fileTimestamp(now)}.${format.extension}',
        ),
      );

      switch (format) {
        case BackupFormat.json:
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(
              _buildPayload(
                reminders: rows,
                categories: categoryRows,
                settings: includeSettings ? _settings.current : null,
                createdAt: now,
              ),
            ),
            flush: true,
          );
        case BackupFormat.csv:
          await file.writeAsString(_buildCsv(rows, categoryRows), flush: true);
        case BackupFormat.sqlite:
          final Result<File> copied = await _copyDatabaseFile(file);
          if (copied case Failure<File>(failure: final AppFailure failure)) {
            return Failure<BackupArtifact>(failure);
          }
      }

      final BackupArtifact artifact = BackupArtifact(
        path: file.path,
        format: format,
        sizeInBytes: await file.length(),
        createdAt: now,
        reminderCount: rows.length,
      );

      await _settings.save(_settings.current.copyWith(lastBackupAt: now));
      _log.info('Exported ${rows.length} reminders to ${artifact.fileName}');
      return Success<BackupArtifact>(artifact);
    } on Object catch (error, stackTrace) {
      _log.error('export failed', error: error, stackTrace: stackTrace);
      return Failure<BackupArtifact>(
        StorageFailure(
          message: 'Could not write the backup file.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void>> share(BackupArtifact artifact) {
    return Result.guardAsync<void>(() async {
      await Share.shareXFiles(
        <XFile>[XFile(artifact.path, mimeType: artifact.format.mimeType)],
        subject: 'Voice Reminder backup',
      );
    });
  }

  @override
  Future<Result<ImportSummary>> import(
    String path, {
    ImportStrategy strategy = ImportStrategy.merge,
    bool restoreSettings = false,
  }) async {
    try {
      final File file = File(path);
      if (!file.existsSync()) {
        return Failure<ImportSummary>(
          StorageFailure(
              message: 'That backup file no longer exists.', path: path),
        );
      }

      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const Failure<ImportSummary>(
          SerializationFailure(
            message: 'That file is not a Voice Reminder backup.',
          ),
        );
      }

      final int version = switch (decoded['version']) {
        final int value => value,
        _ => 0,
      };
      if (version > AppConstants.backupFormatVersion) {
        return Failure<ImportSummary>(
          SerializationFailure(
            message: 'This backup was made by a newer version of the app. '
                'Update Voice Reminder and try again.',
            cause: 'backup version $version',
          ),
        );
      }

      final List<String> warnings = <String>[];

      if (strategy == ImportStrategy.replace) {
        final Result<void> cleared = await _reminders.deleteAll();
        if (cleared case Failure<void>(failure: final AppFailure failure)) {
          return Failure<ImportSummary>(failure);
        }
      }

      final int categoriesImported = await _importCategories(
        decoded['categories'],
        warnings,
      );
      final (int imported, int skipped) = await _importReminders(
        decoded['reminders'],
        strategy: strategy,
        warnings: warnings,
      );

      bool settingsRestored = false;
      if (restoreSettings && decoded['settings'] is Map<String, dynamic>) {
        settingsRestored = await _importSettings(
          decoded['settings'] as Map<String, dynamic>,
        );
      }

      // The imported reminders carry due dates that may be in the past and
      // recurrence that has moved on; rebuilding the whole schedule is the only
      // way to leave the OS consistent with the new database contents.
      await _scheduler.reconcileMissed();
      await _scheduler.rescheduleAll();

      _log.info('Imported $imported reminders ($skipped skipped).');
      return Success<ImportSummary>(
        ImportSummary(
          remindersImported: imported,
          remindersSkipped: skipped,
          categoriesImported: categoriesImported,
          settingsRestored: settingsRestored,
          warnings: warnings,
        ),
      );
    } on FormatException catch (error, stackTrace) {
      return Failure<ImportSummary>(
        SerializationFailure(
          message: 'That backup file is damaged and cannot be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('import failed', error: error, stackTrace: stackTrace);
      return Failure<ImportSummary>(
        StorageFailure(
          message: 'Could not read the backup file.',
          path: path,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<BackupArtifact>>> listLocalBackups() {
    return Result.guardAsync<List<BackupArtifact>>(() async {
      final Directory directory = await _backupDirectory();
      final List<BackupArtifact> artifacts = <BackupArtifact>[];

      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is! File) {
          continue;
        }
        final String name = p.basename(entity.path);
        if (!name.startsWith(AppConstants.backupFilePrefix)) {
          continue;
        }
        final BackupFormat? format = _formatForExtension(
          p.extension(entity.path),
        );
        if (format == null) {
          continue;
        }
        final FileStat stat = await entity.stat();
        artifacts.add(
          BackupArtifact(
            path: entity.path,
            format: format,
            sizeInBytes: stat.size,
            createdAt: stat.modified,
            // Counting rows would mean parsing every file just to render a
            // list; the count is only known for the file just written.
            reminderCount: 0,
          ),
        );
      }

      artifacts.sort(
        (BackupArtifact a, BackupArtifact b) =>
            b.createdAt.compareTo(a.createdAt),
      );
      return artifacts;
    });
  }

  @override
  Future<Result<void>> deleteLocalBackup(String path) {
    return Result.guardAsync<void>(() async {
      final File file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    });
  }

  // -- payload construction ------------------------------------------------

  Map<String, Object?> _buildPayload({
    required List<Reminder> reminders,
    required List<ReminderCategory> categories,
    required AppSettings? settings,
    required DateTime createdAt,
  }) {
    return <String, Object?>{
      'version': AppConstants.backupFormatVersion,
      'createdAt': createdAt.toIso8601String(),
      'application': 'voice_reminder',
      'categories': categories
          .map(
            (ReminderCategory category) => <String, Object?>{
              'id': category.id,
              'name': category.name,
              'colorValue': category.colorValue,
              'iconCodePoint': category.iconCodePoint,
              'isBuiltIn': category.isBuiltIn,
              'sortOrder': category.sortOrder,
              'isHidden': category.isHidden,
            },
          )
          .toList(),
      'reminders': reminders.map(_reminderToJson).toList(),
      if (settings != null) 'settings': _settingsToJson(settings),
    };
  }

  Map<String, Object?> _reminderToJson(Reminder reminder) => <String, Object?>{
        'id': reminder.id,
        'title': reminder.title,
        'notes': reminder.notes,
        'categoryId': reminder.categoryId,
        'priority': reminder.priority.name,
        'anchorAt': reminder.anchorAt.toIso8601String(),
        'dueAt': reminder.dueAt.toIso8601String(),
        'recurrence': reminder.recurrence.toJson(),
        'status': reminder.status.name,
        'colorValue': reminder.colorValue,
        'isSpoken': reminder.isSpoken,
        'spokenTextOverride': reminder.spokenTextOverride,
        'occurrenceCount': reminder.occurrenceCount,
        'timeZoneId': reminder.timeZoneId,
        'createdAt': reminder.createdAt.toIso8601String(),
        'updatedAt': reminder.updatedAt.toIso8601String(),
      };

  Map<String, Object?> _settingsToJson(AppSettings settings) =>
      <String, Object?>{
        'themeMode': settings.themeMode.name,
        'seedColorValue': settings.seedColorValue,
        'useHighContrast': settings.useHighContrast,
        'textScaleOverride': settings.textScaleOverride,
        'speakReminders': settings.speakReminders,
        'speakRepeatCount': settings.speakRepeatCount,
        'speakInSilentMode': settings.speakInSilentMode,
        'notificationVibration': settings.notificationVibration,
        'defaultSnoozeMinutes': settings.defaultSnooze.inMinutes,
        'ttsLanguage': settings.speech.language,
        'ttsRate': settings.speech.rate,
        'ttsPitch': settings.speech.pitch,
        'ttsVolume': settings.speech.volume,
        'speechLocaleId': settings.speechLocaleId,
      };

  String _buildCsv(
    List<Reminder> reminders,
    List<ReminderCategory> categories,
  ) {
    final Map<String, String> names = <String, String>{
      for (final ReminderCategory category in categories)
        category.id: category.name,
    };

    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'Title',
        'Notes',
        'Category',
        'Priority',
        'Due',
        'Repeat',
        'Status',
        'Spoken',
      ],
      for (final Reminder reminder in reminders)
        <Object?>[
          reminder.title,
          reminder.notes ?? '',
          reminder.categoryId == null
              ? ''
              : names[reminder.categoryId] ?? reminder.categoryId,
          reminder.priority.label,
          reminder.dueAt.toIso8601String(),
          reminder.recurrence.describe(),
          reminder.status.label,
          reminder.isSpoken ? 'yes' : 'no',
        ],
    ];

    return const ListToCsvConverter().convert(rows);
  }

  // -- import --------------------------------------------------------------

  Future<int> _importCategories(Object? raw, List<String> warnings) async {
    if (raw is! List<Object?>) {
      return 0;
    }
    int imported = 0;
    for (final Object? entry in raw) {
      if (entry is! Map<String, dynamic>) {
        warnings.add('Skipped a malformed category entry.');
        continue;
      }
      final String? id = entry['id'] as String?;
      final String? name = entry['name'] as String?;
      if (id == null || name == null) {
        warnings.add('Skipped a category with no id or name.');
        continue;
      }

      final ReminderCategory category = ReminderCategory(
        id: id,
        name: name,
        colorValue: (entry['colorValue'] as int?) ?? 0xFF607D8B,
        iconCodePoint: (entry['iconCodePoint'] as int?) ?? 0xe86c,
        isBuiltIn: (entry['isBuiltIn'] as bool?) ?? false,
        sortOrder: (entry['sortOrder'] as int?) ?? 0,
        isHidden: (entry['isHidden'] as bool?) ?? false,
      );

      // Update first, insert when absent: built-ins always exist already.
      final Result<ReminderCategory> updated =
          await _categories.update(category);
      if (updated.isFailure) {
        final Result<ReminderCategory> created =
            await _categories.create(category);
        if (created.isFailure) {
          warnings.add('Could not import the category "$name".');
          continue;
        }
      }
      imported++;
    }
    return imported;
  }

  Future<(int, int)> _importReminders(
    Object? raw, {
    required ImportStrategy strategy,
    required List<String> warnings,
  }) async {
    if (raw is! List<Object?>) {
      return (0, 0);
    }

    int imported = 0;
    int skipped = 0;

    for (final Object? entry in raw) {
      if (entry is! Map<String, dynamic>) {
        warnings.add('Skipped a malformed reminder entry.');
        continue;
      }

      final Reminder? reminder = _reminderFromJson(entry, strategy: strategy);
      if (reminder == null) {
        warnings.add('Skipped a reminder that could not be read.');
        continue;
      }

      if (strategy == ImportStrategy.merge) {
        final Result<Reminder> existing =
            await _reminders.getReminder(reminder.id);
        if (existing.isSuccess) {
          skipped++;
          continue;
        }
      }

      final Result<Reminder> created = await _reminders.create(reminder);
      if (created.isFailure) {
        warnings.add('Could not import "${reminder.title}".');
        continue;
      }
      imported++;
    }

    return (imported, skipped);
  }

  Reminder? _reminderFromJson(
    Map<String, dynamic> json, {
    required ImportStrategy strategy,
  }) {
    final String? title = json['title'] as String?;
    final DateTime? dueAt = _parseDate(json['dueAt']);
    if (title == null || title.trim().isEmpty || dueAt == null) {
      return null;
    }

    final DateTime anchorAt = _parseDate(json['anchorAt']) ?? dueAt;
    final DateTime createdAt = _parseDate(json['createdAt']) ?? _clock.now();

    return Reminder(
      // A fresh id under `duplicate`, so importing someone else's backup never
      // overwrites a reminder of the same id that happens to exist here.
      id: strategy == ImportStrategy.duplicate
          ? _uuid.v4()
          : (json['id'] as String? ?? _uuid.v4()),
      title: title.trim(),
      notes: json['notes'] as String?,
      categoryId: json['categoryId'] as String?,
      priority: ReminderPriority.parse(json['priority'] as String?),
      anchorAt: anchorAt,
      dueAt: dueAt,
      recurrence: json['recurrence'] is Map<String, dynamic>
          ? RecurrenceRule.fromJson(json['recurrence'] as Map<String, dynamic>)
          : const RecurrenceRule.once(),
      status: ReminderStatus.parse(json['status'] as String?),
      colorValue: json['colorValue'] as int?,
      isSpoken: (json['isSpoken'] as bool?) ?? true,
      spokenTextOverride: json['spokenTextOverride'] as String?,
      occurrenceCount: (json['occurrenceCount'] as int?) ?? 0,
      timeZoneId: json['timeZoneId'] as String?,
      createdAt: createdAt,
      updatedAt: _parseDate(json['updatedAt']) ?? createdAt,
    );
  }

  Future<bool> _importSettings(Map<String, dynamic> json) async {
    final AppSettings current = _settings.current;
    final AppSettings restored = current.copyWith(
      themeMode: AppThemeMode.parse(json['themeMode'] as String?),
      seedColorValue: json['seedColorValue'] as int?,
      useHighContrast: json['useHighContrast'] as bool?,
      textScaleOverride: (json['textScaleOverride'] as num?)?.toDouble(),
      speakReminders: json['speakReminders'] as bool?,
      // `copyWith` clamps, so a hand-edited backup asking for 500 repeats
      // restores as the maximum rather than being rejected or obeyed.
      speakRepeatCount: json['speakRepeatCount'] as int?,
      speakInSilentMode: json['speakInSilentMode'] as bool?,
      notificationVibration: json['notificationVibration'] as bool?,
      defaultSnooze: json['defaultSnoozeMinutes'] is int
          ? Duration(minutes: json['defaultSnoozeMinutes'] as int)
          : null,
      speechLocaleId: json['speechLocaleId'] as String?,
      speech: current.speech.copyWith(
        language: json['ttsLanguage'] as String?,
        rate: (json['ttsRate'] as num?)?.toDouble(),
        pitch: (json['ttsPitch'] as num?)?.toDouble(),
        volume: (json['ttsVolume'] as num?)?.toDouble(),
      ),
    );

    final Result<AppSettings> saved = await _settings.save(restored);
    return saved.isSuccess;
  }

  // -- helpers -------------------------------------------------------------

  static DateTime? _parseDate(Object? raw) {
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  static BackupFormat? _formatForExtension(String extension) {
    final String normalised =
        extension.startsWith('.') ? extension.substring(1) : extension;
    for (final BackupFormat format in BackupFormat.values) {
      if (format.extension == normalised) {
        return format;
      }
    }
    return null;
  }

  Future<Directory> _backupDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(documents.path, 'backups'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Result<File>> _copyDatabaseFile(File destination) async {
    try {
      final Directory documents = await getApplicationDocumentsDirectory();
      final File source =
          File(p.join(documents.path, AppConstants.databaseFileName));
      if (!source.existsSync()) {
        return Failure<File>(
          StorageFailure(
            message: 'The database file could not be found.',
            path: source.path,
          ),
        );
      }
      // A plain byte copy can miss data still sitting in the WAL. Reminder
      // volumes are small, so the JSON export is the recommended backup and
      // this one is documented as a support/diagnostic aid.
      return Success<File>(await source.copy(destination.path));
    } on Object catch (error, stackTrace) {
      return Failure<File>(
        StorageFailure(
          message: 'Could not copy the database file.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
