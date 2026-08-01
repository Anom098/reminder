/// Drift-backed [ReminderRepository].
library;

import 'package:drift/drift.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/data/mappers/reminder_mapper.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';

/// Stores reminders in the local SQLite database.
///
/// Every method funnels through [_guard], which converts any driver exception
/// into a [DatabaseFailure] and logs it. Nothing here throws.
final class DriftReminderRepository implements ReminderRepository {
  /// Creates a repository over [database].
  DriftReminderRepository({
    required AppDatabase database,
    required AppLogger logger,
  })  : _db = database,
        _log = logger.forContext('ReminderRepository');

  final AppDatabase _db;
  final AppLogger _log;

  @override
  Stream<List<Reminder>> watchReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  }) {
    return _buildQuery(filter: filter, sort: sort, limit: limit, offset: offset)
        .watch()
        .map(_toEntities)
        // A driver error mid-stream is a bug. Log it and suppress it rather
        // than tearing down every list currently on screen; the next write
        // re-emits and the UI recovers on its own.
        .handleError((Object error, StackTrace stackTrace) {
      _log.error('watchReminders failed', error: error, stackTrace: stackTrace);
    });
  }

  @override
  Stream<Reminder?> watchReminder(String id) {
    return (_db.select(_db.reminderRows)
          ..where(($ReminderRowsTable row) => row.id.equals(id)))
        .watchSingleOrNull()
        .map((ReminderRow? row) => row?.toEntity());
  }

  @override
  Future<Result<List<Reminder>>> getReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  }) {
    return _guard<List<Reminder>>('getReminders', () async {
      final List<ReminderRow> rows = await _buildQuery(
        filter: filter,
        sort: sort,
        limit: limit,
        offset: offset,
      ).get();
      return _toEntities(rows);
    });
  }

  @override
  Future<Result<Reminder>> getReminder(String id) {
    return _guard<Reminder>('getReminder', () async {
      final ReminderRow? row = await (_db.select(_db.reminderRows)
            ..where(($ReminderRowsTable r) => r.id.equals(id)))
          .getSingleOrNull();

      if (row == null) {
        throw _NotFound(id);
      }
      return row.toEntity();
    });
  }

  @override
  Future<Result<List<Reminder>>> getDueBefore(DateTime horizon) {
    return _guard<List<Reminder>>('getDueBefore', () async {
      final List<ReminderRow> rows = await (_db.select(_db.reminderRows)
            ..where(
              ($ReminderRowsTable r) =>
                  r.dueAt.isSmallerOrEqualValue(horizon) &
                  r.status.isIn(_activeStatusNames),
            )
            ..orderBy(<OrderClauseGenerator<$ReminderRowsTable>>[
              ($ReminderRowsTable r) => OrderingTerm.asc(r.dueAt),
            ]))
          .get();
      return _toEntities(rows);
    });
  }

  @override
  Future<Result<List<Reminder>>> getActive() {
    return _guard<List<Reminder>>('getActive', () async {
      final List<ReminderRow> rows = await (_db.select(_db.reminderRows)
            ..where(($ReminderRowsTable r) => r.status.isIn(_activeStatusNames))
            ..orderBy(<OrderClauseGenerator<$ReminderRowsTable>>[
              ($ReminderRowsTable r) => OrderingTerm.asc(r.dueAt),
            ]))
          .get();
      return _toEntities(rows);
    });
  }

  @override
  Future<Result<Reminder>> create(Reminder reminder) {
    return _guard<Reminder>('create', () async {
      await _db.into(_db.reminderRows).insert(reminder.toCompanion());
      _log.info('Created reminder ${reminder.id} due ${reminder.dueAt}');
      return reminder;
    });
  }

  @override
  Future<Result<Reminder>> update(Reminder reminder) {
    return _guard<Reminder>('update', () async {
      final bool replaced =
          await _db.update(_db.reminderRows).replace(reminder.toCompanion());
      if (!replaced) {
        throw _NotFound(reminder.id);
      }
      return reminder;
    });
  }

  @override
  Future<Result<void>> updateAll(List<Reminder> reminders) {
    if (reminders.isEmpty) {
      return Future<Result<void>>.value(voidSuccess);
    }
    return _guard<void>('updateAll', () async {
      await _db.batch((Batch batch) {
        for (final Reminder reminder in reminders) {
          batch.replace(_db.reminderRows, reminder.toCompanion());
        }
      });
      _log.debug('Updated ${reminders.length} reminders in one transaction');
    });
  }

  @override
  Future<Result<void>> delete(String id) {
    // Deliberately succeeds when the row is already gone: a duplicate
    // notification action must not surface an error to the user.
    return _guard<void>('delete', () async {
      await (_db.delete(_db.reminderRows)
            ..where(($ReminderRowsTable r) => r.id.equals(id)))
          .go();
    });
  }

  @override
  Future<Result<int>> deleteWhere(ReminderFilter filter) {
    return _guard<int>('deleteWhere', () async {
      final List<Reminder> matching = _toEntities(
        await _buildQuery(
          filter: filter,
          sort: ReminderSort.dueDateAscending,
        ).get(),
      );
      if (matching.isEmpty) {
        return 0;
      }
      final List<String> ids =
          matching.map((Reminder reminder) => reminder.id).toList();
      await (_db.delete(_db.reminderRows)
            ..where(($ReminderRowsTable r) => r.id.isIn(ids)))
          .go();
      return ids.length;
    });
  }

  @override
  Future<Result<void>> deleteAll() {
    return _guard<void>('deleteAll', () async {
      await _db.delete(_db.reminderRows).go();
      _log.warning('Deleted every reminder');
    });
  }

  @override
  Future<Result<int>> count({ReminderFilter filter = ReminderFilter.none}) {
    return _guard<int>('count', () async {
      final List<ReminderRow> rows = await _buildQuery(
        filter: filter,
        sort: ReminderSort.dueDateAscending,
      ).get();
      return rows.length;
    });
  }

  /// Statuses that count as "on the schedule".
  static final List<String> _activeStatusNames = <String>[
    ReminderStatus.scheduled.name,
    ReminderStatus.snoozed.name,
  ];

  /// Translates a [ReminderFilter] and [ReminderSort] into a Drift query.
  ///
  /// Filtering and ordering happen in SQL rather than in Dart so that the
  /// `limit`/`offset` pagination is meaningful and the indexes on `due_at` and
  /// `status` are actually used.
  SimpleSelectStatement<$ReminderRowsTable, ReminderRow> _buildQuery({
    required ReminderFilter filter,
    required ReminderSort sort,
    int? limit,
    int offset = 0,
  }) {
    final SimpleSelectStatement<$ReminderRowsTable, ReminderRow> query =
        _db.select(_db.reminderRows);

    if (filter.statuses.isNotEmpty) {
      final List<String> names =
          filter.statuses.map((ReminderStatus status) => status.name).toList();
      query.where(($ReminderRowsTable r) => r.status.isIn(names));
    }

    if (!filter.includeDisabled) {
      query.where(
        ($ReminderRowsTable r) =>
            r.status.equals(ReminderStatus.disabled.name).not(),
      );
    }

    if (filter.priorities.isNotEmpty) {
      final List<String> names = filter.priorities
          .map((ReminderPriority priority) => priority.name)
          .toList();
      query.where(($ReminderRowsTable r) => r.priority.isIn(names));
    }

    if (filter.categoryIds.isNotEmpty) {
      final List<String> ids = filter.categoryIds.toList();
      query.where(($ReminderRowsTable r) => r.categoryId.isIn(ids));
    }

    final DateRange? range = filter.dueRange;
    if (range != null) {
      query.where(
        ($ReminderRowsTable r) =>
            r.dueAt.isBiggerOrEqualValue(range.start) &
            r.dueAt.isSmallerThanValue(range.end),
      );
    }

    final String? term = filter.normalisedSearchTerm;
    if (term != null) {
      // SQLite's LIKE has no ESCAPE clause here, so `%` and `_` typed into the
      // search box behave as wildcards. That is a harmless superset of the
      // expected behaviour for a search field, and avoids hand-rolling an
      // escaped comparison that drift cannot express.
      final String pattern = '%$term%';
      query.where(($ReminderRowsTable r) {
        // Category names participate in search, so typing "medicine" finds the
        // reminders filed under that category as well as those mentioning it.
        final Expression<bool> categoryMatch = r.categoryId.isInQuery(
          _db.selectOnly(_db.categoryRows)
            ..addColumns(<Expression<Object>>[_db.categoryRows.id])
            ..where(_db.categoryRows.name.lower().like(pattern)),
        );

        return r.title.lower().like(pattern) |
            r.notes.lower().like(pattern) |
            categoryMatch;
      });
    }

    query.orderBy(_orderingFor(sort));

    if (limit != null) {
      query.limit(limit, offset: offset);
    } else if (offset > 0) {
      // SQLite requires a LIMIT before an OFFSET; -1 means "no limit".
      query.limit(-1, offset: offset);
    }

    return query;
  }

  List<OrderClauseGenerator<$ReminderRowsTable>> _orderingFor(
    ReminderSort sort,
  ) {
    return switch (sort) {
      ReminderSort.dueDateAscending =>
        <OrderClauseGenerator<$ReminderRowsTable>>[
          ($ReminderRowsTable r) => OrderingTerm.asc(r.dueAt),
          ($ReminderRowsTable r) => OrderingTerm.asc(r.id),
        ],
      ReminderSort.dueDateDescending =>
        <OrderClauseGenerator<$ReminderRowsTable>>[
          ($ReminderRowsTable r) => OrderingTerm.desc(r.dueAt),
          ($ReminderRowsTable r) => OrderingTerm.asc(r.id),
        ],
      // Priority is stored as its enum *name*, so it cannot be ordered
      // lexicographically. A CASE expression maps each name to its weight.
      ReminderSort.priorityDescending =>
        <OrderClauseGenerator<$ReminderRowsTable>>[
          ($ReminderRowsTable r) => OrderingTerm.desc(_priorityWeight(r)),
          ($ReminderRowsTable r) => OrderingTerm.asc(r.dueAt),
        ],
      ReminderSort.titleAscending => <OrderClauseGenerator<$ReminderRowsTable>>[
          ($ReminderRowsTable r) => OrderingTerm.asc(r.title.lower()),
          ($ReminderRowsTable r) => OrderingTerm.asc(r.dueAt),
        ],
      ReminderSort.createdDescending =>
        <OrderClauseGenerator<$ReminderRowsTable>>[
          ($ReminderRowsTable r) => OrderingTerm.desc(r.createdAt),
          ($ReminderRowsTable r) => OrderingTerm.asc(r.id),
        ],
    };
  }

  Expression<int> _priorityWeight($ReminderRowsTable row) =>
      CaseWhenExpression<int>(
        cases: <CaseWhen<bool, int>>[
          CaseWhen<bool, int>(
            row.priority.equals('urgent'),
            then: const Constant<int>(3),
          ),
          CaseWhen<bool, int>(
            row.priority.equals('high'),
            then: const Constant<int>(2),
          ),
          CaseWhen<bool, int>(
            row.priority.equals('normal'),
            then: const Constant<int>(1),
          ),
        ],
        orElse: const Constant<int>(0),
      );

  List<Reminder> _toEntities(List<ReminderRow> rows) =>
      rows.map((ReminderRow row) => row.toEntity()).toList(growable: false);

  /// Runs [action], mapping exceptions to failures and logging them.
  Future<Result<T>> _guard<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return Success<T>(await action());
    } on _NotFound catch (error) {
      return Failure<T>(
        NotFoundFailure(
          message: 'That reminder no longer exists.',
          entityId: error.id,
        ),
      );
    } on Object catch (error, stackTrace) {
      _log.error('$operation failed', error: error, stackTrace: stackTrace);
      return Failure<T>(
        DatabaseFailure(
          message: 'Could not reach your reminders. Please try again.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Internal sentinel distinguishing "no such row" from a driver error.
final class _NotFound implements Exception {
  const _NotFound(this.id);

  final String id;
}
