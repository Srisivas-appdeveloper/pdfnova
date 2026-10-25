import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

/// Picking, opening and sharing. Kept out of blocs so tools stay testable.
class FileService {
  FileService._();
  static final FileService instance = FileService._();

  Future<List<PickedPdf>> pickPdfs({bool multiple = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null) return [];
    final list = <PickedPdf>[];
    for (final f in result.files) {
      if (f.bytes != null) {
        list.add(PickedPdf(f.name, f.bytes!));
      } else if (f.path != null) {
        try {
          final file = File(f.path!);
          if (file.existsSync()) {
            list.add(PickedPdf(f.name, file.readAsBytesSync()));
          }
        } catch (_) {}
      }
    }
    return list;
  }

  /// Pick a single .docx file (used by Word → PDF tool).
  Future<List<PickedPdf>> pickDocx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return [];
    final list = <PickedPdf>[];
    for (final f in result.files) {
      if (f.bytes != null) {
        list.add(PickedPdf(f.name, f.bytes!));
      } else if (f.path != null) {
        try {
          final file = File(f.path!);
          if (file.existsSync()) {
            list.add(PickedPdf(f.name, file.readAsBytesSync()));
          }
        } catch (_) {}
      }
    }
    return list;
  }

  Future<List<Uint8List>> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return [];
    final list = <Uint8List>[];
    for (final f in result.files) {
      if (f.bytes != null) {
        list.add(f.bytes!);
      } else if (f.path != null) {
        try {
          final file = File(f.path!);
          if (file.existsSync()) {
            list.add(file.readAsBytesSync());
          }
        } catch (_) {}
      }
    }
    return list;
  }

  Future<void> open(String path) => OpenFilex.open(path, type: _mimeFor(path));

  static String? _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    } else if (p.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    } else if (p.endsWith('.pdf')) {
      return 'application/pdf';
    } else if (p.endsWith('.txt')) {
      return 'text/plain';
    } else if (p.endsWith('.jpg') || p.endsWith('.jpeg')) {
      return 'image/jpeg';
    } else if (p.endsWith('.png')) {
      return 'image/png';
    }
    return null;
  }

  static const _downloadsChannel = MethodChannel('pdfnova/downloads');

  /// Save file to the public Download/PDFNova folder on device.
  /// Android 10+ blocks direct writes there (scoped storage), so the copy
  /// runs natively through MediaStore (see MainActivity). Returns a
  /// human-readable location label.
  Future<String> saveToDownloads(String srcPath) async {
    final fileName = srcPath.split('/').last;
    if (Platform.isAndroid) {
      try {
        final saved = await _downloadsChannel.invokeMethod<String>(
          'saveToDownloads',
          {
            'srcPath': srcPath,
            'fileName': fileName,
            'mime': _mimeFor(srcPath) ?? 'application/octet-stream',
          },
        );
        if (saved != null) return saved; // "Download/PDFNova/<name>"
      } catch (_) {
        // fall through to the app-specific copy below
      }
      final dir = await getExternalStorageDirectory();
      final dest = '${dir!.path}/$fileName';
      await File(srcPath).copy(dest);
      return dest;
    }
    final targetDir = await getApplicationDocumentsDirectory();
    final destPath = '${targetDir.path}/$fileName';
    await File(srcPath).copy(destPath);
    return destPath;
  }

  /// Persist picked bytes to a temp file (WiFi share serves from disk).
  Future<String> persistTemp(PickedPdf f) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${f.name}';
    await File(path).writeAsBytes(f.bytes, flush: true);
    return path;
  }

  // ---- Generated-output management ---------------------------------------

  /// True when [path] is a file the app generated inside its own storage
  /// (the PDFNova output folder or saved Notes). Only such files may be
  /// renamed or deleted from the Files tab; anything else can only be
  /// removed from the history list, never touched on disk.
  Future<bool> isAppOutput(String path) async {
    final docs = (await getApplicationDocumentsDirectory()).absolute.path;
    final abs = File(path).absolute.path;
    if (abs.contains('/../')) return false;
    return abs.startsWith('$docs/PDFNova/') ||
        (abs.startsWith('$docs/') &&
            !abs.substring(docs.length + 1).contains('/') &&
            abs.contains('_Note_'));
  }

  /// Deletes a generated output. Refuses (returns false) for files outside
  /// app storage. Missing files count as already deleted.
  Future<bool> deleteOutput(String path) async {
    if (!await isAppOutput(path)) return false;
    final f = File(path);
    if (f.existsSync()) await f.delete();
    return true;
  }

  /// Renames a generated output in place, keeping its extension. Returns the
  /// new path. Throws [FileSystemException] if the name is taken, and
  /// [ArgumentError] for empty names or files outside app storage.
  Future<String> renameOutput(String path, String newBaseName) async {
    if (!await isAppOutput(path)) {
      throw ArgumentError('Only files created by PDF Nova can be renamed.');
    }
    final clean = newBaseName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    if (clean.isEmpty) throw ArgumentError('Name cannot be empty.');
    final src = File(path);
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot) : '';
    final dir = path.substring(0, path.length - name.length);
    final dest = '$dir$clean$ext';
    if (dest == path) return path;
    if (File(dest).existsSync()) {
      throw FileSystemException('A file with that name already exists', dest);
    }
    await src.rename(dest);
    return dest;
  }

  Future<void> share(String path) =>
      Share.shareXFiles([XFile(path)], text: 'Made with PDF Nova');

  Future<void> shareAll(List<String> paths) =>
      Share.shareXFiles([for (final p in paths) XFile(p)],
          text: 'Made with PDF Nova');
}

class PickedPdf {
  PickedPdf(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  String get sizeLabel {
    final kb = bytes.length / 1024;
    return kb > 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.toStringAsFixed(0)} KB';
  }
}
