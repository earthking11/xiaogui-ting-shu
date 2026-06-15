import '../core/constants.dart';

class ReaderParagraph {
  const ReaderParagraph({
    required this.index,
    required this.text,
    required this.startCharOffset,
    required this.endCharOffset,
  });

  final int index;
  final String text;
  final int startCharOffset;
  final int endCharOffset;
}

class ReaderParagraphParser {
  static const int _softSplitChars = AppConstants.ttsSoftMaxChars;
  static const int _hardSplitChars = AppConstants.ttsHardMaxChars;

  static List<ReaderParagraph> parse(String text) {
    final String normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (normalized.isEmpty) {
      return const [];
    }

    final List<String> blocks = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((block) => block.trimRight())
        .where((block) => block.trim().isNotEmpty)
        .expand(_splitLongBlock)
        .toList();

    int startOffset = 0;
    return [
      for (int i = 0; i < blocks.length; i++)
        () {
          final String block = blocks[i];
          final ReaderParagraph paragraph = ReaderParagraph(
            index: i,
            text: block,
            startCharOffset: startOffset,
            endCharOffset: startOffset + block.length,
          );
          startOffset = paragraph.endCharOffset + 2;
          return paragraph;
        }(),
    ];
  }

  static List<String> _splitLongBlock(String block) {
    if (block.length <= _hardSplitChars) {
      return [block];
    }

    final List<String> segments = [];
    final StringBuffer current = StringBuffer();

    for (int i = 0; i < block.length; i++) {
      final String char = block[i];
      current.write(char);
      final bool isSoftBoundary = '。！？；!?;…\n'.contains(char);

      if (current.length >= _softSplitChars && isSoftBoundary) {
        segments.add(current.toString().trim());
        current.clear();
        continue;
      }

      if (current.length >= _hardSplitChars) {
        segments.add(current.toString().trim());
        current.clear();
      }
    }

    if (current.isNotEmpty) {
      segments.add(current.toString().trim());
    }

    return segments.where((segment) => segment.isNotEmpty).toList();
  }
}
