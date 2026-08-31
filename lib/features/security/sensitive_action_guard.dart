import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';

/// Requests a fresh password proof for one high-risk domain action.
/// The resulting short-lived, action-scoped grant is held only in memory and enforced by the domain layer.
Future<bool> requestSensitiveActionAuthorization(
  BuildContext context,
  AppStore store, {
  required String action,
}) async {
  final tr = AppLocalizations.of(context);
  final passwordController = TextEditingController();
  var submitting = false;
  String? errorText;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr.text('sensitive_action_reauth_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('sensitive_action_reauth_desc')),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                enabled: !submitting,
                decoration: InputDecoration(
                  labelText: tr.text('password'),
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onSubmitted: submitting
                    ? null
                    : (_) async {
                        final ok = await _authorize(
                          dialogContext,
                          store,
                          action,
                          passwordController.text,
                          setState,
                          onBusy: (value) => submitting = value,
                          onError: (value) => errorText = value,
                          incorrectText:
                              tr.text('sensitive_action_reauth_incorrect'),
                        );
                        if (ok && dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    final ok = await _authorize(
                      dialogContext,
                      store,
                      action,
                      passwordController.text,
                      setState,
                      onBusy: (value) => submitting = value,
                      onError: (value) => errorText = value,
                      incorrectText:
                          tr.text('sensitive_action_reauth_incorrect'),
                    );
                    if (ok && dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr.text('verify')),
          ),
        ],
      ),
    ),
  );
  passwordController.dispose();
  return result == true;
}

Future<bool> _authorize(
  BuildContext context,
  AppStore store,
  String action,
  String password,
  StateSetter setState, {
  required ValueChanged<bool> onBusy,
  required ValueChanged<String?> onError,
  required String incorrectText,
}) async {
  if (password.trim().isEmpty) {
    setState(() => onError(incorrectText));
    return false;
  }
  setState(() {
    onBusy(true);
    onError(null);
  });
  final ok = await store.security.authorizeSensitiveAction(
    action: action,
    password: password,
  );
  if (!context.mounted) return false;
  setState(() {
    onBusy(false);
    if (!ok) onError(incorrectText);
  });
  return ok;
}
