class TtsChunk {
  const TtsChunk({
    required this.bookId,
    required this.startParagraphIndex,
    required this.endParagraphIndexInclusive,
    required this.startCharOffset,
    required this.endCharOffsetExclusive,
    required this.text,
  });

  final String bookId;
  final int startParagraphIndex;
  final int endParagraphIndexInclusive;
  final int startCharOffset;
  final int endCharOffsetExclusive;
  final String text;

  int get charCount => text.length;
}
