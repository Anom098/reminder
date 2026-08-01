/// Translation between Drift rows and domain entities.
///
/// Mapping lives in the data layer so the domain never learns that Drift
/// exists, and so a malformed row degrades gracefully instead of throwing on a
/// list rebuild.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';

/// Converts reminder rows to and from [Reminder].
extension ReminderRowMapper on ReminderRow {
  /// Builds the domain entity for this row.
  Reminder toEntity() => Reminder(
        id: id,
        title: title,
        notes: notes,
        categoryId: categoryId,
        priority: ReminderPriority.parse(priority),
        anchorAt: anchorAt,
        dueAt: dueAt,
        recurrence: decodeRecurrence(recurrence),
        status: ReminderStatus.parse(status),
        colorValue: colorValue,
        isSpoken: isSpoken,
        spokenTextOverride: spokenTextOverride,
        snoozedFrom: snoozedFrom,
        completedAt: completedAt,
        lastFiredAt: lastFiredAt,
        occurrenceCount: occurrenceCount,
        attachmentPath: attachmentPath,
        timeZoneId: timeZoneId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Decodes a stored recurrence, degrading to [RecurrenceRule.once].
  ///
  /// A corrupt rule must not make an existing reminder unopenable; the worst
  /// case is that it stops repeating, which the user can see and fix.
  static RecurrenceRule decodeRecurrence(String encoded) {
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        return RecurrenceRule.fromJson(decoded);
      }
    } on FormatException {
      // Fall through to the default below.
    }
    return const RecurrenceRule.once();
  }
}

/// Converts [Reminder] to a Drift companion.
extension ReminderEntityMapper on Reminder {
  /// Builds an insert/update companion with every column set.
  ///
  /// All fields are `Value`-wrapped explicitly, including the nullable ones, so
  /// that an update clears a field the user emptied instead of leaving the old
  /// value in place.
  ReminderRowsCompanion toCompanion() => ReminderRowsCompanion(
        id: Value<String>(id),
        title: Value<String>(title),
        notes: Value<String?>(notes),
        categoryId: Value<String?>(categoryId),
        priority: Value<String>(priority.name),
        anchorAt: Value<DateTime>(anchorAt),
        dueAt: Value<DateTime>(dueAt),
        recurrence: Value<String>(jsonEncode(recurrence.toJson())),
        status: Value<String>(status.name),
        colorValue: Value<int?>(colorValue),
        isSpoken: Value<bool>(isSpoken),
        spokenTextOverride: Value<String?>(spokenTextOverride),
        snoozedFrom: Value<DateTime?>(snoozedFrom),
        completedAt: Value<DateTime?>(completedAt),
        lastFiredAt: Value<DateTime?>(lastFiredAt),
        occurrenceCount: Value<int>(occurrenceCount),
        attachmentPath: Value<String?>(attachmentPath),
        timeZoneId: Value<String?>(timeZoneId),
        createdAt: Value<DateTime>(createdAt),
        updatedAt: Value<DateTime>(updatedAt),
      );
}

/// Converts category rows to and from [ReminderCategory].
extension CategoryRowMapper on CategoryRow {
  /// Builds the domain entity for this row.
  ReminderCategory toEntity() => ReminderCategory(
        id: id,
        name: name,
        colorValue: colorValue,
        iconCodePoint: iconCodePoint,
        isBuiltIn: isBuiltIn,
        sortOrder: sortOrder,
        isHidden: isHidden,
      );
}

/// Converts [ReminderCategory] to a Drift companion.
extension CategoryEntityMapper on ReminderCategory {
  /// Builds an insert/update companion with every column set.
  CategoryRowsCompanion toCompanion() => CategoryRowsCompanion(
        id: Value<String>(id),
        name: Value<String>(name),
        colorValue: Value<int>(colorValue),
        iconCodePoint: Value<int>(iconCodePoint),
        isBuiltIn: Value<bool>(isBuiltIn),
        sortOrder: Value<int>(sortOrder),
        isHidden: Value<bool>(isHidden),
      );
}
