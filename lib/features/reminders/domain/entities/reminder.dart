/// The central domain entity.
library;

import 'package:equatable/equatable.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/utils/date_time_extensions.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';

/// A scheduled, optionally repeating, optionally spoken reminder.
///
/// The entity is immutable. State transitions are expressed as methods that
/// return a new instance ([complete], [snooze], [advanceToNextOccurrence], …),
/// which keeps the transition rules in the domain layer instead of scattered
/// across repositories and view models.
///
/// ### Time model
///
/// * [anchorAt] is the reminder's *original* due instant. It never changes and
///   defines the wall-clock time and day-of-month that recurrence inherits.
/// * [dueAt] is the *next* instant the reminder should fire. Completing or
///   snoozing moves it; recurrence advances it.
///
/// Keeping the two separate is what stops a repeating reminder from drifting:
/// occurrences are always computed from [anchorAt], never from the last fire
/// time.
final class Reminder extends Equatable {
  /// Creates a reminder.
  const Reminder({
    required this.id,
    required this.title,
    required this.anchorAt,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.categoryId,
    this.priority = ReminderPriority.normal,
    this.recurrence = const RecurrenceRule.once(),
    this.status = ReminderStatus.scheduled,
    this.colorValue,
    this.isSpoken = true,
    this.spokenTextOverride,
    this.snoozedFrom,
    this.completedAt,
    this.lastFiredAt,
    this.occurrenceCount = 0,
    this.attachmentPath,
    this.timeZoneId,
  });

  /// Stable UUID.
  final String id;

  /// What the reminder is about. Non-empty; see [validate].
  final String title;

  /// Free-form additional detail.
  final String? notes;

  /// Identifier of the owning category, or `null` for uncategorised.
  final String? categoryId;

  /// Importance.
  final ReminderPriority priority;

  /// The original due instant; the fixed point recurrence expands from.
  final DateTime anchorAt;

  /// The next instant this reminder fires.
  final DateTime dueAt;

  /// How the reminder repeats.
  final RecurrenceRule recurrence;

  /// Lifecycle state.
  final ReminderStatus status;

  /// Per-reminder colour override, ARGB. Falls back to the category colour.
  final int? colorValue;

  /// Whether the reminder is announced aloud when it fires.
  final bool isSpoken;

  /// Exact phrase to speak. When `null`, [spokenText] composes one.
  final String? spokenTextOverride;

  /// The due instant the reminder had before it was snoozed.
  ///
  /// Restored on un-snooze, and used to keep the recurrence anchored to the
  /// original schedule rather than to the snoozed time.
  final DateTime? snoozedFrom;

  /// When the reminder was last marked complete.
  final DateTime? completedAt;

  /// When the reminder last fired.
  final DateTime? lastFiredAt;

  /// How many occurrences have already fired, used to honour
  /// [RecurrenceRule.maxOccurrences].
  final int occurrenceCount;

  /// Path to an attached file. Reserved; no UI ships in this release.
  final String? attachmentPath;

  /// IANA time zone the reminder was created in, e.g. `Europe/London`.
  ///
  /// Recorded so that a future release can offer "keep the local time when I
  /// travel" behaviour. Scheduling currently always uses the device zone.
  final String? timeZoneId;

  /// When the reminder was created.
  final DateTime createdAt;

  /// When the reminder was last modified.
  final DateTime updatedAt;

  /// Whether the reminder currently occupies an OS notification slot.
  bool get isActive => status.isActive;

  /// Whether the reminder is snoozed.
  bool get isSnoozed => status == ReminderStatus.snoozed;

  /// Whether the user has switched this reminder off.
  bool get isDisabled => status == ReminderStatus.disabled;

  /// Whether [dueAt] has passed relative to [now], with the fire tolerance
  /// applied.
  bool isOverdue(DateTime now) =>
      isActive && dueAt.add(AppConstants.reminderFireTolerance).isBefore(now);

  /// Whether [dueAt] falls on [now]'s calendar day.
  bool isDueToday(DateTime now) => dueAt.isSameDayAs(now);

  /// Whether [dueAt] falls within the upcoming window after today.
  bool isUpcoming(DateTime now) =>
      dueAt.isAfter(now) &&
      dueAt.isBefore(now.add(AppConstants.upcomingWindow));

  /// The phrase announced when the reminder fires.
  ///
  /// A trailing full stop is added so that TTS engines apply sentence
  /// intonation and a natural pause instead of running into the next utterance.
  String get spokenText {
    final String? override = spokenTextOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final String subject = title.trim();
    return subject.endsWith('.') ||
            subject.endsWith('!') ||
            subject.endsWith('?')
        ? 'Reminder. $subject'
        : 'Reminder. $subject.';
  }

  /// A deterministic 31-bit notification id derived from [id].
  ///
  /// Android and iOS key pending notifications by integer, while reminders are
  /// keyed by UUID. Deriving the integer from the UUID means the id survives
  /// app restarts and database restores without a separate mapping table.
  int get notificationId => id.hashCode & 0x7fffffff;

  /// Validates domain invariants.
  ///
  /// Returns a field-name → message map; empty means valid. Kept as a plain map
  /// so the editor screen can show inline errors without a separate DTO.
  Map<String, String> validate() {
    final Map<String, String> errors = <String, String>{};

    final String trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      errors['title'] = 'Give the reminder a title.';
    } else if (trimmedTitle.length > AppConstants.maxTitleLength) {
      errors['title'] =
          'Keep the title under ${AppConstants.maxTitleLength} characters.';
    }

    if ((notes?.length ?? 0) > AppConstants.maxNotesLength) {
      errors['notes'] =
          'Notes are limited to ${AppConstants.maxNotesLength} characters.';
    }

    final DateTime? until = recurrence.until;
    if (until != null && until.isBefore(anchorAt)) {
      errors['recurrence'] = 'The end date is before the first reminder.';
    }

    return errors;
  }

  /// The occurrence that follows [dueAt], or `null` when the rule is exhausted.
  DateTime? nextOccurrenceAfter(DateTime reference) {
    if (!recurrence.isRepeating) {
      return null;
    }
    final int? max = recurrence.maxOccurrences;
    if (max != null && occurrenceCount + 1 >= max) {
      return null;
    }
    return recurrence.nextOccurrence(anchor: anchorAt, after: reference);
  }

  /// Marks this reminder as fired at [firedAt].
  ///
  /// Repeating reminders roll forward to their next occurrence and stay
  /// [ReminderStatus.scheduled]; one-shot reminders become
  /// [ReminderStatus.completed]. A repeating reminder that has run out of
  /// occurrences becomes [ReminderStatus.finished].
  Reminder complete({required DateTime firedAt}) {
    final DateTime? next = nextOccurrenceAfter(firedAt);

    if (next == null) {
      return copyWith(
        status: recurrence.isRepeating
            ? ReminderStatus.finished
            : ReminderStatus.completed,
        completedAt: firedAt,
        lastFiredAt: firedAt,
        occurrenceCount: occurrenceCount + 1,
        updatedAt: firedAt,
        clearSnoozedFrom: true,
      );
    }

    return copyWith(
      dueAt: next,
      status: ReminderStatus.scheduled,
      lastFiredAt: firedAt,
      occurrenceCount: occurrenceCount + 1,
      updatedAt: firedAt,
      clearSnoozedFrom: true,
      clearCompletedAt: true,
    );
  }

  /// Pushes the reminder back by [duration] from [now].
  ///
  /// The pre-snooze due instant is preserved in [snoozedFrom] so that
  /// recurrence continues from the original schedule.
  Reminder snooze({required Duration duration, required DateTime now}) {
    final Duration clamped = duration < AppConstants.minSnooze
        ? AppConstants.minSnooze
        : (duration > AppConstants.maxSnooze
            ? AppConstants.maxSnooze
            : duration);

    return copyWith(
      dueAt: now.add(clamped).truncatedToMinute,
      snoozedFrom: snoozedFrom ?? dueAt,
      status: ReminderStatus.snoozed,
      lastFiredAt: now,
      updatedAt: now,
    );
  }

  /// Rolls a repeating reminder forward without counting an acknowledgement.
  ///
  /// Used by the catch-up pass that runs at start-up: occurrences the device
  /// slept through are moved past rather than fired late in a burst.
  Reminder advanceToNextOccurrence({required DateTime now}) {
    final DateTime? next = recurrence.nextOccurrence(
      anchor: anchorAt,
      after: now,
    );
    if (next == null) {
      return copyWith(
        status: ReminderStatus.finished,
        updatedAt: now,
        clearSnoozedFrom: true,
      );
    }
    return copyWith(
      dueAt: next,
      status: ReminderStatus.scheduled,
      updatedAt: now,
      clearSnoozedFrom: true,
    );
  }

  /// Marks an unacknowledged reminder as missed.
  Reminder markMissed({required DateTime now}) => copyWith(
        status: ReminderStatus.missed,
        updatedAt: now,
      );

  /// Turns the reminder on or off without losing its configuration.
  Reminder setEnabled({required bool enabled, required DateTime now}) {
    if (enabled == !isDisabled) {
      return this;
    }
    if (!enabled) {
      return copyWith(status: ReminderStatus.disabled, updatedAt: now);
    }
    // Re-enabling a reminder whose time has passed moves it to its next
    // occurrence, so switching it back on never fires immediately.
    final bool inPast = dueAt.isBefore(now);
    if (!inPast) {
      return copyWith(status: ReminderStatus.scheduled, updatedAt: now);
    }
    final DateTime? next = recurrence.nextOccurrence(
      anchor: anchorAt,
      after: now,
    );
    return copyWith(
      dueAt: next ?? dueAt,
      status: next == null ? ReminderStatus.missed : ReminderStatus.scheduled,
      updatedAt: now,
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields need explicit `clear*` flags to distinguish "leave
  /// unchanged" from "set to null".
  Reminder copyWith({
    String? id,
    String? title,
    String? notes,
    String? categoryId,
    ReminderPriority? priority,
    DateTime? anchorAt,
    DateTime? dueAt,
    RecurrenceRule? recurrence,
    ReminderStatus? status,
    int? colorValue,
    bool? isSpoken,
    String? spokenTextOverride,
    DateTime? snoozedFrom,
    DateTime? completedAt,
    DateTime? lastFiredAt,
    int? occurrenceCount,
    String? attachmentPath,
    String? timeZoneId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearNotes = false,
    bool clearCategoryId = false,
    bool clearColorValue = false,
    bool clearSpokenTextOverride = false,
    bool clearSnoozedFrom = false,
    bool clearCompletedAt = false,
    bool clearAttachmentPath = false,
  }) =>
      Reminder(
        id: id ?? this.id,
        title: title ?? this.title,
        notes: clearNotes ? null : (notes ?? this.notes),
        categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
        priority: priority ?? this.priority,
        anchorAt: anchorAt ?? this.anchorAt,
        dueAt: dueAt ?? this.dueAt,
        recurrence: recurrence ?? this.recurrence,
        status: status ?? this.status,
        colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
        isSpoken: isSpoken ?? this.isSpoken,
        spokenTextOverride: clearSpokenTextOverride
            ? null
            : (spokenTextOverride ?? this.spokenTextOverride),
        snoozedFrom:
            clearSnoozedFrom ? null : (snoozedFrom ?? this.snoozedFrom),
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        lastFiredAt: lastFiredAt ?? this.lastFiredAt,
        occurrenceCount: occurrenceCount ?? this.occurrenceCount,
        attachmentPath: clearAttachmentPath
            ? null
            : (attachmentPath ?? this.attachmentPath),
        timeZoneId: timeZoneId ?? this.timeZoneId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        title,
        notes,
        categoryId,
        priority,
        anchorAt,
        dueAt,
        recurrence,
        status,
        colorValue,
        isSpoken,
        spokenTextOverride,
        snoozedFrom,
        completedAt,
        lastFiredAt,
        occurrenceCount,
        attachmentPath,
        timeZoneId,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'Reminder($id, "$title", due $dueAt, ${status.name}, '
      '${recurrence.frequency.name})';
}
