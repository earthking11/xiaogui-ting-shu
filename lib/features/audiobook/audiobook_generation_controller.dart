// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/audiobook_manifest.dart';
import '../../services/audiobook_repository.dart';
import '../../services/mimo_tts_api_client.dart';
import '../../services/secure_key_store.dart';

class AudiobookGenerationController extends ChangeNotifier {
  AudiobookGenerationController({
    required AudiobookRepository repository,
    required MimoTtsApiClient apiClient,
    required SecureKeyStore keyStore,
    required AudiobookManifest manifest,
  }) : _repository = repository,
       _apiClient = apiClient,
       _keyStore = keyStore,
       _manifest = manifest;

  final AudiobookRepository _repository;
  final MimoTtsApiClient _apiClient;
  final SecureKeyStore _keyStore;
  static const int maxConcurrentRequests = 2;

  AudiobookManifest _manifest;
  AudiobookManifest get manifest => _manifest;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  bool _pauseRequested = false;
  bool get pauseRequested => _pauseRequested;

  String? _runtimeMessage;
  String? get runtimeMessage => _runtimeMessage ?? _manifest.statusMessage;

  Future<void>? _currentRun;

  Future<void> replaceManifest(AudiobookManifest manifest) async {
    if (_isGenerating) {
      await pause();
      await _currentRun;
    }
    _manifest = manifest;
    _runtimeMessage = null;
    notifyListeners();
  }

  Future<void> start({bool retryFailed = false}) async {
    if (_isGenerating) {
      await _currentRun;
      return;
    }

    final Future<void> run = _runGeneration(retryFailed: retryFailed);
    _currentRun = run;
    try {
      await run;
    } finally {
      if (identical(_currentRun, run)) {
        _currentRun = null;
      }
    }
  }

  Future<void> _runGeneration({required bool retryFailed}) async {
    final String? apiKey = (await _keyStore.readApiKey())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      _runtimeMessage = '请先填写 MiMo API Key。';
      notifyListeners();
      return;
    }

    _isGenerating = true;
    _pauseRequested = false;
    int consecutiveFailureBatches = 0;

    _prepareClipsForRun(retryFailed: retryFailed);

    await _updateManifest(
      _manifest.copyWith(
        status: AudiobookJobStatus.generating,
        updatedAt: DateTime.now(),
        statusMessage: '开始生成整本听书音频。',
      ),
    );

    try {
      while (!_pauseRequested) {
        final List<int> indexes = _nextPendingIndexes(maxConcurrentRequests);
        if (indexes.isEmpty) {
          await _finishGeneration();
          return;
        }

        await _markBatchGenerating(indexes);
        final List<_ClipGenerationResult> results = await Future.wait(
          indexes.map((index) => _generateClip(apiKey, index)),
        );

        final _ClipGenerationResult? fatal = _firstFatalResult(results);
        if (fatal != null) {
          await _pauseWithError(fatal.message);
          return;
        }

        final bool allFailed = results.every((result) => !result.success);
        consecutiveFailureBatches = allFailed
            ? consecutiveFailureBatches + 1
            : 0;
        if (consecutiveFailureBatches >= 3) {
          await _pauseWithError('连续生成失败，已暂停。请检查网络后继续。');
          return;
        }
      }

      await _pauseNow('已暂停，可稍后继续生成。');
    } finally {
      _isGenerating = false;
      _pauseRequested = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (!_isGenerating) {
      return;
    }
    _pauseRequested = true;
    _runtimeMessage = '正在暂停，当前句完成后停止。';
    notifyListeners();
  }

  Future<void> deletePlan() async {
    if (_isGenerating) {
      await pause();
      await _currentRun;
    }
    await _repository.deletePlan(_manifest);
    final DateTime now = DateTime.now();
    _manifest = _manifest.copyWith(
      status: AudiobookJobStatus.pending,
      clips: [
        for (final AudiobookClip clip in _manifest.clips)
          clip.copyWith(
            status: AudiobookClipStatus.pending,
            clearAudioPath: true,
            clearError: true,
            updatedAt: now,
          ),
      ],
      updatedAt: now,
      statusMessage: '已删除整本听书音频。',
    );
    await _repository.saveManifest(_manifest);
    _runtimeMessage = '已删除整本听书音频。';
    notifyListeners();
  }

  int firstPlayableIndex() {
    return _manifest.clips.indexWhere(
      (clip) => clip.status == AudiobookClipStatus.done,
    );
  }

  int nextPlayableIndexAfter(int index) {
    for (int i = index + 1; i < _manifest.clips.length; i++) {
      if (_manifest.clips[i].status == AudiobookClipStatus.done) {
        return i;
      }
    }
    return -1;
  }

  int previousPlayableIndexBefore(int index) {
    for (int i = index - 1; i >= 0; i--) {
      if (_manifest.clips[i].status == AudiobookClipStatus.done) {
        return i;
      }
    }
    return -1;
  }

  List<int> _nextPendingIndexes(int limit) {
    final indexes = <int>[];
    for (int i = 0; i < _manifest.clips.length; i++) {
      if (_manifest.clips[i].status == AudiobookClipStatus.pending) {
        indexes.add(i);
        if (indexes.length >= limit) {
          break;
        }
      }
    }
    return indexes;
  }

  Future<void> _markBatchGenerating(List<int> indexes) async {
    final DateTime now = DateTime.now();
    final List<AudiobookClip> clips = [..._manifest.clips];
    for (final int index in indexes) {
      final AudiobookClip clip = clips[index];
      clips[index] = clip.copyWith(
        status: AudiobookClipStatus.generating,
        clearError: true,
        updatedAt: now,
      );
    }

    final String rangeLabel = indexes.length == 1
        ? '第 ${indexes.first + 1}'
        : '第 ${indexes.first + 1}-${indexes.last + 1}';
    await _updateManifest(
      _manifest.copyWith(
        status: AudiobookJobStatus.generating,
        clips: clips,
        updatedAt: now,
        statusMessage:
            '正在并发生成$rangeLabel / ${_manifest.totalSentenceCount} 句...',
      ),
    );
  }

  Future<_ClipGenerationResult> _generateClip(String apiKey, int index) async {
    final AudiobookClip clip = _manifest.clips[index];
    if (clip.status != AudiobookClipStatus.generating) {
      return const _ClipGenerationResult(success: false, message: '任务已更新');
    }

    try {
      final bytes = await _synthesizeWithRetry(apiKey, clip.text);
      final String path = await _repository.saveClipAudio(
        manifest: _manifest,
        sentenceIndex: clip.sentenceIndex,
        bytes: bytes,
      );
      await _updateClip(
        index,
        clip.copyWith(
          status: AudiobookClipStatus.done,
          audioPath: path,
          clearError: true,
          updatedAt: DateTime.now(),
        ),
        status: AudiobookJobStatus.generating,
        message:
            '已生成 ${_manifest.generatedSentenceCount + 1} / ${_manifest.totalSentenceCount} 句。',
      );
      return const _ClipGenerationResult(success: true, message: 'ok');
    } on MimoTtsException catch (error) {
      await _updateClip(
        index,
        clip.copyWith(
          status: AudiobookClipStatus.failed,
          errorMessage: error.message,
          updatedAt: DateTime.now(),
        ),
        status: _isFatal(error)
            ? AudiobookJobStatus.error
            : AudiobookJobStatus.generating,
        message: error.message,
      );
      return _ClipGenerationResult(
        success: false,
        fatal: _isFatal(error),
        message: error.message,
      );
    } on Exception {
      const String message = '生成失败，请稍后重试。';
      await _updateClip(
        index,
        clip.copyWith(
          status: AudiobookClipStatus.failed,
          errorMessage: message,
          updatedAt: DateTime.now(),
        ),
        status: AudiobookJobStatus.generating,
        message: message,
      );
      return const _ClipGenerationResult(success: false, message: message);
    }
  }

  Future<Uint8List> _synthesizeWithRetry(String apiKey, String text) async {
    int attempt = 0;
    while (true) {
      try {
        return await _apiClient.synthesize(
          apiKey: apiKey,
          text: text,
          voiceId: _manifest.voiceId,
          speedPrompt: _manifest.speedPrompt,
          audioFormat: _manifest.audioFormat,
        );
      } on MimoTtsException catch (error) {
        if (!error.isRetryable || attempt >= 2 || _pauseRequested) {
          rethrow;
        }
        final Duration delay = attempt == 0
            ? const Duration(milliseconds: 1500)
            : const Duration(seconds: 4);
        attempt += 1;
        await Future.delayed(delay);
      }
    }
  }

  _ClipGenerationResult? _firstFatalResult(
    List<_ClipGenerationResult> results,
  ) {
    for (final _ClipGenerationResult result in results) {
      if (result.fatal) {
        return result;
      }
    }
    return null;
  }

  Future<void> _finishGeneration() async {
    final int unfinishedCount = _manifest.clips
        .where(
          (clip) =>
              clip.status == AudiobookClipStatus.pending ||
              clip.status == AudiobookClipStatus.generating,
        )
        .length;
    if (unfinishedCount > 0) {
      await _pauseNow('还有 $unfinishedCount 句未完成，可继续生成。');
      return;
    }

    final bool completed =
        _manifest.generatedSentenceCount == _manifest.totalSentenceCount;
    final AudiobookJobStatus status = completed
        ? AudiobookJobStatus.completed
        : AudiobookJobStatus.error;
    final String message = completed
        ? '整本听书已生成完成。'
        : '有 ${_manifest.failedSentenceCount} 句失败，可单独重试。';
    await _updateManifest(
      _manifest.copyWith(
        status: status,
        updatedAt: DateTime.now(),
        statusMessage: message,
      ),
    );
  }

  Future<void> _pauseWithError(String message) async {
    await _updateManifest(
      _manifest.copyWith(
        status: AudiobookJobStatus.error,
        updatedAt: DateTime.now(),
        statusMessage: message,
      ),
    );
  }

  Future<void> _pauseNow(String message) async {
    final List<AudiobookClip> clips = [
      for (final AudiobookClip clip in _manifest.clips)
        clip.status == AudiobookClipStatus.generating
            ? clip.copyWith(
                status: AudiobookClipStatus.pending,
                updatedAt: DateTime.now(),
              )
            : clip,
    ];
    await _updateManifest(
      _manifest.copyWith(
        status: AudiobookJobStatus.paused,
        clips: clips,
        updatedAt: DateTime.now(),
        statusMessage: message,
      ),
    );
  }

  void _prepareClipsForRun({required bool retryFailed}) {
    final DateTime now = DateTime.now();
    _manifest = _manifest.copyWith(
      clips: [
        for (final AudiobookClip clip in _manifest.clips)
          clip.status == AudiobookClipStatus.generating ||
                  (retryFailed && clip.status == AudiobookClipStatus.failed)
              ? clip.copyWith(
                  status: AudiobookClipStatus.pending,
                  clearAudioPath: true,
                  clearError: true,
                  updatedAt: now,
                )
              : clip,
      ],
      updatedAt: now,
      clearStatusMessage: true,
    );
  }

  Future<void> _updateClip(
    int index,
    AudiobookClip clip, {
    required AudiobookJobStatus status,
    required String message,
  }) async {
    final List<AudiobookClip> clips = [..._manifest.clips];
    clips[index] = clip;
    await _updateManifest(
      _manifest.copyWith(
        status: status,
        clips: clips,
        updatedAt: DateTime.now(),
        statusMessage: message,
      ),
    );
  }

  Future<void> _updateManifest(AudiobookManifest manifest) async {
    _manifest = manifest;
    _runtimeMessage = manifest.statusMessage;
    await _repository.saveManifest(manifest);
    notifyListeners();
  }

  bool _isFatal(MimoTtsException error) {
    return error.statusCode == 401 ||
        error.statusCode == 402 ||
        error.statusCode == 403;
  }
}

class _ClipGenerationResult {
  const _ClipGenerationResult({
    required this.success,
    required this.message,
    this.fatal = false,
  });

  final bool success;
  final bool fatal;
  final String message;
}
