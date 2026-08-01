/// Injectable source of the current time.
///
/// Scheduling and recurrence logic is the heart of this app and is entirely
/// time-dependent. Reading `DateTime.now()` directly would make that logic
/// untestable, so every component that needs the current instant takes a
/// [Clock].
library;

/// Provides the current wall-clock time.
abstract interface class Clock {
  /// The current local time.
  DateTime now();

  /// The current time in UTC.
  DateTime nowUtc();
}

/// A [Clock] backed by the device clock.
final class SystemClock implements Clock {
  /// Creates a system clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A [Clock] frozen at a fixed instant, for deterministic tests.
final class FixedClock implements Clock {
  /// Creates a clock that always reports [instant].
  FixedClock(this.instant);

  /// The instant reported by [now].
  DateTime instant;

  /// Moves the clock forward (or backward, for a negative [delta]).
  void advance(Duration delta) => instant = instant.add(delta);

  @override
  DateTime now() => instant;

  @override
  DateTime nowUtc() => instant.toUtc();
}
