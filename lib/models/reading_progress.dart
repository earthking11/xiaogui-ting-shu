class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.paragraphIndex,
    required this.alignment,
    required this.approxCharOffset,
    required this.percent,
    required this.updatedAt,
  });

  final String bookId;
  final int paragraphIndex;
  final double alignment;
  final int approxCharOffset;
  final double percent;
  final DateTime updatedAt;

  ReadingProgress copyWith({
    String? bookId,
    int? paragraphIndex,
    double? alignment,
    int? approxCharOffset,
    double? percent,
    DateTime? updatedAt,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      alignment: alignment ?? this.alignment,
      approxCharOffset: approxCharOffset ?? this.approxCharOffset,
      percent: percent ?? this.percent,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'paragraphIndex': paragraphIndex,
      'alignment': alignment,
      'approxCharOffset': approxCharOffset,
      'percent': percent,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      bookId: json['bookId'] as String? ?? '',
      paragraphIndex: json['paragraphIndex'] as int? ?? 0,
      alignment: (json['alignment'] as num?)?.toDouble() ?? 0,
      approxCharOffset: json['approxCharOffset'] as int? ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
