/// Drift table definitions.
///
/// Enums and the recurrence rule are stored as text rather than integers so
/// that a database opened by hand — or a SQLite export sent to support — is
/// readable, and so that reordering an enum can never silently reinterpret
/// existing rows.
library;

import 'package:drift/drift.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';

/// Category rows.
@DataClassName('CategoryRow')
class CategoryRows extends Table {
  /// Stable identifier; built-ins use their enum name.
  TextColumn get id => text().withLength(min: 1, max: 64)();

  /// Display name.
  TextColumn get name =>
      text().withLength(min: 1, max: AppConstants.maxCategoryNameLength)();

  /// ARGB colour.
  IntColumn get colorValue => integer()();

  /// Material icon code point.
  IntColumn get iconCodePoint => integer()();

  /// Whether the category ships with the app.
  BoolColumn get isBuiltIn =>
      boolean().withDefault(const Constant<bool>(false))();

  /// Position in the picker.
  IntColumn get sortOrder => integer().withDefault(const Constant<int>(0))();

  /// Whether the user has hidden it.
  BoolColumn get isHidden =>
      boolean().withDefault(const Constant<bool>(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Reminder rows.
///
/// `dueAt` is indexed because every list query and the scheduler order by it;
/// `status` because every query filters on it.
@DataClassName('ReminderRow')
@TableIndex(name: 'idx_reminders_due_at', columns: <Symbol>{#dueAt})
@TableIndex(name: 'idx_reminders_status', columns: <Symbol>{#status})
@TableIndex(name: 'idx_reminders_category', columns: <Symbol>{#categoryId})
class ReminderRows extends Table {
  /// UUID primary key.
  TextColumn get id => text().withLength(min: 1, max: 64)();

  /// Reminder title.
  TextColumn get title =>
      text().withLength(min: 1, max: AppConstants.maxTitleLength)();

  /// Optional notes.
  TextColumn get notes =>
      text().withLength(max: AppConstants.maxNotesLength).nullable()();

  /// Owning category.
  ///
  /// `ON DELETE SET NULL`: deleting a category must not delete the reminders
  /// filed under it.
  ///
  /// Written as a raw constraint rather than `.references(CategoryRows, #id)`
  /// because drift's typed form does not resolve the reference here and
  /// silently emits the column with no foreign key at all — verified by the
  /// "orphans rather than deletes" test in the repository suite.
  TextColumn get categoryId => text().nullable().customConstraint(
        'NULL REFERENCES category_rows(id) ON DELETE SET NULL',
      )();

  /// Priority enum name.
  TextColumn get priority =>
      text().withDefault(const Constant<String>('normal'))();

  /// Original due instant; the fixed point recurrence expands from.
  DateTimeColumn get anchorAt => dateTime()();

  /// Next due instant.
  DateTimeColumn get dueAt => dateTime()();

  /// Recurrence rule, JSON-encoded.
  TextColumn get recurrence =>
      text().withDefault(const Constant<String>('{"frequency":"once"}'))();

  /// Lifecycle status enum name.
  TextColumn get status =>
      text().withDefault(const Constant<String>('scheduled'))();

  /// Colour override.
  IntColumn get colorValue => integer().nullable()();

  /// Whether to announce aloud.
  BoolColumn get isSpoken =>
      boolean().withDefault(const Constant<bool>(true))();

  /// Exact phrase to speak.
  TextColumn get spokenTextOverride =>
      text().withLength(max: AppConstants.maxTitleLength).nullable()();

  /// Pre-snooze due instant.
  DateTimeColumn get snoozedFrom => dateTime().nullable()();

  /// Completion timestamp.
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Last fire timestamp.
  DateTimeColumn get lastFiredAt => dateTime().nullable()();

  /// How many occurrences have fired.
  IntColumn get occurrenceCount =>
      integer().withDefault(const Constant<int>(0))();

  /// Attachment path. Reserved for a future release.
  TextColumn get attachmentPath => text().nullable()();

  /// IANA time zone the reminder was authored in.
  TextColumn get timeZoneId => text().nullable()();

  /// Creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Last modification timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
