import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_card.dart';

import '../../../helpers/test_doubles.dart';

void main() {
  final DateTime now = DateTime(2026, 8, 1, 12);

  Future<void> pumpCard(
    WidgetTester tester,
    Reminder reminder, {
    ReminderCategory? category,
    VoidCallback? onTap,
    ValueChanged<bool>? onToggleEnabled,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderCard(
            reminder: reminder,
            now: now,
            category: category,
            onTap: onTap ?? () {},
            onToggleEnabled: onToggleEnabled,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the title and due label', (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(title: 'Call Mom', dueAt: DateTime(2026, 8, 1, 19)),
    );

    expect(find.text('Call Mom'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('flags an overdue reminder', (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(dueAt: DateTime(2026, 8, 1, 9)),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsNothing);
  });

  testWidgets('shows the recurrence description when repeating',
      (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(
        dueAt: DateTime(2026, 8, 1, 19),
        recurrence: const RecurrenceRule.daily(),
      ),
    );

    expect(find.text('Every day'), findsOneWidget);
  });

  testWidgets('marks a silent reminder', (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(dueAt: DateTime(2026, 8, 1, 19), isSpoken: false),
    );

    expect(find.text('Silent'), findsOneWidget);
  });

  testWidgets('shows the category name and icon', (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(dueAt: DateTime(2026, 8, 1, 19), categoryId: 'medicine'),
      category: BuiltInCategory.medicine.toCategory(),
    );

    expect(find.text('Medicine'), findsOneWidget);
  });

  testWidgets('invokes onTap', (WidgetTester tester) async {
    int taps = 0;
    await pumpCard(
      tester,
      buildReminder(dueAt: DateTime(2026, 8, 1, 19)),
      onTap: () => taps++,
    );

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('the enable switch reflects and reports state',
      (WidgetTester tester) async {
    bool? reported;
    await pumpCard(
      tester,
      buildReminder(dueAt: DateTime(2026, 8, 1, 19)),
      onToggleEnabled: (bool value) => reported = value,
    );

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(reported, isFalse);
  });

  testWidgets('hides the switch for a completed reminder',
      (WidgetTester tester) async {
    await pumpCard(
      tester,
      buildReminder(status: ReminderStatus.completed),
      onToggleEnabled: (_) {},
    );

    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('renders without overflow at a large text scale',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ReminderCard(
              reminder: buildReminder(
                title: 'Take the long-named evening medication',
                dueAt: DateTime(2026, 8, 1, 19),
                recurrence: const RecurrenceRule.daily(),
              ),
              now: now,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    // A layout overflow is reported as a framework exception; asserting none
    // occurred is the whole point of this test.
    expect(tester.takeException(), isNull);
  });
}
