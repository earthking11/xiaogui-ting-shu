class ReaderSettings {
  const ReaderSettings({
    required this.themeId,
    required this.fontSize,
    required this.lineHeight,
  });

  factory ReaderSettings.defaults() {
    return const ReaderSettings(
      themeId: 'paper',
      fontSize: 19,
      lineHeight: 1.75,
    );
  }

  final String themeId;
  final double fontSize;
  final double lineHeight;

  ReaderSettings copyWith({
    String? themeId,
    double? fontSize,
    double? lineHeight,
  }) {
    return ReaderSettings(
      themeId: themeId ?? this.themeId,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }

  Map<String, dynamic> toJson() {
    return {'themeId': themeId, 'fontSize': fontSize, 'lineHeight': lineHeight};
  }

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      themeId: json['themeId'] as String? ?? 'paper',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.75,
    );
  }
}
