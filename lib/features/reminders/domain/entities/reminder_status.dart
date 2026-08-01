/// Lifecycle state of a reminder.
library;

/// Where a reminder sits in its lifecycle.
///
/// This is a *derived-but-stored* value: it is persisted so that queries can
/// filter on it cheaply, and recomputed whenever the reminder is completed,
/// snoozed, disabled or its next occurrence passes.
enum ReminderStatus {
  /// Scheduled and waiting to fire.
  scheduled('Scheduled'),

  /// Temporarily pushed back; `dueAt` points at the snoozed time.
  snoozed('Snoozed'),

  /// Fired and acknowledged by the user.
  completed('Completed'),

  /// Fired but never acknowledged, and now past the grace period.
  missed('Missed'),

  /// Turned off by the user. Keeps its configuration but is not scheduled.
  disabled('Disabled'),

  /// A repeating reminder whose recurrence has run out.
  finished('Finished');

  const ReminderStatus(this.label);

  /// User-facing name.
  final String label;

  /// Whether a reminder in this state occupies an OS notification slot.
  bool get isActive =>
      this == ReminderStatus.scheduled || this == ReminderStatus.snoozed;

  /// Whether the reminder is done with, one way or another.
  bool get isTerminal =>
      this == ReminderStatus.completed || this == ReminderStatus.finished;

  /// Parses a stored name, defaulting to [ReminderStatus.scheduled].
  static ReminderStatus parse(String? raw) {
    for (final ReminderStatus value in ReminderStatus.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return ReminderStatus.scheduled;
  }
}
