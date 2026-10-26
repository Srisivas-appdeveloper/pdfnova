import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'tool_errors.dart';

/// One page of indexed text.
class IndexedPage {
  const IndexedPage(this.page, this.text);
  final int page;
  final String text;
}

/// Index record for one document (see docs/INTELLIGENCE_FOUNDATION.md).
class IndexedDocument {
  const IndexedDocument({
    required this.path,
    required this.fingerprint,
    required this.indexedAt,
    required this.pages,
  });

  final String path;

  /// SHA-256 of the file bytes — detects changes and replacements.
  final String fingerprint;
  final DateTime indexedAt;
  final List<IndexedPage> pages;

  /// Pages with (almost) no text, e.g. scans — not searchable.
  int get unsearchablePages =>
      pages.where((p) => p.text.trim().length < 15).length;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'path': path,
        'fp': fingerprint,
        'at': indexedAt.toIso8601String(),
        'pages': [
          for (final p in pages) {'n': p.page, 't': p.text}
        ],
      };

  static IndexedDocument fromJson(Map<String, dynamic> j) => IndexedDocument(
        path: j['path'] as String,
        fingerprint: j['fp'] as String,
        indexedAt: DateTime.parse(j['at'] as String),
        pages: [
          for (final p in (j['pages'] as List).cast<Map>())
            IndexedPage((p['n'] as num).toInt(), p['t'] as String)
        ],
      );
}

/// A content match: which document, which page, and the text around it.
class SearchHit {
  const SearchHit({
    required this.path,
    required this.page,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
  });
  final String path;
  final int page;
  final String snippet;

  /// Position of the match inside [snippet] (for highlighting).
  final int matchStart;
  final int matchLength;
}

/// Local, opt-in full-text index of files PDF Nova created.
///
/// - Lives in app-private support storage (`<support>/content_index/`), one
///   JSON file per document, named by a hash of its path.
/// - Text comes from each page's text layer (no OCR — scanned pages are
///   reported as not searchable instead of silently missing).
/// - Never indexes the vault: only paths passed in from output history.
/// - [clear] deletes everything; [remove] drops one document.
class DocumentIndex {
  DocumentIndex({Future<Directory> Function()? dir})
      : _dir = dir ?? _defaultDir;

  static final DocumentIndex instance = DocumentIndex();

  final Future<Directory> Function() _dir;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/content_index')..createSync(recursive: true);
  }

  static Future<String> _hash(List<int> bytes) async =>
      base64Url.encode((await Sha256().hash(bytes)).bytes).replaceAll('=', '');

  Future<File> _fileFor(String path) async =>
      File('${(await _dir()).path}/${await _hash(utf8.encode(path))}.json');

  /// Indexes (or re-indexes, if the file changed) one PDF. Returns null
  /// for non-PDFs and unreadable/locked files — they are simply skipped.
  Future<IndexedDocument?> indexFile(String path) async {
    if (!path.toLowerCase().endsWith('.pdf')) return null;
    final f = File(path);
    if (!f.existsSync()) {
      await remove(path);
      return null;
    }
    final bytes = await f.readAsBytes();
    final fp = await _hash(bytes);
    final existing = await read(path);
    if (existing != null && existing.fingerprint == fp) return existing;

    // Parsing is CPU-heavy: keep it off the UI isolate.
    final pages = await Isolate.run(() => _extractPages(bytes));
    if (pages == null) return null;
    final doc = IndexedDocument(
        path: path, fingerprint: fp, indexedAt: DateTime.now(), pages: pages);
    await writeAtomic(
        (await _fileFor(path)).path, utf8.encode(jsonEncode(doc.toJson())));
    return doc;
  }

  static List<IndexedPage>? _extractPages(Uint8List bytes) {
    try {
      final pdf = PdfDocument(inputBytes: bytes);
      final ex = PdfTextExtractor(pdf);
      final out = <IndexedPage>[];
      for (var i = 0; i < pdf.pages.count; i++) {
        var text = '';
        try {
          // Line extraction: plain extractText() mis-decodes after font
          // switches (see DocumentTextService).
          text = ex
              .extractTextLines(startPageIndex: i, endPageIndex: i)
              .map((l) => l.text)
              .join('\n');
        } catch (_) {}
        out.add(IndexedPage(i + 1, text));
      }
      pdf.dispose();
      return out;
    } catch (_) {
      return null; // damaged or password-protected
    }
  }

  Future<IndexedDocument?> read(String path) async {
    final f = await _fileFor(path);
    if (!f.existsSync()) return null;
    try {
      return IndexedDocument.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt index entry — treated as not indexed
    }
  }

  Future<void> remove(String path) async {
    final f = await _fileFor(path);
    if (f.existsSync()) await f.delete();
  }

  /// Deletes all indexed content (used when indexing is turned off).
  Future<void> clear() async {
    final d = await _dir();
    if (d.existsSync()) await d.delete(recursive: true);
  }

  Future<List<IndexedDocument>> all() async {
    final d = await _dir();
    final out = <IndexedDocument>[];
    for (final f in d.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        out.add(IndexedDocument.fromJson(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  /// Brings the index in line with [paths] (the output history): indexes
  /// new or changed PDFs, drops documents no longer listed or missing.
  Future<({int indexed, int removed})> sync(Iterable<String> paths) async {
    final wanted = {
      for (final p in paths)
        if (p.toLowerCase().endsWith('.pdf')) p
    };
    var removed = 0;
    for (final doc in await all()) {
      if (!wanted.contains(doc.path) || !File(doc.path).existsSync()) {
        await remove(doc.path);
        removed++;
      }
    }
    var indexed = 0;
    for (final p in wanted) {
      if (await indexFile(p) != null) indexed++;
    }
    return (indexed: indexed, removed: removed);
  }

  /// Case-insensitive search across [docs] (or the whole index). Returns at
  /// most [perDocument] hits per document, in page order.
  Future<List<SearchHit>> search(String query,
      {List<IndexedDocument>? docs, int perDocument = 3}) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final hits = <SearchHit>[];
    for (final doc in docs ?? await all()) {
      var n = 0;
      for (final page in doc.pages) {
        final text = page.text.replaceAll(RegExp(r'\s+'), ' ');
        final at = text.toLowerCase().indexOf(q);
        if (at < 0) continue;
        final from = (at - 40).clamp(0, text.length);
        final to = (at + q.length + 60).clamp(0, text.length);
        final prefix = from > 0 ? '…' : '';
        hits.add(SearchHit(
          path: doc.path,
          page: page.page,
          snippet:
              '$prefix${text.substring(from, to)}${to < text.length ? '…' : ''}',
          matchStart: prefix.length + at - from,
          matchLength: q.length,
        ));
        if (++n >= perDocument) break;
      }
    }
    return hits;
  }
}
