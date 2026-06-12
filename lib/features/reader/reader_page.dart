import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_theme.dart';
import '../../models/book.dart';
import '../../models/bookmark.dart';
import '../../models/reader_paragraph.dart';
import '../../models/reader_settings.dart';
import '../../models/reading_progress.dart';
import '../../models/tts_chunk.dart';
import '../../models/tts_settings.dart';
import '../../services/book_repository.dart';
import '../../services/mimo_tts_api_client.dart';
import '../../services/secure_key_store.dart';
import '../../services/settings_repository.dart';
import '../../services/tts_cache_store.dart';
import '../../widgets/loading_overlay.dart';
import '../tts/tts_playback_controller.dart';
import '../tts/widgets/tts_control_sheet.dart';
import '../tts/widgets/tts_status_bar.dart';
import 'widgets/bookmark_sheet.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_settings_sheet.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.bookRepository,
    required this.settingsRepository,
    required this.keyStore,
    required this.apiClient,
    required this.cacheStore,
    required this.onBackToLibrary,
  });

  final Book book;
  final BookRepository bookRepository;
  final SettingsRepository settingsRepository;
  final SecureKeyStore keyStore;
  final MimoTtsApiClient apiClient;
  final TtsCacheStore cacheStore;
  final VoidCallback onBackToLibrary;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  late final TtsPlaybackController _ttsController = TtsPlaybackController(
    apiClient: widget.apiClient,
    keyStore: widget.keyStore,
    cacheStore: widget.cacheStore,
    onChunkStart: _handleChunkStart,
  );

  List<ReaderParagraph> _paragraphs = const [];
  List<Bookmark> _bookmarks = const [];
  ReaderSettings _readerSettings = ReaderSettings.defaults();
  TtsSettings _ttsSettings = TtsSettings.defaults();
  String _maskedApiKey = '未填写';
  bool _loading = true;
  bool _controlsVisible = false;
  bool _isReadingSurfaceMoving = false;
  bool _isRestoringInitialPosition = false;
  bool _suppressNextSurfaceTap = false;
  String? _errorText;
  int _currentParagraphIndex = 0;
  double _currentAlignment = 0;
  Timer? _saveDebounce;
  Timer? _scrollSettleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemPositionsListener.itemPositions.addListener(
      _handleVisibleItemsChanged,
    );
    unawaited(_load());
  }

  ReaderThemePalette get _palette =>
      AppTheme.paletteFor(_readerSettings.themeId);

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
      final ReaderSettings readerSettings = await widget.settingsRepository
          .loadReaderSettings();
      final TtsSettings ttsSettings = await widget.settingsRepository
          .loadTtsSettings();
      final List<Bookmark> bookmarks = await widget.settingsRepository
          .loadBookmarks(widget.book.id);
      final ReadingProgress? progress = await widget.settingsRepository
          .loadReadingProgress(widget.book.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _paragraphs = paragraphs;
        _readerSettings = readerSettings;
        _ttsSettings = ttsSettings;
        _bookmarks = bookmarks;
        _currentParagraphIndex = min(
          progress?.paragraphIndex ?? 0,
          max(paragraphs.length - 1, 0),
        );
        _currentAlignment = progress?.alignment ?? 0;
        _isRestoringInitialPosition = progress != null;
        _loading = false;
      });

      await widget.settingsRepository.saveLastBookId(widget.book.id);
      unawaited(_refreshMaskedApiKey());

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_itemScrollController.isAttached || _paragraphs.isEmpty) {
          _isRestoringInitialPosition = false;
          return;
        }
        _itemScrollController.jumpTo(
          index: _currentParagraphIndex,
          alignment: _currentAlignment.clamp(0, 1),
        );
        Timer(const Duration(milliseconds: 400), () {
          if (!mounted) {
            return;
          }
          _isRestoringInitialPosition = false;
        });
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorText = '这本书暂时没有读出来，可能是文件内容异常。';
      });
    }
  }

  Future<void> _refreshMaskedApiKey() async {
    final String maskedKey = widget.keyStore.mask(
      await widget.keyStore.readApiKey(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _maskedApiKey = maskedKey);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistProgress());
    }
  }

  Future<void> _handleChunkStart(TtsChunk chunk) async {
    if (!mounted || _paragraphs.isEmpty) {
      return;
    }
    _currentParagraphIndex = chunk.startParagraphIndex;
    _currentAlignment = 0.08;
    if (_itemScrollController.isAttached) {
      await _itemScrollController.scrollTo(
        index: chunk.startParagraphIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    await _persistProgress(
      forcedParagraphIndex: chunk.startParagraphIndex,
      forcedAlignment: 0.08,
    );
  }

  void _handleVisibleItemsChanged() {
    if (_loading || _isRestoringInitialPosition || _paragraphs.isEmpty) {
      return;
    }

    final List<ItemPosition> positions =
        _itemPositionsListener.itemPositions.value
            .where((item) => item.itemTrailingEdge > 0)
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));

    if (positions.isEmpty) {
      return;
    }

    final ItemPosition anchor = positions.firstWhere(
      (item) => item.itemLeadingEdge >= -0.02,
      orElse: () => positions.first,
    );
    _currentParagraphIndex = anchor.index;
    _currentAlignment = anchor.itemLeadingEdge.clamp(0, 1);
    _schedulePersistProgress();
  }

  void _schedulePersistProgress() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_persistProgress()),
    );
  }

  void _markReadingSurfaceMoving() {
    _isReadingSurfaceMoving = true;
    _scrollSettleTimer?.cancel();
  }

  void _markReadingSurfaceSettling() {
    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = Timer(const Duration(milliseconds: 220), () {
      _isReadingSurfaceMoving = false;
      _suppressNextSurfaceTap = false;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _markReadingSurfaceMoving();
    } else if (notification is ScrollEndNotification) {
      _markReadingSurfaceSettling();
      unawaited(_persistProgress());
    }
    return false;
  }

  Future<void> _persistProgress({
    int? forcedParagraphIndex,
    double? forcedAlignment,
  }) async {
    if (_paragraphs.isEmpty) {
      return;
    }

    final int index = min(
      forcedParagraphIndex ?? _currentParagraphIndex,
      _paragraphs.length - 1,
    );
    final ReaderParagraph paragraph = _paragraphs[index];
    final ReadingProgress progress = ReadingProgress(
      bookId: widget.book.id,
      paragraphIndex: index,
      alignment: forcedAlignment ?? _currentAlignment,
      approxCharOffset: paragraph.startCharOffset,
      percent: widget.book.textLength == 0
          ? 0
          : (paragraph.startCharOffset / widget.book.textLength) * 100,
      updatedAt: DateTime.now(),
    );
    await widget.settingsRepository.saveReadingProgress(progress);
    await widget.settingsRepository.saveLastBookId(widget.book.id);
  }

  Future<void> _applyReaderSettings(ReaderSettings value) async {
    setState(() => _readerSettings = value);
    await widget.settingsRepository.saveReaderSettings(value);
  }

  Future<void> _applyTtsSettings(TtsSettings value) async {
    setState(() => _ttsSettings = value);
    await widget.settingsRepository.saveTtsSettings(value);
    await _ttsController.updateSettings(value);
  }

  Future<void> _saveApiKey(String apiKey) async {
    await widget.keyStore.saveApiKey(apiKey);
    setState(() => _maskedApiKey = widget.keyStore.mask(apiKey));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('MiMo API Key 已保存')));
    }
  }

  Future<void> _clearApiKey() async {
    await widget.keyStore.clearApiKey();
    setState(() => _maskedApiKey = '未填写');
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('MiMo API Key 已清除')));
    }
  }

  Future<void> _promptForApiKeyAndStart() async {
    final TextEditingController controller = TextEditingController();
    final bool? shouldStart = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('填写 MiMo API Key'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Key 只保存在本机'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存并开始朗读'),
            ),
          ],
        );
      },
    );

    final String apiKey = controller.text.trim();
    controller.dispose();

    if (shouldStart != true || apiKey.isEmpty) {
      return;
    }

    await _saveApiKey(apiKey);
    await _handlePrimaryAction();
  }

  Future<void> _handlePrimaryAction() async {
    if (_paragraphs.isEmpty) {
      return;
    }
    await _ttsController.handlePrimaryAction(
      bookId: widget.book.id,
      paragraphs: _paragraphs,
      startParagraphIndex: _currentParagraphIndex,
      settings: _ttsSettings,
    );
    if (_ttsController.state == TtsPlaybackState.needsApiKey && mounted) {
      await _promptForApiKeyAndStart();
    }
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ReaderSettingsSheet(
          palette: _palette,
          readerSettings: _readerSettings,
          ttsSettings: _ttsSettings,
          maskedApiKey: _maskedApiKey,
          onReaderSettingsChanged: (value) {
            unawaited(_applyReaderSettings(value));
          },
          onTtsSettingsChanged: (value) {
            unawaited(_applyTtsSettings(value));
          },
          onSaveApiKey: _saveApiKey,
          onClearApiKey: _clearApiKey,
          onTestApiKey: _testApiKey,
        );
      },
    );
  }

  Future<String> _testApiKey(String draftApiKey) async {
    final String apiKey = draftApiKey.trim().isEmpty
        ? (await widget.keyStore.readApiKey() ?? '').trim()
        : draftApiKey.trim();
    if (apiKey.isEmpty) {
      return '请先填写或保存 MiMo API Key。';
    }

    try {
      final bytes = await widget.apiClient.synthesize(
        apiKey: apiKey,
        text: '连通性测试。',
        voiceId: _ttsSettings.voiceId,
        speedPrompt: _ttsSettings.speedPrompt,
      );
      return '连通性正常，已收到测试音频（${bytes.length} 字节）。';
    } on MimoTtsException catch (error) {
      final String prefix = error.statusCode == null
          ? '请求失败'
          : '请求失败（HTTP ${error.statusCode}）';
      return '$prefix：${error.message}';
    } on Exception catch (error) {
      return '请求异常：${error.runtimeType}。';
    }
  }

  Future<void> _addBookmark() async {
    if (_paragraphs.isEmpty) {
      return;
    }

    final int paragraphIndex = _currentParagraphIndex;
    final bool exists = _bookmarks.any(
      (bookmark) => bookmark.paragraphIndex == paragraphIndex,
    );
    if (exists) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这一段已经加过书签了')));
      return;
    }

    final ReaderParagraph paragraph = _paragraphs[paragraphIndex];
    final String preview = paragraph.text.replaceAll('\n', ' ').trim();
    final Bookmark bookmark = Bookmark(
      id: const Uuid().v4(),
      bookId: widget.book.id,
      paragraphIndex: paragraphIndex,
      approxCharOffset: paragraph.startCharOffset,
      percent: widget.book.textLength == 0
          ? 0
          : (paragraph.startCharOffset / widget.book.textLength) * 100,
      previewText: preview.substring(0, min(80, preview.length)),
      createdAt: DateTime.now(),
    );

    setState(() {
      _bookmarks = [bookmark, ..._bookmarks];
    });
    await widget.settingsRepository.saveBookmarks(widget.book.id, _bookmarks);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已添加书签')));
    }
  }

  Future<void> _openBookmarksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return BookmarkSheet(
          palette: _palette,
          bookmarks: _bookmarks,
          onJump: (bookmark) {
            Navigator.of(context).pop();
            unawaited(_jumpToParagraph(bookmark.paragraphIndex));
          },
          onDelete: (bookmark) {
            setState(() {
              _bookmarks = _bookmarks
                  .where((item) => item.id != bookmark.id)
                  .toList(growable: false);
            });
            unawaited(
              widget.settingsRepository.saveBookmarks(
                widget.book.id,
                _bookmarks,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _jumpToParagraph(int paragraphIndex) async {
    await _ttsController.stop();
    if (!_itemScrollController.isAttached) {
      return;
    }
    _currentParagraphIndex = paragraphIndex;
    _currentAlignment = 0.06;
    await _itemScrollController.scrollTo(
      index: paragraphIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
    await _persistProgress(
      forcedParagraphIndex: paragraphIndex,
      forcedAlignment: 0.06,
    );
  }

  Future<void> _openMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return TtsControlSheet(
          palette: _palette,
          state: _ttsController.state,
          statusMessage: _ttsController.statusMessage,
          maskedApiKey: _maskedApiKey,
          onStop: () {
            Navigator.of(context).pop();
            unawaited(_ttsController.stop());
          },
          onOpenSettings: () {
            Navigator.of(context).pop();
            unawaited(_openSettingsSheet());
          },
        );
      },
    );
  }

  Future<void> _goBackToLibrary() async {
    await _ttsController.stop();
    await _persistProgress();
    if (mounted) {
      widget.onBackToLibrary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReaderThemePalette palette = _palette;
    final Brightness iconBrightness = palette.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    final double currentPercent =
        _paragraphs.isEmpty || widget.book.textLength == 0
        ? 0
        : (_paragraphs[_currentParagraphIndex].startCharOffset /
                  widget.book.textLength) *
              100;

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
          message: '正在整理书页...',
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
                  child: AnimatedBuilder(
                    animation: _ttsController,
                    builder: (context, _) {
                      return Stack(
                        children: [
                          Listener(
                            onPointerDown: (_) {
                              if (_isReadingSurfaceMoving) {
                                _suppressNextSurfaceTap = true;
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (_suppressNextSurfaceTap ||
                                    _isReadingSurfaceMoving) {
                                  _suppressNextSurfaceTap = false;
                                  return;
                                }
                                setState(() {
                                  _controlsVisible = !_controlsVisible;
                                });
                              },
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: ScrollablePositionedList.separated(
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    84,
                                    24,
                                    180,
                                  ),
                                  itemCount: _paragraphs.length,
                                  separatorBuilder: (_, index) => SizedBox(
                                    height: _readerSettings.fontSize * 0.78,
                                  ),
                                  itemBuilder: (context, index) {
                                    final ReaderParagraph paragraph =
                                        _paragraphs[index];
                                    return Text(
                                      paragraph.text,
                                      style: TextStyle(
                                        color: palette.foreground,
                                        fontSize: _readerSettings.fontSize,
                                        height: _readerSettings.lineHeight,
                                        letterSpacing: 0.12,
                                      ),
                                      textAlign: TextAlign.justify,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (_controlsVisible)
                            Positioned(
                              top: 14,
                              left: 16,
                              right: 16,
                              child: Row(
                                children: [
                                  _CapsuleButton(
                                    palette: palette,
                                    icon: Icons.arrow_back_ios_new_rounded,
                                    onTap: () {
                                      unawaited(_goBackToLibrary());
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.toolbar,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.book.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: palette.foreground,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '已读 ${currentPercent.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              color: palette.secondaryText,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 18,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_ttsController.state !=
                                    TtsPlaybackState.idle)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TtsStatusBar(
                                      palette: palette,
                                      controller: _ttsController,
                                      primaryLabel:
                                          _ttsController.primaryActionLabel,
                                      onPrimary: () {
                                        unawaited(_handlePrimaryAction());
                                      },
                                      onStop: () =>
                                          unawaited(_ttsController.stop()),
                                    ),
                                  ),
                                if (_controlsVisible)
                                  ReaderBottomBar(
                                    palette: palette,
                                    primaryLabel:
                                        _ttsController.primaryActionLabel,
                                    onLibraryTap: () {
                                      unawaited(_goBackToLibrary());
                                    },
                                    onBookmarksTap: () {
                                      unawaited(_openBookmarksSheet());
                                    },
                                    onSettingsTap: () {
                                      unawaited(_openSettingsSheet());
                                    },
                                    onPrimaryTap: () {
                                      unawaited(_handlePrimaryAction());
                                    },
                                    onMoreTap: () {
                                      unawaited(_openMoreSheet());
                                    },
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 18,
                            bottom: _controlsVisible
                                ? 104
                                : _ttsController.state == TtsPlaybackState.idle
                                ? 18
                                : 132,
                            child: _ReadingProgressPill(
                              palette: palette,
                              percent: currentPercent,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
        floatingActionButton: _controlsVisible
            ? FloatingActionButton.small(
                onPressed: () {
                  unawaited(_addBookmark());
                },
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                child: const Icon(Icons.bookmark_add_outlined),
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(
      _handleVisibleItemsChanged,
    );
    _saveDebounce?.cancel();
    _scrollSettleTimer?.cancel();
    unawaited(_persistProgress());
    _ttsController.dispose();
    super.dispose();
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.palette,
    required this.icon,
    required this.onTap,
  });

  final ReaderThemePalette palette;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.toolbar,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: palette.foreground, size: 18),
        ),
      ),
    );
  }
}

class _ReadingProgressPill extends StatelessWidget {
  const _ReadingProgressPill({required this.palette, required this.percent});

  final ReaderThemePalette palette;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: palette.toolbar,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Text(
          '${percent.toStringAsFixed(1)}%',
          style: TextStyle(
            color: palette.foreground,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
