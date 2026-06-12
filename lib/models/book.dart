class Book {
  const Book({
    required this.id,
    required this.title,
    required this.fileName,
    required this.storagePath,
    required this.textLength,
    required this.paragraphCount,
    required this.importedAt,
    required this.encoding,
    required this.sourceSizeBytes,
  });

  final String id;
  final String title;
  final String fileName;
  final String storagePath;
  final int textLength;
  final int paragraphCount;
  final DateTime importedAt;
  final String encoding;
  final int sourceSizeBytes;

  Book copyWith({
    String? id,
    String? title,
    String? fileName,
    String? storagePath,
    int? textLength,
    int? paragraphCount,
    DateTime? importedAt,
    String? encoding,
    int? sourceSizeBytes,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      storagePath: storagePath ?? this.storagePath,
      textLength: textLength ?? this.textLength,
      paragraphCount: paragraphCount ?? this.paragraphCount,
      importedAt: importedAt ?? this.importedAt,
      encoding: encoding ?? this.encoding,
      sourceSizeBytes: sourceSizeBytes ?? this.sourceSizeBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'fileName': fileName,
      'storagePath': storagePath,
      'textLength': textLength,
      'paragraphCount': paragraphCount,
      'importedAt': importedAt.toIso8601String(),
      'encoding': encoding,
      'sourceSizeBytes': sourceSizeBytes,
    };
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名书籍',
      fileName: json['fileName'] as String? ?? '',
      storagePath: json['storagePath'] as String? ?? '',
      textLength: json['textLength'] as int? ?? 0,
      paragraphCount: json['paragraphCount'] as int? ?? 0,
      importedAt:
          DateTime.tryParse(json['importedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      encoding: json['encoding'] as String? ?? 'utf-8',
      sourceSizeBytes: json['sourceSizeBytes'] as int? ?? 0,
    );
  }
}
