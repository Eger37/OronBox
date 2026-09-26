import 'package:material_ui/material_ui.dart';

/// Displays release notes using the same selectable text style as the
/// firmware page, while parsing the small block syntax used by release
/// bodies locally. It intentionally does not depend on a Markdown widget.
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final blocks = ReleaseNotesParser.parse(data);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _ReleaseNotesBlockView(block: blocks[index]),
        ],
      ],
    );
  }
}

sealed class ReleaseNotesBlock {
  const ReleaseNotesBlock();
}

class ReleaseNotesHeading extends ReleaseNotesBlock {
  const ReleaseNotesHeading(this.level, this.text);

  final int level;
  final String text;
}

class ReleaseNotesParagraph extends ReleaseNotesBlock {
  const ReleaseNotesParagraph(this.text);

  final String text;
}

class ReleaseNotesList extends ReleaseNotesBlock {
  const ReleaseNotesList({required this.ordered, required this.items});

  final bool ordered;
  final List<String> items;
}

class ReleaseNotesCodeBlock extends ReleaseNotesBlock {
  const ReleaseNotesCodeBlock(this.text);

  final String text;
}

class ReleaseNotesDivider extends ReleaseNotesBlock {
  const ReleaseNotesDivider();
}

class ReleaseNotesParser {
  const ReleaseNotesParser._();

  static List<ReleaseNotesBlock> parse(String source) {
    final lines = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final blocks = <ReleaseNotesBlock>[];
    final paragraphLines = <String>[];
    final listItems = <String>[];
    bool? listOrdered;
    var inCodeBlock = false;
    final codeLines = <String>[];

    void flushParagraph() {
      if (paragraphLines.isEmpty) return;
      final text = paragraphLines.join('\n').trim();
      paragraphLines.clear();
      if (text.isNotEmpty) blocks.add(ReleaseNotesParagraph(text));
    }

    void flushList() {
      if (listItems.isEmpty || listOrdered == null) return;
      blocks.add(
        ReleaseNotesList(
          ordered: listOrdered!,
          items: List.unmodifiable(listItems),
        ),
      );
      listItems.clear();
      listOrdered = null;
    }

    void flushCode() {
      blocks.add(ReleaseNotesCodeBlock(codeLines.join('\n')));
      codeLines.clear();
      inCodeBlock = false;
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (inCodeBlock) {
        if (RegExp(r'^(```|~~~)\s*$').hasMatch(trimmed)) {
          flushCode();
        } else {
          codeLines.add(line);
        }
        continue;
      }

      if (RegExp(r'^(```|~~~)').hasMatch(trimmed)) {
        flushParagraph();
        flushList();
        inCodeBlock = true;
        continue;
      }

      if (trimmed.isEmpty) {
        flushParagraph();
        flushList();
        continue;
      }

      final heading = RegExp(
        r'^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$',
      ).firstMatch(line);
      if (heading != null) {
        flushParagraph();
        flushList();
        blocks.add(
          ReleaseNotesHeading(heading.group(1)!.length, heading.group(2)!),
        );
        continue;
      }

      if (RegExp(r'^(\*{3,}|-{3,}|_{3,})$').hasMatch(trimmed)) {
        flushParagraph();
        flushList();
        blocks.add(const ReleaseNotesDivider());
        continue;
      }

      final bullet = RegExp(
        r'^\s*[-*+]\s+(?:\[[ xX]\]\s*)?(.+?)\s*$',
      ).firstMatch(line);
      final ordered = RegExp(r'^\s*\d+[.)]\s+(.+?)\s*$').firstMatch(line);
      if (bullet != null || ordered != null) {
        flushParagraph();
        final isOrdered = ordered != null;
        if (listOrdered != null && listOrdered != isOrdered) flushList();
        listOrdered ??= isOrdered;
        listItems.add((bullet?.group(1) ?? ordered!.group(1)!).trim());
        continue;
      }

      if (listItems.isNotEmpty &&
          (raw.startsWith(' ') || raw.startsWith('\t'))) {
        listItems[listItems.length - 1] = '${listItems.last}\n$trimmed'.trim();
        continue;
      }

      if (listItems.isNotEmpty) flushList();
      paragraphLines.add(line);
    }

    if (inCodeBlock) flushCode();
    flushParagraph();
    flushList();
    return List.unmodifiable(blocks);
  }
}

class _ReleaseNotesBlockView extends StatelessWidget {
  const _ReleaseNotesBlockView({required this.block});

  final ReleaseNotesBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );

    return switch (block) {
      ReleaseNotesHeading(:final level, :final text) => SelectableText(
        text,
        style: _headingStyle(theme, level),
      ),
      ReleaseNotesParagraph(:final text) => SelectableText(
        text,
        style: bodyStyle,
      ),
      ReleaseNotesList(:final ordered, :final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < items.length; index++)
            SelectableText(
              '${ordered ? '${index + 1}. ' : '• '}${items[index]}',
              style: bodyStyle,
            ),
        ],
      ),
      ReleaseNotesCodeBlock(:final text) => SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
      ReleaseNotesDivider() => const Divider(),
    };
  }
}

TextStyle? _headingStyle(ThemeData theme, int level) {
  final style = switch (level) {
    1 => theme.textTheme.titleLarge,
    2 => theme.textTheme.titleMedium,
    _ => theme.textTheme.titleSmall,
  };
  return style?.copyWith(fontWeight: FontWeight.w700);
}
