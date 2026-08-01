/// Logging abstraction.
///
/// Application code depends on [AppLogger], never on the `logger` package
/// directly. That keeps the logging backend swappable (console today, Crashlytics
/// or a file sink tomorrow) and makes logging trivially fakeable in tests.
library;

/// Severity levels understood by [AppLogger].
///
/// Ordered from most to least verbose; [LogLevel.off] disables logging entirely.
enum LogLevel {
  /// Extremely fine-grained tracing. Off outside local debugging.
  trace(0),

  /// Developer diagnostics.
  debug(1),

  /// Notable lifecycle events (reminder scheduled, backup written).
  info(2),

  /// Recoverable problems that did not fail the operation.
  warning(3),

  /// Operations that failed.
  error(4),

  /// No logging at all.
  off(5);

  const LogLevel(this.severity);

  /// Numeric severity; higher is more severe.
  final int severity;

  /// Parses a level from its lowercase name, falling back to [fallback].
  ///
  /// Accepts the aliases `verbose` (→ [trace]), `warn` (→ [warning]) and
  /// `nothing`/`none` (→ [off]) so that configuration files can use whichever
  /// spelling their author expects.
  static LogLevel parse(String? raw, {LogLevel fallback = LogLevel.info}) {
    switch (raw?.trim().toLowerCase()) {
      case 'trace':
      case 'verbose':
        return LogLevel.trace;
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warning':
      case 'warn':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      case 'off':
      case 'none':
      case 'nothing':
        return LogLevel.off;
      default:
        return fallback;
    }
  }
}

/// Records diagnostic messages.
///
/// Implementations must be safe to call from any isolate, including the
/// background isolates used for notification actions and scheduled work.
abstract interface class AppLogger {
  /// Logs at [LogLevel.trace].
  void trace(String message, {Object? error, StackTrace? stackTrace});

  /// Logs at [LogLevel.debug].
  void debug(String message, {Object? error, StackTrace? stackTrace});

  /// Logs at [LogLevel.info].
  void info(String message, {Object? error, StackTrace? stackTrace});

  /// Logs at [LogLevel.warning].
  void warning(String message, {Object? error, StackTrace? stackTrace});

  /// Logs at [LogLevel.error].
  void error(String message, {Object? error, StackTrace? stackTrace});

  /// Returns a logger that prefixes every message with [name].
  ///
  /// Used to tag output by subsystem, e.g. `logger.forContext('Scheduler')`.
  AppLogger forContext(String name);
}

/// An [AppLogger] that discards everything.
///
/// The default in tests, so that unit tests do not spam the console.
final class NoopLogger implements AppLogger {
  /// Creates a no-op logger.
  const NoopLogger();

  @override
  void trace(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  AppLogger forContext(String name) => this;
}
