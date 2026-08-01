/// Animated microphone indicator shown while listening.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A pulsing microphone whose halo tracks the input level.
///
/// Two motions are combined deliberately. The continuous pulse tells the user
/// the app is listening even in silence; the level-driven halo tells them the
/// microphone is actually picking their voice up. A level-only animation looks
/// broken in a quiet room, which is exactly when users doubt it is working.
class ListeningIndicator extends StatefulWidget {
  /// Creates an indicator.
  const ListeningIndicator({required this.soundLevel, super.key});

  /// Latest sound level in decibels, as reported by the recogniser.
  ///
  /// Platforms report wildly different ranges (and some report nothing at all),
  /// so the value is normalised rather than trusted.
  final double soundLevel;

  @override
  State<ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Maps a decibel reading onto `0.0`–`1.0`.
  ///
  /// Android reports roughly -2..10 and iOS roughly -60..0, so the input is
  /// clamped generously rather than scaled precisely; the halo only needs to
  /// convey "louder" and "quieter".
  double get _normalisedLevel {
    final double level = widget.soundLevel;
    if (level.isNaN || level.isInfinite) {
      return 0;
    }
    final double shifted = level < -20 ? (level + 60) / 60 : (level + 2) / 12;
    return shifted.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Listening',
      liveRegion: true,
      child: SizedBox(
        height: 140,
        child: Center(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) {
              final double breathing = 0.5 + (_pulse.value * 0.5);
              final double radius =
                  44 + (breathing * 8) + (_normalisedLevel * 26);

              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: radius * 2,
                    height: radius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(
                        alpha: 0.10 + (_normalisedLevel * 0.15),
                      ),
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primaryContainer,
                    ),
                    child: Transform.rotate(
                      // A barely-perceptible tilt keeps the icon from looking
                      // frozen inside the moving halo.
                      angle: math.sin(_pulse.value * math.pi) * 0.02,
                      child: Icon(
                        Icons.mic,
                        size: 40,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
