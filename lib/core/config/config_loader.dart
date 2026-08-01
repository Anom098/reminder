/// Loads [AppConfig] from the bundled `.env` asset.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:voice_reminder/core/config/app_config.dart';

/// Reads runtime configuration from disk.
///
/// Separated from [AppConfig] so that the parsing logic stays free of I/O and
/// can be unit-tested without a Flutter binding.
abstract final class ConfigLoader {
  /// Loads configuration from [fileName], falling back to defaults.
  ///
  /// A missing or unreadable `.env` is not an error. The app ships with sane
  /// defaults for every value, and refusing to start because an optional
  /// configuration asset is absent would be a worse outcome than running with
  /// defaults.
  static Future<AppConfig> load({String fileName = '.env'}) async {
    try {
      await dotenv.load(fileName: fileName);
      return AppConfig.fromMap(dotenv.env);
    } on Object {
      // Intentionally swallowed: see doc comment. The logger does not exist yet
      // at this point in the boot sequence, so there is nowhere to report to.
      return const AppConfig();
    }
  }
}
