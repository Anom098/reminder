/// The voice capture bottom sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/di/core_providers.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/router/app_router.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/core/services/permissions/permission_service.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/formatters.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder.dart';
import 'package:voice_reminder/features/reminders/domain/entities/reminder_priority.dart';
import 'package:voice_reminder/features/reminders/domain/usecases/create_reminder.dart';
import 'package:voice_reminder/features/voice/domain/entities/parsed_reminder_draft.dart';
import 'package:voice_reminder/features/voice/presentation/controllers/voice_capture_controller.dart';
import 'package:voice_reminder/features/voice/presentation/widgets/listening_indicator.dart';

/// Opens the voice capture sheet and starts listening.
Future<void> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Dismissing mid-capture must be possible: the microphone being open is a
    // state users want an obvious way out of.
    builder: (BuildContext sheetContext) => const _VoiceCaptureSheet(),
  );
}

class _VoiceCaptureSheet extends ConsumerStatefulWidget {
  const _VoiceCaptureSheet();

  @override
  ConsumerState<_VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends ConsumerState<_VoiceCaptureSheet> {
  final TextEditingController _typed = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(voiceCaptureProvider.notifier).start()),
    );
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VoiceCaptureState state = ref.watch(voiceCaptureProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Insets.lg,
          right: Insets.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.lg,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch (state) {
            VoiceCaptureIdle() ||
            VoiceCaptureRequestingPermission() =>
              _Preparing(onType: _interpretTyped, controller: _typed),
            VoiceCaptureListening(
              :final String transcript,
              :final double soundLevel,
            ) =>
              _Listening(
                transcript: transcript,
                soundLevel: soundLevel,
                onStop: () =>
                    unawaited(ref.read(voiceCaptureProvider.notifier).stop()),
              ),
            VoiceCaptureParsing(:final String transcript) =>
              _Parsing(transcript: transcript),
            VoiceCaptureDraftReady(
              :final ParsedReminderDraft draft,
              :final bool needsConfirmation,
            ) =>
              _DraftReview(
                draft: draft,
                needsConfirmation: needsConfirmation,
                saving: _saving,
                onSave: () => unawaited(_save(draft)),
                onRetry: _restart,
              ),
            VoiceCaptureFailed(:final AppFailure failure) => _Failed(
                failure: failure,
                onRetry: _restart,
                onOpenSettings: () => unawaited(
                  ref
                      .read(permissionServiceProvider)
                      .openPermissionSettings(AppPermission.microphone),
                ),
                onType: _interpretTyped,
                controller: _typed,
              ),
          },
        ),
      ),
    );
  }

  void _restart() => unawaited(ref.read(voiceCaptureProvider.notifier).start());

  void _interpretTyped(String text) {
    if (text.trim().isEmpty) {
      return;
    }
    unawaited(ref.read(voiceCaptureProvider.notifier).interpretText(text));
  }

  Future<void> _save(ParsedReminderDraft draft) async {
    final AppLogger log =
        ref.read(appLoggerProvider).forContext('VoiceCapture');

    final DateTime? dueAt = draft.dueAt;
    if (dueAt == null) {
      // Unreachable from the button, which is disabled without a time, but a
      // silent return here is exactly how this flow used to dead-end.
      log.warning('Save requested with no due date; ignoring.');
      return;
    }

    setState(() => _saving = true);

    final Result<Reminder> created =
        await ref.read(createReminderProvider).call(
              CreateReminderInput(
                title: draft.title,
                dueAt: dueAt,
                recurrence: draft.recurrence,
                categoryId: draft.categoryId,
                priority: draft.priority ?? ReminderPriority.normal,
              ),
            );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);

    switch (created) {
      case Success<Reminder>(value: final Reminder reminder):
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Reminder set for '
                '${Formatters.dateAndTime(reminder.dueAt)}',
              ),
              action: SnackBarAction(
                label: 'Edit',
                onPressed: () => context.goToEditReminder(reminder.id),
              ),
            ),
          );
      case Failure<Reminder>(failure: final AppFailure failure):
        log.error('Could not save: ${failure.code} — ${failure.message}');
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing({required this.onType, required this.controller});

  final ValueChanged<String> onType;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: Insets.xl),
        const CircularProgressIndicator(),
        const SizedBox(height: Insets.lg),
        Text(
          'Getting the microphone ready…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Insets.xl),
        _TypeInsteadField(controller: controller, onSubmit: onType),
      ],
    );
  }
}

class _Listening extends StatelessWidget {
  const _Listening({
    required this.transcript,
    required this.soundLevel,
    required this.onStop,
  });

  final String transcript;
  final double soundLevel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: Insets.md),
        ListeningIndicator(soundLevel: soundLevel),
        const SizedBox(height: Insets.lg),
        Text(
          transcript.isEmpty ? 'Listening…' : transcript,
          textAlign: TextAlign.center,
          style: transcript.isEmpty
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Insets.xl),
        Text(
          'Try: "remind me to take my tablets every day at 8 AM"',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.lg),
        FilledButton.tonalIcon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Done speaking'),
        ),
        const SizedBox(height: Insets.md),
      ],
    );
  }
}

class _Parsing extends StatelessWidget {
  const _Parsing({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: Insets.xl),
        const CircularProgressIndicator(),
        const SizedBox(height: Insets.lg),
        Text('"$transcript"', style: theme.textTheme.bodyMedium),
        const SizedBox(height: Insets.xl),
      ],
    );
  }
}

class _DraftReview extends ConsumerWidget {
  const _DraftReview({
    required this.draft,
    required this.needsConfirmation,
    required this.saving,
    required this.onSave,
    required this.onRetry,
  });

  final ParsedReminderDraft draft;
  final bool needsConfirmation;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = ref.watch(clockProvider).now();
    final String? prompt = draft.clarificationPrompt;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            draft.title.isEmpty ? 'Untitled reminder' : draft.title,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Insets.md),
          // Tappable whether or not a time was resolved. When the parser found
          // one this is a correction; when it did not, this is the follow-up
          // that `missingFields` exists to prompt — without it an utterance
          // like "remind me to call Mom" is understood, displayed, and then
          // impossible to save.
          _DraftRow(
            icon: Icons.event,
            label: draft.dueAt == null
                ? 'Set a date and time'
                : Formatters.dueLabel(draft.dueAt!, now),
            emphasised: draft.dueAt == null,
            onTap: saving ? null : () => unawaited(_pickDueAt(context, ref, now)),
          ),
          if (draft.recurrence.isRepeating)
            _DraftRow(
              icon: Icons.repeat,
              label: draft.recurrence.describe(),
            ),
          if (draft.priority != null)
            _DraftRow(
              icon: Icons.flag_outlined,
              label: '${draft.priority!.label} priority',
            ),
          if (draft.interpretationNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: Insets.md),
            for (final String note in draft.interpretationNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.xs),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          if (prompt != null) ...<Widget>[
            const SizedBox(height: Insets.lg),
            Container(
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.help_outline,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      prompt,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Insets.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onRetry,
                  icon: const Icon(Icons.mic),
                  label: const Text('Try again'),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (saving || draft.dueAt == null) ? null : onSave,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(needsConfirmation ? 'Looks right' : 'Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
        ],
      ),
    );
  }

  /// Asks for the date and then the time, and folds the answer into the draft.
  ///
  /// Cancelling either picker abandons the edit rather than committing half of
  /// it — a draft with a new date but the old time would be a worse guess than
  /// the one the parser made.
  Future<void> _pickDueAt(
    BuildContext context,
    WidgetRef ref,
    DateTime now,
  ) async {
    final DateTime initial = draft.dueAt ?? now.add(const Duration(hours: 1));

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Which day?',
    );
    if (date == null || !context.mounted) {
      return;
    }

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'What time?',
    );
    if (time == null) {
      return;
    }

    final DateTime dueAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    ref.read(voiceCaptureProvider.notifier).updateDraft(
          draft.copyWith(
            dueAt: dueAt,
            // The user has now supplied both, so neither is outstanding. Left
            // in place, they would keep the draft "incomplete" and the Save
            // button disabled.
            missingFields: draft.missingFields
                .where(
                  (ParsedField field) =>
                      field != ParsedField.date && field != ParsedField.time,
                )
                .toSet(),
          ),
        );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Draws the row as an unanswered question rather than a stated fact.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color colour =
        emphasised ? theme.colorScheme.primary : theme.colorScheme.onSurface;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 18,
            color:
                emphasised ? colour : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colour,
                fontWeight: emphasised ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Insets.sm),
        child: row,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: row,
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onType,
    required this.controller,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onType;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool needsSettings =
        failure is PermissionFailure && !failure.isRetryable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        Icon(
          needsSettings ? Icons.mic_off_outlined : Icons.error_outline,
          size: 36,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: Insets.md),
        Text(
          failure.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Insets.lg),
        if (needsSettings)
          FilledButton.tonalIcon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open settings'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        const SizedBox(height: Insets.lg),
        // Typing is always available, so a broken or denied microphone never
        // blocks the user from creating a reminder.
        _TypeInsteadField(controller: controller, onSubmit: onType),
      ],
    );
  }
}

class _TypeInsteadField extends StatelessWidget {
  const _TypeInsteadField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmit,
      decoration: InputDecoration(
        hintText: 'Or type it — "call Mom tomorrow at 7 PM"',
        prefixIcon: const Icon(Icons.keyboard_alt_outlined),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => onSubmit(controller.text),
          tooltip: 'Interpret',
        ),
      ),
    );
  }
}
