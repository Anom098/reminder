/// Runtime permission contract.
///
/// Wraps `permission_handler` behind a domain-shaped interface so that the
/// presentation layer reasons about *capabilities* ("can this app speak a
/// reminder while the screen is off?") rather than about platform permission
/// enums.
library;

import 'package:voice_reminder/core/utils/result.dart';

/// Permissions this application can request.
enum AppPermission {
  /// Microphone access, required for voice capture.
  microphone('Microphone', 'Needed so you can dictate reminders.'),

  /// Speech recognition entitlement. iOS only; a no-op on Android.
  speechRecognition(
    'Speech recognition',
    'Needed to turn what you say into a reminder.',
  ),

  /// Permission to post notifications. Android 13+ and iOS.
  notifications(
    'Notifications',
    'Needed to alert you when a reminder is due.',
  ),

  /// Permission to schedule exact alarms. Android 12+ only.
  exactAlarm(
    'Exact alarms',
    'Needed so reminders fire at the exact minute you chose.',
  ),

  /// Exemption from battery optimisation. Android only.
  ignoreBatteryOptimisation(
    'Background activity',
    'Stops the system delaying reminders while the phone is idle.',
  );

  const AppPermission(this.label, this.rationale);

  /// User-facing name.
  final String label;

  /// Why the app is asking, shown in the pre-permission prompt.
  final String rationale;

  /// Whether the app remains usable without this permission.
  ///
  /// Only [notifications] is genuinely required; everything else degrades to a
  /// reduced but working experience.
  bool get isOptional => this != AppPermission.notifications;
}

/// The state of a single permission.
enum PermissionState {
  /// Granted.
  granted,

  /// Denied, but the OS will still show a prompt.
  denied,

  /// Denied with "don't ask again"; only a trip to Settings can change it.
  permanentlyDenied,

  /// Blocked by device policy or parental controls.
  restricted,

  /// Not applicable on this platform or OS version.
  ///
  /// Treated as granted by callers, because a permission that does not exist
  /// cannot be withheld.
  notApplicable;

  /// Whether the capability is usable.
  bool get isUsable =>
      this == PermissionState.granted || this == PermissionState.notApplicable;

  /// Whether asking again could plausibly succeed.
  bool get canRequest => this == PermissionState.denied;

  /// Whether the user must be sent to system settings.
  bool get requiresSettings =>
      this == PermissionState.permanentlyDenied ||
      this == PermissionState.restricted;
}

/// Queries and requests OS permissions.
abstract interface class PermissionService {
  /// Reads the current state of [permission] without prompting.
  Future<Result<PermissionState>> status(AppPermission permission);

  /// Reads the state of every permission the app uses.
  Future<Result<Map<AppPermission, PermissionState>>> statuses();

  /// Requests [permission], prompting the user if the OS allows it.
  Future<Result<PermissionState>> request(AppPermission permission);

  /// Requests several permissions in sequence.
  Future<Result<Map<AppPermission, PermissionState>>> requestAll(
    List<AppPermission> permissions,
  );

  /// Opens the app's page in system settings.
  ///
  /// Returns whether the settings screen was actually opened.
  Future<Result<bool>> openSettings();

  /// Opens the OS screen for [permission], falling back to [openSettings].
  ///
  /// Android exposes dedicated screens for exact alarms and battery
  /// optimisation that the generic app-settings page does not reach.
  Future<Result<bool>> openPermissionSettings(AppPermission permission);
}
