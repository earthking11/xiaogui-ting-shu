import 'package:flutter_test/flutter_test.dart';
import 'package:novel_tts_reader/models/audiobook_sentence.dart';
import 'package:novel_tts_reader/models/reader_paragraph.dart';

void main() {
  group('AudiobookSentenceParser', () {
    test('splits paragraph text into sentence cues', () {
      const paragraph = ReaderParagraph(
        index: 0,
        text: '第一句。第二句！第三句',
        startCharOffset: 10,
        endCharOffset: 20,
      );

      final cues = AudiobookSentenceParser.parse([paragraph]);

      expect(cues.map((cue) => cue.text), ['第一句。', '第二句！', '第三句']);
      expect(cues[1].paragraphIndex, 0);
      expect(cues[1].startOffsetInParagraph, 4);
      expect(cues[1].globalStartCharOffset, 14);
    });

    test('hard splits very long unpunctuated text', () {
      final paragraph = ReaderParagraph(
        index: 0,
        text: '甲' * 620,
        startCharOffset: 0,
        endCharOffset: 620,
      );

      final cues = AudiobookSentenceParser.parse([paragraph]);

      expect(cues.map((cue) => cue.text.length), [260, 260, 100]);
    });
  });
}
