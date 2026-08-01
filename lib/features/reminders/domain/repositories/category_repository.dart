/// Persistence contract for reminder categories.
library;

import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';

/// Stores and retrieves [ReminderCategory] rows.
abstract interface class CategoryRepository {
  /// Emits all categories in display order.
  ///
  /// When [includeHidden] is false, categories the user has hidden are omitted.
  /// Hidden categories are still returned by [getCategory] so that reminders
  /// referencing them keep rendering correctly.
  Stream<List<ReminderCategory>> watchCategories({bool includeHidden = false});

  /// One-shot read of all categories.
  Future<Result<List<ReminderCategory>>> getCategories({
    bool includeHidden = true,
  });

  /// Reads a single category, failing with `NotFoundFailure` if absent.
  Future<Result<ReminderCategory>> getCategory(String id);

  /// Inserts a user-defined category.
  Future<Result<ReminderCategory>> create(ReminderCategory category);

  /// Updates an existing category.
  ///
  /// Built-in categories accept appearance and visibility changes but not a
  /// change of [ReminderCategory.id].
  Future<Result<ReminderCategory>> update(ReminderCategory category);

  /// Deletes a user-defined category.
  ///
  /// Reminders referencing it are set to uncategorised rather than deleted.
  /// Fails with a `ValidationFailure` for built-in categories, which can only
  /// be hidden.
  Future<Result<void>> delete(String id);

  /// Inserts the built-in categories if they are not already present.
  ///
  /// Idempotent, so it can run on every launch as a self-healing step.
  Future<Result<void>> seedBuiltIns();
}
