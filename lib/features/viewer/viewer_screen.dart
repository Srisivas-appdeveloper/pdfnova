import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../core/widgets/nova_entrance.dart';
import '../tool/pick_zone.dart';
import '../tool/tool_header.dart';
import '../../services/file_service.dart';
import '../../services/ocr_service.dart';
import '../home/tools.dart';

/// Reader: PDFium-rendered viewer with night mode and human-like multilingual
/// text-to-speech supporting Tamil, Hindi, English, Telugu, Malayalam, Kannada & more.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen(
      {super.key, required this.tool, this.initialPath, this.initialPage = 1});
  final Tool tool;

  /// Open this file directly (e.g. from a content-search hit)…
  final String? initialPath;

  /// …at this 1-based page.
  final int initialPage;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  px.PdfControllerPinch? _controller;
  Uint8List? _bytes;
  final _tts = FlutterTts();
  bool _night = false;
  bool _speaking = false;
  int _page = 1;
  double _speechRate = 0.44; // Relaxed natural reading pace
  final double _speechPitch = 1.0; // Natural human voice pitch
  String? _selectedLanguageCode; // null = Auto-detect
  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoiceMap;

  static const Map<String, String> _languages = {
    'Auto (Smart Detect)': 'auto',
    'Tamil (தமிழ்)': 'ta-IN',
    'Hindi (हिंदी)': 'hi-IN',
    'English (India)': 'en-IN',
    'English (US)': 'en-US',
    'Telugu (తెలుగు)': 'te-IN',
    'Malayalam (മലയാളം)': 'ml-IN',
    'Kannada (ಕನ್ನಡ)': 'kn-IN',
    'Spanish (Español)': 'es-ES',
    'French (Français)': 'fr-FR',
  };

  @override
  void initState() {
    super.initState();
    final path = widget.initialPath;
    if (path != null && File(path).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _open(File(path).readAsBytesSync(), page: widget.initialPage));
    }
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      if (Platform.isAndroid) {
        await _tts.setEngine("com.google.android.tts");
      }
      final dynamic voices = await _tts.getVoices;
      if (voices is List) {
        _availableVoices = voices
            .whereType<Map>()
            .map((v) => {
                  'name': v['name'].toString(),
                  'locale': v['locale'].toString(),
                })
            .toList();
      }
    } catch (_) {}
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_speechPitch);
    await _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _tts.stop();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FileService.instance.pickPdfs();
    if (picked.isEmpty) return;
    _open(picked.first.bytes);
  }

  void _open(Uint8List bytes, {int page = 1}) {
    _bytes = bytes;
    setState(() {
      _page = page;
      _controller = px.PdfControllerPinch(
          document: px.PdfDocument.openData(bytes), initialPage: page);
    });
  }

  String _detectLanguage(String text) {
    if (_selectedLanguageCode != null && _selectedLanguageCode != 'auto') {
      return _selectedLanguageCode!;
    }
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta-IN'; // Tamil
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi-IN'; // Hindi
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'te-IN'; // Telugu
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'ml-IN'; // Malayalam
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kn-IN'; // Kannada
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(text)) return 'bn-IN'; // Bengali
    if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(text)) return 'gu-IN'; // Gujarati
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar'; // Arabic
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return 'zh-CN'; // Chinese
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) return 'ja-JP'; // Japanese
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'ru-RU'; // Russian
    if (RegExp(r'[áéíóúñ¿¡]', caseSensitive: false).hasMatch(text)) {
      return 'es-ES'; // Spanish
    }
    return 'en-IN'; // Default English
  }

  Future<void> _applyVoiceSettingsAndRestart() async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) _toggleSpeak();
    }
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }

    if (_bytes == null) return;

    // 1. Extract text from PDF page
    final doc = sf.PdfDocument(inputBytes: _bytes!);
    var text = sf.PdfTextExtractor(doc)
        .extractText(startPageIndex: _page - 1, endPageIndex: _page - 1);
    doc.dispose();

    // 2. OCR fallback if scanned image page
    if (text.trim().length < 5) {
      try {
        final ocrPages = await OcrService.instance.ocrPdfToPageTexts(_bytes!);
        if (_page <= ocrPages.length) {
          text = ocrPages[_page - 1];
        }
      } catch (_) {}
    }

    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No readable text found on this page.')));
      }
      return;
    }

    // 3. Configure natural human voice
    final lang = _detectLanguage(text);

    try {
      await _tts.setLanguage(lang);

      if (_selectedVoiceMap != null) {
        await _tts.setVoice({
          'name': _selectedVoiceMap!['name']!,
          'locale': _selectedVoiceMap!['locale']!,
        });
      } else if (_availableVoices.isNotEmpty) {
        final langPrefix = lang.split('-').first.toLowerCase();
        final matching = _availableVoices.where((v) {
          final loc = v['locale']?.toLowerCase().replaceAll('_', '-') ?? '';
          return loc.contains(langPrefix);
        }).toList();

        if (matching.isNotEmpty) {
          final chosenVoice = matching.firstWhere(
            (v) {
              final n = v['name']?.toLowerCase() ?? '';
              return n.contains('network') ||
                  n.contains('female') ||
                  n.contains('end') ||
                  n.contains('tap') ||
                  n.contains('sfg') ||
                  n.contains('hie') ||
                  n.contains('tpf');
            },
            orElse: () => matching.first,
          );

          await _tts.setVoice({
            'name': chosenVoice['name']!,
            'locale': chosenVoice['locale']!,
          });
        }
      }
    } catch (_) {}

    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_speechPitch);

    setState(() => _speaking = true);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });

    await _tts.speak(text);
  }

  void _showSettingsSheet() {
    showNovaSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final c = context.nova;
          final t = Theme.of(context).textTheme;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voice', style: t.headlineMedium),
                  const SizedBox(height: 18),
                  Text('Language', style: t.labelMedium),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _languages.entries)
                      NovaChip(
                        label: e.key,
                        selected: (_selectedLanguageCode ?? 'auto') == e.value,
                        onTap: () {
                          setState(() => _selectedLanguageCode =
                              e.value == 'auto' ? null : e.value);
                          setSheetState(() {});
                          _applyVoiceSettingsAndRestart();
                        },
                      ),
                  ]),
                  const SizedBox(height: 24),
                  Row(children: [
                    Text('Reading speed', style: t.labelMedium),
                    const Spacer(),
                    Text('${(_speechRate * 2.2).toStringAsFixed(1)}×',
                        style: t.titleMedium?.copyWith(color: c.accent)),
                  ]),
                  Slider(
                    value: _speechRate,
                    min: 0.3,
                    max: 0.7,
                    onChanged: (val) {
                      setState(() => _speechRate = val);
                      setSheetState(() {});
                      _tts.setSpeechRate(val);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  static const _invert = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final pages = _controller?.pagesCount;
    return Scaffold(
      backgroundColor: _controller == null ? c.canvas : c.surfaceAlt,
      appBar: AppBar(
        backgroundColor: _controller == null ? c.canvas : c.surfaceAlt,
        title: _controller == null ? null : Text(widget.tool.title),
      ),
      body: _controller == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                ToolHeader(tool: widget.tool),
                PickZone(
                  icon: Icons.menu_book_outlined,
                  title: 'Open a PDF',
                  hint: 'Pinch to zoom · night mode · read aloud',
                  onTap: _pick,
                ).enter(context, delayMs: 200),
              ],
            )
          : Stack(children: [
              // Night mode eases between normal and inverted colours.
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _night ? 1 : 0),
                  duration: NovaMotion.page,
                  curve: NovaMotion.emphasized,
                  builder: (_, v, child) => ColorFiltered(
                    colorFilter: ColorFilter.matrix([
                      for (var i = 0; i < 20; i++)
                        _identity[i] + (_invert[i] - _identity[i]) * v,
                    ]),
                    child: child,
                  ),
                  child: px.PdfViewPinch(
                    controller: _controller!,
                    onPageChanged: (p) => setState(() => _page = p),
                    onDocumentLoaded: (_) => setState(() {}),
                  ),
                ),
              ),
              // Floating control pill.
              Positioned(
                left: 0,
                right: 0,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(pages == null ? '$_page' : '$_page / $pages',
                          style: t.labelLarge),
                      const SizedBox(width: 10),
                      NovaIconButton(
                        tooltip: _speaking ? 'Stop reading' : 'Read aloud',
                        icon: _speaking
                            ? Icons.stop_rounded
                            : Icons.volume_up_outlined,
                        active: _speaking,
                        onPressed: _toggleSpeak,
                      ),
                      NovaIconButton(
                        tooltip: 'Voice settings',
                        icon: Icons.tune_rounded,
                        onPressed: _showSettingsSheet,
                      ),
                      NovaIconButton(
                        tooltip: _night ? 'Day mode' : 'Night mode',
                        icon: _night
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        active: _night,
                        onPressed: () => setState(() => _night = !_night),
                      ),
                    ]),
                  ),
                ).enter(context, delayMs: 300),
              ),
            ]),
    );
  }
}
