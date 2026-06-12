import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/tts_chunk.dart';

class TtsCacheStore {
  Future<String> saveChunkAudio({
    required String bookId,
    required TtsChunk chunk,
    required String voiceId,
    required double speed,
    required Uint8List bytes,
  }) async {
    final Directory directory = await _cacheDirectory();
    final File file = File(
      '${directory.path}/${bookId}_${chunk.startParagraphIndex}_${chunk.endParagraphIndexInclusive}_${_safe(voiceId)}_${(speed * 100).round()}.wav',
    );
    await file.writeAsBytes(bytes, flush: true);
    await trimCache();
    return file.path;
  }

  Future<void> cleanupStale() async {
    final Directory directory = await _cacheDirectory();
    final DateTime expiry = DateTime.now().subtract(const Duration(hours: 24));
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final FileStat stat = await entity.stat();
      if (stat.modified.isBefore(expiry)) {
        await entity.delete();
      }
    }
  }

  Future<void> trimCache({int maxBytes = 100 * 1024 * 1024}) async {
    final Directory directory = await _cacheDirectory();
    final List<File> files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    int totalBytes = files.fold<int>(0, (sum, file) => sum + file.lengthSync());

    for (final File file in files) {
      if (totalBytes <= maxBytes) {
        break;
      }
      totalBytes -= file.lengthSync();
      await file.delete();
    }
  }

  Future<void> deletePaths(Iterable<String?> paths) async {
    for (final String? path in paths) {
      if (path == null || path.isEmpty) {
        continue;
      }
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<Directory> _cacheDirectory() async {
    final Directory temporary = await getTemporaryDirectory();
    final Directory cache = Directory('${temporary.path}/tts_cache');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache;
  }

  String _safe(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5]+'), '_');
  }
}
