import 'reader_paragraph.dart';

class AudiobookSentenceCue {
  const AudiobookSentenceCue({
    required this.index,
    required this.paragraphIndex,
    required this.sentenceIndexInParagraph,
    required this.text,
    required this.startOffsetInParagraph,
    required this.endOffsetInParagraph,
    required this.globalStartCharOffset,
    required this.globalEndCharOffset,
  });

  final int index;
  final int paragraphIndex;
  final int sentenceIndexInParagraph;
  final String text;
  final int startOffsetInParagraph;
  final int endOffsetInParagraph;
  final int globalStartCharOffset;
  final int globalEndCharOffset;
}

class AudiobookSentenceParser {
  static const int _hardMaxChars = 260;
  static const String _sentenceEndings = '。！？!?；;…';
  static const String _trailingQuotes = '”」』’》）)]';

  static List<AudiobookSentenceCue> parse(List<ReaderParagraph> paragraphs) {
    final cues = <AudiobookSentenceCue>[];
    int globalIndex = 0;

    for (final ReaderParagraph paragraph in paragraphs) {
      final List<_SentenceRange> ranges = _splitParagraph(paragraph.text);
      for (int i = 0; i < ranges.length; i++) {
        final _SentenceRange range = ranges[i];
        cues.add(
          AudiobookSentenceCue(
            index: globalIndex,
            paragraphIndex: paragraph.index,
            sentenceIndexInParagraph: i,
            text: paragraph.text.substring(range.start, range.end),
            startOffsetInParagraph: range.start,
            endOffsetInParagraph: range.end,
            globalStartCharOffset: paragraph.startCharOffset + range.start,
            globalEndCharOffset: paragraph.startCharOffset + range.end,
          ),
        );
        globalIndex += 1;
      }
    }

    return cues;
  }

  static List<_SentenceRange> _splitParagraph(String text) {
    final ranges = <_SentenceRange>[];
    int start = 0;
    int i = 0;

    while (i < text.length) {
      final String char = text[i];
      final bool isSentenceEnding = _sentenceEndings.contains(char);
      final bool isHardLimit = i - start + 1 >= _hardMaxChars;

      if (isSentenceEnding || isHardLimit) {
        int end = i + 1;
        while (end < text.length && _trailingQuotes.contains(text[end])) {
          end += 1;
        }
        _addTrimmedRange(ranges, text, start, end);
        start = end;
        i = end;
        continue;
      }

      i += 1;
    }

    _addTrimmedRange(ranges, text, start, text.length);
    return ranges;
  }

  static void _addTrimmedRange(
    List<_SentenceRange> ranges,
    String text,
    int rawStart,
    int rawEnd,
  ) {
    int start = rawStart;
    int end = rawEnd;
    while (start < end && text[start].trim().isEmpty) {
      start += 1;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end -= 1;
    }
    if (start < end) {
      ranges.add(_SentenceRange(start, end));
    }
  }
}

class _SentenceRange {
  const _SentenceRange(this.start, this.end);

  final int start;
  final int end;
}
