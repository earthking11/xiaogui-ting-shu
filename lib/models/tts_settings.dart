import '../core/constants.dart';

class TtsSettings {
  const TtsSettings({
    required this.voiceId,
    required this.voiceName,
    required this.playbackSpeed,
    required this.speedPrompt,
  });

  factory TtsSettings.defaults() {
    return const TtsSettings(
      voiceId: '冰糖',
      voiceName: '冰糖',
      playbackSpeed: 1.0,
      speedPrompt: '语速正常，段落停顿自然。',
    );
  }

  final String voiceId;
  final String voiceName;
  final double playbackSpeed;
  final String speedPrompt;

  TtsSettings copyWith({
    String? voiceId,
    String? voiceName,
    double? playbackSpeed,
    String? speedPrompt,
  }) {
    return TtsSettings(
      voiceId: voiceId ?? this.voiceId,
      voiceName: voiceName ?? this.voiceName,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      speedPrompt: speedPrompt ?? this.speedPrompt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'voiceId': voiceId,
      'voiceName': voiceName,
      'playbackSpeed': playbackSpeed,
      'speedPrompt': speedPrompt,
    };
  }

  factory TtsSettings.fromJson(Map<String, dynamic> json) {
    final double speed = (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0;
    final option = speedOptionFor(speed);
    return TtsSettings(
      voiceId: json['voiceId'] as String? ?? '冰糖',
      voiceName: json['voiceName'] as String? ?? '冰糖',
      playbackSpeed: speed,
      speedPrompt: json['speedPrompt'] as String? ?? option.prompt,
    );
  }
}
