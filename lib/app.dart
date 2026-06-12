import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
import 'core/constants.dart';
import 'features/library/library_page.dart';
import 'features/reader/reader_page.dart';
import 'models/book.dart';
import 'models/reading_progress.dart';
import 'services/book_repository.dart';
import 'services/mimo_tts_api_client.dart';
import 'services/native_file_service.dart';
import 'services/secure_key_store.dart';
import 'services/settings_repository.dart';
import 'services/tts_cache_store.dart';

class AppServices {
  const AppServices({
    required this.bookRepository,
    required this.settingsRepository,
    required this.nativeFileService,
    required this.keyStore,
    required this.apiClient,
    required this.cacheStore,
  });

  final BookRepository bookRepository;
  final SettingsRepository settingsRepository;
  final NativeFileService nativeFileService;
  final SecureKeyStore keyStore;
  final MimoTtsApiClient apiClient;
  final TtsCacheStore cacheStore;
}

class AppSnapshot {
  const AppSnapshot({required this.books, required this.initialBook});

  final List<Book> books;
  final Book? initialBook;
}

class NovelTtsReaderBootstrap extends StatefulWidget {
  const NovelTtsReaderBootstrap({super.key});

  @override
  State<NovelTtsReaderBootstrap> createState() =>
      _NovelTtsReaderBootstrapState();
}

class _NovelTtsReaderBootstrapState extends State<NovelTtsReaderBootstrap> {
  late final AppServices _services = AppServices(
    bookRepository: BookRepository(),
    settingsRepository: SettingsRepository(),
    nativeFileService: NativeFileService(),
    keyStore: SecureKeyStore(),
    apiClient: MimoTtsApiClient(),
    cacheStore: TtsCacheStore(),
  );

  late final Future<AppSnapshot> _bootstrapFuture = _bootstrap();

  Future<AppSnapshot> _bootstrap() async {
    await _services.cacheStore.cleanupStale();
    final List<Book> books = await _services.bookRepository.loadBooks();
    final String? lastBookId = await _services.settingsRepository
        .loadLastBookId();
    final Book? candidate = books.cast<Book?>().firstWhere(
      (book) => book?.id == lastBookId,
      orElse: () => null,
    );
    final ReadingProgress? progress = candidate == null
        ? null
        : await _services.settingsRepository.loadReadingProgress(candidate.id);
    return AppSnapshot(
      books: books,
      initialBook: progress == null ? null : candidate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSnapshot>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.buildAppTheme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return NovelTtsReaderApp(
          services: _services,
          snapshot:
              snapshot.data ?? const AppSnapshot(books: [], initialBook: null),
        );
      },
    );
  }
}

class NovelTtsReaderApp extends StatefulWidget {
  const NovelTtsReaderApp({
    super.key,
    required this.services,
    required this.snapshot,
  });

  final AppServices services;
  final AppSnapshot snapshot;

  @override
  State<NovelTtsReaderApp> createState() => _NovelTtsReaderAppState();
}

class _NovelTtsReaderAppState extends State<NovelTtsReaderApp> {
  late List<Book> _books;
  Book? _currentBook;
  bool _importing = false;
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _books = [...widget.snapshot.books];
    _currentBook = widget.snapshot.initialBook;
    widget.services.nativeFileService.setSharedTxtListener(_importSharedBook);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeInitialSharedBook());
    });
  }

  @override
  void dispose() {
    widget.services.nativeFileService.clearSharedTxtListener();
    super.dispose();
  }

  Future<void> _importBook() async {
    setState(() => _importing = true);
    try {
      final pickedFile = await widget.services.nativeFileService.pickTxtFile();
      if (pickedFile == null) {
        return;
      }

      await _finishImport(pickedFile, fromShare: false);
    } on FormatException catch (error) {
      _showSnackBar(error.message);
    } on PlatformException catch (error) {
      _showSnackBar(error.message ?? '导入失败，请换一个 TXT 再试试。');
    } on Exception {
      _showSnackBar('导入失败，请换一个 TXT 再试试。');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _consumeInitialSharedBook() async {
    try {
      final PickedTxtFile? pickedFile = await widget.services.nativeFileService
          .consumeSharedTxtFile();
      if (pickedFile != null) {
        await _importSharedBook(pickedFile);
      }
    } on PlatformException catch (error) {
      _showSnackBar(error.message ?? '读取分享的 TXT 失败。');
    } on Exception {
      _showSnackBar('读取分享的 TXT 失败。');
    }
  }

  Future<void> _importSharedBook(PickedTxtFile pickedFile) async {
    if (!mounted) {
      return;
    }

    setState(() => _importing = true);
    try {
      await _finishImport(pickedFile, fromShare: true);
    } on FormatException catch (error) {
      _showSnackBar(error.message);
    } on PlatformException catch (error) {
      _showSnackBar(error.message ?? '读取分享的 TXT 失败。');
    } on Exception {
      _showSnackBar('读取分享的 TXT 失败。');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _finishImport(
    PickedTxtFile pickedFile, {
    required bool fromShare,
  }) async {
    final Book book = await widget.services.bookRepository.importPickedFile(
      pickedFile,
    );
    final List<Book> books = await widget.services.bookRepository.loadBooks();
    await widget.services.settingsRepository.saveLastBookId(book.id);

    if (!mounted) {
      return;
    }

    setState(() {
      _books = books;
      _currentBook = book;
    });

    final String successMessage = fromShare
        ? '已从分享导入《${book.title}》'
        : '已导入《${book.title}》';
    String? importNote;
    if (pickedFile.sizeBytes >= AppConstants.importSizeWarningBytes) {
      importNote = '文件较大，首次整理内容可能会稍慢一点。';
    } else if (pickedFile.encoding.toLowerCase() == 'gb18030') {
      importNote = '已用 GB18030 解码导入这本书。';
    }
    _showSnackBar(
      importNote == null ? successMessage : '$successMessage\n$importNote',
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState? messenger = _messengerKey.currentState;
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildAppTheme(),
      home: _currentBook == null
          ? LibraryPage(
              books: _books,
              isImporting: _importing,
              settingsRepository: widget.services.settingsRepository,
              onImportRequested: _importBook,
              onBookSelected: (book) => setState(() => _currentBook = book),
            )
          : ReaderPage(
              key: ValueKey(_currentBook!.id),
              book: _currentBook!,
              bookRepository: widget.services.bookRepository,
              settingsRepository: widget.services.settingsRepository,
              keyStore: widget.services.keyStore,
              apiClient: widget.services.apiClient,
              cacheStore: widget.services.cacheStore,
              onBackToLibrary: () => setState(() => _currentBook = null),
            ),
    );
  }
}
