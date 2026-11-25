import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/javbus/javbus_verification.dart';
import 'app_glass_components.dart';

class JavBusVerificationDialog extends StatefulWidget {
  const JavBusVerificationDialog({super.key, required this.challenge});

  final JavBusVerificationChallenge challenge;

  @override
  State<JavBusVerificationDialog> createState() =>
      _JavBusVerificationDialogState();
}

class _JavBusVerificationDialogState extends State<JavBusVerificationDialog> {
  final answers = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final complete = answers.length == widget.challenge.questions.length;

    return appAlertDialog(
      context,
      title: Text(l10n.javBusVerificationTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.javBusVerificationInstructions),
              const SizedBox(height: 16),
              for (final question in widget.challenge.questions) ...[
                Text(
                  question.prompt,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                RadioGroup<String>(
                  groupValue: answers[question.name],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => answers[question.name] = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in question.options)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: option.value,
                          title: Text(option.label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: complete
              ? () => Navigator.of(
                  context,
                ).pop(Map<String, String>.unmodifiable(answers))
              : null,
          child: Text(l10n.javBusVerificationSubmit),
        ),
      ],
    );
  }
}
