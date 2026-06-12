import 'package:flutter_test/flutter_test.dart';
import 'package:novel_tts_reader/models/bookmark.dart';
import 'package:novel_tts_reader/models/reader_settings.dart';
import 'package:novel_tts_reader/models/tts_settings.dart';
import 'package:novel_tts_reader/services/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and loads reader settings', () async {
      final repository = SettingsRepository();
      const ReaderSettings settings = ReaderSettings(
        themeId: 'sage',
        fontSize: 22,
        lineHeight: 1.9,
      );

      await repository.saveReaderSettings(settings);
      final restored = await repository.loadReaderSettings();

      expect(restored.themeId, 'sage');
      expect(restored.fontSize, 22);
      expect(restored.lineHeight, 1.9);
    });

    test('saves and loads tts settings', () async {
      final repository = SettingsRepository();
      const TtsSettings settings = TtsSettings(
        voiceId: '苏打',
        voiceName: '苏打',
        playbackSpeed: 1.15,
        speedPrompt: '语速稍快，但咬字清晰。',
      );

      await repository.saveTtsSettings(settings);
      final restored = await repository.loadTtsSettings();

      expect(restored.voiceId, '苏打');
      expect(restored.playbackSpeed, 1.15);
      expect(restored.speedPrompt, '语速稍快，但咬字清晰。');
    });

    test('saves and loads bookmark json', () async {
      final repository = SettingsRepository();
      final bookmarks = [
        Bookmark(
          id: 'bookmark-1',
          bookId: 'book-1',
          paragraphIndex: 12,
          approxCharOffset: 456,
          percent: 21.5,
          previewText: '这一段文字很重要，先在这里停一下。',
          createdAt: DateTime(2026, 6, 10, 12, 0),
        ),
      ];

      await repository.saveBookmarks('book-1', bookmarks);
      final restored = await repository.loadBookmarks('book-1');

      expect(restored, hasLength(1));
      expect(restored.first.id, 'bookmark-1');
      expect(restored.first.paragraphIndex, 12);
      expect(restored.first.previewText, contains('这一段文字'));
    });
  });
}
