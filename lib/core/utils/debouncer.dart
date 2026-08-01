/// Coalesces bursts of calls into a single trailing invocation.
library;

import 'dart:async';

/// Delays an action until [duration] has elapsed without a further call.
///
/// Used by the search field so that typing does not issue a database query per
/// keystroke. Callers **must** [dispose] the debouncer, otherwise a pending
/// timer can fire against a disposed consumer.
final class Debouncer {
  /// Creates a debouncer with the given quiet period.
  Debouncer({this.duration = const Duration(milliseconds: 300)});

  /// Quiet period that must elapse before the action runs.
  final Duration duration;

  Timer? _timer;

  /// Whether an invocation is currently pending.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action], replacing any previously scheduled one.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancels any pending invocation without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cancels the pending invocation and releases the timer.
  void dispose() => cancel();
}
