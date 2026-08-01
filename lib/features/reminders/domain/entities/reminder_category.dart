/// Reminder categories, both built-in and user-defined.
library;

import 'package:equatable/equatable.dart';

/// A grouping label with an icon and colour.
///
/// Built-in categories ship with the app and cannot be deleted, only hidden;
/// user-defined categories are stored in the same table with
/// [isBuiltIn] set to `false`.
final class ReminderCategory extends Equatable {
  /// Creates a category.
  const ReminderCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconCodePoint,
    this.isBuiltIn = false,
    this.sortOrder = 0,
    this.isHidden = false,
  });

  /// Stable identifier. Built-in categories use their [BuiltInCategory] name.
  final String id;

  /// Display name.
  final String name;

  /// ARGB colour value, stored as an `int` so it survives serialisation
  /// without depending on `dart:ui` in the domain layer.
  final int colorValue;

  /// Material icon code point.
  final int iconCodePoint;

  /// Whether this category is shipped with the app.
  final bool isBuiltIn;

  /// Position within the category picker; lower sorts first.
  final int sortOrder;

  /// Whether the user has hidden this category from the picker.
  ///
  /// Hiding rather than deleting keeps existing reminders' category references
  /// valid.
  final bool isHidden;

  /// Returns a copy with the given fields replaced.
  ReminderCategory copyWith({
    String? id,
    String? name,
    int? colorValue,
    int? iconCodePoint,
    bool? isBuiltIn,
    int? sortOrder,
    bool? isHidden,
  }) =>
      ReminderCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        iconCodePoint: iconCodePoint ?? this.iconCodePoint,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        sortOrder: sortOrder ?? this.sortOrder,
        isHidden: isHidden ?? this.isHidden,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        colorValue,
        iconCodePoint,
        isBuiltIn,
        sortOrder,
        isHidden,
      ];
}

/// The categories seeded on first launch.
///
/// Code points are taken from the Material Icons font. They are written as
/// literals rather than referencing `Icons.*` so that the domain layer stays
/// free of Flutter imports; `CategoryIcons` in the presentation layer maps them
/// back to `IconData`.
enum BuiltInCategory {
  /// Medication and appointments.
  medicine('Medicine', 0xFFE53935, 0xe3a1),

  /// Payments and renewals.
  bills('Bills', 0xFF8E24AA, 0xe263),

  /// Exercise.
  workout('Workout', 0xFF00897B, 0xe1a3),

  /// Learning and revision.
  study('Study', 0xFF3949AB, 0xe865),

  /// Work tasks and meetings.
  office('Office', 0xFF1E88E5, 0xe0af),

  /// Family commitments.
  family('Family', 0xFFD81B60, 0xe7ef),

  /// Anything personal.
  personal('Personal', 0xFF43A047, 0xe7fd),

  /// Shopping lists and errands.
  shopping('Shopping', 0xFFF4511E, 0xe8cc),

  /// Trips and travel logistics.
  travel('Travel', 0xFF00ACC1, 0xe539);

  const BuiltInCategory(this.displayName, this.colorValue, this.iconCodePoint);

  /// Display name.
  final String displayName;

  /// ARGB colour.
  final int colorValue;

  /// Material icon code point.
  final int iconCodePoint;

  /// Stable identifier used as the primary key.
  String get id => name;

  /// Materialises this built-in as a [ReminderCategory] row.
  ReminderCategory toCategory() => ReminderCategory(
        id: id,
        name: displayName,
        colorValue: colorValue,
        iconCodePoint: iconCodePoint,
        isBuiltIn: true,
        sortOrder: index,
      );

  /// All built-ins, in display order.
  static List<ReminderCategory> seed() => BuiltInCategory.values
      .map((BuiltInCategory value) => value.toCategory())
      .toList(growable: false);
}
