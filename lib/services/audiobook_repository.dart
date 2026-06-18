import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/audiobook_manifest.dart';
import '../models/audiobook_sentence.dart';
import '../models/book.dart';
import '../models/tts_settings.dart';

class AudiobookRepository {
  static const String audioFormat = AppConstants.ttsAudioFormat;

  Future<AudiobookManifest> loadOrCreateManifest({
    required Book book,
    required String bookText,
    required TtsSettings settings,
    required List<AudiobookSentenceCue> sentences,
  }) async {
    final String textHash = hashText(bookText);
    final String planId = buildPlanId(
      textHash: textHash,
      voiceId: settings.voiceId,
      playbackSpeed: settings.playbackSpeed,
      speedPrompt: settings.speedPrompt,
    );
    final File file = await _manifestFile(book.id, planId);
    if (await file.exists()) {
      final AudiobookManifest? manifest = await _readManifest(file);
      if (manifest != null && manifest.clips.length == sentences.length) {
        await deleteOtherPlans(book.id, planId);
        return _normalizeInterrupted(manifest);
      }
    }

    final DateTime now = DateTime.now();
    final manifest = AudiobookManifest(
      bookId: book.id,
      planId: planId,
      textVersionHash: textHash,
      voiceId: settings.voiceId,
      voiceName: settings.voiceName,
      playbackSpeed: settings.playbackSpeed,
      speedPrompt: settings.speedPrompt,
      audioFormat: audioFormat,
      status: AudiobookJobStatus.pending,
      clips: [
        for (final AudiobookSentenceCue sentence in sentences)
          AudiobookClip(
            sentenceIndex: sentence.index,
            paragraphIndex: sentence.paragraphIndex,
            text: sentence.text,
            status: AudiobookClipStatus.pending,
            updatedAt: now,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await saveManifest(manifest);
    await deleteOtherPlans(book.id, planId);
    return manifest;
  }

  Future<void> saveManifest(AudiobookManifest manifest) async {
    final File file = await _manifestFile(manifest.bookId, manifest.planId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
  }

  Future<String> saveClipAudio({
    required AudiobookManifest manifest,
    required int sentenceIndex,
    required Uint8List bytes,
  }) async {
    final File file = await _clipFile(
      manifest.bookId,
      manifest.planId,
      sentenceIndex,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deletePlan(AudiobookManifest manifest) async {
    final Directory directory = await _planDirectory(
      manifest.bookId,
      manifest.planId,
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> deleteOtherPlans(String bookId, String keepPlanId) async {
    final Directory bookDirectory = await _bookDirectory(bookId);
    if (!await bookDirectory.exists()) {
      return;
    }

    final Directory keepDirectory = await _planDirectory(bookId, keepPlanId);
    await for (final FileSystemEntity entity in bookDirectory.list()) {
      if (entity is! Directory || entity.path == keepDirectory.path) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // Storage cleanup should not block opening the current audiobook plan.
      }
    }
  }

  Future<Map<String, AudiobookSummary>> loadSummaries(List<Book> books) async {
    final summaries = <String, AudiobookSummary>{};
    for (final Book book in books) {
      final AudiobookSummary? summary = await loadLatestSummary(book.id);
      if (summary != null) {
        summaries[book.id] = summary;
      }
    }
    return summaries;
  }

  Future<AudiobookSummary?> loadLatestSummary(String bookId) async {
    final Directory bookDirectory = await _bookDirectory(bookId);
    if (!await bookDirectory.exists()) {
      return null;
    }

    AudiobookManifest? latest;
    await for (final FileSystemEntity entity in bookDirectory.list()) {
      if (entity is! Directory) {
        continue;
      }
      final File manifestFile = File('${entity.path}/manifest.json');
      final AudiobookManifest? manifest = await _readManifest(manifestFile);
      if (manifest == null) {
        continue;
      }
      if (latest == null || manifest.updatedAt.isAfter(latest.updatedAt)) {
        latest = manifest;
      }
    }

    if (latest == null) {
      return null;
    }

    return AudiobookSummary(
      bookId: latest.bookId,
      status: latest.status,
      generatedSentenceCount: latest.generatedSentenceCount,
      totalSentenceCount: latest.totalSentenceCount,
      failedSentenceCount: latest.failedSentenceCount,
      audioBytes: await _audioBytes(latest),
      voiceName: latest.voiceName,
      playbackSpeed: latest.playbackSpeed,
      updatedAt: latest.updatedAt,
    );
  }

  String hashText(String text) {
    return _fnv1a(text).toRadixString(16);
  }

  String buildPlanId({
    required String textHash,
    required String voiceId,
    required double playbackSpeed,
    required String speedPrompt,
  }) {
    final int promptHash = _fnv1a(speedPrompt);
    final String safeVoice = _safe(voiceId);
    final int speed = (playbackSpeed * 100).round();
    return '${textHash}_${safeVoice}_${speed}_${promptHash.toRadixString(16)}';
  }

  AudiobookManifest _normalizeInterrupted(AudiobookManifest manifest) {
    final List<AudiobookClip> clips = [
      for (final AudiobookClip clip in manifest.clips)
        clip.status == AudiobookClipStatus.generating
            ? clip.copyWith(
                status: AudiobookClipStatus.pending,
                clearError: true,
                updatedAt: DateTime.now(),
              )
            : clip,
    ];
    final AudiobookJobStatus status =
        manifest.status == AudiobookJobStatus.generating
        ? AudiobookJobStatus.paused
        : manifest.status;
    return manifest.copyWith(
      clips: clips,
      status: status,
      updatedAt: DateTime.now(),
      statusMessage: status == AudiobookJobStatus.paused
          ? '上次生成中断，可继续生成。'
          : null,
    );
  }

  Future<AudiobookManifest?> _readManifest(File file) async {
    if (!await file.exists()) {
      return null;
    }

    try {
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return AudiobookManifest.fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<int> _audioBytes(AudiobookManifest manifest) async {
    int total = 0;
    for (final AudiobookClip clip in manifest.clips) {
      final String? path = clip.audioPath;
      if (clip.status != AudiobookClipStatus.done ||
          path == null ||
          path.isEmpty) {
        continue;
      }
      final File file = File(path);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<File> _manifestFile(String bookId, String planId) async {
    final Directory directory = await _planDirectory(bookId, planId);
    return File('${directory.path}/manifest.json');
  }

  Future<File> _clipFile(
    String bookId,
    String planId,
    int sentenceIndex,
  ) async {
    final Directory directory = await _planDirectory(bookId, planId);
    final String padded = sentenceIndex.toString().padLeft(6, '0');
    return File('${directory.path}/sentence_$padded.$audioFormat');
  }

  Future<Directory> _planDirectory(String bookId, String planId) async {
    final Directory bookDirectory = await _bookDirectory(bookId);
    return Directory('${bookDirectory.path}/$planId');
  }

  Future<Directory> _bookDirectory(String bookId) async {
    final Directory root = await _audiobookRootDirectory();
    return Directory('${root.path}/${_safe(bookId)}');
  }

  Future<Directory> _audiobookRootDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory root = Directory('${documents.path}/audiobooks');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  int _fnv1a(String input) {
    int hash = 0x811c9dc5;
    for (final int unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  String _safe(String value) {
    final String safe = value.replaceAll(
      RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5_-]+'),
      '_',
    );
    return safe.isEmpty ? 'default' : safe;
  }
}
