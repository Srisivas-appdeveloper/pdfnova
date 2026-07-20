import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// One slide of a .pptx, ready to display.
class PptSlide {
  const PptSlide({this.imageBytes, this.text = ''});
  final Uint8List? imageBytes; // full-slide picture (PDF Nova exports)
  final String text;           // fallback: extracted slide text
}

/// Minimal offline .pptx reader for the in-app viewer.
///
/// A .pptx is a ZIP: slides live at ppt/slides/slideN.xml, each slide's
/// pictures at ppt/media/*, wired together by per-slide .rels files.
/// We resolve <a:blip r:embed> → media bytes; when a slide carries no
/// picture (presentations made elsewhere) we fall back to its <a:t> text.
class PptxReader {
  PptxReader._();

  static List<PptSlide> read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{
      for (final f in archive.files) f.name: f,
    };

    // Slide part names, ordered numerically (slide2 < slide10).
    final slideNames = files.keys
        .where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n))
        .toList()
      ..sort((a, b) => _num(a).compareTo(_num(b)));

    final slides = <PptSlide>[];
    for (final name in slideNames) {
      final xml = _asString(files[name]);
      final idx = _num(name);

      // rId → target media path for this slide.
      final rels = <String, String>{};
      final relsXml = _asString(files['ppt/slides/_rels/slide$idx.xml.rels']);
      if (relsXml != null) {
        for (final m in RegExp(
                '<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"')
            .allMatches(relsXml)) {
          rels[m.group(1)!] = m.group(2)!;
        }
      }

      // First embedded picture on the slide.
      Uint8List? image;
      final blip =
          RegExp(r'<a:blip[^>]*r:embed="([^"]+)"').firstMatch(xml ?? '');
      final target = blip == null ? null : rels[blip.group(1)];
      if (target != null) {
        // Targets are relative to ppt/slides/ ("../media/image1.jpeg").
        final mediaPath = target.startsWith('../')
            ? 'ppt/${target.substring(3)}'
            : 'ppt/slides/$target';
        final data = files[mediaPath];
        if (data != null) {
          image = Uint8List.fromList(data.content as List<int>);
        }
      }

      // Text fallback (and useful even alongside images).
      final runs = RegExp(r'<a:t>(.*?)</a:t>', dotAll: true)
          .allMatches(xml ?? '')
          .map((m) => _unescape(m.group(1)!))
          .where((s) => s.trim().isNotEmpty)
          .toList();

      slides.add(PptSlide(imageBytes: image, text: runs.join('\n')));
    }
    return slides;
  }

  static int _num(String slideName) =>
      int.parse(RegExp(r'(\d+)').firstMatch(slideName)!.group(1)!);

  static String? _asString(ArchiveFile? f) =>
      f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
