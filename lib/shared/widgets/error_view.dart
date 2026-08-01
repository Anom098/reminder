/// Full-area error presentation.
library;

import 'package:flutter/material.dart';
import 'package:voice_reminder/core/errors/app_failure.dart';
import 'package:voice_reminder/core/theme/app_theme.dart';

/// Explains a failure and offers a way forward.
///
/// Never shows a stack trace or an exception's `toString()`: the message comes
/// from [AppFailure.message], which is written for end users.
class ErrorView extends StatelessWidget {
  /// Creates an error view from explicit text.
  const ErrorView({
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.error_outline,
    super.key,
  });

  /// Creates an error view from a [failure].
  ///
  /// The retry action is only offered when the failure says retrying could
  /// plausibly work, so the user is never invited to repeat something that
  /// cannot succeed.
  factory ErrorView.fromFailure(
    AppFailure failure, {
    VoidCallback? onRetry,
    Key? key,
  }) =>
      ErrorView(
        key: key,
        title: 'Something went wrong',
        message: failure.message,
        onRetry: failure.isRetryable ? onRetry : null,
        icon: switch (failure) {
          PermissionFailure() => Icons.lock_outline,
          NotFoundFailure() => Icons.search_off,
          StorageFailure() || SerializationFailure() => Icons.folder_off,
          _ => Icons.error_outline,
        },
      );

  /// Short headline.
  final String title;

  /// Explanation shown beneath the headline.
  final String message;

  /// Invoked when the user asks to retry. Hidden when `null`.
  final VoidCallback? onRetry;

  /// Label for the retry button.
  final String retryLabel;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: Insets.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: Insets.xl),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
