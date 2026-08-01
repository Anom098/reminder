/// Reminder importance.
library;

/// How urgent a reminder is.
///
/// Priority drives sort order, the accent shown on the reminder card, and
/// whether the notification is allowed to bypass Do Not Disturb.
enum ReminderPriority {
  /// Nice to know. Sorted last, no interruption.
  low('Low', 0),

  /// The default.
  normal('Normal', 1),

  /// Sorted first within a time bucket and visually emphasised.
  high('High', 2),

  /// Treated as time-critical; the notification is delivered with maximum
  /// importance so the OS surfaces it as a heads-up alert.
  urgent('Urgent', 3);

  const ReminderPriority(this.label, this.weight);

  /// User-facing name.
  final String label;

  /// Sort weight; higher is more important.
  final int weight;

  /// Parses a stored name, defaulting to [ReminderPriority.normal].
  static ReminderPriority parse(String? raw) {
    for (final ReminderPriority value in ReminderPriority.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return ReminderPriority.normal;
  }

  /// Whether this priority should escape Do Not Disturb.
  bool get isTimeCritical => this == ReminderPriority.urgent;
}
