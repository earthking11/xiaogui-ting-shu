import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/book.dart';
import '../../models/reading_progress.dart';
import '../../services/settings_repository.dart';
import '../../widgets/empty_state.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.books,
    required this.isImporting,
    required this.settingsRepository,
    required this.onImportRequested,
    required this.onBookSelected,
  });

  final List<Book> books;
  final bool isImporting;
  final SettingsRepository settingsRepository;
  final Future<void> Function() onImportRequested;
  final ValueChanged<Book> onBookSelected;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<Map<String, ReadingProgress>> _progressFuture = _loadProgress();

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books != widget.books) {
      _progressFuture = _loadProgress();
    }
  }

  Future<Map<String, ReadingProgress>> _loadProgress() {
    return widget.settingsRepository.loadAllProgress();
  }

  @override
  Widget build(BuildContext context) {
    final ReaderThemePalette palette = AppTheme.paper;
    return Scaffold(
      backgroundColor: palette.background,
      body: FutureBuilder<Map<String, ReadingProgress>>(
        future: _progressFuture,
        builder: (context, snapshot) {
          final Map<String, ReadingProgress> progressMap =
              snapshot.data ?? const {};
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
                            return _BookCard(
                              palette: palette,
                              book: book,
                              progress: progress,
                              onTap: () => widget.onBookSelected(book),
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
            '把界面收安静一点，把故事交还给文字。你读累了，也可以让 MiMo 接着念。',
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
    required this.onTap,
  });

  final ReaderThemePalette palette;
  final Book book;
  final ReadingProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double percent = progress?.percent ?? 0;
    final double clamped = percent.clamp(0, 100);
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
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
