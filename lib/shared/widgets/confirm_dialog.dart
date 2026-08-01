/// Confirmation dialogs for destructive actions.
library;

import 'package:flutter/material.dart';

/// Asks the user to confirm an action.
///
/// Returns `true` only when the user explicitly confirms; dismissing the dialog
/// by tapping outside or pressing back returns `false`, never `null`, so call
/// sites cannot mistake a dismissal for a confirmation.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final ThemeData theme = Theme.of(context);

  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}
