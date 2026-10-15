part of 'assistant_chat_page.dart';

class _AssistantMessageBubble extends StatelessWidget {
  const _AssistantMessageBubble({
    required this.turn,
    this.onRetry,
    this.onExportExcel,
    this.onExportPdf,
  });

  final AssistantChatTurn turn;
  final VoidCallback? onRetry;
  final VoidCallback? onExportExcel;
  final VoidCallback? onExportPdf;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final isUser = turn.role == AssistantChatRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width.clamp(280, 900).toDouble() *
                  0.88,
        ),
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: isUser
              ? colors.primaryContainer
              : turn.isError
                  ? colors.errorContainer.withValues(alpha: 0.55)
                  : colors.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (turn.attachedFileName != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file, size: 16),
                      const SizedBox(width: 4),
                      Text(turn.attachedFileName!,
                          style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (isUser)
                  SelectableText(turn.content)
                else
                  _AssistantAnswerContent(text: turn.content),
                if (turn.errorDiagnostic != null &&
                    turn.errorDiagnostic!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    dense: true,
                    title: Text(tr.text('assistant_error_details')),
                    children: [
                      SelectableText(
                        turn.errorDiagnostic!,
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ],
                if (onRetry != null ||
                    onExportExcel != null ||
                    onExportPdf != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (onRetry != null)
                          OutlinedButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(tr.text('assistant_retry')),
                          ),
                        if (onExportExcel != null)
                          TextButton.icon(
                            onPressed: onExportExcel,
                            icon:
                                const Icon(Icons.table_view_outlined, size: 18),
                            label: Text(tr.text('assistant_export_excel')),
                          ),
                        if (onExportPdf != null)
                          TextButton.icon(
                            onPressed: onExportPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                            label: Text(tr.text('assistant_export_pdf')),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantAnswerContent extends StatelessWidget {
  const _AssistantAnswerContent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = AppLocalizations.of(context).textDirection;
    final blocks = <Widget>[];
    final paragraph = <String>[];
    final code = <String>[];
    var inCode = false;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final value = paragraph.join(' ').trim();
      paragraph.clear();
      if (value.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: SelectableText.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium,
            children: _inlineSpans(value, theme),
          ),
          textDirection: direction,
        ),
      ));
    }

    void flushCode() {
      if (code.isEmpty) return;
      blocks.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(
          code.join('\n'),
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
      ));
      code.clear();
    }

    final lines = text.split('\n');
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
      final sourceLine = lines[lineIndex];
      final line = sourceLine.trimRight();
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          flushCode();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      final heading = RegExp(r'^\s{0,3}(#{1,3})\s+(.+)$').firstMatch(line);
      if (heading != null) {
        flushParagraph();
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SelectableText.rich(
            TextSpan(
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              children: _inlineSpans(heading.group(2)!, theme),
            ),
            textDirection: direction,
          ),
        ));
        continue;
      }
      if (line.trimLeft().startsWith('|')) {
        flushParagraph();
        final tableRows = <List<String>>[];
        while (lineIndex < lines.length &&
            lines[lineIndex].trimLeft().startsWith('|')) {
          final cells = _tableCells(lines[lineIndex]);
          final separator = cells.isNotEmpty &&
              cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell));
          if (!separator) tableRows.add(cells);
          lineIndex += 1;
        }
        lineIndex -= 1;
        if (tableRows.isNotEmpty) {
          blocks.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                children: [
                  for (var rowIndex = 0;
                      rowIndex < tableRows.length;
                      rowIndex += 1)
                    TableRow(
                      decoration: rowIndex == 0
                          ? BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                            )
                          : null,
                      children: [
                        for (final cell in tableRows[rowIndex])
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 88,
                              maxWidth: 240,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: SelectableText.rich(
                                TextSpan(
                                  style: rowIndex == 0
                                      ? theme.textTheme.labelMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : theme.textTheme.bodySmall,
                                  children: _inlineSpans(cell, theme),
                                ),
                                textDirection: direction,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ));
        }
        continue;
      }
      final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
      if (quote != null) {
        flushParagraph();
        blocks.add(Container(
          margin: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          padding: const EdgeInsetsDirectional.only(start: 10),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: SelectableText(
            quote.group(1)!,
            textDirection: direction,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ));
        continue;
      }
      final bullet = RegExp(r'^\s*[-*+]\s+(.+)$').firstMatch(line);
      final numbered = RegExp(r'^\s*\d+[.)]\s+(.+)$').firstMatch(line);
      final listText = bullet?.group(1) ?? numbered?.group(1);
      if (listText != null) {
        flushParagraph();
        blocks.add(Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8, top: 2),
                child: Icon(
                  bullet != null ? Icons.circle : Icons.arrow_right,
                  size: bullet != null ? 7 : 15,
                ),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: _inlineSpans(listText, theme),
                  ),
                  textDirection: direction,
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      if (RegExp(r'^\s*[-*_]{3,}\s*$').hasMatch(line)) {
        flushParagraph();
        blocks.add(const Divider(height: 16));
        continue;
      }
      paragraph.add(line.trim());
    }
    if (inCode) flushCode();
    flushParagraph();
    if (blocks.isEmpty) return SelectableText(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  static List<InlineSpan> _inlineSpans(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final normalized = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)'),
      (match) => '${match.group(1)} (${match.group(2)})',
    );
    final pattern = RegExp(
      r'(\*\*.+?\*\*|__.+?__|`[^`]+`|\*[^*]+?\*|_[^_]+?_)',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(normalized)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: normalized.substring(cursor, match.start)));
      }
      final value = match.group(0)!;
      if (value.startsWith('`')) {
        spans.add(TextSpan(
          text: value.substring(1, value.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surface,
          ),
        ));
      } else {
        final isStrong = value.startsWith('__') || value.startsWith('**');
        final content = isStrong
            ? value.substring(2, value.length - 2)
            : value.substring(1, value.length - 1);
        spans.add(TextSpan(
          text: content,
          style: TextStyle(
            fontWeight: isStrong ? FontWeight.w700 : FontWeight.normal,
            fontStyle: isStrong ? FontStyle.normal : FontStyle.italic,
          ),
        ));
      }
      cursor = match.end;
    }
    if (cursor < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(cursor)));
    }
    return spans;
  }

  static List<String> _tableCells(String line) {
    var normalized = line.trim();
    if (normalized.startsWith('|')) normalized = normalized.substring(1);
    if (normalized.endsWith('|')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized
        .split('|')
        .map((cell) => cell.trim().replaceAll(r'\|', '|'))
        .toList(growable: false);
  }
}

class _AssistantTypingIndicator extends StatelessWidget {
  const _AssistantTypingIndicator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(label),
            ],
          ),
        ),
      );
}
