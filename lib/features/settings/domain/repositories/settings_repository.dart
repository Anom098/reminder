/// Persistence contract for user settings.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';

/// Reads and writes [AppSettings].
///
/// Settings are read synchronously on first frame (see
/// `sharedPreferencesProvider`), which is why [current] is not a `Future`:
/// flashing the wrong theme for one frame is a visible defect.
abstract interface class SettingsRepository {
  /// Emits the settings on every change, starting with the current value.
  Stream<AppSettings> watch();

  /// The settings as of now.
  AppSettings get current;

  /// Persists [settings] in full.
  Future<Result<AppSettings>> save(AppSettings settings);

  /// Restores every setting to its default.
  Future<Result<AppSettings>> reset();
}
