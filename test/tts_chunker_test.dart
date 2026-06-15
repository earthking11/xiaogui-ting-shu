import 'package:flutter_test/flutter_test.dart';
import 'package:novel_tts_reader/core/constants.dart';
import 'package:novel_tts_reader/features/tts/tts_chunker.dart';
import 'package:novel_tts_reader/models/reader_paragraph.dart';

void main() {
  group('TtsChunker', () {
    const TtsChunker chunker = TtsChunker();

    test('returns the whole remainder when content is smaller than target', () {
      final List<ReaderParagraph> paragraphs = _paragraphsFrom([
        '第一段很短。',
        '第二段也很短。',
      ]);

      final chunk = chunker.buildChunk(
        bookId: 'book-1',
        paragraphs: paragraphs,
        startParagraphIndex: 0,
      );

      expect(chunk, isNotNull);
      expect(chunk!.endParagraphIndexInclusive, 1);
      expect(chunk.text, contains('第一段很短。'));
      expect(chunk.text, contains('第二段也很短。'));
    });

    test('cuts at paragraph boundaries when enough text is accumulated', () {
      final List<ReaderParagraph> paragraphs = _paragraphsFrom([
        '甲' * 1000,
        '乙' * 1000,
        '丙' * 900,
        '丁' * 600,
      ]);

      final chunk = chunker.buildChunk(
        bookId: 'book-2',
        paragraphs: paragraphs,
        startParagraphIndex: 0,
      );

      expect(chunk, isNotNull);
      expect(chunk!.endParagraphIndexInclusive, 0);
      expect(chunk.charCount, lessThanOrEqualTo(1100));
    });

    test('works with long text that has already been split by sentence', () {
      final String longBlock = List.filled(420, '这是一个句子。').join();
      final List<ReaderParagraph> paragraphs = ReaderParagraphParser.parse(
        longBlock,
      );

      expect(paragraphs.length, greaterThan(1));

      final chunk = chunker.buildChunk(
        bookId: 'book-3',
        paragraphs: paragraphs,
        startParagraphIndex: 0,
      );

      expect(chunk, isNotNull);
      expect(chunk!.charCount, lessThanOrEqualTo(1100));
    });

    test('keeps unpunctuated parser segments within the hard TTS limit', () {
      final List<ReaderParagraph> paragraphs = ReaderParagraphParser.parse(
        '甲' * 2000,
      );

      expect(paragraphs.map((paragraph) => paragraph.text.length), [
        AppConstants.ttsHardMaxChars,
        900,
      ]);

      final chunk = chunker.buildChunk(
        bookId: 'book-4',
        paragraphs: paragraphs,
        startParagraphIndex: 0,
      );

      expect(chunk, isNotNull);
      expect(chunk!.charCount, lessThanOrEqualTo(AppConstants.ttsHardMaxChars));
    });

    test('does not create a chunk for empty paragraph text', () {
      final chunk = chunker.buildChunk(
        bookId: 'book-empty',
        paragraphs: _paragraphsFrom(['   ']),
        startParagraphIndex: 0,
      );

      expect(chunk, isNull);
    });
  });
}

List<ReaderParagraph> _paragraphsFrom(List<String> raw) {
  int offset = 0;
  return [
    for (int index = 0; index < raw.length; index++)
      () {
        final String text = raw[index];
        final ReaderParagraph paragraph = ReaderParagraph(
          index: index,
          text: text,
          startCharOffset: offset,
          endCharOffset: offset + text.length,
        );
        offset = paragraph.endCharOffset + 2;
        return paragraph;
      }(),
  ];
}
