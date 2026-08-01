/// `flutter_local_notifications`-backed [NotificationService].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_reminder/core/constants/notification_constants.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/notifications/notification_background_handler.dart';
import 'package:voice_reminder/core/services/notifications/notification_service.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// Delivers reminders through the OS notification centre.
final class LocalNotificationService implements NotificationService {
  /// Creates a service.
  LocalNotificationService({
    required AppLogger logger,
    FlutterLocalNotificationsPlugin? plugin,
  })  : _log = logger.forContext('Notifications'),
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final AppLogger _log;

  /// Replays the most recent action to late subscribers.
  ///
  /// The app can be launched *by* a notification tap, which arrives before any
  /// widget has had a chance to subscribe. Without replay that interaction
  /// would be lost and the app would open on the home screen instead of the
  /// reminder the user tapped.
  final StreamController<NotificationAction> _actions =
      StreamController<NotificationAction>.broadcast();
  NotificationAction? _pendingAction;
  bool _initialized = false;

  @override
  Stream<NotificationAction> get actions async* {
    final NotificationAction? pending = _pendingAction;
    if (pending != null) {
      _pendingAction = null;
      yield pending;
    }
    yield* _actions.stream;
  }

  @override
  Future<Result<void>> initialize() async {
    if (_initialized) {
      return voidSuccess;
    }
    try {
      await _configureTimeZone();

      const AndroidInitializationSettings android =
          AndroidInitializationSettings(
        NotificationConstants.androidSmallIcon,
      );

      final DarwinInitializationSettings darwin = DarwinInitializationSettings(
        // Permission is requested explicitly later, after the app has explained
        // why it needs it. Prompting during start-up gets denied far more often.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: <DarwinNotificationCategory>[
          _iosReminderCategory,
        ],
      );

      await _plugin.initialize(
        InitializationSettings(android: android, iOS: darwin, macOS: darwin),
        onDidReceiveNotificationResponse: _handleForegroundResponse,
        onDidReceiveBackgroundNotificationResponse:
            onDidReceiveBackgroundNotificationResponse,
      );

      await _createAndroidChannels();
      await _captureLaunchAction();

      _initialized = true;
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _log.error('initialize failed', error: error, stackTrace: stackTrace);
      return Failure<void>(
        NotificationFailure(
          message: 'Notifications could not be set up on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<bool>> requestPermission() async {
    return Result.guardAsync<bool>(() async {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? android =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        // Android 12 and below have no runtime notification permission, and
        // the plugin returns null there rather than false.
        return await android?.requestNotificationsPermission() ?? true;
      }
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    });
  }

  @override
  Future<Result<bool>> hasPermission() async {
    return Result.guardAsync<bool>(() async {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? android =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? true;
      }
      // iOS exposes no synchronous query; requesting again returns the current
      // grant without re-prompting once a decision has been made.
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      return await ios?.checkPermissions().then(
                (NotificationsEnabledOptions? options) =>
                    options?.isEnabled ?? false,
              ) ??
          false;
    });
  }

  @override
  Future<Result<bool>> canScheduleExactAlarms() async {
    return Result.guardAsync<bool>(() async {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    });
  }

  @override
  Future<Result<void>> schedule(ScheduledNotification notification) async {
    final Result<void> ready = await initialize();
    if (ready.isFailure) {
      return ready;
    }

    final tz.TZDateTime when = tz.TZDateTime.from(
      notification.scheduledAt,
      tz.local,
    );

    if (!when.isAfter(tz.TZDateTime.now(tz.local))) {
      return Failure<void>(
        SchedulingFailure(
          message: 'That time has already passed.',
          cause: 'scheduledAt=${notification.scheduledAt}',
        ),
      );
    }

    try {
      final bool exactAllowed =
          (await canScheduleExactAlarms()).getOrElse(false);

      await _plugin.zonedSchedule(
        notification.id,
        notification.title,
        notification.body,
        when,
        _detailsFor(notification),
        payload: jsonEncode(notification.payload),
        // The scheduled instant is already an absolute point in time in the
        // device's zone, so it must not be reinterpreted as wall-clock time.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: switch ((
          notification.allowWhileIdle,
          exactAllowed
        )) {
          (true, true) => AndroidScheduleMode.exactAllowWhileIdle,
          (false, true) => AndroidScheduleMode.exact,
          // Without the exact-alarm grant the OS rejects an exact request
          // outright, so fall back to an inexact alarm rather than not
          // scheduling at all. The reminder may be a few minutes late; not
          // firing would be far worse.
          _ => AndroidScheduleMode.inexactAllowWhileIdle,
        },
      );
      return voidSuccess;
    } on Object catch (error, stackTrace) {
      _log.error(
        'schedule failed for id ${notification.id}',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>(
        SchedulingFailure(
          message: 'Could not schedule that reminder.',
          requiresExactAlarmPermission:
              !(await canScheduleExactAlarms()).getOrElse(true),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<int>>> scheduleAll(
    List<ScheduledNotification> notifications,
  ) async {
    final List<int> failed = <int>[];
    for (final ScheduledNotification notification in notifications) {
      final Result<void> result = await schedule(notification);
      if (result.isFailure) {
        failed.add(notification.id);
      }
    }
    return Success<List<int>>(failed);
  }

  @override
  Future<Result<void>> showNow(ScheduledNotification notification) async {
    final Result<void> ready = await initialize();
    if (ready.isFailure) {
      return ready;
    }
    return Result.guardAsync<void>(
      () => _plugin.show(
        notification.id,
        notification.title,
        notification.body,
        _detailsFor(notification),
        payload: jsonEncode(notification.payload),
      ),
    );
  }

  @override
  Future<Result<void>> cancel(int id) =>
      Result.guardAsync<void>(() => _plugin.cancel(id));

  @override
  Future<Result<void>> cancelMany(Iterable<int> ids) =>
      Result.guardAsync<void>(() async {
        for (final int id in ids) {
          await _plugin.cancel(id);
        }
      });

  @override
  Future<Result<void>> cancelAll() =>
      Result.guardAsync<void>(() => _plugin.cancelAll());

  @override
  Future<Result<List<int>>> pendingIds() =>
      Result.guardAsync<List<int>>(() async {
        final List<PendingNotificationRequest> pending =
            await _plugin.pendingNotificationRequests();
        return pending
            .map((PendingNotificationRequest request) => request.id)
            .toList(growable: false);
      });

  @override
  Future<Result<NotificationAction?>> launchAction() async {
    await initialize();
    final NotificationAction? action = _pendingAction;
    _pendingAction = null;
    return Success<NotificationAction?>(action);
  }

  /// Releases the action stream.
  Future<void> dispose() => _actions.close();

  // -- internals ----------------------------------------------------------

  Future<void> _configureTimeZone() async {
    tz_data.initializeTimeZones();
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } on Object catch (error) {
      // A device reporting an unknown zone must not stop notifications
      // entirely; UTC keeps absolute instants correct even if the label is
      // wrong.
      _log.warning(
          'Falling back to UTC; local time zone lookup failed: $error');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  Future<void> _createAndroidChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return;
    }

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationConstants.reminderChannelId,
        NotificationConstants.reminderChannelName,
        description: NotificationConstants.reminderChannelDescription,
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      ),
    );

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        NotificationConstants.statusChannelId,
        NotificationConstants.statusChannelName,
        description: NotificationConstants.statusChannelDescription,
        importance: Importance.low,
        enableVibration: false,
        playSound: false,
      ),
    );
  }

  Future<void> _captureLaunchAction() async {
    final NotificationAppLaunchDetails? details =
        await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) {
      return;
    }
    final NotificationResponse? response = details.notificationResponse;
    if (response == null) {
      return;
    }
    _pendingAction = _toAction(response);
  }

  NotificationDetails _detailsFor(ScheduledNotification notification) {
    final bool urgent = notification.priority.isTimeCritical;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.reminderChannelId,
        NotificationConstants.reminderChannelName,
        channelDescription: NotificationConstants.reminderChannelDescription,
        importance: Importance.max,
        priority: urgent ? Priority.max : Priority.high,
        category: AndroidNotificationCategory.reminder,
        // Reminders are the app's whole purpose; letting the OS bundle them
        // away behind a summary would hide the thing the user asked for.
        groupKey: 'voice_reminder.due',
        styleInformation: notification.body == null
            ? null
            : BigTextStyleInformation(notification.body!),
        actions: notification.withActions ? _androidActions : null,
        fullScreenIntent: urgent,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: notification.withActions
            ? NotificationConstants.iosReminderCategoryId
            : null,
        interruptionLevel:
            urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
      ),
    );
  }

  static const List<AndroidNotificationAction> _androidActions =
      <AndroidNotificationAction>[
    AndroidNotificationAction(
      NotificationConstants.actionComplete,
      'Done',
      showsUserInterface: false,
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      NotificationConstants.actionSnooze,
      'Snooze',
      showsUserInterface: false,
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      NotificationConstants.actionDismiss,
      'Dismiss',
      showsUserInterface: false,
      cancelNotification: true,
    ),
  ];

  // Not `const`: DarwinNotificationAction.plain is a factory, so the whole
  // category has to be built at first use rather than at compile time.
  static final DarwinNotificationCategory _iosReminderCategory =
      DarwinNotificationCategory(
    NotificationConstants.iosReminderCategoryId,
    actions: <DarwinNotificationAction>[
      DarwinNotificationAction.plain(
        NotificationConstants.actionComplete,
        'Done',
      ),
      DarwinNotificationAction.plain(
        NotificationConstants.actionSnooze,
        'Snooze',
      ),
      DarwinNotificationAction.plain(
        NotificationConstants.actionDismiss,
        'Dismiss',
        options: <DarwinNotificationActionOption>{
          DarwinNotificationActionOption.destructive,
        },
      ),
    ],
    options: <DarwinNotificationCategoryOption>{
      DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
    },
  );

  void _handleForegroundResponse(NotificationResponse response) {
    final NotificationAction action = _toAction(response);
    if (_actions.hasListener) {
      _actions.add(action);
    } else {
      _pendingAction = action;
    }
  }

  static NotificationAction _toAction(NotificationResponse response) {
    return NotificationAction(
      notificationId: response.id ?? 0,
      actionId: response.actionId,
      payload: decodeNotificationPayload(response.payload),
    );
  }
}

/// Decodes a notification payload, tolerating anything malformed.
///
/// Shared with the background isolate, which receives the same string.
Map<String, Object?> decodeNotificationPayload(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const <String, Object?>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, Object?>
        ? decoded
        : const <String, Object?>{};
  } on FormatException {
    return const <String, Object?>{};
  }
}
