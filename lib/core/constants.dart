import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = '小龟听书';
  static const String methodChannelName = 'novel_tts_reader/native_file';
  static const String mimoBaseUrl =
      'https://api.xiaomimimo.com/v1/chat/completions';
  static const String mimoModel = 'mimo-v2.5-tts';
  static const String defaultNarrationPrompt =
      '请用适合长篇中文小说听书的自然旁白语气朗读。咬字清晰，情绪克制但有画面感，段落停顿自然。';
  static const int importSizeWarningBytes = 30 * 1024 * 1024;
  static const int ttsTargetChars = 700;
  static const int ttsMinChars = 420;
  static const int ttsSoftMaxChars = 900;
  static const int ttsHardMaxChars = 1100;
}

class PreferenceKeys {
  static const String readerSettings = 'reader_settings';
  static const String ttsSettings = 'tts_settings';
  static const String lastBookId = 'last_book_id';
  static const String readingProgressMap = 'reading_progress_map';
  static const String bookmarksMap = 'bookmarks_map';
}

@immutable
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
  });

  final String id;
  final String name;
  final String language;
  final String gender;
}

const List<VoiceOption> kVoiceOptions = [
  VoiceOption(id: '冰糖', name: '冰糖', language: '中文', gender: '女'),
  VoiceOption(id: '茉莉', name: '茉莉', language: '中文', gender: '女'),
  VoiceOption(id: '苏打', name: '苏打', language: '中文', gender: '男'),
  VoiceOption(id: '白桦', name: '白桦', language: '中文', gender: '男'),
  VoiceOption(
    id: 'mimo_default',
    name: 'MiMo 默认',
    language: '默认',
    gender: '默认',
  ),
  VoiceOption(id: 'Mia', name: 'Mia', language: '英文', gender: '女'),
  VoiceOption(id: 'Chloe', name: 'Chloe', language: '英文', gender: '女'),
  VoiceOption(id: 'Milo', name: 'Milo', language: '英文', gender: '男'),
  VoiceOption(id: 'Dean', name: 'Dean', language: '英文', gender: '男'),
];

VoiceOption voiceOptionFor(String voiceId) {
  return kVoiceOptions.firstWhere(
    (option) => option.id == voiceId,
    orElse: () => kVoiceOptions.first,
  );
}

@immutable
class PlaybackSpeedOption {
  const PlaybackSpeedOption({
    required this.label,
    required this.playbackSpeed,
    required this.prompt,
  });

  final String label;
  final double playbackSpeed;
  final String prompt;
}

const List<PlaybackSpeedOption> kPlaybackSpeedOptions = [
  PlaybackSpeedOption(
    label: '慢',
    playbackSpeed: 0.85,
    prompt: '语速偏慢，停顿稍多，但保持吐字清晰。',
  ),
  PlaybackSpeedOption(
    label: '稍慢',
    playbackSpeed: 0.95,
    prompt: '语速略慢，节奏舒缓，段落停顿自然。',
  ),
  PlaybackSpeedOption(label: '标准', playbackSpeed: 1.0, prompt: '语速正常，段落停顿自然。'),
  PlaybackSpeedOption(
    label: '稍快',
    playbackSpeed: 1.15,
    prompt: '语速稍快，但咬字清晰，语义停顿保留。',
  ),
  PlaybackSpeedOption(
    label: '快',
    playbackSpeed: 1.30,
    prompt: '语速较快，减少停顿，但不要含糊。',
  ),
];

PlaybackSpeedOption speedOptionFor(double speed) {
  return kPlaybackSpeedOptions.firstWhere(
    (option) => option.playbackSpeed == speed,
    orElse: () => kPlaybackSpeedOptions[2],
  );
}
