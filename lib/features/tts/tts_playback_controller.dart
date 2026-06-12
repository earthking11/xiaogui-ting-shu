// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/reader_paragraph.dart';
import '../../models/tts_chunk.dart';
import '../../models/tts_settings.dart';
import '../../services/mimo_tts_api_client.dart';
import '../../services/secure_key_store.dart';
import '../../services/tts_cache_store.dart';
import 'tts_chunker.dart';

enum TtsPlaybackState {
  idle,
  needsApiKey,
  preparing,
  playing,
  paused,
  bufferingNext,
  completed,
  error,
}

typedef TtsChunkStartCallback = Future<void> Function(TtsChunk chunk);

class TtsPlaybackController extends ChangeNotifier {
  TtsPlaybackController({
    required MimoTtsApiClient apiClient,
    required SecureKeyStore keyStore,
    required TtsCacheStore cacheStore,
    TtsChunker chunker = const TtsChunker(),
    AudioPlayer? player,
    TtsChunkStartCallback? onChunkStart,
  }) : _apiClient = apiClient,
       _keyStore = keyStore,
       _cacheStore = cacheStore,
       _chunker = chunker,
       _player = player ?? AudioPlayer(),
       _onChunkStart = onChunkStart {
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerStateChanged,
    );
    _positionSubscription = _player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
  }

  final MimoTtsApiClient _apiClient;
  final SecureKeyStore _keyStore;
  final TtsCacheStore _cacheStore;
  final TtsChunker _chunker;
  final AudioPlayer _player;
  final TtsChunkStartCallback? _onChunkStart;

  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;

  static const TtsChunker _quickStartChunker = TtsChunker(
    targetChars: 260,
    minChars: 160,
    softMaxChars: 360,
    hardMaxChars: 520,
  );

  TtsPlaybackState _state = TtsPlaybackState.idle;
  TtsPlaybackState get state => _state;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  TtsChunk? _currentChunk;
  TtsChunk? get currentChunk => _currentChunk;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  double get playbackProgress {
    if (_duration.inMilliseconds <= 0) {
      return 0;
    }
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  }

  String get currentPreview {
    final String text = _currentChunk?.text.trim() ?? '';
    if (text.isEmpty) {
      return '正在生成快速起播段';
    }
    final String compact = text.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length <= 42 ? compact : '${compact.substring(0, 42)}...';
  }

  String get nextStatusLabel {
    final TtsChunk? current = _currentChunk;
    if (_state == TtsPlaybackState.preparing) {
      return '下一段稍后生成';
    }
    if (current == null || _paragraphs.isEmpty) {
      return '等待开始';
    }
    final int nextStart = current.endParagraphIndexInclusive + 1;
    if (nextStart >= _paragraphs.length) {
      return '已到最后一段';
    }
    if (_nextChunk?.startParagraphIndex == nextStart &&
        _nextAudioPath != null) {
      return '下一段已生成';
    }
    if (_nextPreparation != null || _state == TtsPlaybackState.bufferingNext) {
      return '下一段生成中...';
    }
    return '下一段等待生成';
  }

  String? _currentBookId;
  List<ReaderParagraph> _paragraphs = const [];
  TtsSettings _settings = TtsSettings.defaults();

  String? _currentAudioPath;
  TtsChunk? _nextChunk;
  String? _nextAudioPath;
  Future<void>? _nextPreparation;
  bool _handlingCompletion = false;
  bool _disposed = false;
  int _sessionId = 0;
  int _settingsRevision = 0;

  String get primaryActionLabel {
    switch (_state) {
      case TtsPlaybackState.idle:
        return '我想听书';
      case TtsPlaybackState.needsApiKey:
        return '填写 Key';
      case TtsPlaybackState.preparing:
        return '准备中...';
      case TtsPlaybackState.playing:
        return '暂停';
      case TtsPlaybackState.paused:
        return '继续';
      case TtsPlaybackState.bufferingNext:
        return '准备下一段...';
      case TtsPlaybackState.completed:
        return '再听一遍';
      case TtsPlaybackState.error:
        return '重试';
    }
  }

  Future<void> startFrom({
    required String bookId,
    required List<ReaderParagraph> paragraphs,
    required int startParagraphIndex,
    required TtsSettings settings,
  }) async {
    final String? apiKey = (await _keyStore.readApiKey())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      _state = TtsPlaybackState.needsApiKey;
      _statusMessage = '请先填写 MiMo API Key';
      notifyListeners();
      return;
    }

    await stop(resetMessage: false);
    _sessionId += 1;
    _settingsRevision += 1;
    final int sessionId = _sessionId;
    final int revision = _settingsRevision;

    _currentBookId = bookId;
    _paragraphs = paragraphs;
    _settings = settings;
    _currentChunk = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _state = TtsPlaybackState.preparing;
    _statusMessage = '正在生成快速起播段...';
    notifyListeners();

    final TtsChunk? firstChunk = _quickStartChunker.buildChunk(
      bookId: bookId,
      paragraphs: paragraphs,
      startParagraphIndex: startParagraphIndex,
    );

    if (firstChunk == null) {
      _state = TtsPlaybackState.completed;
      _statusMessage = '朗读完成';
      notifyListeners();
      return;
    }

    await _playChunk(sessionId, revision, firstChunk, bufferNext: true);
  }

  Future<void> pause() async {
    if (_state != TtsPlaybackState.playing &&
        _state != TtsPlaybackState.bufferingNext) {
      return;
    }
    await _player.pause();
    _state = TtsPlaybackState.paused;
    _statusMessage = '已暂停';
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != TtsPlaybackState.paused) {
      return;
    }
    _state = TtsPlaybackState.playing;
    _statusMessage = '继续朗读';
    notifyListeners();
    unawaited(_player.play());
    final int nextStart = (_currentChunk?.endParagraphIndexInclusive ?? -1) + 1;
    _scheduleNextPreparation(_sessionId, _settingsRevision, nextStart);
  }

  Future<void> stop({bool resetMessage = true}) async {
    _sessionId += 1;
    _settingsRevision += 1;
    _nextPreparation = null;
    _nextChunk = null;
    await _player.stop();
    await _cacheStore.deletePaths([_currentAudioPath, _nextAudioPath]);
    _currentAudioPath = null;
    _nextAudioPath = null;
    _currentChunk = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _state = TtsPlaybackState.idle;
    _statusMessage = resetMessage ? null : _statusMessage;
    notifyListeners();
  }

  Future<void> retry() async {
    final TtsChunk? chunk = _currentChunk;
    if (chunk == null || _currentBookId == null || _paragraphs.isEmpty) {
      return;
    }
    await startFrom(
      bookId: _currentBookId!,
      paragraphs: _paragraphs,
      startParagraphIndex: chunk.startParagraphIndex,
      settings: _settings,
    );
  }

  Future<void> updateSettings(TtsSettings settings) async {
    final bool changedVoice = settings.voiceId != _settings.voiceId;
    final bool changedPrompt = settings.speedPrompt != _settings.speedPrompt;
    final bool changedSpeed = settings.playbackSpeed != _settings.playbackSpeed;

    _settings = settings;
    await _player.setSpeed(settings.playbackSpeed);

    if (changedVoice || changedPrompt || changedSpeed) {
      _settingsRevision += 1;
      await _cacheStore.deletePaths([_nextAudioPath]);
      _nextAudioPath = null;
      _nextChunk = null;
      final int nextStart =
          (_currentChunk?.endParagraphIndexInclusive ?? -1) + 1;
      _scheduleNextPreparation(_sessionId, _settingsRevision, nextStart);
    }

    notifyListeners();
  }

  Future<void> handlePrimaryAction({
    required String bookId,
    required List<ReaderParagraph> paragraphs,
    required int startParagraphIndex,
    required TtsSettings settings,
  }) async {
    switch (_state) {
      case TtsPlaybackState.idle:
      case TtsPlaybackState.completed:
      case TtsPlaybackState.needsApiKey:
      case TtsPlaybackState.error:
        await startFrom(
          bookId: bookId,
          paragraphs: paragraphs,
          startParagraphIndex: startParagraphIndex,
          settings: settings,
        );
      case TtsPlaybackState.playing:
        await pause();
      case TtsPlaybackState.paused:
        await resume();
      case TtsPlaybackState.preparing:
      case TtsPlaybackState.bufferingNext:
        return;
    }
  }

  Future<void> _playChunk(
    int sessionId,
    int revision,
    TtsChunk chunk, {
    required bool bufferNext,
  }) async {
    if (_disposed || sessionId != _sessionId) {
      return;
    }

    try {
      final String path = await _audioPathForChunk(sessionId, revision, chunk);
      if (_disposed ||
          sessionId != _sessionId ||
          revision != _settingsRevision) {
        return;
      }

      final String? oldCurrentPath = _currentAudioPath;
      _currentChunk = chunk;
      _currentAudioPath = path;
      _statusMessage = '正在朗读';
      _state = TtsPlaybackState.playing;
      notifyListeners();

      await _player.setFilePath(path);
      await _player.setSpeed(_settings.playbackSpeed);
      await _onChunkStart?.call(chunk);
      unawaited(_player.play());

      if (bufferNext) {
        _scheduleNextPreparation(
          sessionId,
          revision,
          chunk.endParagraphIndexInclusive + 1,
        );
      }

      if (oldCurrentPath != null && oldCurrentPath != path) {
        unawaited(_cacheStore.deletePaths([oldCurrentPath]));
      }
    } on MimoTtsException catch (error) {
      if (_isStaleTaskError(error)) {
        return;
      }
      _state = TtsPlaybackState.error;
      _statusMessage = error.message;
      notifyListeners();
    } on PlayerException {
      _state = TtsPlaybackState.error;
      _statusMessage = '音频播放失败，请重试。';
      notifyListeners();
    } on Exception {
      _state = TtsPlaybackState.error;
      _statusMessage = '朗读准备失败，请检查网络或 API Key。';
      notifyListeners();
    }
  }

  Future<String> _audioPathForChunk(
    int sessionId,
    int revision,
    TtsChunk chunk,
  ) async {
    if (_nextChunk?.startParagraphIndex == chunk.startParagraphIndex &&
        _nextAudioPath != null) {
      final String cachedPath = _nextAudioPath!;
      _nextChunk = null;
      _nextAudioPath = null;
      return cachedPath;
    }

    final Uint8List bytes = await _requestChunkAudio(
      sessionId,
      revision,
      chunk,
    );
    if (sessionId != _sessionId || revision != _settingsRevision) {
      throw const MimoTtsException(message: '朗读任务已更新');
    }
    return _cacheStore.saveChunkAudio(
      bookId: chunk.bookId,
      chunk: chunk,
      voiceId: _settings.voiceId,
      speed: _settings.playbackSpeed,
      bytes: bytes,
    );
  }

  Future<Uint8List> _requestChunkAudio(
    int sessionId,
    int revision,
    TtsChunk chunk,
  ) async {
    int attempt = 0;
    while (true) {
      try {
        return await _apiClient.synthesize(
          apiKey: (await _keyStore.readApiKey())?.trim() ?? '',
          text: chunk.text,
          voiceId: _settings.voiceId,
          speedPrompt: _settings.speedPrompt,
        );
      } on MimoTtsException catch (error) {
        if (!error.isRetryable || attempt >= 2) {
          rethrow;
        }
        final Duration delay = attempt == 0
            ? const Duration(milliseconds: 1500)
            : const Duration(seconds: 4);
        attempt += 1;
        await Future.delayed(delay);
        if (sessionId != _sessionId || revision != _settingsRevision) {
          throw const MimoTtsException(message: '朗读任务已更新');
        }
      }
    }
  }

  void _scheduleNextPreparation(int sessionId, int revision, int startIndex) {
    if (startIndex < 0 || startIndex >= _paragraphs.length) {
      _nextChunk = null;
      _nextAudioPath = null;
      _nextPreparation = null;
      return;
    }

    if (_nextChunk?.startParagraphIndex == startIndex &&
        _nextAudioPath != null) {
      return;
    }

    if (_nextPreparation != null) {
      return;
    }

    _nextPreparation = _prepareNext(sessionId, revision, startIndex);
    notifyListeners();
  }

  Future<void> _prepareNext(int sessionId, int revision, int startIndex) async {
    try {
      final TtsChunk? nextChunk = _chunker.buildChunk(
        bookId: _currentBookId ?? '',
        paragraphs: _paragraphs,
        startParagraphIndex: startIndex,
      );
      if (nextChunk == null) {
        _nextChunk = null;
        _nextAudioPath = null;
        return;
      }

      final Uint8List bytes = await _requestChunkAudio(
        sessionId,
        revision,
        nextChunk,
      );
      if (_disposed ||
          sessionId != _sessionId ||
          revision != _settingsRevision) {
        return;
      }

      final String path = await _cacheStore.saveChunkAudio(
        bookId: nextChunk.bookId,
        chunk: nextChunk,
        voiceId: _settings.voiceId,
        speed: _settings.playbackSpeed,
        bytes: bytes,
      );

      if (_disposed ||
          sessionId != _sessionId ||
          revision != _settingsRevision) {
        await _cacheStore.deletePaths([path]);
        return;
      }

      await _cacheStore.deletePaths([_nextAudioPath]);
      _nextChunk = nextChunk;
      _nextAudioPath = path;
      notifyListeners();
    } on MimoTtsException catch (error) {
      if (!_isStaleTaskError(error)) {
        rethrow;
      }
    } finally {
      _nextPreparation = null;
      notifyListeners();
    }
  }

  bool _isStaleTaskError(MimoTtsException error) {
    return error.message == '朗读任务已更新';
  }

  void _handlePlayerStateChanged(PlayerState state) {
    if (_disposed) {
      return;
    }

    if (state.processingState == ProcessingState.completed) {
      unawaited(_handleCompletion());
    }
  }

  Future<void> _handleCompletion() async {
    if (_handlingCompletion || _state == TtsPlaybackState.paused) {
      return;
    }

    _handlingCompletion = true;
    try {
      final int sessionId = _sessionId;
      final int revision = _settingsRevision;
      final int nextStart =
          (_currentChunk?.endParagraphIndexInclusive ?? -1) + 1;

      if (nextStart < 0 || nextStart >= _paragraphs.length) {
        _state = TtsPlaybackState.completed;
        _statusMessage = '朗读完成';
        notifyListeners();
        return;
      }

      if (_nextChunk == null || _nextAudioPath == null) {
        _state = TtsPlaybackState.bufferingNext;
        _statusMessage = '正在准备下一段...';
        notifyListeners();
        if (_nextPreparation != null) {
          await _nextPreparation;
        } else {
          await _prepareNext(sessionId, revision, nextStart);
        }
      }

      if (_disposed ||
          sessionId != _sessionId ||
          revision != _settingsRevision ||
          _state == TtsPlaybackState.paused) {
        return;
      }

      if (_nextChunk == null) {
        _state = TtsPlaybackState.completed;
        _statusMessage = '朗读完成';
        notifyListeners();
        return;
      }

      final TtsChunk nextChunk = _nextChunk!;
      await _playChunk(sessionId, revision, nextChunk, bufferNext: true);
    } finally {
      _handlingCompletion = false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _playerStateSubscription.cancel();
    await _positionSubscription.cancel();
    await _durationSubscription.cancel();
    await _player.dispose();
    super.dispose();
  }
}
