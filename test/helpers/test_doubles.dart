/// Shared fakes and builders for the test suite.
///
/// Hand-written fakes are preferred over generated mocks for the repository and
/// scheduler: the tests assert on *behaviour* (what ended up scheduled), which
/// a small in-memory implementation expresses far more clearly than a stack of
/// `when(...)` stubs.
library;

import 'dart:async';

import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Builds a reminder with sensible defaults, overriding only what matters.
Reminder buildReminder({
  String id = 'reminder-1',
  String title = 'Take tablets',
  DateTime? dueAt,
  DateTime? anchorAt,
  RecurrenceRule recurrence = const RecurrenceRule.once(),
  ReminderStatus status = ReminderStatus.scheduled,
  ReminderPriority priority = ReminderPriority.normal,
  String? notes,
  String? categoryId,
  bool isSpoken = true,
  int occurrenceCount = 0,
  DateTime? createdAt,
}) {
  final DateTime due = dueAt ?? DateTime(2026, 8, 1, 9);
  final DateTime created = createdAt ?? DateTime(2026, 7, 31, 12);
  return Reminder(
    id: id,
    title: title,
    notes: notes,
    categoryId: categoryId,
    priority: priority,
    anchorAt: anchorAt ?? due,
    dueAt: due,
    recurrence: recurrence,
    status: status,
    isSpoken: isSpoken,
    occurrenceCount: occurrenceCount,
    createdAt: created,
    updatedAt: created,
  );
}

/// An in-memory [ReminderRepository].
final class FakeReminderRepository implements ReminderRepository {
  /// Creates a repository seeded with [initial].
  FakeReminderRepository([List<Reminder> initial = const <Reminder>[]]) {
    for (final Reminder reminder in initial) {
      _rows[reminder.id] = reminder;
    }
  }

  final Map<String, Reminder> _rows = <String, Reminder>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Set to fail every operation with this failure, to exercise error paths.
  AppFailure? failWith;

  /// Everything currently stored, for assertions.
  List<Reminder> get rows => _rows.values.toList();

  @override
  Stream<List<Reminder>> watchReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  }) async* {
    yield _query(filter: filter, sort: sort, limit: limit, offset: offset);
    yield* _changes.stream.map(
      (_) => _query(filter: filter, sort: sort, limit: limit, offset: offset),
    );
  }

  @override
  Stream<Reminder?> watchReminder(String id) async* {
    yield _rows[id];
    yield* _changes.stream.map((_) => _rows[id]);
  }

  @override
  Future<Result<List<Reminder>>> getReminders({
    ReminderFilter filter = ReminderFilter.none,
    ReminderSort sort = ReminderSort.dueDateAscending,
    int? limit,
    int offset = 0,
  }) async =>
      _guard(
        () => _query(filter: filter, sort: sort, limit: limit, offset: offset),
      );

  @override
  Future<Result<Reminder>> getReminder(String id) async {
    final AppFailure? failure = failWith;
    if (failure != null) {
      return Failure<Reminder>(failure);
    }
    final Reminder? reminder = _rows[id];
    return reminder == null
        ? Failure<Reminder>(
            NotFoundFailure(message: 'Not found', entityId: id),
          )
        : Success<Reminder>(reminder);
  }

  @override
  Future<Result<List<Reminder>>> getDueBefore(DateTime horizon) async => _guard(
        () => _rows.values
            .where(
              (Reminder r) => r.isActive && !r.dueAt.isAfter(horizon),
            )
            .toList()
          ..sort((Reminder a, Reminder b) => a.dueAt.compareTo(b.dueAt)),
      );

  @override
  Future<Result<List<Reminder>>> getActive() async => _guard(
        () => _rows.values.where((Reminder r) => r.isActive).toList()
          ..sort((Reminder a, Reminder b) => a.dueAt.compareTo(b.dueAt)),
      );

  @override
  Future<Result<Reminder>> create(Reminder reminder) async => _guard(() {
        _rows[reminder.id] = reminder;
        _notify();
        return reminder;
      });

  @override
  Future<Result<Reminder>> update(Reminder reminder) async {
    final AppFailure? failure = failWith;
    if (failure != null) {
      return Failure<Reminder>(failure);
    }
    if (!_rows.containsKey(reminder.id)) {
      return Failure<Reminder>(
        NotFoundFailure(message: 'Not found', entityId: reminder.id),
      );
    }
    _rows[reminder.id] = reminder;
    _notify();
    return Success<Reminder>(reminder);
  }

  @override
  Future<Result<void>> updateAll(List<Reminder> reminders) async => _guard(() {
        for (final Reminder reminder in reminders) {
          _rows[reminder.id] = reminder;
        }
        _notify();
      });

  @override
  Future<Result<void>> delete(String id) async => _guard(() {
        _rows.remove(id);
        _notify();
      });

  @override
  Future<Result<int>> deleteWhere(ReminderFilter filter) async => _guard(() {
        final List<Reminder> matching =
            _query(filter: filter, sort: ReminderSort.dueDateAscending);
        for (final Reminder reminder in matching) {
          _rows.remove(reminder.id);
        }
        _notify();
        return matching.length;
      });

  @override
  Future<Result<void>> deleteAll() async => _guard(() {
        _rows.clear();
        _notify();
      });

  @override
  Future<Result<int>> count(
          {ReminderFilter filter = ReminderFilter.none}) async =>
      _guard(
        () =>
            _query(filter: filter, sort: ReminderSort.dueDateAscending).length,
      );

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();

  List<Reminder> _query({
    required ReminderFilter filter,
    required ReminderSort sort,
    int? limit,
    int offset = 0,
  }) {
    final List<Reminder> matching = _rows.values
        .where((Reminder reminder) => filter.matches(reminder))
        .toList()
      ..sort(sort.comparator);

    final List<Reminder> paged = matching.skip(offset).toList(growable: false);
    return limit == null ? paged : paged.take(limit).toList(growable: false);
  }

  Result<T> _guard<T>(T Function() action) {
    final AppFailure? failure = failWith;
    return failure != null ? Failure<T>(failure) : Success<T>(action());
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

/// Records what the scheduler was asked to do.
final class RecordingScheduler implements ReminderScheduler {
  /// Reminders passed to [schedule], newest last.
  final List<Reminder> scheduled = <Reminder>[];

  /// Ids passed to [cancelById] or [cancel].
  final List<String> cancelled = <String>[];

  /// How many times [rescheduleAll] ran.
  int rescheduleAllCount = 0;

  /// How many times [reconcileMissed] ran.
  int reconcileCount = 0;

  /// Set to fail every operation.
  AppFailure? failWith;

  @override
  Future<Result<void>> schedule(Reminder reminder) async {
    final AppFailure? failure = failWith;
    if (failure != null) {
      return Failure<void>(failure);
    }
    scheduled.add(reminder);
    return voidSuccess;
  }

  @override
  Future<Result<void>> cancel(Reminder reminder) => cancelById(reminder.id);

  @override
  Future<Result<void>> cancelById(String id) async {
    final AppFailure? failure = failWith;
    if (failure != null) {
      return Failure<void>(failure);
    }
    cancelled.add(id);
    return voidSuccess;
  }

  @override
  Future<Result<int>> rescheduleAll() async {
    rescheduleAllCount++;
    return const Success<int>(0);
  }

  @override
  Future<Result<int>> reconcileMissed() async {
    reconcileCount++;
    return const Success<int>(0);
  }

  @override
  Future<Result<void>> ensureBackgroundRefreshScheduled() async => voidSuccess;
}
