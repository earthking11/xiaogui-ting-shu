import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/app_theme.dart';
import '../../models/audiobook_manifest.dart';
import '../../models/audiobook_sentence.dart';
import '../../models/book.dart';
import '../../models/reader_paragraph.dart';
import '../../models/reader_settings.dart';
import '../../models/tts_settings.dart';
import '../../services/audiobook_repository.dart';
import '../../services/book_repository.dart';
import '../../services/mimo_tts_api_client.dart';
import '../../services/secure_key_store.dart';
import '../../services/settings_repository.dart';
import '../../widgets/loading_overlay.dart';
import 'audiobook_generation_controller.dart';

class AudiobookPage extends StatefulWidget {
  const AudiobookPage({
    super.key,
    required this.book,
    required this.bookRepository,
    required this.settingsRepository,
    required this.audiobookRepository,
    required this.keyStore,
    required this.apiClient,
    required this.onBackToLibrary,
  });

  final Book book;
  final BookRepository bookRepository;
  final SettingsRepository settingsRepository;
  final AudiobookRepository audiobookRepository;
  final SecureKeyStore keyStore;
  final MimoTtsApiClient apiClient;
  final VoidCallback onBackToLibrary;

  @override
  State<AudiobookPage> createState() => _AudiobookPageState();
}

class _AudiobookPageState extends State<AudiobookPage> {
  static const double _textHorizontalPadding = 24;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final GlobalKey _listViewportKey = GlobalKey();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  AudiobookGenerationController? _generationController;
  List<ReaderParagraph> _paragraphs = const [];
  List<AudiobookSentenceCue> _sentences = const [];
  Map<int, List<AudiobookSentenceCue>> _sentencesByParagraph = const {};
  ReaderSettings _readerSettings = ReaderSettings.defaults();
  String _maskedApiKey = '未填写';
  bool _loading = true;
  String? _errorText;
  int _activeSentenceIndex = -1;
  int _lastAutoAdvancedFromSentenceIndex = -1;
  int _followRequestSerial = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _generationCardExpanded = false;
  bool _disposed = false;
  bool _reachedEnd = false;

  ReaderThemePalette get _palette =>
      AppTheme.paletteFor(_readerSettings.themeId);

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.playerStateStream.listen(
      _handlePlayerState,
    );
    _positionSubscription = _player.positionStream.listen((position) {
      if (!_disposed && mounted) {
        setState(() => _position = position);
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (!_disposed && mounted) {
        setState(() => _duration = duration ?? Duration.zero);
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final String text = await widget.bookRepository.readBookText(widget.book);
      final List<ReaderParagraph> paragraphs = ReaderParagraphParser.parse(
        text,
      );
      final List<AudiobookSentenceCue> sentences =
          AudiobookSentenceParser.parse(paragraphs);
      final ReaderSettings readerSettings = await widget.settingsRepository
          .loadReaderSettings();
      final TtsSettings ttsSettings = await widget.settingsRepository
          .loadTtsSettings();
      final AudiobookManifest manifest = await widget.audiobookRepository
          .loadOrCreateManifest(
            book: widget.book,
            bookText: text,
            settings: ttsSettings,
            sentences: sentences,
          );
      final String? apiKey = await widget.keyStore.readApiKey();

      if (!mounted) {
        return;
      }

      final controller = AudiobookGenerationController(
        repository: widget.audiobookRepository,
        apiClient: widget.apiClient,
        keyStore: widget.keyStore,
        manifest: manifest,
      )..addListener(_handleGenerationChanged);

      setState(() {
        _paragraphs = paragraphs;
        _sentences = sentences;
        _sentencesByParagraph = _groupSentences(sentences);
        _readerSettings = readerSettings;
        _maskedApiKey = widget.keyStore.mask(apiKey);
        _generationController = controller;
        _loading = false;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _errorText = '整本听书准备失败，请返回后重试。';
          _loading = false;
        });
      }
    }
  }

  Map<int, List<AudiobookSentenceCue>> _groupSentences(
    List<AudiobookSentenceCue> sentences,
  ) {
    final result = <int, List<AudiobookSentenceCue>>{};
    for (final AudiobookSentenceCue sentence in sentences) {
      result.putIfAbsent(sentence.paragraphIndex, () => []).add(sentence);
    }
    return result;
  }

  void _handleGenerationChanged() {
    if (!_disposed && mounted) {
      setState(() {});
    }
  }

  Future<void> _handlePlayerState(PlayerState state) async {
    if (_disposed || !mounted) {
      return;
    }
    setState(() => _playing = state.playing);
    if (!_disposed && state.processingState == ProcessingState.completed) {
      await _advanceAfterCompletionIfNeeded();
    }
  }

  Future<void> _advanceAfterCompletionIfNeeded() async {
    if (_disposed) {
      return;
    }
    final int completedIndex = _activeSentenceIndex;
    if (completedIndex < 0 ||
        _lastAutoAdvancedFromSentenceIndex == completedIndex) {
      return;
    }
    _lastAutoAdvancedFromSentenceIndex = completedIndex;
    await _playNext();
  }

  Future<void> _startGeneration({bool retryFailed = false}) async {
    final AudiobookGenerationController? controller = _generationController;
    if (controller == null) {
      return;
    }
    if (!await _ensureApiKey()) {
      return;
    }
    await controller.start(retryFailed: retryFailed);
  }

  Future<bool> _ensureApiKey() async {
    final String? apiKey = (await widget.keyStore.readApiKey())?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      return true;
    }
    return await _promptForApiKey() ?? false;
  }

  Future<bool?> _promptForApiKey() async {
    final TextEditingController controller = TextEditingController();
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('填写 MiMo API Key'),
          content: TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Key 只保存在本机'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    final String apiKey = controller.text.trim();
    controller.dispose();
    if (saved != true) {
      return false;
    }
    if (apiKey.isEmpty) {
      _showSnackBar('请先填写 API Key');
      return false;
    }
    await widget.keyStore.saveApiKey(apiKey);
    if (mounted) {
      setState(() => _maskedApiKey = widget.keyStore.mask(apiKey));
      _showSnackBar('MiMo API Key 已保存');
    }
    return true;
  }

  Future<void> _playFirstAvailable() async {
    if (_disposed) {
      return;
    }
    final int index = _generationController?.firstPlayableIndex() ?? -1;
    if (index < 0) {
      _showSnackBar('还没有可播放的句子，请先生成音频');
      return;
    }
    await _playFromSentence(index);
  }

  Future<void> _togglePlayback() async {
    if (_disposed) {
      return;
    }
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_activeSentenceIndex < 0 ||
        _reachedEnd ||
        _player.processingState == ProcessingState.completed) {
      await _playFirstAvailable();
      return;
    }
    _startPlayer();
    _scrollToSentence(_activeSentenceIndex);
  }

  Future<void> _playPrevious() async {
    if (_disposed) {
      return;
    }
    final int previous =
        _generationController?.previousPlayableIndexBefore(
          _activeSentenceIndex,
        ) ??
        -1;
    if (previous >= 0) {
      await _playFromSentence(previous);
    }
  }

  Future<void> _playNext() async {
    if (_disposed) {
      return;
    }
    final int next =
        _generationController?.nextPlayableIndexAfter(_activeSentenceIndex) ??
        -1;
    if (next < 0) {
      if (mounted && !_disposed) {
        setState(() {
          _playing = false;
          _reachedEnd = true;
          _position = _duration;
        });
      }
      return;
    }
    await _playFromSentence(next);
  }

  Future<void> _playFromSentence(int sentenceIndex) async {
    if (_disposed) {
      return;
    }
    final AudiobookGenerationController? controller = _generationController;
    if (controller == null ||
        sentenceIndex < 0 ||
        sentenceIndex >= controller.manifest.clips.length) {
      return;
    }

    final AudiobookClip clip = controller.manifest.clips[sentenceIndex];
    final String? audioPath = clip.audioPath;
    if (clip.status != AudiobookClipStatus.done ||
        audioPath == null ||
        audioPath.isEmpty ||
        !await File(audioPath).exists()) {
      _showSnackBar('这一句还没有生成音频');
      return;
    }

    if (_disposed) {
      return;
    }
    try {
      await _player.stop();
      if (_disposed) {
        return;
      }
      await _player.setFilePath(audioPath);
    } on Object {
      if (!_disposed) {
        _showSnackBar('音频播放失败，请重试。');
      }
      return;
    }
    if (!mounted || _disposed) {
      return;
    }
    setState(() {
      _activeSentenceIndex = sentenceIndex;
      _lastAutoAdvancedFromSentenceIndex = -1;
      _position = Duration.zero;
      _reachedEnd = false;
    });
    _scrollToSentence(sentenceIndex);
    _startPlayer();
  }

  void _startPlayer() {
    if (_disposed) {
      return;
    }
    unawaited(
      _player
          .play()
          .then((_) {
            if (!_disposed &&
                mounted &&
                _player.processingState == ProcessingState.completed) {
              unawaited(_advanceAfterCompletionIfNeeded());
            }
          })
          .catchError((Object _) {
            if (!_disposed && mounted) {
              _showSnackBar('音频播放失败，请重试。');
            }
          }),
    );
  }

  void _scrollToSentence(int sentenceIndex) {
    if (_disposed ||
        !_itemScrollController.isAttached ||
        sentenceIndex < 0 ||
        sentenceIndex >= _sentences.length) {
      return;
    }
    final AudiobookSentenceCue sentence = _sentences[sentenceIndex];
    final int requestSerial = ++_followRequestSerial;
    unawaited(_followPlayingSentence(sentence, requestSerial));
  }

  Future<void> _followPlayingSentence(
    AudiobookSentenceCue sentence,
    int requestSerial,
  ) async {
    if (!_isCurrentFollowRequest(sentence, requestSerial) ||
        !_itemScrollController.isAttached) {
      return;
    }
    if (_isParagraphVisible(sentence.paragraphIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isCurrentFollowRequest(sentence, requestSerial)) {
          _nudgeSentenceIntoReadingBand(sentence);
        }
      });
      return;
    }

    await _itemScrollController.scrollTo(
      index: sentence.paragraphIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
    if (!_isCurrentFollowRequest(sentence, requestSerial)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentFollowRequest(sentence, requestSerial)) {
        _nudgeSentenceIntoReadingBand(sentence);
      }
    });
  }

  bool _isCurrentFollowRequest(
    AudiobookSentenceCue sentence,
    int requestSerial,
  ) {
    return mounted &&
        !_disposed &&
        requestSerial == _followRequestSerial &&
        sentence.index == _activeSentenceIndex;
  }

  bool _isParagraphVisible(int paragraphIndex) {
    final ItemPosition? position = _visibleItemPosition(paragraphIndex);
    return position != null &&
        position.itemTrailingEdge > 0.03 &&
        position.itemLeadingEdge < 0.97;
  }

  void _nudgeSentenceIntoReadingBand(AudiobookSentenceCue sentence) {
    if (sentence.index != _activeSentenceIndex) {
      return;
    }
    final ItemPosition? itemPosition = _visibleItemPosition(
      sentence.paragraphIndex,
    );
    final BuildContext? viewportContext = _listViewportKey.currentContext;
    if (itemPosition == null || viewportContext == null) {
      return;
    }

    final RenderObject? viewportRenderObject = viewportContext
        .findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize) {
      return;
    }

    final double viewportHeight = viewportRenderObject.size.height;
    final double paragraphWidth = max(
      1,
      viewportRenderObject.size.width - (_textHorizontalPadding * 2),
    ).toDouble();
    final double sentenceCenterY = _sentenceCenterY(
      sentence: sentence,
      paragraphWidth: paragraphWidth,
    );
    final double sentenceYInViewport =
        (itemPosition.itemLeadingEdge * viewportHeight) + sentenceCenterY;
    final double comfortableTop = viewportHeight * 0.24;
    final double comfortableBottom = viewportHeight * 0.56;
    if (sentenceYInViewport >= comfortableTop &&
        sentenceYInViewport <= comfortableBottom) {
      return;
    }

    final double desiredY = viewportHeight * 0.38;
    final double offsetDelta = sentenceYInViewport - desiredY;
    if (offsetDelta.abs() < 18) {
      return;
    }

    unawaited(
      _scrollOffsetController.animateScroll(
        offset: offsetDelta,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  ItemPosition? _visibleItemPosition(int paragraphIndex) {
    for (final ItemPosition position
        in _itemPositionsListener.itemPositions.value) {
      if (position.index == paragraphIndex) {
        return position;
      }
    }
    return null;
  }

  double _sentenceCenterY({
    required AudiobookSentenceCue sentence,
    required double paragraphWidth,
  }) {
    final ReaderParagraph paragraph = _paragraphs[sentence.paragraphIndex];
    final TextPainter painter = TextPainter(
      text: _buildAudiobookParagraphSpan(
        palette: _palette,
        paragraph: paragraph,
        sentences: _sentencesByParagraph[sentence.paragraphIndex] ?? const [],
        activeSentenceIndex: _activeSentenceIndex,
        fontSize: _readerSettings.fontSize,
        lineHeight: _readerSettings.lineHeight,
      ),
      textAlign: TextAlign.justify,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: paragraphWidth);
    final double maxParagraphHeight = painter.height;

    final List<TextBox> boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: sentence.startOffsetInParagraph,
        extentOffset: sentence.endOffsetInParagraph,
      ),
    );
    if (boxes.isEmpty) {
      final Offset caret = painter.getOffsetForCaret(
        TextPosition(offset: sentence.startOffsetInParagraph),
        Rect.zero,
      );
      return caret.dy.clamp(0, maxParagraphHeight).toDouble();
    }

    double top = boxes.first.top;
    double bottom = boxes.first.bottom;
    for (final TextBox box in boxes.skip(1)) {
      top = min(top, box.top);
      bottom = max(bottom, box.bottom);
    }
    return ((top + bottom) / 2).clamp(0, maxParagraphHeight).toDouble();
  }

  Future<void> _deletePlan() async {
    if (_disposed) {
      return;
    }
    final AudiobookGenerationController? controller = _generationController;
    if (controller == null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除整本听书音频？'),
          content: const Text('已生成的 MP3 会被删除，但原 TXT 和阅读进度不会受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    if (_disposed) {
      return;
    }
    try {
      await _player.stop();
    } on Object {
      if (!_disposed) {
        _showSnackBar('音频停止失败，请重试。');
      }
      return;
    }
    await controller.deletePlan();
    if (mounted && !_disposed) {
      setState(() {
        _activeSentenceIndex = -1;
        _reachedEnd = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (_disposed || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double get _playbackProgress {
    if (_duration.inMilliseconds <= 0) {
      return 0;
    }
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 MB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  int _generatedAudioBytes(AudiobookManifest manifest) {
    int total = 0;
    for (final AudiobookClip clip in manifest.clips) {
      final String? path = clip.audioPath;
      if (clip.status != AudiobookClipStatus.done ||
          path == null ||
          path.isEmpty) {
        continue;
      }
      final File file = File(path);
      if (file.existsSync()) {
        total += file.lengthSync();
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final ReaderThemePalette palette = _palette;
    final AudiobookGenerationController? controller = _generationController;
    final AudiobookManifest? manifest = controller?.manifest;
    final Brightness iconBrightness = palette.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: iconBrightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: palette.background,
        body: LoadingOverlay(
          visible: _loading,
          message: '正在准备整本听书...',
          child: _errorText != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorText!,
                      style: TextStyle(color: palette.secondaryText),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      _AudiobookHeader(
                        palette: palette,
                        title: widget.book.title,
                        onBack: () {
                          unawaited(controller?.pause());
                          widget.onBackToLibrary();
                        },
                      ),
                      if (controller != null && manifest != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: _GenerationCard(
                            palette: palette,
                            manifest: manifest,
                            isGenerating: controller.isGenerating,
                            pauseRequested: controller.pauseRequested,
                            maskedApiKey: _maskedApiKey,
                            audioBytes: _generatedAudioBytes(manifest),
                            runtimeMessage: controller.runtimeMessage,
                            expanded: _generationCardExpanded,
                            onToggleExpanded: () {
                              setState(() {
                                _generationCardExpanded =
                                    !_generationCardExpanded;
                              });
                            },
                            onStart: () {
                              unawaited(_startGeneration());
                            },
                            onPause: () {
                              unawaited(controller.pause());
                            },
                            onRetryFailed: () {
                              unawaited(_startGeneration(retryFailed: true));
                            },
                            onPlayGenerated: () {
                              unawaited(_playFirstAvailable());
                            },
                            onSaveKey: () {
                              unawaited(_promptForApiKey());
                            },
                            onDelete: () {
                              unawaited(_deletePlan());
                            },
                            formatBytes: _formatBytes,
                          ),
                        ),
                      Expanded(
                        child: KeyedSubtree(
                          key: _listViewportKey,
                          child: _paragraphs.isEmpty
                              ? Center(
                                  child: Text(
                                    '这本书还没有可朗读的正文。',
                                    style: TextStyle(
                                      color: palette.secondaryText,
                                    ),
                                  ),
                                )
                              : ScrollablePositionedList.separated(
                                  itemScrollController: _itemScrollController,
                                  scrollOffsetController:
                                      _scrollOffsetController,
                                  itemPositionsListener: _itemPositionsListener,
                                  padding: EdgeInsets.fromLTRB(
                                    _textHorizontalPadding,
                                    10,
                                    _textHorizontalPadding,
                                    manifest?.hasPlayableAudio == true
                                        ? 132
                                        : 36,
                                  ),
                                  itemCount: _paragraphs.length,
                                  separatorBuilder: (_, index) => SizedBox(
                                    height: _readerSettings.fontSize * 0.78,
                                  ),
                                  itemBuilder: (context, index) {
                                    final ReaderParagraph paragraph =
                                        _paragraphs[index];
                                    return AudiobookParagraphView(
                                      palette: palette,
                                      paragraph: paragraph,
                                      sentences:
                                          _sentencesByParagraph[index] ??
                                          const [],
                                      activeSentenceIndex: _activeSentenceIndex,
                                      fontSize: _readerSettings.fontSize,
                                      lineHeight: _readerSettings.lineHeight,
                                      onSentenceTap: (sentence) {
                                        unawaited(
                                          _playFromSentence(sentence.index),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        bottomNavigationBar: manifest?.hasPlayableAudio == true
            ? _AudiobookPlayerBar(
                palette: palette,
                playing: _playing,
                sentenceIndex: _activeSentenceIndex,
                totalSentences: manifest!.totalSentenceCount,
                progress: _playbackProgress,
                onPrevious: () {
                  unawaited(_playPrevious());
                },
                onPlayPause: () {
                  unawaited(_togglePlayback());
                },
                onNext: () {
                  unawaited(_playNext());
                },
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final AudiobookGenerationController? controller = _generationController;
    controller?.removeListener(_handleGenerationChanged);
    unawaited(controller?.pause());
    unawaited(_disposePlayerResources());
    super.dispose();
  }

  Future<void> _disposePlayerResources() async {
    try {
      await _playerStateSubscription?.cancel();
      await _positionSubscription?.cancel();
      await _durationSubscription?.cancel();
      await _player.dispose();
    } on Object {
      // The page is already leaving; ignore late platform cleanup failures.
    }
  }
}

TextStyle _audiobookParagraphBaseStyle({
  required ReaderThemePalette palette,
  required double fontSize,
  required double lineHeight,
}) {
  return TextStyle(
    color: palette.foreground,
    fontSize: fontSize,
    height: lineHeight,
    letterSpacing: 0.12,
  );
}

TextSpan _buildAudiobookParagraphSpan({
  required ReaderThemePalette palette,
  required ReaderParagraph paragraph,
  required List<AudiobookSentenceCue> sentences,
  required int activeSentenceIndex,
  required double fontSize,
  required double lineHeight,
}) {
  final TextStyle baseStyle = _audiobookParagraphBaseStyle(
    palette: palette,
    fontSize: fontSize,
    lineHeight: lineHeight,
  );
  final spans = <InlineSpan>[];
  int cursor = 0;
  final Paint highlightPaint = Paint()
    ..color = palette.accent.withValues(alpha: 0.18);

  for (final AudiobookSentenceCue sentence in sentences) {
    if (sentence.startOffsetInParagraph > cursor) {
      spans.add(
        TextSpan(
          text: paragraph.text.substring(
            cursor,
            sentence.startOffsetInParagraph,
          ),
          style: baseStyle,
        ),
      );
    }

    final bool active = sentence.index == activeSentenceIndex;
    spans.add(
      TextSpan(
        text: paragraph.text.substring(
          sentence.startOffsetInParagraph,
          sentence.endOffsetInParagraph,
        ),
        style: baseStyle.copyWith(
          color: active ? palette.accent : palette.foreground,
          fontWeight: active ? FontWeight.w800 : FontWeight.w400,
          background: active ? highlightPaint : null,
        ),
      ),
    );
    cursor = sentence.endOffsetInParagraph;
  }

  if (cursor < paragraph.text.length) {
    spans.add(
      TextSpan(text: paragraph.text.substring(cursor), style: baseStyle),
    );
  }

  return TextSpan(style: baseStyle, children: spans);
}

class AudiobookParagraphView extends StatelessWidget {
  const AudiobookParagraphView({
    super.key,
    required this.palette,
    required this.paragraph,
    required this.sentences,
    required this.activeSentenceIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.onSentenceTap,
  });

  final ReaderThemePalette palette;
  final ReaderParagraph paragraph;
  final List<AudiobookSentenceCue> sentences;
  final int activeSentenceIndex;
  final double fontSize;
  final double lineHeight;
  final ValueChanged<AudiobookSentenceCue> onSentenceTap;

  @override
  Widget build(BuildContext context) {
    final TextSpan span = _buildAudiobookParagraphSpan(
      palette: palette,
      paragraph: paragraph,
      sentences: sentences,
      activeSentenceIndex: activeSentenceIndex,
      fontSize: fontSize,
      lineHeight: lineHeight,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) {
            final TextPainter painter = TextPainter(
              text: span,
              textAlign: TextAlign.justify,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final TextPosition position = painter.getPositionForOffset(
              details.localPosition,
            );
            final AudiobookSentenceCue? sentence = _sentenceAt(position.offset);
            if (sentence != null) {
              onSentenceTap(sentence);
            }
          },
          child: RichText(text: span, textAlign: TextAlign.justify),
        );
      },
    );
  }

  AudiobookSentenceCue? _sentenceAt(int offset) {
    for (final AudiobookSentenceCue sentence in sentences) {
      if (offset >= sentence.startOffsetInParagraph &&
          offset < sentence.endOffsetInParagraph) {
        return sentence;
      }
    }
    return null;
  }
}

class _AudiobookHeader extends StatelessWidget {
  const _AudiobookHeader({
    required this.palette,
    required this.title,
    required this.onBack,
  });

  final ReaderThemePalette palette;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Material(
            color: palette.toolbar,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: palette.foreground,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '整本听书',
                  style: TextStyle(
                    color: palette.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerationCard extends StatelessWidget {
  const _GenerationCard({
    required this.palette,
    required this.manifest,
    required this.isGenerating,
    required this.pauseRequested,
    required this.maskedApiKey,
    required this.audioBytes,
    required this.runtimeMessage,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onStart,
    required this.onPause,
    required this.onRetryFailed,
    required this.onPlayGenerated,
    required this.onSaveKey,
    required this.onDelete,
    required this.formatBytes,
  });

  final ReaderThemePalette palette;
  final AudiobookManifest manifest;
  final bool isGenerating;
  final bool pauseRequested;
  final String maskedApiKey;
  final int audioBytes;
  final String? runtimeMessage;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onRetryFailed;
  final VoidCallback onPlayGenerated;
  final VoidCallback onSaveKey;
  final VoidCallback onDelete;
  final String Function(int bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final double percent = manifest.progress * 100;
    final String statusText = runtimeMessage ?? _statusDescription;
    if (!expanded) {
      return _buildCompactCard(percent);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onToggleExpanded,
                tooltip: expanded ? '收起生成信息' : '展开生成信息',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: palette.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: manifest.progress,
              minHeight: 10,
              backgroundColor: palette.border,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.secondaryText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildInfoPills(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildActionButtons(compact: false),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCard(double percent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_title · ${manifest.generatedSentenceCount}/${manifest.totalSentenceCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              _CompactIconButton(
                palette: palette,
                tooltip: _compactActionTooltip,
                icon: _compactActionIcon,
                onPressed: _compactAction,
              ),
              _CompactIconButton(
                palette: palette,
                tooltip: '展开生成信息',
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: onToggleExpanded,
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: manifest.progress,
              minHeight: 4,
              backgroundColor: palette.border,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _compactActionIcon {
    if (isGenerating) {
      return Icons.pause_rounded;
    }
    if (manifest.hasPlayableAudio) {
      return Icons.play_arrow_rounded;
    }
    if (manifest.failedSentenceCount > 0) {
      return Icons.refresh_rounded;
    }
    return Icons.bolt_rounded;
  }

  String get _compactActionTooltip {
    if (isGenerating) {
      return pauseRequested ? '暂停中' : '暂停生成';
    }
    if (manifest.hasPlayableAudio) {
      return '播放已生成';
    }
    if (manifest.failedSentenceCount > 0) {
      return '重试失败句';
    }
    return '继续生成';
  }

  VoidCallback? get _compactAction {
    if (isGenerating) {
      return pauseRequested ? null : onPause;
    }
    if (manifest.hasPlayableAudio) {
      return onPlayGenerated;
    }
    if (manifest.failedSentenceCount > 0) {
      return onRetryFailed;
    }
    if (manifest.status != AudiobookJobStatus.completed) {
      return onStart;
    }
    return null;
  }

  List<Widget> _buildInfoPills() {
    return [
      _InfoPill(
        palette: palette,
        label:
            '${manifest.generatedSentenceCount}/${manifest.totalSentenceCount} 句',
      ),
      if (manifest.failedSentenceCount > 0)
        _InfoPill(
          palette: palette,
          label: '失败 ${manifest.failedSentenceCount} 句',
        ),
      _InfoPill(
        palette: palette,
        label:
            '${manifest.voiceName} · ${(manifest.playbackSpeed * 100).round()}%',
      ),
      _InfoPill(palette: palette, label: manifest.audioFormat.toUpperCase()),
      _InfoPill(
        palette: palette,
        label: '${AudiobookGenerationController.maxConcurrentRequests} 路并发',
      ),
      _InfoPill(palette: palette, label: '约 ${formatBytes(audioBytes)}'),
      _InfoPill(palette: palette, label: 'Key $maskedApiKey'),
    ];
  }

  List<Widget> _buildActionButtons({required bool compact}) {
    final bool canContinue =
        !isGenerating && manifest.status != AudiobookJobStatus.completed;
    final String generateLabel = compact ? '生成' : '继续生成';
    final String pauseLabel = compact
        ? (pauseRequested ? '暂停中' : '暂停')
        : (pauseRequested ? '暂停中' : '暂停生成');
    final String playLabel = compact ? '播放' : '播放已生成';
    final String retryLabel = compact ? '重试' : '重试失败句';
    final String keyLabel = compact ? 'Key' : '填写 Key';

    return [
      if (isGenerating)
        FilledButton.icon(
          onPressed: pauseRequested ? null : onPause,
          icon: const Icon(Icons.pause_rounded),
          label: Text(pauseLabel),
        )
      else if (canContinue)
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.bolt_rounded),
          label: Text(generateLabel),
        ),
      if (manifest.hasPlayableAudio)
        OutlinedButton.icon(
          onPressed: onPlayGenerated,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(playLabel),
        ),
      if (!isGenerating && manifest.failedSentenceCount > 0)
        OutlinedButton.icon(
          onPressed: onRetryFailed,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(retryLabel),
        ),
      if (expanded || maskedApiKey == '未填写')
        OutlinedButton.icon(
          onPressed: onSaveKey,
          icon: const Icon(Icons.key_rounded),
          label: Text(keyLabel),
        ),
      if (expanded && !isGenerating && manifest.hasPlayableAudio)
        TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('删除音频'),
        ),
    ];
  }

  String get _title {
    switch (manifest.status) {
      case AudiobookJobStatus.pending:
        return '准备生成整本 MP3';
      case AudiobookJobStatus.generating:
        return '正在生成整本听书';
      case AudiobookJobStatus.paused:
        return '已暂停，可恢复';
      case AudiobookJobStatus.completed:
        return '整本音频已完成';
      case AudiobookJobStatus.error:
        return '生成遇到问题';
    }
  }

  String get _statusDescription {
    switch (manifest.status) {
      case AudiobookJobStatus.pending:
        return '首次生成会逐句请求 MiMo，生成完的句子会立刻保存。';
      case AudiobookJobStatus.generating:
        return '正在逐句生成，退出前建议先暂停。';
      case AudiobookJobStatus.paused:
        return '已生成的 MP3 都保留在本机，下次可以继续。';
      case AudiobookJobStatus.completed:
        return '可以像歌词一样点句跳播，文本会跟随播放高亮。';
      case AudiobookJobStatus.error:
        return '请检查失败原因，修复后可以继续或重试失败句。';
    }
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.palette, required this.label});

  final ReaderThemePalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final ReaderThemePalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      iconSize: 21,
      color: palette.foreground,
      disabledColor: palette.secondaryText.withValues(alpha: 0.45),
      icon: Icon(icon),
    );
  }
}

class _AudiobookPlayerBar extends StatelessWidget {
  const _AudiobookPlayerBar({
    required this.palette,
    required this.playing,
    required this.sentenceIndex,
    required this.totalSentences,
    required this.progress,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final ReaderThemePalette palette;
  final bool playing;
  final int sentenceIndex;
  final int totalSentences;
  final double progress;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final int displayIndex = max(sentenceIndex + 1, 0);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: palette.toolbar,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  sentenceIndex < 0
                      ? '未开始播放'
                      : '第 $displayIndex / $totalSentences 句',
                  style: TextStyle(
                    color: palette.foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: palette.foreground,
                ),
                FilledButton(
                  onPressed: onPlayPause,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: palette.foreground,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: palette.border,
                valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
