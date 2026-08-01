import 'package:flutter_test/flutter_test.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/utils/result.dart';

void main() {
  group('Result', () {
    const AppFailure failure = DatabaseFailure(message: 'boom');

    test('success carries its value and reports isSuccess', () {
      const Result<int> result = Success<int>(7);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
    });

    test('failure carries its failure and reports isFailure', () {
      const Result<int> result = Failure<int>(failure);

      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('map transforms success and leaves failure untouched', () {
      expect(
        const Success<int>(2).map((int value) => value * 3),
        const Success<int>(6),
      );
      expect(
        const Failure<int>(failure).map((int value) => value * 3),
        const Failure<int>(failure),
      );
    });

    test('flatMap chains only on success', () {
      Result<String> stringify(int value) => Success<String>('$value');

      expect(
          const Success<int>(4).flatMap(stringify), const Success<String>('4'));
      expect(
        const Failure<int>(failure).flatMap(stringify),
        const Failure<String>(failure),
      );
    });

    test('fold collapses both arms', () {
      expect(
        const Success<int>(1).fold((int v) => 'ok $v', (AppFailure f) => 'no'),
        'ok 1',
      );
      expect(
        const Failure<int>(failure)
            .fold((int v) => 'ok', (AppFailure f) => 'no ${f.code}'),
        'no database_failure',
      );
    });

    test('getOrElse returns the fallback only on failure', () {
      expect(const Success<int>(1).getOrElse(9), 1);
      expect(const Failure<int>(failure).getOrElse(9), 9);
    });

    test('onSuccess and onFailure run the matching side effect only', () {
      int successes = 0;
      int failures = 0;

      const Success<int>(1)
        ..onSuccess((_) => successes++)
        ..onFailure((_) => failures++);
      const Failure<int>(failure)
        ..onSuccess((_) => successes++)
        ..onFailure((_) => failures++);

      expect(successes, 1);
      expect(failures, 1);
    });

    test('guard converts a thrown object into an UnexpectedFailure', () {
      final Result<int> result = Result.guard<int>(
        () => throw StateError('nope'),
      );

      expect(result.failureOrNull, isA<UnexpectedFailure>());
      expect(result.failureOrNull?.cause, isA<StateError>());
    });

    test('guardAsync converts a thrown object into an UnexpectedFailure',
        () async {
      final Result<int> result = await Result.guardAsync<int>(
        () async => throw StateError('nope'),
      );

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });

    test('sequence short-circuits on the first failure', () {
      // Compared unwrapped: `Result` equality delegates to the wrapped value,
      // and Dart lists are compared by identity, not contents.
      expect(
        <Result<int>>[
          const Success<int>(1),
          const Success<int>(2),
        ].sequence().valueOrNull,
        <int>[1, 2],
      );

      final Result<List<int>> mixed = <Result<int>>[
        const Success<int>(1),
        const Failure<int>(failure),
        const Success<int>(3),
      ].sequence();

      expect(mixed.failureOrNull, failure);
    });
  });

  group('AppFailure', () {
    test('classifies retryability per subtype', () {
      expect(
        const DatabaseFailure(message: 'x').isRetryable,
        isTrue,
      );
      expect(
        const ValidationFailure(message: 'x').isRetryable,
        isFalse,
      );
      expect(
        const PermissionFailure(
          message: 'x',
          permission: 'microphone',
          isPermanentlyDenied: true,
        ).isRetryable,
        isFalse,
        reason: 'a permanently denied permission cannot be re-prompted',
      );
      expect(
        const PermissionFailure(message: 'x', permission: 'microphone')
            .isRetryable,
        isTrue,
      );
    });
  });
}
