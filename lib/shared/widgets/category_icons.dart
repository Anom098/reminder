/// Bridges the domain's integer icon code points back to Flutter icons.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';

/// Icon resolution for categories.
///
/// The domain stores an `int` code point so it stays free of Flutter imports
/// and remains serialisable. Turning that back into an [IconData] is a
/// presentation concern and lives here.
abstract final class CategoryIcons {
  /// Icons offered when creating or editing a category.
  ///
  /// A curated list rather than the whole Material set: the icons must be
  /// legible at 20dp and distinguishable from one another in a grid.
  static const List<IconData> palette = <IconData>[
    Icons.medication_outlined,
    Icons.receipt_long_outlined,
    Icons.fitness_center_outlined,
    Icons.school_outlined,
    Icons.work_outline,
    Icons.family_restroom_outlined,
    Icons.person_outline,
    Icons.shopping_cart_outlined,
    Icons.flight_outlined,
    Icons.alarm_outlined,
    Icons.favorite_outline,
    Icons.pets_outlined,
    Icons.home_outlined,
    Icons.local_cafe_outlined,
    Icons.directions_car_outlined,
    Icons.cake_outlined,
    Icons.music_note_outlined,
    Icons.book_outlined,
    Icons.phone_outlined,
    Icons.water_drop_outlined,
  ];

  /// Resolves [codePoint] to an icon, falling back to a generic label.
  ///
  /// Tree shaking removes icons that are only referenced through a non-constant
  /// [IconData], so every icon the app can show must appear in [palette] or in
  /// the built-in mapping below. Constructing `IconData(codePoint)` directly
  /// would compile but render as a blank box in release builds.
  static IconData resolve(int codePoint) {
    for (final IconData icon in palette) {
      if (icon.codePoint == codePoint) {
        return icon;
      }
    }
    for (final BuiltInCategory category in BuiltInCategory.values) {
      if (category.iconCodePoint == codePoint) {
        return builtIn(category);
      }
    }
    return Icons.label_outline;
  }

  /// The icon for a built-in category.
  static IconData builtIn(BuiltInCategory category) => switch (category) {
        BuiltInCategory.medicine => Icons.medication_outlined,
        BuiltInCategory.bills => Icons.receipt_long_outlined,
        BuiltInCategory.workout => Icons.fitness_center_outlined,
        BuiltInCategory.study => Icons.school_outlined,
        BuiltInCategory.office => Icons.work_outline,
        BuiltInCategory.family => Icons.family_restroom_outlined,
        BuiltInCategory.personal => Icons.person_outline,
        BuiltInCategory.shopping => Icons.shopping_cart_outlined,
        BuiltInCategory.travel => Icons.flight_outlined,
      };
}
