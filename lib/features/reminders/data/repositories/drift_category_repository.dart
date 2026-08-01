/// Drift-backed [CategoryRepository].
library;

import 'package:drift/drift.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/data/mappers/reminder_mapper.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/category_repository.dart';

/// Stores categories in the local SQLite database.
final class DriftCategoryRepository implements CategoryRepository {
  /// Creates a repository over [database].
  DriftCategoryRepository({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _log = logger.forContext('CategoryRepository');

  final AppDatabase _db;
  final AppLogger _log;

  @override
  Stream<List<ReminderCategory>> watchCategories({
    bool includeHidden = false,
  }) {
    final SimpleSelectStatement<$CategoryRowsTable, CategoryRow> query =
        _db.select(_db.categoryRows)
          ..orderBy(<OrderClauseGenerator<$CategoryRowsTable>>[
            ($CategoryRowsTable c) => OrderingTerm.asc(c.sortOrder),
            ($CategoryRowsTable c) => OrderingTerm.asc(c.name),
          ]);

    if (!includeHidden) {
      query.where(($CategoryRowsTable c) => c.isHidden.equals(false));
    }

    return query.watch().map(_toEntities).handleError(
      (Object error, StackTrace stackTrace) {
        _log.error(
          'watchCategories failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  @override
  Future<Result<List<ReminderCategory>>> getCategories({
    bool includeHidden = true,
  }) {
    return _guard<List<ReminderCategory>>('getCategories', () async {
      final SimpleSelectStatement<$CategoryRowsTable, CategoryRow> query =
          _db.select(_db.categoryRows)
            ..orderBy(<OrderClauseGenerator<$CategoryRowsTable>>[
              ($CategoryRowsTable c) => OrderingTerm.asc(c.sortOrder),
              ($CategoryRowsTable c) => OrderingTerm.asc(c.name),
            ]);
      if (!includeHidden) {
        query.where(($CategoryRowsTable c) => c.isHidden.equals(false));
      }
      return _toEntities(await query.get());
    });
  }

  @override
  Future<Result<ReminderCategory>> getCategory(String id) {
    return _guard<ReminderCategory>('getCategory', () async {
      final CategoryRow? row = await (_db.select(_db.categoryRows)
            ..where(($CategoryRowsTable c) => c.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw _CategoryNotFound(id);
      }
      return row.toEntity();
    });
  }

  @override
  Future<Result<ReminderCategory>> create(ReminderCategory category) {
    return _guard<ReminderCategory>('create', () async {
      await _db.into(_db.categoryRows).insert(
            category.copyWith(isBuiltIn: false).toCompanion(),
          );
      return category;
    });
  }

  @override
  Future<Result<ReminderCategory>> update(ReminderCategory category) {
    return _guard<ReminderCategory>('update', () async {
      final bool replaced =
          await _db.update(_db.categoryRows).replace(category.toCompanion());
      if (!replaced) {
        throw _CategoryNotFound(category.id);
      }
      return category;
    });
  }

  @override
  Future<Result<void>> delete(String id) async {
    final Result<ReminderCategory> existing = await getCategory(id);
    if (existing
        case Failure<ReminderCategory>(
          failure: final AppFailure failure,
        )) {
      return Failure<void>(failure);
    }

    if ((existing as Success<ReminderCategory>).value.isBuiltIn) {
      return const Failure<void>(
        ValidationFailure(
          message:
              'Built-in categories cannot be deleted. Hide it instead to keep '
              'existing reminders intact.',
        ),
      );
    }

    return _guard<void>('delete', () async {
      // Reminders referencing this category are set to uncategorised by the
      // ON DELETE SET NULL foreign key, which requires `PRAGMA foreign_keys`
      // to be on — see AppDatabase.migration.beforeOpen.
      await (_db.delete(_db.categoryRows)
            ..where(($CategoryRowsTable c) => c.id.equals(id)))
          .go();
    });
  }

  @override
  Future<Result<void>> seedBuiltIns() {
    return _guard<void>('seedBuiltIns', () async {
      await _db.batch((Batch batch) {
        batch.insertAll(
          _db.categoryRows,
          BuiltInCategory.seed().map(
            (ReminderCategory category) => category.toCompanion(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });
    });
  }

  List<ReminderCategory> _toEntities(List<CategoryRow> rows) =>
      rows.map((CategoryRow row) => row.toEntity()).toList(growable: false);

  Future<Result<T>> _guard<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return Success<T>(await action());
    } on _CategoryNotFound catch (error) {
      return Failure<T>(
        NotFoundFailure(
          message: 'That category no longer exists.',
          entityId: error.id,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('$operation failed', error: error, stackTrace: stackTrace);
      return Failure<T>(
        DatabaseFailure(
          message: 'Could not reach your categories. Please try again.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Internal sentinel distinguishing "no such row" from a driver error.
final class _CategoryNotFound implements Exception {
  const _CategoryNotFound(this.id);

  final String id;
}
