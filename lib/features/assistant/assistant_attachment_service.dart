import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'assistant_provider.dart';

class AssistantAttachment {
  const AssistantAttachment({required this.name, required this.text});

  final String name;
  final String text;
}

class AssistantAttachmentService {
  AssistantAttachmentService._();

  static const int _maximumBytes = 500 * 1024;
  static const int _maximumCharacters = 24000;
  static const List<String> supportedExtensions = <String>[
    'txt',
    'csv',
    'json',
    'md',
  ];

  static Future<AssistantAttachment?> pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > _maximumBytes ||
        (file.bytes?.length ?? 0) > _maximumBytes) {
      throw const AssistantConversationException(
        'assistant_attachment_too_large',
        'The selected file exceeds the assistant attachment size limit.',
      );
    }
    final extension = (file.extension ?? '').toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const AssistantConversationException(
        'assistant_attachment_unsupported',
        'Choose a TXT, CSV, JSON, or Markdown file.',
      );
    }
    final bytes = file.bytes;
    if (bytes == null) {
      throw const AssistantConversationException(
        'assistant_attachment_unreadable',
        'Ventio could not read the selected file.',
      );
    }
    try {
      final text = utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '')
          .trim();
      if (text.isEmpty) {
        throw const AssistantConversationException(
          'assistant_attachment_empty',
          'The selected file is empty.',
        );
      }
      if (text.length > _maximumCharacters) {
        throw const AssistantConversationException(
          'assistant_attachment_too_large',
          'The selected text is longer than Ventio can attach to one question.',
        );
      }
      return AssistantAttachment(name: file.name, text: text);
    } on FormatException {
      throw const AssistantConversationException(
        'assistant_attachment_invalid_text',
        'This file is not valid UTF-8 text.',
      );
    }
  }
}
