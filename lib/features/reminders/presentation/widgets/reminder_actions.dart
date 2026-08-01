/// Shared reminder actions, so every surface behaves identically.
///
/// The home list, the detail screen and the search results all offer complete,
/// snooze, delete and duplicate. Centralising them here means one definition of
/// what each does, one confirmation policy, and one set of user-facing
/// messages.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/presentation/widgets/snooze_sheet.dart';
import 'package:voice_reminder/features/settings/presentation/controllers/settings_controller.dart';
import 'package:voice_reminder/shared/widgets/confirm_dialog.dart';

/// Reminder actions bound to a [WidgetRef] and a [BuildContext].
///
/// Instantiated per call site rather than held in state; it owns no data.
final class ReminderActions {
  /// Creates an action helper.
  const ReminderActions(this._ref, this._context);

  final WidgetRef _ref;
  final BuildContext _context;

  /// Marks [reminder] complete and offers an undo.
  Future<void> complete(Reminder reminder) async {
    final Result<Reminder?> result =
        await _ref.read(completeReminderProvider).call(reminder.id);

    if (!_context.mounted) {
      return;
    }
    _report(
      result,
      // Undo restores the exact pre-completion entity, including its
      // occurrence count, so completing a repeating reminder by mistake does
      // not silently skip an occurrence.
      success: reminder.recurrence.isRepeating
          ? 'Marked done — moved to the next occurrence.'
          : 'Marked done.',
      onUndo: () async {
        await _ref.read(updateReminderProvider).call(reminder);
      },
    );
  }

  /// Asks how long to snooze for, then applies it.
  Future<void> snooze(Reminder reminder) async {
    final Duration? duration = await showSnoozeSheet(
      _context,
      defaultSnooze: _ref.read(settingsProvider).defaultSnooze,
    );
    if (duration == null || !_context.mounted) {
      return;
    }

    final Result<Reminder?> result =
        await _ref.read(snoozeReminderProvider).call(reminder.id, duration);

    if (!_context.mounted) {
      return;
    }
    _report(result, success: 'Snoozed.');
  }

  /// Confirms, then deletes [reminder].
  ///
  /// Deletion is confirmed rather than undoable: a reminder removed by mistake
  /// and only noticed later cannot be recovered from a snackbar.
  Future<void> delete(Reminder reminder) async {
    final bool confirmed = await showConfirmDialog(
      _context,
      title: 'Delete this reminder?',
      message: '"${reminder.title}" will be removed and will not alert you '
          'again.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !_context.mounted) {
      return;
    }

    final Result<void> result =
        await _ref.read(deleteReminderProvider).call(reminder.id);

    if (!_context.mounted) {
      return;
    }
    _report(result, success: 'Reminder deleted.');
  }

  /// Creates a copy of [reminder].
  Future<void> duplicate(Reminder reminder) async {
    final Result<Reminder> result =
        await _ref.read(duplicateReminderProvider).call(reminder.id);

    if (!_context.mounted) {
      return;
    }
    _report(result, success: 'Copy created.');
  }

  /// Turns [reminder] on or off.
  Future<void> setEnabled(Reminder reminder, {required bool enabled}) async {
    final Result<Reminder> result = await _ref
        .read(setReminderEnabledProvider)
        .call(reminder.id, enabled: enabled);

    if (!_context.mounted) {
      return;
    }
    _report(
      result,
      success: enabled ? 'Reminder turned on.' : 'Reminder turned off.',
    );
  }

  /// Speaks the reminder immediately, so the user can hear how it will sound.
  Future<void> preview(Reminder reminder) async {
    final Result<void> result = await _ref
        .read(textToSpeechServiceProvider)
        .speak(reminder.spokenText,
            settings: _ref.read(settingsProvider).speech);

    if (!_context.mounted) {
      return;
    }
    if (result case Failure<void>(failure: final AppFailure failure)) {
      _showMessage(failure.message);
    }
  }

  void _report<T>(
    Result<T> result, {
    required String success,
    Future<void> Function()? onUndo,
  }) {
    switch (result) {
      case Success<T>():
        _showMessage(success, onUndo: onUndo);
      case Failure<T>(failure: final AppFailure failure):
        _showMessage(failure.message);
    }
  }

  void _showMessage(String message, {Future<void> Function()? onUndo}) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(_context)
      ..clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () => unawaited(onUndo()),
              ),
      ),
    );
  }
}

/// Convenience accessor: `ref.reminderActions(context)`.
extension ReminderActionsExtension on WidgetRef {
  /// Builds a [ReminderActions] bound to [context].
  ReminderActions reminderActions(BuildContext context) =>
      ReminderActions(this, context);
}
