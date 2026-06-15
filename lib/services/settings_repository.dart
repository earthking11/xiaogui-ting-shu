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
    final Map<String, dynamic>? json = await _loadJsonObject(
      PreferenceKeys.readerSettings,
    );
    if (json == null) {
      return ReaderSettings.defaults();
    }

    try {
      return ReaderSettings.fromJson(json);
    } on Object {
      return ReaderSettings.defaults();
    }
  }

  Future<void> saveReaderSettings(ReaderSettings settings) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(
      PreferenceKeys.readerSettings,
      jsonEncode(settings.toJson()),
    );
  }

  Future<TtsSettings> loadTtsSettings() async {
    final Map<String, dynamic>? json = await _loadJsonObject(
      PreferenceKeys.ttsSettings,
    );
    if (json == null) {
      return TtsSettings.defaults();
    }

    try {
      return TtsSettings.fromJson(json);
    } on Object {
      return TtsSettings.defaults();
    }
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
    try {
      return ReadingProgress.fromJson(Map<String, dynamic>.from(raw));
    } on Object {
      return null;
    }
  }

  Future<Map<String, ReadingProgress>> loadAllProgress() async {
    final Map<String, dynamic> map = await _loadJsonMap(
      PreferenceKeys.readingProgressMap,
    );
    final result = <String, ReadingProgress>{};
    for (final entry in map.entries) {
      final dynamic raw = entry.value;
      if (raw is! Map) {
        continue;
      }
      try {
        result[entry.key] = ReadingProgress.fromJson(
          Map<String, dynamic>.from(raw),
        );
      } on Object {
        // Ignore one damaged entry instead of hiding all progress.
      }
    }
    return result;
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
    final bookmarks = <Bookmark>[];
    for (final item in raw.whereType<Map>()) {
      try {
        bookmarks.add(Bookmark.fromJson(Map<String, dynamic>.from(item)));
      } on Object {
        // Ignore one damaged bookmark instead of hiding the whole list.
      }
    }
    return bookmarks;
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
    return await _loadJsonObject(key) ?? {};
  }

  Future<Map<String, dynamic>?> _loadJsonObject(String key) async {
    final SharedPreferences prefs = await _prefs;
    final String? raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> _saveJsonMap(String key, Map<String, dynamic> value) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString(key, jsonEncode(value));
  }
}
