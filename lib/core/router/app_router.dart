/// Application routing.
///
/// Routes are declared in one place and referenced through the typed helpers on
/// [AppRoute], so a renamed path is a compile error rather than a dead link.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_reminder/features/reminders/presentation/screens/categories_screen.dart';
import 'package:voice_reminder/features/reminders/presentation/screens/home_screen.dart';
import 'package:voice_reminder/features/reminders/presentation/screens/reminder_detail_screen.dart';
import 'package:voice_reminder/features/reminders/presentation/screens/reminder_editor_screen.dart';
import 'package:voice_reminder/features/reminders/presentation/screens/search_screen.dart';
import 'package:voice_reminder/features/settings/presentation/screens/backup_screen.dart';
import 'package:voice_reminder/features/settings/presentation/screens/permissions_screen.dart';
import 'package:voice_reminder/features/settings/presentation/screens/settings_screen.dart';
import 'package:voice_reminder/features/settings/presentation/screens/voice_settings_screen.dart';
import 'package:voice_reminder/shared/widgets/error_view.dart';

/// Every named destination in the app.
enum AppRoute {
  /// The reminder list.
  home('/', 'home'),

  /// Creating a reminder.
  createReminder('/reminder/new', 'createReminder'),

  /// Viewing a reminder.
  reminderDetail('/reminder/:id', 'reminderDetail'),

  /// Editing a reminder.
  editReminder('/reminder/:id/edit', 'editReminder'),

  /// Full-screen search.
  search('/search', 'search'),

  /// Managing categories.
  categories('/categories', 'categories'),

  /// Settings root.
  settings('/settings', 'settings'),

  /// Voice and speech settings.
  voiceSettings('/settings/voice', 'voiceSettings'),

  /// Backup, export and import.
  backup('/settings/backup', 'backup'),

  /// Permission status and repair.
  permissions('/settings/permissions', 'permissions');

  const AppRoute(this.path, this.routeName);

  /// The GoRouter path pattern.
  final String path;

  /// The GoRouter route name, used for name-based navigation.
  final String routeName;
}

/// Builds the router.
///
/// A provider rather than a global so that tests can construct an isolated
/// router, and so the initial location can depend on application state.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (Ref ref) {
    final GoRouter router = GoRouter(
      initialLocation: AppRoute.home.path,
      debugLogDiagnostics: false,
      errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: ErrorView(
          title: 'That page does not exist',
          message: 'The link "${state.uri}" could not be opened.',
          onRetry: () => context.goNamed(AppRoute.home.routeName),
          retryLabel: 'Go home',
        ),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: AppRoute.home.path,
          name: AppRoute.home.routeName,
          builder: (BuildContext context, GoRouterState state) =>
              const HomeScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'search',
              name: AppRoute.search.routeName,
              builder: (BuildContext context, GoRouterState state) =>
                  const SearchScreen(),
            ),
            GoRoute(
              path: 'categories',
              name: AppRoute.categories.routeName,
              builder: (BuildContext context, GoRouterState state) =>
                  const CategoriesScreen(),
            ),
            GoRoute(
              path: 'reminder/new',
              name: AppRoute.createReminder.routeName,
              builder: (BuildContext context, GoRouterState state) =>
                  const ReminderEditorScreen(),
            ),
            GoRoute(
              path: 'reminder/:id',
              name: AppRoute.reminderDetail.routeName,
              builder: (BuildContext context, GoRouterState state) =>
                  ReminderDetailScreen(
                reminderId: state.pathParameters['id']!,
              ),
              routes: <RouteBase>[
                GoRoute(
                  path: 'edit',
                  name: AppRoute.editReminder.routeName,
                  builder: (BuildContext context, GoRouterState state) =>
                      ReminderEditorScreen(
                    reminderId: state.pathParameters['id'],
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'settings',
              name: AppRoute.settings.routeName,
              builder: (BuildContext context, GoRouterState state) =>
                  const SettingsScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'voice',
                  name: AppRoute.voiceSettings.routeName,
                  builder: (BuildContext context, GoRouterState state) =>
                      const VoiceSettingsScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  name: AppRoute.backup.routeName,
                  builder: (BuildContext context, GoRouterState state) =>
                      const BackupScreen(),
                ),
                GoRoute(
                  path: 'permissions',
                  name: AppRoute.permissions.routeName,
                  builder: (BuildContext context, GoRouterState state) =>
                      const PermissionsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    ref.onDispose(router.dispose);
    return router;
  },
  name: 'appRouter',
);

/// Navigation helpers that keep path construction in one place.
extension AppNavigation on BuildContext {
  /// Opens the reminder with [id].
  void goToReminder(String id) => pushNamed(
        AppRoute.reminderDetail.routeName,
        pathParameters: <String, String>{'id': id},
      );

  /// Opens the editor for the reminder with [id].
  void goToEditReminder(String id) => pushNamed(
        AppRoute.editReminder.routeName,
        pathParameters: <String, String>{'id': id},
      );

  /// Opens the editor for a new reminder.
  void goToCreateReminder() => pushNamed(AppRoute.createReminder.routeName);

  /// Opens full-screen search.
  void goToSearch() => pushNamed(AppRoute.search.routeName);

  /// Opens settings.
  void goToSettings() => pushNamed(AppRoute.settings.routeName);
}
