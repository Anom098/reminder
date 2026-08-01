/// Creates a reminder and places it on the OS schedule.
library;

import 'package:uuid/uuid.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/services/reminder_scheduler.dart';

/// The fields a caller supplies when creating a reminder.
///
/// A dedicated input type keeps the use case's signature stable as the editor
/// grows fields, and lets the voice flow and the manual form share one entry
/// point.
final class CreateReminderInput {
  /// Creates an input.
  const CreateReminderInput({
    required this.title,
    required this.dueAt,
    this.notes,
    this.categoryId,
    this.priority = ReminderPriority.normal,
    this.recurrence = const RecurrenceRule.once(),
    this.colorValue,
    this.isSpoken = true,
    this.spokenTextOverride,
    this.timeZoneId,
  });

  /// What the reminder is about.
  final String title;

  /// When it first fires.
  final DateTime dueAt;

  /// Optional detail.
  final String? notes;

  /// Owning category.
  final String? categoryId;

  /// Importance.
  final ReminderPriority priority;

  /// Repetition.
  final RecurrenceRule recurrence;

  /// Colour override.
  final int? colorValue;

  /// Whether to announce it aloud.
  final bool isSpoken;

  /// Exact phrase to speak.
  final String? spokenTextOverride;

  /// IANA zone the reminder was authored in.
  final String? timeZoneId;
}

/// Validates, persists and schedules a new reminder.
final class CreateReminder {
  /// Creates the use case.
  const CreateReminder({
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
  /// Fails with a [ValidationFailure] when the input breaks a domain
  /// invariant, including a due time in the past: silently bumping it to
  /// "now + 1 minute" would create a reminder the user did not ask for.
  ///
  /// Scheduling failures do **not** fail the operation. The reminder is already
  /// persisted at that point, and the background top-up pass will retry; losing
  /// the user's input because a notification slot could not be claimed would be
  /// the worse outcome.
  Future<Result<Reminder>> call(CreateReminderInput input) async {
    final DateTime now = _clock.now();
    final DateTime dueAt = input.dueAt.truncatedToMinute;

    if (!dueAt.isAfter(now.subtract(const Duration(minutes: 1)))) {
      return const Failure<Reminder>(
        ValidationFailure(
          message: 'Choose a time in the future.',
          fieldErrors: <String, String>{
            'dueAt': 'This time has already passed.'
          },
        ),
      );
    }

    final Reminder reminder = Reminder(
      id: _uuid.v4(),
      title: input.title.trim(),
      notes: _blankToNull(input.notes),
      categoryId: input.categoryId,
      priority: input.priority,
      anchorAt: dueAt,
      dueAt: dueAt,
      recurrence: input.recurrence,
      status: ReminderStatus.scheduled,
      colorValue: input.colorValue,
      isSpoken: input.isSpoken,
      spokenTextOverride: _blankToNull(input.spokenTextOverride),
      timeZoneId: input.timeZoneId,
      createdAt: now,
      updatedAt: now,
    );

    final Map<String, String> errors = reminder.validate();
    if (errors.isNotEmpty) {
      return Failure<Reminder>(
        ValidationFailure(
          message: errors.values.first,
          fieldErrors: errors,
        ),
      );
    }

    final Result<Reminder> saved = await _repository.create(reminder);
    if (saved case Success<Reminder>(value: final Reminder created)) {
      await _scheduler.schedule(created);
    }
    return saved;
  }

  static String? _blankToNull(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
