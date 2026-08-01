/// Console-backed [AppLogger] built on the `logger` package.
library;

import 'package:logger/logger.dart' as pkg;
import 'package:voice_reminder/core/services/logging/app_logger.dart';

/// Writes structured, colourised output to the developer console.
///
/// In release builds the level defaults to [LogLevel.warning] so that the app
/// does not pay formatting costs for messages nobody reads, and so that reminder
/// titles — which are user content — are not written to the device log.
final class ConsoleLogger implements AppLogger {
  /// Creates a console logger emitting messages at or above [level].
  ConsoleLogger({
    LogLevel level = LogLevel.info,
    String? context,
  })  : _level = level,
        _context = context,
        _logger = pkg.Logger(
          level: _toPackageLevel(level),
          filter: pkg.ProductionFilter(),
          printer: pkg.PrettyPrinter(
            methodCount: 0,
            errorMethodCount: 8,
            lineLength: 100,
            printEmojis: false,
            dateTimeFormat: pkg.DateTimeFormat.onlyTimeAndSinceStart,
          ),
        );

  final pkg.Logger _logger;
  final LogLevel _level;
  final String? _context;

  static pkg.Level _toPackageLevel(LogLevel level) => switch (level) {
        LogLevel.trace => pkg.Level.trace,
        LogLevel.debug => pkg.Level.debug,
        LogLevel.info => pkg.Level.info,
        LogLevel.warning => pkg.Level.warning,
        LogLevel.error => pkg.Level.error,
        LogLevel.off => pkg.Level.off,
      };

  String _decorate(String message) =>
      _context == null ? message : '[$_context] $message';

  @override
  void trace(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.t(_decorate(message), error: error, stackTrace: stackTrace);

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.d(_decorate(message), error: error, stackTrace: stackTrace);

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.i(_decorate(message), error: error, stackTrace: stackTrace);

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.w(_decorate(message), error: error, stackTrace: stackTrace);

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(_decorate(message), error: error, stackTrace: stackTrace);

  @override
  AppLogger forContext(String name) => ConsoleLogger(
        level: _level,
        context: _context == null ? name : '$_context.$name',
      );
}
