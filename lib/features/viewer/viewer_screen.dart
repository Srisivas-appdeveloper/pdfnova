import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../../services/ocr_service.dart';
import '../home/tools.dart';

/// Reader: PDFium-rendered viewer with night mode and human-like multilingual
/// text-to-speech supporting Tamil, Hindi, English, Telugu, Malayalam, Kannada & more.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.tool});
  final Tool tool;

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
    _bytes = picked.first.bytes;
    setState(() {
      _controller = px.PdfControllerPinch(
          document: px.PdfDocument.openData(_bytes!));
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
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar';    // Arabic
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return 'zh-CN'; // Chinese
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) return 'ja-JP'; // Japanese
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'ru-RU'; // Russian
    if (RegExp(r'[áéíóúñ¿¡]', caseSensitive: false).hasMatch(text)) return 'es-ES'; // Spanish
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => GlassCard(
          radius: 24,
          strong: true,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Voice & Language Settings',
                        style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Language / accent',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguageCode ?? 'auto',
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E2E),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      items: _languages.entries
                          .map((e) => DropdownMenuItem(
                                value: e.value,
                                child: Text(e.key),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedLanguageCode = val == 'auto' ? null : val);
                        setSheetState(() {});
                        _applyVoiceSettingsAndRestart();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Reading Speed',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text('${(_speechRate * 2.2).toStringAsFixed(1)}x',
                        style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _speechRate,
                  min: 0.3,
                  max: 0.7,
                  activeColor: AppColors.cyan,
                  onChanged: (val) {
                    setState(() => _speechRate = val);
                    setSheetState(() {});
                    _tts.setSpeechRate(val);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.tool.title),
          actions: [
            if (_controller != null) ...[
              IconButton(
                icon: Icon(
                    _speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_rounded,
                    color: AppColors.cyan),
                onPressed: _toggleSpeak,
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppColors.cyan),
                onPressed: _showSettingsSheet,
              ),
              IconButton(
                icon: Icon(
                    _night
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: AppColors.cyan),
                onPressed: () => setState(() => _night = !_night),
              ),
            ],
          ],
        ),
        body: _controller == null
            ? Center(
                child: GlassCard(
                  frosted: true,
                  strong: true,
                  onTap: _pick,
                  padding: const EdgeInsets.symmetric(
                      vertical: 40, horizontal: 40),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.menu_book_rounded,
                        color: AppColors.cyan, size: 40),
                    const SizedBox(height: 12),
                    Text('Open a PDF',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                ),
              )
            : ColorFiltered(
                colorFilter: _night
                    ? const ColorFilter.matrix([
                        -1, 0, 0, 0, 255, //
                        0, -1, 0, 0, 255, //
                        0, 0, -1, 0, 255, //
                        0, 0, 0, 1, 0,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent, BlendMode.dst),
                child: px.PdfViewPinch(
                  controller: _controller!,
                  onPageChanged: (p) => _page = p,
                ),
              ),
      ),
    );
  }
}
