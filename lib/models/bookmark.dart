class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.paragraphIndex,
    required this.approxCharOffset,
    required this.percent,
    required this.previewText,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final int paragraphIndex;
  final int approxCharOffset;
  final double percent;
  final String previewText;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'paragraphIndex': paragraphIndex,
      'approxCharOffset': approxCharOffset,
      'percent': percent,
      'previewText': previewText,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String? ?? '',
      bookId: json['bookId'] as String? ?? '',
      paragraphIndex: json['paragraphIndex'] as int? ?? 0,
      approxCharOffset: json['approxCharOffset'] as int? ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      previewText: json['previewText'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
