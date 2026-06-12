// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/bookmark.dart';
import '../models/reader_settings.dart';
import '../models/reading_progress.dart';
import '../models/tts_settings.dart';

class SettingsRepository {
  SettingsRepository({SharedPreferences? sharedPreferences})
    : _sharedPreferences = sharedPreferences;

  SharedPreferences? _sharedPreferences;

  Future<SharedPreferences> get _prefs async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  Future<ReaderSettings> loadReaderSettings() async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(PreferenceKeys.readerSettings);
    if (raw == null || raw.isEmpty) {
      return ReaderSettings.defaults();
    }

    return ReaderSettings.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> saveReaderSettings(ReaderSettings settings) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(
      PreferenceKeys.readerSettings,
      jsonEncode(settings.toJson()),
    );
  }

  Future<TtsSettings> loadTtsSettings() async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(PreferenceKeys.ttsSettings);
    if (raw == null || raw.isEmpty) {
      return TtsSettings.defaults();
    }

    return TtsSettings.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> saveTtsSettings(TtsSettings settings) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(
      PreferenceKeys.ttsSettings,
      jsonEncode(settings.toJson()),
    );
  }

  Future<ReadingProgress?> loadReadingProgress(String bookId) async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.readingProgressMap,
    );
    final dynamic raw = map[bookId];
    if (raw is! Map) {
      return null;
    }
    return ReadingProgress.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<Map<String, ReadingProgress>> loadAllProgress() async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.readingProgressMap,
    );
    return map.map(
      (key, value) => MapEntry(
        key,
        ReadingProgress.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<void> saveReadingProgress(ReadingProgress progress) async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.readingProgressMap,
    );
    map[progress.bookId] = progress.toJson();
    await _saveJsonMap(PreferenceKeys.readingProgressMap, map);
  }

  Future<List<Bookmark>> loadBookmarks(String bookId) async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.bookmarksMap,
    );
    final dynamic raw = map[bookId];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => Bookmark.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> saveBookmarks(String bookId, List<Bookmark> bookmarks) async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.bookmarksMap,
    );
    map[bookId] = bookmarks.map((bookmark) => bookmark.toJson()).toList();
    await _saveJsonMap(PreferenceKeys.bookmarksMap, map);
  }

  Future<String?> loadLastBookId() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getString(PreferenceKeys.lastBookId);
  }

  Future<void> saveLastBookId(String? bookId) async {
    final SharedPreferences prefs = await _prefs;
    if (bookId == null || bookId.isEmpty) {
      await prefs.remove(PreferenceKeys.lastBookId);
      return;
    }
    await prefs.setString(PreferenceKeys.lastBookId, bookId);
  }

  Future<Map<String, dynamic>> _loadJsonMap(String key) async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _saveJsonMap(String key, Map<String, dynamic> value) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(key, jsonEncode(value));
  }
}
