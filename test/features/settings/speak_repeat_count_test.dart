/// Tests for the spoken-announcement repeat count.
///
/// The value reaches the text-to-speech loop from three directions — the
/// settings screen, stored preferences, and an imported backup — and only one
/// of those is under the app's control. Every entry point clamps, because the
/// consequence of a bad value is an app that will not stop talking.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';

void main() {
  group('defaults', () {
    test('speaks once unless asked otherwise', () {
      expect(const AppSettings().speakRepeatCount, 1);
    });
  });

  group('clamping', () {
    test('rejects zero and negatives, which would silence reminders', () {
      expect(AppSettings.clampSpeakRepeatCount(0), 1);
      expect(AppSettings.clampSpeakRepeatCount(-3), 1);
    });

    test('caps absurd values rather than obeying them', () {
      expect(AppSettings.clampSpeakRepeatCount(500), 5);
    });

    test('passes valid values through unchanged', () {
      for (int value = 1; value <= 5; value++) {
        expect(AppSettings.clampSpeakRepeatCount(value), value);
      }
    });
  });

  group('copyWith', () {
    test('clamps on the way in', () {
      expect(
        const AppSettings().copyWith(speakRepeatCount: 99).speakRepeatCount,
        5,
      );
      expect(
        const AppSettings().copyWith(speakRepeatCount: 0).speakRepeatCount,
        1,
      );
    });

    test('keeps the current value when not specified', () {
      const AppSettings settings = AppSettings(speakRepeatCount: 3);

      expect(settings.copyWith(speakReminders: false).speakRepeatCount, 3);
    });

    test('participates in equality', () {
      expect(
        const AppSettings(speakRepeatCount: 2),
        isNot(const AppSettings(speakRepeatCount: 3)),
      );
      expect(
        const AppSettings(speakRepeatCount: 2),
        const AppSettings(speakRepeatCount: 2),
      );
    });
  });

  group('the repeat interval', () {
    test('defaults to something long enough to hear as a separate utterance', () {
      // Back-to-back repeats run together into one sentence and stop reading
      // as a repetition, which defeats the point of the setting.
      expect(
        const AppSettings().speakRepeatInterval.inMilliseconds,
        greaterThanOrEqualTo(500),
      );
    });

    test('rejects a zero or negative interval', () {
      expect(
        AppSettings.clampSpeakRepeatInterval(Duration.zero),
        AppSettings.minSpeakRepeatInterval,
      );
      expect(
        AppSettings.clampSpeakRepeatInterval(const Duration(seconds: -3)),
        AppSettings.minSpeakRepeatInterval,
      );
    });

    test('caps absurd values rather than obeying them', () {
      expect(
        AppSettings.clampSpeakRepeatInterval(const Duration(minutes: 5)),
        AppSettings.maxSpeakRepeatInterval,
      );
    });

    test('passes valid values through unchanged', () {
      const Duration interval = Duration(seconds: 5);
      expect(AppSettings.clampSpeakRepeatInterval(interval), interval);
    });

    test('clamps on the way in via copyWith', () {
      expect(
        const AppSettings()
            .copyWith(speakRepeatInterval: const Duration(minutes: 5))
            .speakRepeatInterval,
        AppSettings.maxSpeakRepeatInterval,
      );
    });
  });
}
