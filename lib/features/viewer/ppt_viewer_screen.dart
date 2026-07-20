import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../../services/pptx_reader.dart';

/// In-app PowerPoint viewer — opens .pptx without needing PowerPoint/WPS
/// installed. Slides made by PDF Nova render as full-page images (pinch to
/// zoom); foreign decks fall back to extracted slide text.
class PptViewerScreen extends StatefulWidget {
  const PptViewerScreen({super.key, required this.path});
  final String path;

  @override
  State<PptViewerScreen> createState() => _PptViewerScreenState();
}

class _PptViewerScreenState extends State<PptViewerScreen> {
  final _pages = PageController();
  List<PptSlide>? _slides;
  String? _error;
  int _page = 0;

  String get _name => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final slides = PptxReader.read(bytes);
      if (!mounted) return;
      if (slides.isEmpty) {
        setState(() => _error = 'No slides found in this file.');
      } else {
        setState(() => _slides = slides);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open this presentation.');
      }
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final where = await FileService.instance.saveToDownloads(widget.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved to $where')));
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              tooltip: 'Save to Downloads',
              icon: const Icon(Icons.download_rounded, size: 22),
              onPressed: _save,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              onPressed: () => FileService.instance.share(widget.path),
            ),
          ],
        ),
        body: _error != null
            ? _ErrorView(message: _error!)
            : _slides == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan))
                : Column(children: [
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _slides!.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) =>
                            _SlideView(slide: _slides![i], number: i + 1),
                      ),
                    ),
                    _NavBar(
                      page: _page,
                      total: _slides!.length,
                      onPrev: _page > 0
                          ? () => _pages.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut)
                          : null,
                      onNext: _page < _slides!.length - 1
                          ? () => _pages.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut)
                          : null,
                    ),
                  ]),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.number});
  final PptSlide slide;
  final int number;

  @override
  Widget build(BuildContext context) {
    final image = slide.imageBytes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: image != null
              ? InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(image, fit: BoxFit.contain),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: slide.text.isEmpty
                        ? Text('Slide $number — no content',
                            style: TextStyle(color: AppColors.textLow))
                        : SelectableText(slide.text,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(height: 1.5)),
                  ),
                ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar(
      {required this.page,
      required this.total,
      required this.onPrev,
      required this.onNext});
  final int page;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: GlassCard(
        strong: true,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: Colors.white,
              disabledColor: AppColors.textLow,
              onPressed: onPrev,
            ),
            Text('Slide ${page + 1} of $total',
                style: Theme.of(context).textTheme.titleSmall),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              color: Colors.white,
              disabledColor: AppColors.textLow,
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, size: 52, color: AppColors.textLow),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ),
    );
  }
}
