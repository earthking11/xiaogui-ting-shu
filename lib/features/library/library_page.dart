import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/audiobook_manifest.dart';
import '../../models/book.dart';
import '../../models/reading_progress.dart';
import '../../services/audiobook_repository.dart';
import '../../services/settings_repository.dart';
import '../../widgets/empty_state.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.books,
    required this.isImporting,
    required this.settingsRepository,
    required this.audiobookRepository,
    required this.onImportRequested,
    required this.onBookSelected,
    required this.onAudiobookSelected,
  });

  final List<Book> books;
  final bool isImporting;
  final SettingsRepository settingsRepository;
  final AudiobookRepository audiobookRepository;
  final Future<void> Function() onImportRequested;
  final ValueChanged<Book> onBookSelected;
  final ValueChanged<Book> onAudiobookSelected;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<_LibraryData> _libraryFuture = _loadLibraryData();

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books != widget.books) {
      _libraryFuture = _loadLibraryData();
    }
  }

  Future<_LibraryData> _loadLibraryData() async {
    final results = await Future.wait([
      widget.settingsRepository.loadAllProgress(),
      widget.audiobookRepository.loadSummaries(widget.books),
    ]);
    return _LibraryData(
      progressMap: results[0] as Map<String, ReadingProgress>,
      audiobookSummaries: results[1] as Map<String, AudiobookSummary>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReaderThemePalette palette = AppTheme.paper;
    return Scaffold(
      backgroundColor: palette.background,
      body: FutureBuilder<_LibraryData>(
        future: _libraryFuture,
        builder: (context, snapshot) {
          final Map<String, ReadingProgress> progressMap =
              snapshot.data?.progressMap ?? const {};
          final Map<String, AudiobookSummary> audiobookSummaries =
              snapshot.data?.audiobookSummaries ?? const {};
          return SafeArea(
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        child: _HeroCard(
                          palette: palette,
                          onImportRequested: widget.onImportRequested,
                        ),
                      ),
                    ),
                    if (widget.books.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.import_contacts_outlined,
                          title: '还没有导入小说',
                          description: '导入 TXT 后，可以阅读，也可以用 MiMo 朗读给你听。',
                          actionLabel: '导入 TXT',
                          onAction: widget.onImportRequested,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        sliver: SliverList.separated(
                          itemCount: widget.books.length,
                          itemBuilder: (context, index) {
                            final Book book = widget.books[index];
                            final ReadingProgress? progress =
                                progressMap[book.id];
                            final AudiobookSummary? audiobookSummary =
                                audiobookSummaries[book.id];
                            return _BookCard(
                              palette: palette,
                              book: book,
                              progress: progress,
                              audiobookSummary: audiobookSummary,
                              onReadTap: () => widget.onBookSelected(book),
                              onAudiobookTap: () =>
                                  widget.onAudiobookSelected(book),
                            );
                          },
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 14),
                        ),
                      ),
                  ],
                ),
                if (widget.isImporting)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.12),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: palette.card,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 14),
                              Text('正在导入 TXT...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.palette, required this.onImportRequested});

  final ReaderThemePalette palette;
  final Future<void> Function() onImportRequested;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [palette.card, palette.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '小龟听书',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: palette.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            '想马上听，就边读边听；想像歌词一样逐句跳播，就先生成整本 MP3。',
            style: TextStyle(
              color: palette.secondaryText,
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onImportRequested,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入 TXT'),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.palette,
    required this.book,
    required this.progress,
    required this.audiobookSummary,
    required this.onReadTap,
    required this.onAudiobookTap,
  });

  final ReaderThemePalette palette;
  final Book book;
  final ReadingProgress? progress;
  final AudiobookSummary? audiobookSummary;
  final VoidCallback onReadTap;
  final VoidCallback onAudiobookTap;

  @override
  Widget build(BuildContext context) {
    final double percent = progress?.percent ?? 0;
    final double clamped = percent.clamp(0, 100);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onReadTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: palette.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${book.paragraphCount} 段 · ${_prettyCount(book.textLength)} 字 · ${book.encoding}',
                style: TextStyle(color: palette.secondaryText, fontSize: 14),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: clamped / 100,
                  minHeight: 9,
                  backgroundColor: palette.border,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    clamped == 0 ? '还没开始' : '已读 ${clamped.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: palette.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(book.importedAt),
                    style: TextStyle(color: palette.secondaryText),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AudiobookStatusLine(palette: palette, summary: audiobookSummary),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onReadTap,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('打开阅读'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAudiobookTap,
                      icon: const Icon(Icons.lyrics_outlined),
                      label: const Text('整本听书'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _prettyCount(int value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    return '$value';
  }

  static String _formatDate(DateTime dateTime) {
    final String month = dateTime.month.toString().padLeft(2, '0');
    final String day = dateTime.day.toString().padLeft(2, '0');
    return '${dateTime.year}.$month.$day';
  }
}

class _AudiobookStatusLine extends StatelessWidget {
  const _AudiobookStatusLine({required this.palette, required this.summary});

  final ReaderThemePalette palette;
  final AudiobookSummary? summary;

  @override
  Widget build(BuildContext context) {
    final AudiobookSummary? value = summary;
    final String text = value == null
        ? '整本听书：未生成'
        : '整本听书：${_statusLabel(value)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.secondaryText,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  String _statusLabel(AudiobookSummary summary) {
    final String progress =
        '${summary.generatedSentenceCount}/${summary.totalSentenceCount} 句';
    switch (summary.status) {
      case AudiobookJobStatus.pending:
        return '未开始 · $progress';
      case AudiobookJobStatus.generating:
        return '生成中 ${(summary.progress * 100).toStringAsFixed(1)}% · $progress';
      case AudiobookJobStatus.paused:
        return '已暂停 · $progress';
      case AudiobookJobStatus.completed:
        return '可播放 · $progress';
      case AudiobookJobStatus.error:
        return '有 ${summary.failedSentenceCount} 句失败 · $progress';
    }
  }
}

class _LibraryData {
  const _LibraryData({
    required this.progressMap,
    required this.audiobookSummaries,
  });

  final Map<String, ReadingProgress> progressMap;
  final Map<String, AudiobookSummary> audiobookSummaries;
}
