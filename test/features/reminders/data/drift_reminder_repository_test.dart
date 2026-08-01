@Tags(<String>['db'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/database/app_database.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_category_repository.dart';
import 'package:voice_reminder/features/reminders/data/repositories/drift_reminder_repository.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_status.dart';

import '../../../helpers/test_doubles.dart';

/// These tests run against a real, in-memory SQLite database rather than a
/// mock. The value of this repository is entirely in the SQL it generates, so
/// mocking the query layer would test nothing.
void main() {
  late AppDatabase database;
  late DriftReminderRepository repository;
  late DriftCategoryRepository categories;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftReminderRepository(
      database: database,
      logger: const NoopLogger(),
    );
    categories = DriftCategoryRepository(
      database: database,
      logger: const NoopLogger(),
    );
    await categories.seedBuiltIns();
  });

  tearDown(() => database.close());

  group('CRUD', () {
    test('creates and reads back a reminder', () async {
      final Reminder reminder = buildReminder(
        recurrence: const RecurrenceRule.daily(interval: 2),
        notes: 'The blue ones',
        categoryId: 'medicine',
      );

      expect((await repository.create(reminder)).isSuccess, isTrue);

      final Result<Reminder> read = await repository.getReminder(reminder.id);
      final Reminder stored = (read as Success<Reminder>).value;

      expect(stored.title, reminder.title);
      expect(stored.notes, 'The blue ones');
      expect(stored.categoryId, 'medicine');
      expect(stored.recurrence, reminder.recurrence);
      expect(stored.dueAt, reminder.dueAt);
    });

    test('reading a missing reminder fails with NotFoundFailure', () async {
      final Result<Reminder> read = await repository.getReminder('nope');

      expect(read.failureOrNull, isA<NotFoundFailure>());
    });

    test('update replaces every column, including cleared ones', () async {
      final Reminder reminder = buildReminder(notes: 'original');
      await repository.create(reminder);

      await repository.update(reminder.copyWith(clearNotes: true));

      final Reminder stored =
          (await repository.getReminder(reminder.id) as Success<Reminder>)
              .value;
      expect(stored.notes, isNull);
    });

    test('update fails when the row does not exist', () async {
      final Result<Reminder> result =
          await repository.update(buildReminder(id: 'ghost'));

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('delete is idempotent', () async {
      await repository.create(buildReminder());

      expect((await repository.delete('reminder-1')).isSuccess, isTrue);
      expect(
        (await repository.delete('reminder-1')).isSuccess,
        isTrue,
        reason: 'a duplicate notification action must not surface an error',
      );
    });

    test('updateAll applies every change', () async {
      await repository.create(buildReminder(id: 'a'));
      await repository.create(buildReminder(id: 'b'));

      final Result<List<Reminder>> before = await repository.getReminders();
      final List<Reminder> updated = (before as Success<List<Reminder>>)
          .value
          .map((Reminder r) => r.copyWith(title: 'Updated'))
          .toList();

      expect((await repository.updateAll(updated)).isSuccess, isTrue);

      final List<Reminder> after =
          (await repository.getReminders() as Success<List<Reminder>>).value;
      expect(after.every((Reminder r) => r.title == 'Updated'), isTrue);
    });
  });

  group('querying', () {
    setUp(() async {
      await repository.create(
        buildReminder(
          id: 'a',
          title: 'Take tablets',
          dueAt: DateTime(2026, 8, 1, 8),
          categoryId: 'medicine',
          priority: ReminderPriority.high,
        ),
      );
      await repository.create(
        buildReminder(
          id: 'b',
          title: 'Pay rent',
          dueAt: DateTime(2026, 8, 3, 9),
          categoryId: 'bills',
          notes: 'Standing order',
        ),
      );
      await repository.create(
        buildReminder(
          id: 'c',
          title: 'Gym session',
          dueAt: DateTime(2026, 8, 2, 18),
          status: ReminderStatus.disabled,
        ),
      );
    });

    test('orders by due date ascending by default', () async {
      final List<Reminder> rows =
          (await repository.getReminders() as Success<List<Reminder>>).value;

      expect(
        rows.map((Reminder r) => r.id).toList(),
        <String>['a', 'c', 'b'],
      );
    });

    test('orders by priority using the stored enum name', () async {
      final List<Reminder> rows = (await repository.getReminders(
        sort: ReminderSort.priorityDescending,
      ) as Success<List<Reminder>>)
          .value;

      expect(
        rows.first.id,
        'a',
        reason: 'priority is stored as text and must be ordered by weight',
      );
    });

    test('filters by status', () async {
      final List<Reminder> rows = (await repository.getReminders(
        filter: ReminderFilter.active,
      ) as Success<List<Reminder>>)
          .value;

      expect(rows.map((Reminder r) => r.id), <String>['a', 'b']);
    });

    test('filters by category', () async {
      final List<Reminder> rows = (await repository.getReminders(
        filter: const ReminderFilter(categoryIds: <String>{'bills'}),
      ) as Success<List<Reminder>>)
          .value;

      expect(rows.single.id, 'b');
    });

    test('filters by due range', () async {
      final List<Reminder> rows = (await repository.getReminders(
        filter: ReminderFilter(
          dueRange: DateRange(
            start: DateTime(2026, 8, 2),
            end: DateTime(2026, 8, 3),
          ),
        ),
      ) as Success<List<Reminder>>)
          .value;

      expect(rows.single.id, 'c');
    });

    test('searches titles, notes and category names', () async {
      Future<List<String>> search(String term) async => ((await repository
                      .getReminders(filter: ReminderFilter(searchTerm: term))
                  as Success<List<Reminder>>)
              .value)
          .map((Reminder r) => r.id)
          .toList();

      expect(await search('tablets'), <String>['a']);
      expect(await search('standing'), <String>['b']);
      expect(
        await search('medicine'),
        <String>['a'],
        reason: 'the category name participates in search',
      );
      expect(await search('TABLETS'), <String>['a'],
          reason: 'case-insensitive');
    });

    test('getActive excludes disabled and terminal reminders', () async {
      final List<Reminder> rows =
          (await repository.getActive() as Success<List<Reminder>>).value;

      expect(rows.map((Reminder r) => r.id), <String>['a', 'b']);
    });

    test('getDueBefore respects the horizon', () async {
      final List<Reminder> rows = (await repository.getDueBefore(
        DateTime(2026, 8, 2),
      ) as Success<List<Reminder>>)
          .value;

      expect(rows.single.id, 'a');
    });

    test('limit and offset paginate', () async {
      final List<Reminder> page = (await repository.getReminders(
        limit: 1,
        offset: 1,
      ) as Success<List<Reminder>>)
          .value;

      expect(page.single.id, 'c');
    });

    test('watchReminders re-emits after a write', () async {
      final Stream<List<Reminder>> stream = repository.watchReminders();

      expectLater(
        stream.map((List<Reminder> rows) => rows.length),
        emitsInOrder(<int>[3, 4]),
      );

      await repository.create(buildReminder(id: 'd', title: 'New'));
    });
  });

  group('categories', () {
    test('seeding is idempotent', () async {
      await categories.seedBuiltIns();

      final List<ReminderCategory> rows =
          (await categories.getCategories() as Success<List<ReminderCategory>>)
              .value;

      expect(
          rows.where((ReminderCategory c) => c.id == 'medicine'), hasLength(1));
    });

    test('built-in categories cannot be deleted', () async {
      final Result<void> result = await categories.delete('medicine');

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('deleting a custom category orphans rather than deletes reminders',
        () async {
      const ReminderCategory custom = ReminderCategory(
        id: 'custom-1',
        name: 'Garden',
        colorValue: 0xFF00FF00,
        iconCodePoint: 0xe1a3,
      );
      await categories.create(custom);
      await repository.create(buildReminder(categoryId: 'custom-1'));

      expect((await categories.delete('custom-1')).isSuccess, isTrue);

      final Reminder stored =
          (await repository.getReminder('reminder-1') as Success<Reminder>)
              .value;
      expect(stored.categoryId, isNull);
    });
  });
}
