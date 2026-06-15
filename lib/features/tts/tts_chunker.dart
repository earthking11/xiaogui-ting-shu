import '../../core/constants.dart';
import '../../models/reader_paragraph.dart';
import '../../models/tts_chunk.dart';

class TtsChunker {
  const TtsChunker({
    this.targetChars = AppConstants.ttsTargetChars,
    this.minChars = AppConstants.ttsMinChars,
    this.softMaxChars = AppConstants.ttsSoftMaxChars,
    this.hardMaxChars = AppConstants.ttsHardMaxChars,
  });

  final int targetChars;
  final int minChars;
  final int softMaxChars;
  final int hardMaxChars;

  TtsChunk? buildChunk({
    required String bookId,
    required List<ReaderParagraph> paragraphs,
    required int startParagraphIndex,
  }) {
    if (paragraphs.isEmpty || startParagraphIndex >= paragraphs.length) {
      return null;
    }

    final int startIndex = startParagraphIndex.clamp(0, paragraphs.length - 1);
    final StringBuffer buffer = StringBuffer();
    int currentIndex = startIndex;
    int endIndex = startIndex;

    while (currentIndex < paragraphs.length) {
      final ReaderParagraph paragraph = paragraphs[currentIndex];
      final int separatorLength = buffer.isEmpty ? 0 : 2;
      final int projectedLength =
          buffer.length + separatorLength + paragraph.text.length;

      final bool mustTake =
          currentIndex == startIndex || buffer.length < minChars;
      final bool canTake = projectedLength <= softMaxChars;

      if (!mustTake && !canTake) {
        break;
      }

      if (projectedLength > hardMaxChars && buffer.isNotEmpty) {
        break;
      }

      if (separatorLength > 0) {
        buffer.write('\n\n');
      }
      buffer.write(paragraph.text);
      endIndex = currentIndex;
      currentIndex += 1;

      if (buffer.length >= targetChars) {
        final bool nextWouldOverflow = currentIndex >= paragraphs.length
            ? true
            : buffer.length + 2 + paragraphs[currentIndex].text.length >
                  softMaxChars;
        if (nextWouldOverflow) {
          break;
        }
      }
    }

    final ReaderParagraph startParagraph = paragraphs[startIndex];
    final ReaderParagraph endParagraph = paragraphs[endIndex];
    final String chunkText = buffer.toString().trim();
    if (chunkText.isEmpty) {
      return null;
    }

    return TtsChunk(
      bookId: bookId,
      startParagraphIndex: startIndex,
      endParagraphIndexInclusive: endIndex,
      startCharOffset: startParagraph.startCharOffset,
      endCharOffsetExclusive: endParagraph.endCharOffset,
      text: chunkText,
    );
  }
}
