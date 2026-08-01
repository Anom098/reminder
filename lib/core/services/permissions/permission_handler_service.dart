/// `permission_handler`-backed [PermissionService].
library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/utils/result.dart';

/// Queries and requests OS permissions via `permission_handler`.
final class PermissionHandlerService implements PermissionService {
  /// Creates a service.
  PermissionHandlerService({required AppLogger logger})
      : _log = logger.forContext('Permissions');

  final AppLogger _log;

  @override
  Future<Result<PermissionState>> status(AppPermission permission) async {
    final ph.Permission? mapped = _map(permission);
    if (mapped == null) {
      return const Success<PermissionState>(PermissionState.notApplicable);
    }
    return Result.guardAsync<PermissionState>(
      () async => _toState(await mapped.status),
    );
  }

  @override
  Future<Result<Map<AppPermission, PermissionState>>> statuses() async {
    final Map<AppPermission, PermissionState> result =
        <AppPermission, PermissionState>{};
    for (final AppPermission permission in AppPermission.values) {
      final Result<PermissionState> state = await status(permission);
      result[permission] = state.getOrElse(PermissionState.denied);
    }
    return Success<Map<AppPermission, PermissionState>>(result);
  }

  @override
  Future<Result<PermissionState>> request(AppPermission permission) async {
    final ph.Permission? mapped = _map(permission);
    if (mapped == null) {
      return const Success<PermissionState>(PermissionState.notApplicable);
    }

    return Result.guardAsync<PermissionState>(() async {
      final ph.PermissionStatus current = await mapped.status;
      // Requesting a permanently denied permission returns immediately without
      // a prompt, which looks to the user like the button did nothing. Report
      // the state so the caller can offer "Open settings" instead.
      if (current.isPermanentlyDenied || current.isRestricted) {
        return _toState(current);
      }
      final ph.PermissionStatus updated = await mapped.request();
      _log.debug('${permission.name} → ${updated.name}');
      return _toState(updated);
    });
  }

  @override
  Future<Result<Map<AppPermission, PermissionState>>> requestAll(
    List<AppPermission> permissions,
  ) async {
    final Map<AppPermission, PermissionState> result =
        <AppPermission, PermissionState>{};
    // Sequential rather than parallel: Android shows one system dialog at a
    // time and concurrent requests are dropped.
    for (final AppPermission permission in permissions) {
      final Result<PermissionState> state = await request(permission);
      result[permission] = state.getOrElse(PermissionState.denied);
    }
    return Success<Map<AppPermission, PermissionState>>(result);
  }

  @override
  Future<Result<bool>> openSettings() =>
      Result.guardAsync<bool>(ph.openAppSettings);

  @override
  Future<Result<bool>> openPermissionSettings(AppPermission permission) async {
    // Android exposes dedicated screens for these two; the generic app settings
    // page does not contain either toggle.
    if (Platform.isAndroid &&
        (permission == AppPermission.exactAlarm ||
            permission == AppPermission.ignoreBatteryOptimisation)) {
      final ph.Permission? mapped = _map(permission);
      if (mapped != null) {
        return Result.guardAsync<bool>(() async {
          final ph.PermissionStatus status = await mapped.request();
          return status.isGranted;
        });
      }
    }
    return openSettings();
  }

  /// Maps a domain permission onto the plugin's, or `null` when the platform
  /// has no such concept.
  ph.Permission? _map(AppPermission permission) => switch (permission) {
        AppPermission.microphone => ph.Permission.microphone,
        AppPermission.speechRecognition =>
          Platform.isIOS ? ph.Permission.speech : null,
        AppPermission.notifications => ph.Permission.notification,
        AppPermission.exactAlarm =>
          Platform.isAndroid ? ph.Permission.scheduleExactAlarm : null,
        AppPermission.ignoreBatteryOptimisation =>
          Platform.isAndroid ? ph.Permission.ignoreBatteryOptimizations : null,
      };

  static PermissionState _toState(ph.PermissionStatus status) =>
      switch (status) {
        ph.PermissionStatus.granted ||
        ph.PermissionStatus.limited ||
        ph.PermissionStatus.provisional =>
          PermissionState.granted,
        ph.PermissionStatus.permanentlyDenied =>
          PermissionState.permanentlyDenied,
        ph.PermissionStatus.restricted => PermissionState.restricted,
        ph.PermissionStatus.denied => PermissionState.denied,
      };
}
