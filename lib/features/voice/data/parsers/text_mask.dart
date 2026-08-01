/// Index-aligned text masking used by the rule-based parser.
library;

/// A string that patterns can consume from, leaving the rest intact.
///
/// The parser matches against a lowercase view of the text. When a pattern
/// matches, the characters it covered are *masked*: blanked out in the view so
/// no later pattern can match them again, and marked as consumed so they are
/// excluded from the reminder title.
///
/// The lowercase view is built character by character, and any character whose
/// lowercase form is not exactly one code unit is left as-is. That guarantees
/// the view and the original stay index-aligned, which is the entire basis for
/// mapping a match position back onto the original text.
final class TextMask {
  /// Creates a mask over [source].
  TextMask(this.source)
      : _view = List<String>.generate(
          source.length,
          (int index) {
            final String character = source[index];
            final String lower = character.toLowerCase();
            return lower.length == 1 ? lower : character;
          },
          growable: false,
        ),
        _consumed = List<bool>.filled(source.length, false);

  /// The original text, unchanged.
  final String source;

  final List<String> _view;
  final List<bool> _consumed;

  /// The current lowercase view, with consumed spans blanked to spaces.
  String get view => _view.join();

  /// Finds the first match of [pattern] in the unconsumed text.
  RegExpMatch? firstMatch(RegExp pattern) => pattern.firstMatch(view);

  /// Marks the span covered by [match] as consumed.
  void maskMatch(RegExpMatch match) => _mask(match.start, match.end);

  /// Masks the first match of [pattern], returning whether one was found.
  bool maskFirst(RegExp pattern) {
    final RegExpMatch? match = firstMatch(pattern);
    if (match == null) {
      return false;
    }
    maskMatch(match);
    return true;
  }

  /// Masks every match of [pattern], returning how many were consumed.
  int maskAll(RegExp pattern) {
    int count = 0;
    // Re-query after each mask: consuming a span shifts what the next match
    // sees, so a single `allMatches` pass would use stale positions.
    while (maskFirst(pattern)) {
      count++;
    }
    return count;
  }

  /// The unconsumed text, in its original casing, with whitespace collapsed.
  String remainder() {
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < source.length; index++) {
      if (!_consumed[index]) {
        buffer.write(source[index]);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Whether every character has been consumed.
  bool get isFullyConsumed => !_consumed.contains(false) || remainder().isEmpty;

  void _mask(int start, int end) {
    for (int index = start; index < end && index < source.length; index++) {
      _consumed[index] = true;
      _view[index] = ' ';
    }
  }

  @override
  String toString() => 'TextMask("${remainder()}")';
}
