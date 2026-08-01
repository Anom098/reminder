/// The Drift database.
///
/// Run `dart run build_runner build --delete-conflicting-outputs` after editing
/// this file or the table definitions; `app_database.g.dart` is generated and
/// not checked in.
library;

import 'package:drift/drift.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/database/connection/database_connection.dart';
import 'package:voice_reminder/core/database/tables/reminder_rows.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';

part 'app_database.g.dart';

/// Local SQLite storage for reminders, categories and their indexes.
@DriftDatabase(tables: <Type>[ReminderRows, CategoryRows])
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database.
  AppDatabase() : super(openDatabaseConnection());

  /// Opens a database against [executor].
  ///
  /// Used by tests to run against an in-memory SQLite instance.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => AppConstants.databaseSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _seedBuiltInCategories();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Version 1 is the initial schema; no upgrade paths exist yet.
          // Add `if (from < 2) { ... }` blocks here as the schema evolves, and
          // add a matching test to test/core/database/migration_test.dart.
        },
        beforeOpen: (OpeningDetails details) async {
          // Drift does not enable foreign keys for us, and the reminder →
          // category `ON DELETE SET NULL` rule depends on them.
          await customStatement('PRAGMA foreign_keys = ON');
          // WAL keeps a write from the notification background isolate from
          // blocking a read on the UI isolate.
          await customStatement('PRAGMA journal_mode = WAL');

          if (details.wasCreated) {
            return;
          }
          // Self-healing: a restore from an older backup, or a partially failed
          // migration, can leave the built-ins missing.
          await _seedBuiltInCategories();
        },
      );

  /// Inserts any missing built-in categories.
  ///
  /// Uses `insertOnConflictUpdate`-free `DoNothing` mode so that a user's
  /// customised colour or hidden flag on a built-in survives the check.
  Future<void> _seedBuiltInCategories() async {
    await batch((Batch batch) {
      batch.insertAll(
        categoryRows,
        BuiltInCategory.values.map(
          (BuiltInCategory category) => CategoryRowsCompanion.insert(
            id: category.id,
            name: category.displayName,
            colorValue: category.colorValue,
            iconCodePoint: category.iconCodePoint,
            isBuiltIn: const Value<bool>(true),
            sortOrder: Value<int>(category.index),
          ),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}
