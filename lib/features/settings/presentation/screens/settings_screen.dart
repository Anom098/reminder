/// Settings root.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/presentation/controllers/settings_controller.dart';
import 'package:voice_reminder/shared/widgets/confirm_dialog.dart';

/// Appearance, voice, notifications, data and permissions.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const _SectionHeading('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(settings.themeMode.label),
            onTap: () => unawaited(_pickTheme(context, controller, settings)),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Accent colour'),
            subtitle: const Text('Used across buttons and highlights'),
            trailing: CircleAvatar(
              radius: 12,
              backgroundColor: Color(settings.seedColorValue),
            ),
            onTap: () => unawaited(_pickAccent(context, controller, settings)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            value: settings.useHighContrast,
            onChanged: (bool value) => unawaited(
              controller.setHighContrast(enabled: value),
            ),
            title: const Text('High contrast'),
            subtitle: const Text('Stronger colour separation for readability'),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Text size'),
            subtitle: Text(
              settings.textScaleOverride == null
                  ? 'Following the system setting'
                  : '${(settings.textScaleOverride! * 100).round()}%',
            ),
            onTap: () =>
                unawaited(_pickTextScale(context, controller, settings)),
          ),
          const Divider(),
          const _SectionHeading('Voice'),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice and speech'),
            subtitle: Text(
              settings.speakReminders
                  ? '${settings.speech.language} · '
                      'rate ${(settings.speech.rate * 100).round()}%'
                  : 'Spoken reminders are off',
            ),
            onTap: () => context.pushNamed(AppRoute.voiceSettings.routeName),
          ),
          const Divider(),
          const _SectionHeading('Reminders'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            value: settings.notificationVibration,
            onChanged: (bool value) => unawaited(
              controller.setNotificationVibration(enabled: value),
            ),
            title: const Text('Vibrate'),
            subtitle: const Text('Vibrate when a reminder is due'),
          ),
          ListTile(
            leading: const Icon(Icons.snooze),
            title: const Text('Default snooze'),
            subtitle: Text(Formatters.duration(settings.defaultSnooze)),
            onTap: () => unawaited(_pickSnooze(context, controller, settings)),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Categories'),
            subtitle: const Text('Add, rename, hide or remove categories'),
            onTap: () => context.pushNamed(AppRoute.categories.routeName),
          ),
          const Divider(),
          const _SectionHeading('Data and privacy'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup and restore'),
            subtitle: Text(
              settings.lastBackupAt == null
                  ? 'No backup yet'
                  : 'Last backup '
                      '${Formatters.dateAndTime(settings.lastBackupAt!)}',
            ),
            onTap: () => context.pushNamed(AppRoute.backup.routeName),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Permissions'),
            subtitle: const Text('Microphone, notifications and alarms'),
            onTap: () => context.pushNamed(AppRoute.permissions.routeName),
          ),
          const _PrivacyNote(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset settings'),
            subtitle: const Text('Restores defaults; reminders are kept'),
            onTap: () => unawaited(_confirmReset(context, controller)),
          ),
          const _AboutTile(),
          const SizedBox(height: Insets.xl),
        ],
      ),
    );
  }

  Future<void> _pickTheme(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    final AppThemeMode? picked = await showModalBottomSheet<AppThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final AppThemeMode mode in AppThemeMode.values)
              RadioListTile<AppThemeMode>(
                value: mode,
                groupValue: settings.themeMode,
                title: Text(mode.label),
                onChanged: (AppThemeMode? value) =>
                    Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await controller.setThemeMode(picked);
    }
  }

  Future<void> _pickAccent(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: <Widget>[
              for (final Color color in AppTheme.seedPalette)
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(color.toARGB32()),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.seedColorValue == color.toARGB32()
                            ? Theme.of(sheetContext).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await controller.setSeedColor(picked);
    }
  }

  Future<void> _pickTextScale(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    const Map<String, double?> options = <String, double?>{
      'Follow the system': null,
      'Small (85%)': 0.85,
      'Default (100%)': 1.0,
      'Large (125%)': 1.25,
      'Larger (150%)': 1.5,
      'Largest (200%)': 2.0,
    };

    final MapEntry<String, double?>? picked =
        await showModalBottomSheet<MapEntry<String, double?>>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final MapEntry<String, double?> option in options.entries)
              RadioListTile<double?>(
                value: option.value,
                groupValue: settings.textScaleOverride,
                title: Text(option.key),
                onChanged: (_) => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      await controller.setTextScale(picked.value);
    }
  }

  Future<void> _pickSnooze(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) async {
    const List<Duration> options = <Duration>[
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(hours: 1),
      Duration(hours: 3),
    ];

    final Duration? picked = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final Duration option in options)
              RadioListTile<Duration>(
                value: option,
                groupValue: settings.defaultSnooze,
                title: Text(Formatters.duration(option)),
                onChanged: (Duration? value) =>
                    Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      await controller.setDefaultSnooze(picked);
    }
  }

  Future<void> _confirmReset(
    BuildContext context,
    SettingsController controller,
  ) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Reset settings?',
      message: 'Appearance, voice and notification preferences return to '
          'their defaults. Your reminders are not affected.',
      confirmLabel: 'Reset',
      isDestructive: true,
    );
    if (confirmed) {
      await controller.resetToDefaults();
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.lg,
        Insets.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              'Your reminders never leave this device. There is no account, no '
              'analytics and no server. Speech recognition may use the '
              'recogniser built into your phone, which is governed by your '
              "device's own privacy settings.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        final PackageInfo? info = snapshot.data;
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          subtitle: Text(
            info == null
                ? 'Voice Reminder'
                : 'Voice Reminder ${info.version} (${info.buildNumber})',
          ),
        );
      },
    );
  }
}
