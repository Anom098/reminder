/// Voice, speech and recognition settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/di/app_providers.dart';
import 'package:voice_reminder/core/services/speech/speech_recognition_service.dart';
import 'package:voice_reminder/core/services/tts/text_to_speech_service.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';
import 'package:voice_reminder/core/utils/result.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';
import 'package:voice_reminder/features/settings/presentation/controllers/settings_controller.dart';

/// Lets the user choose and preview the voice used for reminders.
class VoiceSettingsScreen extends ConsumerWidget {
  /// Creates the voice settings screen.
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final TtsSpeechSettings speech = settings.speech;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice and speech')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        children: <Widget>[
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_outlined),
            value: settings.speakReminders,
            onChanged: (bool value) =>
                unawaited(controller.setSpeakReminders(enabled: value)),
            title: const Text('Speak reminders aloud'),
            subtitle: const Text(
              'Announce the reminder when it is due, as well as showing a '
              'notification.',
            ),
          ),
          _RepeatCountPicker(
            count: settings.speakRepeatCount,
            enabled: settings.speakReminders,
            onChanged: (int value) =>
                unawaited(controller.setSpeakRepeatCount(value)),
          ),
          _SpeechSlider(
            icon: Icons.timer_outlined,
            label: 'Pause between repeats',
            value: settings.speakRepeatInterval.inSeconds.toDouble(),
            min: AppSettings.minSpeakRepeatInterval.inSeconds.toDouble(),
            max: AppSettings.maxSpeakRepeatInterval.inSeconds.toDouble(),
            enabled: settings.speakReminders && settings.speakRepeatCount > 1,
            format: (double value) => '${value.round()}s',
            onChanged: (double value) => unawaited(
              controller.setSpeakRepeatInterval(
                Duration(seconds: value.round()),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            value: settings.speakInSilentMode,
            onChanged: settings.speakReminders
                ? (bool value) => unawaited(
                      controller.setSpeakInSilentMode(enabled: value),
                    )
                : null,
            title: const Text('Speak in silent mode'),
            subtitle: const Text(
              'Announce even when the ringer is off. Use with care.',
            ),
          ),
          const Divider(),
          _VoicePicker(enabled: settings.speakReminders),
          const Divider(),
          _SpeechSlider(
            icon: Icons.speed,
            label: 'Speed',
            value: speech.rate,
            min: 0.1,
            max: 1,
            enabled: settings.speakReminders,
            format: (double value) => '${(value * 100).round()}%',
            onChanged: (double value) => unawaited(
              controller.setSpeech(speech.copyWith(rate: value)),
            ),
          ),
          _SpeechSlider(
            icon: Icons.graphic_eq,
            label: 'Pitch',
            value: speech.pitch,
            min: 0.5,
            max: 2,
            enabled: settings.speakReminders,
            format: (double value) => value.toStringAsFixed(2),
            onChanged: (double value) => unawaited(
              controller.setSpeech(speech.copyWith(pitch: value)),
            ),
          ),
          _SpeechSlider(
            icon: Icons.volume_up,
            label: 'Volume',
            value: speech.volume,
            min: 0,
            max: 1,
            enabled: settings.speakReminders,
            format: (double value) => '${(value * 100).round()}%',
            onChanged: (double value) => unawaited(
              controller.setSpeech(speech.copyWith(volume: value)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: FilledButton.tonalIcon(
              onPressed: settings.speakReminders
                  ? () => unawaited(
                        _preview(
                          ref,
                          speech,
                          settings.speakRepeatCount,
                          settings.speakRepeatInterval,
                        ),
                      )
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Hear a sample'),
            ),
          ),
          const Divider(height: Insets.xxl),
          const _RecognitionLocalePicker(),
        ],
      ),
    );
  }

  /// Speaks a sample the same number of times a real reminder would.
  ///
  /// Previewing one utterance while reminders say three would make the setting
  /// impossible to judge without waiting for an actual reminder to fire.
  Future<void> _preview(
    WidgetRef ref,
    TtsSpeechSettings speech,
    int repeats,
    Duration interval,
  ) async {
    final TextToSpeechService tts = ref.read(textToSpeechServiceProvider);
    for (int pass = 0; pass < repeats; pass++) {
      if (pass > 0) {
        await Future<void>.delayed(interval);
      }
      final Result<void> spoken = await tts.speak(
        'Reminder. Take your tablets.',
        settings: speech,
      );
      if (spoken.isFailure) {
        break;
      }
    }
  }
}

/// Chooses how many times an announcement repeats.
///
/// A segmented row rather than a slider or a dialog: the range is small, every
/// option fits on screen, and the current choice stays visible without a tap.
class _RepeatCountPicker extends StatelessWidget {
  const _RepeatCountPicker({
    required this.count,
    required this.enabled,
    required this.onChanged,
  });

  final int count;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const int min = AppSettings.minSpeakRepeatCount;
    const int max = AppSettings.maxSpeakRepeatCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.repeat,
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.disabledColor,
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Text(
                  'Repeat each announcement',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: enabled ? null : theme.disabledColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Padding(
            padding: const EdgeInsets.only(left: Insets.xxl),
            child: Text(
              count == 1
                  ? 'Said once.'
                  : 'Said $count times, with a short pause between.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.disabledColor,
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Padding(
            padding: const EdgeInsets.only(left: Insets.xxl, bottom: Insets.sm),
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                for (int value = min; value <= max; value++)
                  ButtonSegment<int>(
                    value: value,
                    label: Text('$value'),
                    // Screen readers would otherwise announce a bare digit.
                    tooltip: value == 1 ? 'Once' : '$value times',
                  ),
              ],
              selected: <int>{AppSettings.clampSpeakRepeatCount(count)},
              showSelectedIcon: false,
              onSelectionChanged:
                  enabled ? (Set<int> values) => onChanged(values.first) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoicePicker extends ConsumerWidget {
  const _VoicePicker({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TtsVoice>> voices = ref.watch(_voicesProvider);
    final AppSettings settings = ref.watch(settingsProvider);

    return ListTile(
      enabled: enabled,
      leading: const Icon(Icons.person_outline),
      title: const Text('Voice'),
      subtitle: Text(
        settings.speech.voiceName ??
            'Device default (${settings.speech.language})',
      ),
      trailing: voices.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: !enabled
          ? null
          : () => unawaited(
                _pick(context, ref, voices.valueOrNull ?? const <TtsVoice>[]),
              ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<TtsVoice> voices,
  ) async {
    if (voices.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No additional voices are installed on this device.',
            ),
          ),
        );
      return;
    }

    final AppSettings settings = ref.read(settingsProvider);

    final TtsVoice? picked = await showModalBottomSheet<TtsVoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView.builder(
            itemCount: voices.length,
            itemBuilder: (BuildContext context, int index) {
              final TtsVoice voice = voices[index];
              return RadioListTile<TtsVoice>(
                value: voice,
                groupValue: voices.firstWhere(
                  (TtsVoice candidate) =>
                      candidate.name == settings.speech.voiceName,
                  orElse: () => voice,
                ),
                title: Text(voice.name),
                subtitle: Text(
                  voice.isNetworkOnly
                      // Flagged because this app is offline-first: a network
                      // voice silently fails to speak without connectivity.
                      ? '${voice.locale} · needs internet'
                      : voice.locale,
                ),
                onChanged: (_) => Navigator.of(sheetContext).pop(voice),
              );
            },
          ),
        ),
      ),
    );

    if (picked == null) {
      return;
    }

    await ref.read(settingsProvider.notifier).setSpeech(
          settings.speech.copyWith(
            voiceName: picked.name,
            voiceLocale: picked.locale,
            language: picked.locale,
          ),
        );
  }
}

class _RecognitionLocalePicker extends ConsumerWidget {
  const _RecognitionLocalePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SpeechLocale>> locales =
        ref.watch(_speechLocalesProvider);
    final AppSettings settings = ref.watch(settingsProvider);

    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text('Recognition language'),
      subtitle: Text(settings.speechLocaleId ?? 'Device default'),
      trailing: locales.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        _pick(context, ref, locales.valueOrNull ?? const <SpeechLocale>[]),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<SpeechLocale> locales,
  ) async {
    if (locales.isEmpty) {
      return;
    }
    final AppSettings settings = ref.read(settingsProvider);

    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView.builder(
            itemCount: locales.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return ListTile(
                  title: const Text('Device default'),
                  selected: settings.speechLocaleId == null,
                  onTap: () => Navigator.of(sheetContext).pop(''),
                );
              }
              final SpeechLocale locale = locales[index - 1];
              return ListTile(
                title: Text(locale.name),
                subtitle: Text(locale.id),
                selected: settings.speechLocaleId == locale.id,
                onTap: () => Navigator.of(sheetContext).pop(locale.id),
              );
            },
          ),
        ),
      ),
    );

    if (picked == null) {
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .setSpeechLocale(picked.isEmpty ? null : picked);
  }
}

/// A labelled slider that tracks the thumb locally and commits on release.
///
/// Persisting on every drag frame would write to disk and re-configure the TTS
/// engine dozens of times a second, so the value is held in local state while
/// dragging and pushed to the controller once.
class _SpeechSlider extends StatefulWidget {
  const _SpeechSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.format,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;

  @override
  State<_SpeechSlider> createState() => _SpeechSliderState();
}

class _SpeechSliderState extends State<_SpeechSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final double current =
        (_dragging ?? widget.value).clamp(widget.min, widget.max);

    return ListTile(
      enabled: widget.enabled,
      leading: Icon(widget.icon),
      title: Row(
        children: <Widget>[
          Expanded(child: Text(widget.label)),
          Text(widget.format(current)),
        ],
      ),
      subtitle: Slider(
        value: current,
        min: widget.min,
        max: widget.max,
        // 20 steps is fine enough to feel continuous and coarse enough that a
        // value can be reproduced by hand.
        divisions: 20,
        label: widget.format(current),
        onChanged: widget.enabled
            ? (double value) => setState(() => _dragging = value)
            : null,
        onChangeEnd: widget.enabled
            ? (double value) {
                setState(() => _dragging = null);
                widget.onChanged(value);
              }
            : null,
      ),
    );
  }
}

/// Voices installed on this device.
final AutoDisposeFutureProvider<List<TtsVoice>> _voicesProvider =
    FutureProvider.autoDispose<List<TtsVoice>>((Ref ref) async {
  final Result<List<TtsVoice>> result =
      await ref.watch(textToSpeechServiceProvider).availableVoices();
  return result.getOrElse(const <TtsVoice>[]);
});

/// Locales the recogniser supports.
final AutoDisposeFutureProvider<List<SpeechLocale>> _speechLocalesProvider =
    FutureProvider.autoDispose<List<SpeechLocale>>((Ref ref) async {
  final Result<List<SpeechLocale>> result =
      await ref.watch(speechRecognitionServiceProvider).availableLocales();
  return result.getOrElse(const <SpeechLocale>[]);
});
