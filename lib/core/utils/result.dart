/// The `Result` type used across every layer boundary in this application.
///
/// Repositories, use cases and services never throw. They return a [Result],
/// which is either a [Success] carrying a value or a [Failure] carrying an
/// [AppFailure]. Because [Result] is sealed, `switch` expressions over it are
/// exhaustiveness-checked at compile time, which is what keeps error handling
/// from silently rotting as new call sites appear.
library;

import 'package:voice_reminder/core/errors/app_failure.dart';

/// Either a value of type [T] or an [AppFailure].
sealed class Result<T> {
  /// Const base constructor.
  const Result();

  /// Wraps a successful [value].
  const factory Result.success(T value) = Success<T>;

  /// Wraps a [failure].
  const factory Result.failure(AppFailure failure) = Failure<T>;

  /// Runs [action], converting any thrown object into an [UnexpectedFailure].
  ///
  /// Use this only at the outermost edge of a layer — where an untrusted
  /// third-party API can throw — not as a substitute for handling errors that
  /// the code already knows how to classify.
  static Result<T> guard<T>(T Function() action) {
    try {
      return Success<T>(action());
    } on Object catch (error, stackTrace) {
      return Failure<T>(
        UnexpectedFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// Asynchronous counterpart of [guard].
  static Future<Result<T>> guardAsync<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } on Object catch (error, stackTrace) {
      return Failure<T>(
        UnexpectedFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// Whether this is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Whether this is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// The value when successful, otherwise `null`.
  ///
  /// Prefer [fold] or a `switch`: this getter erases the distinction between
  /// "failed" and "succeeded with null".
  T? get valueOrNull => switch (this) {
        Success<T>(:final T value) => value,
        Failure<T>() => null,
      };

  /// The failure when unsuccessful, otherwise `null`.
  AppFailure? get failureOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final AppFailure failure) => failure,
      };

  /// The value when successful, otherwise [fallback].
  T getOrElse(T fallback) => switch (this) {
        Success<T>(:final T value) => value,
        Failure<T>() => fallback,
      };

  /// The value when successful, otherwise the result of [orElse].
  T getOrElseWith(T Function(AppFailure failure) orElse) => switch (this) {
        Success<T>(:final T value) => value,
        Failure<T>(:final AppFailure failure) => orElse(failure),
      };

  /// Collapses both arms into a single value of type [R].
  R fold<R>(
    R Function(T value) onSuccess,
    R Function(AppFailure failure) onFailure,
  ) =>
      switch (this) {
        Success<T>(:final T value) => onSuccess(value),
        Failure<T>(:final AppFailure failure) => onFailure(failure),
      };

  /// Transforms a successful value with [transform], propagating failures.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success<T>(:final T value) => Success<R>(transform(value)),
        Failure<T>(:final AppFailure failure) => Failure<R>(failure),
      };

  /// Chains another fallible operation, propagating failures.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
        Success<T>(:final T value) => transform(value),
        Failure<T>(:final AppFailure failure) => Failure<R>(failure),
      };

  /// Asynchronous counterpart of [flatMap].
  Future<Result<R>> flatMapAsync<R>(
    Future<Result<R>> Function(T value) transform,
  ) async =>
      switch (this) {
        Success<T>(:final T value) => await transform(value),
        Failure<T>(:final AppFailure failure) => Failure<R>(failure),
      };

  /// Replaces the failure with another one produced by [transform].
  Result<T> mapFailure(AppFailure Function(AppFailure failure) transform) =>
      switch (this) {
        Success<T>() => this,
        Failure<T>(:final AppFailure failure) => Failure<T>(transform(failure)),
      };

  /// Runs [action] when successful and returns this result unchanged.
  ///
  /// Useful for side effects such as logging or cache invalidation without
  /// breaking a call chain.
  Result<T> onSuccess(void Function(T value) action) {
    if (this case Success<T>(:final T value)) {
      action(value);
    }
    return this;
  }

  /// Runs [action] when unsuccessful and returns this result unchanged.
  Result<T> onFailure(void Function(AppFailure failure) action) {
    if (this case Failure<T>(:final AppFailure failure)) {
      action(failure);
    }
    return this;
  }
}

/// The successful arm of a [Result].
final class Success<T> extends Result<T> {
  /// Wraps [value] as a success.
  const Success(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Success<T> &&
          runtimeType == other.runtimeType &&
          value == other.value);

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Success<$T>($value)';
}

/// The unsuccessful arm of a [Result].
final class Failure<T> extends Result<T> {
  /// Wraps [failure] as a failed result.
  const Failure(this.failure);

  /// Description of what went wrong.
  final AppFailure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure<T> &&
          runtimeType == other.runtimeType &&
          failure == other.failure);

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'Failure<$T>($failure)';
}

/// Convenience helpers for asynchronous results.
extension FutureResultExtensions<T> on Future<Result<T>> {
  /// Awaits this result and maps its successful value.
  Future<Result<R>> mapAsync<R>(R Function(T value) transform) async =>
      (await this).map(transform);

  /// Awaits this result and chains another fallible operation.
  Future<Result<R>> thenFlatMap<R>(
    Future<Result<R>> Function(T value) transform,
  ) async =>
      (await this).flatMapAsync(transform);

  /// Awaits this result and collapses both arms.
  Future<R> foldAsync<R>(
    R Function(T value) onSuccess,
    R Function(AppFailure failure) onFailure,
  ) async =>
      (await this).fold(onSuccess, onFailure);
}

/// Aggregation helpers for collections of results.
extension ResultIterableExtensions<T> on Iterable<Result<T>> {
  /// Turns a list of results into a result of a list.
  ///
  /// Short-circuits on the first failure, which is the desired behaviour for
  /// batch operations that must not be applied partially.
  Result<List<T>> sequence() {
    final List<T> values = <T>[];
    for (final Result<T> result in this) {
      switch (result) {
        case Success<T>(:final T value):
          values.add(value);
        case Failure<T>(:final AppFailure failure):
          return Failure<List<T>>(failure);
      }
    }
    return Success<List<T>>(values);
  }
}

/// Shorthand for results that carry no meaningful value.
typedef VoidResult = Result<void>;

/// A successful [VoidResult].
const VoidResult voidSuccess = Success<void>(null);
