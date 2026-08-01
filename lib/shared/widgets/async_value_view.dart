/// Consistent loading / error / data presentation for Riverpod values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/shared/widgets/error_view.dart';

/// Renders an [AsyncValue] with a shared loading and error treatment.
///
/// Every asynchronous surface in the app goes through this widget so that a
/// failure looks and behaves the same everywhere, and so no screen accidentally
/// renders a raw exception.
class AsyncValueView<T> extends StatelessWidget {
  /// Creates a view over [value].
  const AsyncValueView({
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
    super.key,
  });

  /// The value to render.
  final AsyncValue<T> value;

  /// Builds the content once data is available.
  final Widget Function(BuildContext context, T data) builder;

  /// Invoked from the error state's retry button.
  final VoidCallback? onRetry;

  /// Overrides the default loading indicator.
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (T data) => builder(context, data),
      loading: () =>
          loading ?? const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) {
        // Providers in this app surface `AppFailure`s. Anything else is a bug,
        // and is shown as a generic message rather than leaking internals.
        final AppFailure failure = error is AppFailure
            ? error
            : UnexpectedFailure(cause: error, stackTrace: stackTrace);
        return ErrorView.fromFailure(failure, onRetry: onRetry);
      },
      // Keep the previous data on screen while a refresh is in flight; a list
      // that flashes to a spinner on every rebuild is worse than a slightly
      // stale one.
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );
  }
}
