/// Tests for [NotificationReminderScheduler].
///
/// The scheduler is the seam where a reminder becomes something the OS knows
/// about, and it has two independent outputs: the notification slots that alert
/// the user, and the alarm that speaks the reminder aloud. Both are asserted
/// here — the second one was silently missing until a device proved it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/notifications/notification_service.dart';
import 'package:voice_reminder/core/utils/clock.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/data/services/notification_reminder_scheduler.dart';
import 'package:voice_reminder/features/reminders/domain/entities/recurrence_rule.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';

import '../../../helpers/test_doubles.dart';

/// Records what was handed to the OS, without touching a platform channel.
final class RecordingNotificationService implements NotificationService {
  final List<ScheduledNotification> scheduled = <ScheduledNotification>[];
  final List<int> cancelled = <int>[];
  int cancelAllCount = 0;

  /// Makes every cancellation fail, as a broken platform plugin would.
  bool failCancellation = false;

  Result<void> get _cancelResult => failCancellation
      ? const Failure<void>(
          NotificationFailure(message: 'plugin threw'),
        )
      : voidSuccess;

  @override
  Stream<NotificationAction> get actions => const Stream<NotificationAction>.empty();

  @override
  Future<Result<List<int>>> scheduleAll(
    List<ScheduledNotification> notifications,
  ) async {
    scheduled.addAll(notifications);
    return const Success<List<int>>(<int>[]);
  }

  @override
  Future<Result<void>> schedule(ScheduledNotification notification) async {
    scheduled.add(notification);
    return voidSuccess;
  }

  @override
  Future<Result<void>> cancelMany(Iterable<int> ids) async {
    cancelled.addAll(ids);
    return _cancelResult;
  }

  @override
  Future<Result<void>> cancel(int id) async {
    cancelled.add(id);
    return _cancelResult;
  }

  @override
  Future<Result<void>> cancelAll() async {
    cancelAllCount++;
    return _cancelResult;
  }

  @override
  Future<Result<void>> initialize() async => voidSuccess;

  @override
  Future<Result<bool>> requestPermission() async => const Success<bool>(true);

  @override
  Future<Result<bool>> hasPermission() async => const Success<bool>(true);

  @override
  Future<Result<bool>> canScheduleExactAlarms() async =>
      const Success<bool>(true);

  @override
  Future<Result<void>> showNow(ScheduledNotification notification) async =>
      voidSuccess;

  @override
  Future<Result<List<int>>> pendingIds() async =>
      Success<List<int>>(scheduled.map((ScheduledNotification n) => n.id).toList());

  @override
  Future<Result<NotificationAction?>> launchAction() async =>
      const Success<NotificationAction?>(null);
}

void main() {
  late RecordingNotificationService notifications;
  late FakeReminderRepository repository;
  late int armCount;

  final DateTime now = DateTime(2026, 8, 1, 8);

  NotificationReminderScheduler build({bool armThrows = false}) =>
      NotificationReminderScheduler(
        repository: repository,
        notifications: notifications,
        logger: const NoopLogger(),
        clock: FixedClock(now),
        armSpokenAnnouncement: () async {
          armCount++;
          if (armThrows) {
            throw StateError('alarm manager unavailable');
          }
        },
      );

  setUp(() {
    notifications = RecordingNotificationService();
    repository = FakeReminderRepository();
    armCount = 0;
  });

  tearDown(() => repository.dispose());

  group('notification slots', () {
    test('schedules a one-shot reminder in the future', () async {
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(notifications.scheduled, hasLength(1));
      expect(notifications.scheduled.single.scheduledAt,
          DateTime(2026, 8, 1, 9));
    });

    test('schedules nothing for a reminder already in the past', () async {
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 7));
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(notifications.scheduled, isEmpty);
    });

    test('caps a repeating reminder at the horizon', () async {
      final Reminder reminder = buildReminder(
        dueAt: DateTime(2026, 8, 1, 9),
        recurrence: const RecurrenceRule.daily(),
      );
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(notifications.scheduled, hasLength(12));
    });
  });

  group('spoken-announcement alarm', () {
    // The regression this file exists for. `schedule` used to place the
    // notification and stop, leaving the speech alarm to be armed only from
    // inside the background isolates — which could not run until an alarm had
    // already fired. Every reminder created in the foreground stayed silent.
    test('is armed when a reminder is scheduled', () async {
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(armCount, 1);
    });

    test('is armed exactly once per schedule, not once per sub-step', () async {
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      await build().schedule(reminder);

      // `schedule` cancels before re-scheduling; that internal cancel must not
      // arm the alarm a second time.
      expect(armCount, 1);
    });

    test('is armed even when the reminder has no future occurrence', () async {
      // Disabling the reminder that the alarm currently points at still changes
      // which reminder should be spoken next.
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 7));
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(armCount, 1);
    });

    test('is armed on cancellation', () async {
      await build().cancelById('reminder-1');

      expect(armCount, 1);
    });

    test('is armed after a full rebuild', () async {
      await repository.create(buildReminder(dueAt: DateTime(2026, 8, 1, 9)));

      await build().rescheduleAll();

      expect(armCount, 1);
    });

    test('a failure to arm does not fail the save', () async {
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      final Result<void> result =
          await build(armThrows: true).schedule(reminder);

      // Losing the voice is worse than nothing, but losing the reminder is
      // worse still.
      expect(result.isSuccess, isTrue);
      expect(notifications.scheduled, hasLength(1));
    });
  });

  group('resilience to a broken cancellation', () {
    // On a real device, R8 stripped the generic signature that
    // flutter_local_notifications needs to read its pending-notification cache,
    // so every `cancel` threw. Because scheduling cancelled first and returned
    // on failure, the app stopped scheduling anything at all — no notification,
    // no announcement, no error the user could see. The ProGuard rules fix the
    // cause; these tests fix the blast radius.
    test('still schedules when clearing the old slots fails', () async {
      notifications.failCancellation = true;
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      final Result<void> result = await build().schedule(reminder);

      expect(result.isSuccess, isTrue);
      expect(notifications.scheduled, hasLength(1));
    });

    test('still arms the speech alarm when clearing fails', () async {
      notifications.failCancellation = true;
      final Reminder reminder =
          buildReminder(dueAt: DateTime(2026, 8, 1, 9));
      await repository.create(reminder);

      await build().schedule(reminder);

      expect(armCount, 1);
    });

    test('still rebuilds the schedule when cancelAll fails', () async {
      notifications.failCancellation = true;
      await repository.create(buildReminder(dueAt: DateTime(2026, 8, 1, 9)));

      final Result<int> result = await build().rescheduleAll();

      expect(result.valueOrNull, 1);
      expect(notifications.scheduled, hasLength(1));
    });
  });

  group('rescheduleAll', () {
    test('clears everything before re-deriving', () async {
      await repository.create(buildReminder(dueAt: DateTime(2026, 8, 1, 9)));

      await build().rescheduleAll();

      expect(notifications.cancelAllCount, 1);
      expect(notifications.scheduled, hasLength(1));
    });

    test('reports how many slots were filled', () async {
      await repository.create(
        buildReminder(id: 'a', dueAt: DateTime(2026, 8, 1, 9)),
      );
      await repository.create(
        buildReminder(id: 'b', dueAt: DateTime(2026, 8, 1, 10)),
      );

      final Result<int> result = await build().rescheduleAll();

      expect(result.valueOrNull, 2);
    });

    test('surfaces a repository failure', () async {
      repository.failWith = const DatabaseFailure(message: 'disk gone');

      final Result<int> result = await build().rescheduleAll();

      expect(result.isFailure, isTrue);
    });
  });
}
