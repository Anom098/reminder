/// Copies an existing reminder.
library;

import 'package:uuid/uuid.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// Creates an independent copy of a reminder.
final class DuplicateReminder {
  /// Creates the use case.
  const DuplicateReminder({
    required ReminderRepository repository,
    required ReminderScheduler scheduler,
    required Clock clock,
    Uuid uuid = const Uuid(),
  })  : _repository = repository,
        _scheduler = scheduler,
        _clock = clock,
        _uuid = uuid;

  final ReminderRepository _repository;
  final ReminderScheduler _scheduler;
  final Clock _clock;
  final Uuid _uuid;

  /// Runs the use case.
  ///
  /// The copy is reset to a fresh scheduled state: history (completion,
  /// occurrence count, last fire) belongs to the original. When the source's
  /// due time has already passed, the copy is moved to the source's next future
  /// occurrence, or to the same clock time tomorrow for a one-shot reminder —
  /// duplicating a reminder to have it fire in the past is never the intent.
  Future<Result<Reminder>> call(String id, {String? titleSuffix}) async {
    final Result<Reminder> source = await _repository.getReminder(id);
    if (source case Failure<Reminder>(failure: final AppFailure failure)) {
      return Failure<Reminder>(failure);
    }

    final Reminder original = (source as Success<Reminder>).value;
    final DateTime now = _clock.now();
    final DateTime dueAt = original.dueAt.isAfter(now)
        ? original.dueAt
        : (original.recurrence.nextOccurrence(
              anchor: original.anchorAt,
              after: now,
            ) ??
            _sameTimeTomorrow(original.dueAt, now));

    final String suffix = titleSuffix ?? ' (copy)';
    final Reminder copy = original.copyWith(
      id: _uuid.v4(),
      title: '${original.title}$suffix',
      anchorAt: dueAt,
      dueAt: dueAt,
      status: ReminderStatus.scheduled,
      occurrenceCount: 0,
      createdAt: now,
      updatedAt: now,
      clearCompletedAt: true,
      clearSnoozedFrom: true,
    );

    final Result<Reminder> saved = await _repository.create(copy);
    if (saved case Success<Reminder>(value: final Reminder created)) {
      await _scheduler.schedule(created);
    }
    return saved;
  }

  static DateTime _sameTimeTomorrow(DateTime source, DateTime now) {
    final DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      source.hour,
      source.minute,
    );
    return candidate.isAfter(now)
        ? candidate
        : candidate.add(const Duration(days: 1));
  }
}
