/// Opens the platform database connection.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';

/// Opens the application database in the platform's documents directory.
///
/// [LazyDatabase] defers the actual open until the first query, which keeps
/// path resolution off the start-up critical path.
QueryExecutor openDatabaseConnection() {
  return LazyDatabase(() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File file =
        File(p.join(directory.path, AppConstants.databaseFileName));

    // Android ships an old, buggy system sqlite3 on some devices; this makes
    // the bundled library the one that actually gets loaded.
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    // sqlite3 writes temporary files during VACUUM and large sorts and needs a
    // writable location on both platforms.
    final Directory cacheDirectory = await getTemporaryDirectory();
    sqlite3.tempDirectory = cacheDirectory.path;

    return NativeDatabase.createInBackground(
      file,
      // Reminder writes happen from the notification isolate as well as the UI
      // isolate; sqlite3's default is already serialised, and the background
      // executor keeps queries off the UI thread.
      logStatements: false,
    );
  });
}
