/// Permission status and repair.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';

/// Shows every permission the app uses, why it needs it, and how to fix it.
///
/// Users who denied a prompt weeks ago have no idea which switch to flip. This
/// screen names the capability, explains the consequence of it being off, and
/// takes them straight to the right system page.
class PermissionsScreen extends ConsumerWidget {
  /// Creates the permissions screen.
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Map<AppPermission, PermissionState>> statuses =
        ref.watch(_permissionStatusesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_permissionStatusesProvider),
          ),
        ],
      ),
      body: AsyncValueView<Map<AppPermission, PermissionState>>(
        value: statuses,
        onRetry: () => ref.invalidate(_permissionStatusesProvider),
        builder: (
          BuildContext context,
          Map<AppPermission, PermissionState> data,
        ) =>
            ListView(
          padding: const EdgeInsets.only(bottom: Insets.xxl),
          children: <Widget>[
            for (final AppPermission permission in AppPermission.values)
              _PermissionTile(
                permission: permission,
                state: data[permission] ?? PermissionState.denied,
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.permission, required this.state});

  final AppPermission permission;
  final PermissionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    final (IconData icon, Color color, String label) = switch (state) {
      PermissionState.granted => (
          Icons.check_circle,
          theme.colorScheme.primary,
          'Allowed',
        ),
      PermissionState.notApplicable => (
          Icons.remove_circle_outline,
          theme.colorScheme.onSurfaceVariant,
          'Not needed on this device',
        ),
      PermissionState.denied => (
          Icons.error_outline,
          theme.colorScheme.error,
          'Not allowed',
        ),
      PermissionState.permanentlyDenied => (
          Icons.block,
          theme.colorScheme.error,
          'Blocked — change it in Settings',
        ),
      PermissionState.restricted => (
          Icons.lock_outline,
          theme.colorScheme.error,
          'Restricted by this device',
        ),
    };

    return ListTile(
      isThreeLine: true,
      leading: Icon(icon, color: color),
      title: Text(permission.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(permission.rationale),
          const SizedBox(height: Insets.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          if (!state.isUsable && permission.isOptional)
            Text(
              'The app still works without this.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: state.isUsable
          ? null
          : TextButton(
              onPressed: () => unawaited(_resolve(ref)),
              child: Text(state.canRequest ? 'Allow' : 'Settings'),
            ),
    );
  }

  Future<void> _resolve(WidgetRef ref) async {
    final PermissionService service = ref.read(permissionServiceProvider);
    if (state.canRequest) {
      await service.request(permission);
    } else {
      await service.openPermissionSettings(permission);
    }
    ref.invalidate(_permissionStatusesProvider);
  }
}

/// Current status of every permission the app uses.
final AutoDisposeFutureProvider<Map<AppPermission, PermissionState>>
    _permissionStatusesProvider =
    FutureProvider.autoDispose<Map<AppPermission, PermissionState>>(
        (Ref ref) async {
  final Result<Map<AppPermission, PermissionState>> result =
      await ref.watch(permissionServiceProvider).statuses();
  return result.getOrElse(const <AppPermission, PermissionState>{});
});
