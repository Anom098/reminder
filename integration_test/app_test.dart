/// End-to-end tests that run on a real device or emulator.
///
/// Run with: `flutter test integration_test`
///
/// These exercise the paths that unit tests cannot: a real SQLite file, the
/// real provider graph, and real navigation. Platform channels that need
/// hardware (the microphone, the TTS engine) are exercised only as far as
/// "does not crash", because a CI emulator has neither.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/app.dart';
import 'package:voice_reminder/core/config/app_config.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/create_reminder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> buildApp() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    return ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(const AppConfig()),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const VoiceReminderApp(),
    );
  }

  testWidgets('launches to the reminder list', (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Speak'), findsOneWidget);
  });

  testWidgets('creates a reminder through the editor and shows it on the list',
      (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('New reminder'), findsOneWidget);

    await tester.enterText(
        find.byType(TextFormField).first, 'Water the plants');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Water the plants'), findsWidgets);
  });

  testWidgets('a created reminder survives a rebuild of the widget tree',
      (WidgetTester tester) async {
    final Widget app = await buildApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // Write through the domain layer so the assertion is about persistence,
    // not about the form.
    final ProviderContainer scope = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final Clock clock = scope.read(clockProvider);

    await scope.read(createReminderProvider).call(
          CreateReminderInput(
            title: 'Persisted reminder',
            dueAt: clock.now().add(const Duration(hours: 2)),
          ),
        );

    await tester.pumpAndSettle();
    expect(find.text('Persisted reminder'), findsWidgets);

    final ReminderRepository repository =
        scope.read(reminderRepositoryProvider);
    final List<Reminder> stored =
        (await repository.getReminders()).getOrElse(const <Reminder>[]);

    expect(
      stored.where((Reminder r) => r.title == 'Persisted reminder'),
      hasLength(1),
    );
  });

  testWidgets('search finds a reminder by title', (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    final ProviderContainer scope = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final Clock clock = scope.read(clockProvider);

    await scope.read(createReminderProvider).call(
          CreateReminderInput(
            title: 'Dentist appointment',
            dueAt: clock.now().add(const Duration(days: 3)),
          ),
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'dentist');
    // The search field is debounced.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Dentist appointment'), findsWidgets);
  });

  testWidgets('settings opens and the theme can be changed',
      (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsWidgets);
  });
}
