import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_tts_reader/features/library/library_page.dart';
import 'package:novel_tts_reader/services/audiobook_repository.dart';
import 'package:novel_tts_reader/services/settings_repository.dart';

void main() {
  testWidgets('shows empty library state', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final SettingsRepository repository = SettingsRepository();
    final AudiobookRepository audiobookRepository = AudiobookRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(
          books: const [],
          isImporting: false,
          settingsRepository: repository,
          audiobookRepository: audiobookRepository,
          onImportRequested: () async {},
          onBookSelected: (_) {},
          onAudiobookSelected: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('还没有导入小说'), findsOneWidget);
    expect(find.text('导入 TXT'), findsWidgets);
  });
}
