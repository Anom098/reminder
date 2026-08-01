/// Bakes a reminder's announcement into a notification sound file on iOS.
library;

import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_reminder/core/constants/app_constants.dart';
import 'package:voice_reminder/core/services/logging/app_logger.dart';
import 'package:voice_reminder/features/settings/domain/entities/app_settings.dart';

/// Produces the `.caf` files that let a reminder speak while iOS is locked.
///
/// No iOS API lets an app wake itself and run code at a scheduled instant, so
/// `flutter_tts` cannot be called live when a reminder fires in the
/// background — see [LocalNotificationService]. What iOS *does* do
/// automatically, even locked, is play a notification's custom sound. This
/// class pre-synthesises the announcement (repeated per the user's settings,
/// with silence gaps) into a sound file at scheduling time and hands its name
/// to `DarwinNotificationDetails.sound`, so the OS plays it on delivery
/// without the app running at all.
final class IosSpokenSoundBaker {
  /// Creates a baker over [engine].
  IosSpokenSoundBaker({
    required AppLogger logger,
    FlutterTts? engine,
  })  : _log = logger.forContext('IosSpokenSound'),
        _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  final AppLogger _log;
  bool _configured = false;

  /// Apple silently rejects a custom sound longer than this and falls back to
  /// the default notification sound — no error is surfaced to the app.
  static const Duration _appleSoundCap = Duration(seconds: 30);

  /// Ceiling used when fitting repeats, below [_appleSoundCap].
  ///
  /// The duration used against this budget is a heuristic estimate, not a
  /// measurement, so this margin exists to absorb it being wrong.
  static const Duration _budget = Duration(seconds: 24);

  static const String _soundsSubdir = 'Sounds';

  static String _fileNameFor(int notificationId) =>
      'voice_reminder_$notificationId.caf';

  /// Synthesises [text] into a sound file for [notificationId], returning the
  /// bare filename (not a path) to pass to `DarwinNotificationDetails.sound`,
  /// or `null` if it could not be produced.
  Future<String?> bake({
    required int notificationId,
    required String text,
  }) async {
    if (!Platform.isIOS) {
      return null;
    }
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(StorageKeys.speakReminders) ?? true)) {
        return null;
      }
      final int repeatSetting = AppSettings.clampSpeakRepeatCount(
        prefs.getInt(StorageKeys.speakRepeatCount) ?? 1,
      );
      final Duration interval = AppSettings.clampSpeakRepeatInterval(
        Duration(
          seconds: prefs.getInt(StorageKeys.speakRepeatIntervalSeconds) ?? 5,
        ),
      );
      final double rate = prefs.getDouble(StorageKeys.ttsRate) ?? 0.5;

      final int repeats = _fitRepeats(
        text: trimmed,
        repeats: repeatSetting,
        interval: interval,
        rate: rate,
      );
      final String script = _buildScript(
        text: trimmed,
        repeats: repeats,
        interval: interval,
      );

      await _configure(prefs);

      final Directory dir = await _soundsDirectory();
      final String fileName = _fileNameFor(notificationId);
      final File file = File('${dir.path}/$fileName');
      // flutter_tts opens the destination for appending; stale content from a
      // previous edit of this reminder must not bleed into the new file.
      if (file.existsSync()) {
        file.deleteSync();
      }

      await _tts.awaitSynthCompletion(true);
      await _tts.synthesizeToFile(script, file.path, true);
      return file.existsSync() ? fileName : null;
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Could not bake spoken sound for notification $notificationId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Deletes the baked sound file for [notificationId], if one exists.
  Future<void> delete(int notificationId) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      final Directory dir = await _soundsDirectory();
      final File file = File('${dir.path}/${_fileNameFor(notificationId)}');
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object catch (error) {
      // Best-effort cleanup: a leftover file costs a few KB of storage, not
      // correctness, and is not worth failing the caller over.
      _log.warning('Could not delete spoken sound for $notificationId: $error');
    }
  }

  /// Deletes every baked sound file this app has produced.
  Future<void> deleteAll() async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      final Directory dir = await _soundsDirectory();
      if (!dir.existsSync()) {
        return;
      }
      for (final FileSystemEntity entity in dir.listSync()) {
        if (entity is File && entity.path.contains('voice_reminder_')) {
          entity.deleteSync();
        }
      }
    } on Object catch (error) {
      _log.warning('Could not clear spoken sound files: $error');
    }
  }

  Future<void> _configure(SharedPreferences prefs) async {
    if (_configured) {
      return;
    }
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      <IosTextToSpeechAudioCategoryOptions>[
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions
            .interruptSpokenAudioAndMixWithOthers,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );
    await _tts.setLanguage(
      prefs.getString(StorageKeys.ttsLanguage) ?? 'en-US',
    );
    await _tts.setSpeechRate(prefs.getDouble(StorageKeys.ttsRate) ?? 0.5);
    await _tts.setPitch(prefs.getDouble(StorageKeys.ttsPitch) ?? 1.0);
    await _tts.setVolume(prefs.getDouble(StorageKeys.ttsVolume) ?? 1.0);

    final String? voiceName = prefs.getString(StorageKeys.ttsVoiceName);
    final String? voiceLocale = prefs.getString(StorageKeys.ttsVoiceLocale);
    if (voiceName != null && voiceLocale != null) {
      try {
        await _tts.setVoice(<String, String>{
          'name': voiceName,
          'locale': voiceLocale,
        });
      } on Object catch (_) {
        // Falls back to the language default; not worth failing the bake.
      }
    }
    _configured = true;
  }

  Future<Directory> _soundsDirectory() async {
    // Custom local-notification sounds must live in the app's own
    // Library/Sounds directory (or its main bundle) — anywhere else, iOS
    // silently ignores the `sound:` name and plays the default tone instead.
    final Directory library = await getLibraryDirectory();
    final Directory dir = Directory('${library.path}/$_soundsSubdir');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Joins [repeats] copies of [text] with an embedded silence command.
  ///
  /// `[[slnc N]]` is a long-standing, undocumented extension the
  /// AVSpeechSynthesizer engine understands, inserting N milliseconds of
  /// silence into the synthesised audio. It is the only way to bake a real
  /// pause into one static sound file — flutter_tts has no API to
  /// concatenate separate utterances. Support varies by voice; the worst
  /// case is repeats running together with no gap, which is still an
  /// improvement over today's total silence while locked.
  String _buildScript({
    required String text,
    required int repeats,
    required Duration interval,
  }) {
    if (repeats <= 1) {
      return text;
    }
    final String silence = '[[slnc ${interval.inMilliseconds}]]';
    return List<String>.filled(repeats, text).join(' $silence ');
  }

  /// Reduces [repeats] so the estimated total duration fits [_budget].
  int _fitRepeats({
    required String text,
    required int repeats,
    required Duration interval,
    required double rate,
  }) {
    final Duration perUtterance = _estimateDuration(text, rate);
    int fitted = repeats;
    while (fitted > 1 &&
        _totalDuration(perUtterance, interval, fitted) > _budget) {
      fitted--;
    }
    return fitted;
  }

  Duration _totalDuration(
    Duration perUtterance,
    Duration interval,
    int repeats,
  ) =>
      perUtterance * repeats + interval * (repeats - 1);

  /// Rough speech-duration estimate from character count and rate.
  ///
  /// flutter_tts's `rate` runs 0.0 (slowest) to 1.0 (fastest); roughly 13
  /// characters per second at the default 0.5 is a reasonable average for
  /// English speech, scaled linearly. A heuristic, not a measurement —
  /// [_budget] leaves headroom for it being wrong in either direction.
  Duration _estimateDuration(String text, double rate) {
    final double clampedRate = rate.clamp(0.1, 1.0);
    final double charsPerSecond = 6.5 + 13 * clampedRate;
    final double seconds = text.length / charsPerSecond;
    final int millis = (seconds * 1000).round().clamp(500, 20000);
    return Duration(milliseconds: millis);
  }

  /// Exposed for tests and callers that want to reason about the cap.
  static Duration get appleSoundCap => _appleSoundCap;
}
