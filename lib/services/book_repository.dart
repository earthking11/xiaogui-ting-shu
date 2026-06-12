import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/reader_paragraph.dart';
import 'native_file_service.dart';

class BookRepository {
  BookRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Future<List<Book>> loadBooks() async {
    final File file = await _catalogFile();
    if (!await file.exists()) {
      return <Book>[];
    }

    final dynamic decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      return <Book>[];
    }

    return decoded
        .whereType<Map>()
        .map((item) => Book.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  }

  Future<Book> importPickedFile(PickedTxtFile pickedFile) async {
    final String cleanedText = normalizeText(pickedFile.text);
    if (cleanedText.trim().isEmpty) {
      throw const FormatException('导入的 TXT 没有可用正文内容');
    }

    final List<Book> books = List<Book>.of(await loadBooks());
    final Directory booksDir = await _booksDirectory();
    final String bookId = _uuid.v4();
    final String storagePath = '${booksDir.path}/$bookId.txt';
    await File(storagePath).writeAsString(cleanedText, flush: true);

    final Book book = Book(
      id: bookId,
      title: _displayTitle(pickedFile.fileName),
      fileName: pickedFile.fileName,
      storagePath: storagePath,
      textLength: cleanedText.length,
      paragraphCount: ReaderParagraphParser.parse(cleanedText).length,
      importedAt: DateTime.now(),
      encoding: pickedFile.encoding,
      sourceSizeBytes: pickedFile.sizeBytes,
    );

    books.insert(0, book);
    await _writeCatalog(books);
    return book;
  }

  Future<String> readBookText(Book book) async {
    return File(book.storagePath).readAsString();
  }

  static String normalizeText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _displayTitle(String fileName) {
    return fileName.replaceFirst(RegExp(r'\.[^.]+$'), '').trim().isEmpty
        ? 'TXT 小说'
        : fileName.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  }

  Future<void> _writeCatalog(List<Book> books) async {
    final File file = await _catalogFile();
    await file.writeAsString(
      jsonEncode(books.map((book) => book.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _catalogFile() async {
    final Directory booksDir = await _booksDirectory();
    return File('${booksDir.path}/books.json');
  }

  Future<Directory> _booksDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory booksDir = Directory('${documents.path}/books');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }
}
