/// Full-screen reminder search.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/debouncer.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_category.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_query.dart';
import 'package:voice_reminder/features/reminders/presentation/controllers/reminder_list_controller.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_actions.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/reminder_card.dart';
import 'package:voice_reminder/shared/widgets/async_value_view.dart';
import 'package:voice_reminder/shared/widgets/empty_state.dart';

/// Searches titles, notes and category names.
class SearchScreen extends ConsumerStatefulWidget {
  /// Creates the search screen.
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final Debouncer _debouncer = Debouncer(duration: AppConstants.searchDebounce);
  String _term = '';

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounced so that typing does not issue a database query per keystroke.
    _debouncer.run(() {
      if (mounted) {
        setState(() => _term = value.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search reminders',
            border: InputBorder.none,
            filled: false,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: _term.isEmpty
          ? const EmptyState(
              icon: Icons.search,
              title: 'Search your reminders',
              message: 'Find by title, notes, category or priority.',
            )
          : _SearchResults(term: _term),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.term});

  final String term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Reminder>> results =
        ref.watch(_searchResultsProvider(term));
    final DateTime now = ref.watch(clockProvider).now();
    final Map<String, ReminderCategory> categories =
        ref.watch(categoryIndexProvider).valueOrNull ??
            const <String, ReminderCategory>{};

    return AsyncValueView<List<Reminder>>(
      value: results,
      onRetry: () => ref.invalidate(_searchResultsProvider(term)),
      builder: (BuildContext context, List<Reminder> reminders) {
        if (reminders.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'No matches for "$term"',
            message: 'Try a different word, or check your spelling.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(Insets.lg),
          itemCount: reminders.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(height: Insets.sm),
          itemBuilder: (BuildContext context, int index) {
            final Reminder reminder = reminders[index];
            return ReminderCard(
              reminder: reminder,
              now: now,
              category: reminder.categoryId == null
                  ? null
                  : categories[reminder.categoryId],
              onTap: () => context.goToReminder(reminder.id),
              onComplete: () =>
                  unawaited(ref.reminderActions(context).complete(reminder)),
              onDelete: () =>
                  unawaited(ref.reminderActions(context).delete(reminder)),
            );
          },
        );
      },
    );
  }
}

/// Search results for a term.
///
/// Auto-disposing and keyed by term so that abandoned searches do not hold
/// database subscriptions open behind the user.
final AutoDisposeStreamProviderFamily<List<Reminder>, String>
    _searchResultsProvider =
    StreamProvider.autoDispose.family<List<Reminder>, String>(
  (Ref ref, String term) =>
      ref.watch(reminderRepositoryProvider).watchReminders(
            filter: ReminderFilter(searchTerm: term),
          ),
);
