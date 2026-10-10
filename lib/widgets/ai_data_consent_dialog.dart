import 'package:flutter/material.dart';

import '../l10n.dart';

enum AiDataChoice { send, local, cancel }

/// Each operation requires an explicit choice before sending personal data.
Future<AiDataChoice> showAiDataConsent(
  BuildContext context, {
  bool voice = false,
}) async {
  final i18n = context.i18n;
  return await showDialog<AiDataChoice>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n.tr('ai_data_consent_title')),
          content: SingleChildScrollView(
            child: Text(
              i18n.tr(
                voice ? 'ai_audio_consent_body' : 'ai_diary_consent_body',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, AiDataChoice.cancel),
              child: Text(i18n.tr('cancel')),
            ),
            if (!voice)
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, AiDataChoice.local),
                child: Text(i18n.tr('ai_save_locally')),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, AiDataChoice.send),
              child: Text(i18n.tr('ai_allow_send')),
            ),
          ],
        ),
      ) ??
      AiDataChoice.cancel;
}
