import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_controls.dart';
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
    return Scaffold(
        backgroundColor: context.nova.canvas,
        appBar: AppBar(
          title: Text(_name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          actions: [
            NovaIconButton(
              tooltip: 'Save to Downloads',
              icon: Icons.download_rounded,
              onPressed: _save,
            ),
            NovaIconButton(
              tooltip: 'Share',
              icon: Icons.ios_share_rounded,
              onPressed: () => FileService.instance.share(widget.path),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _error != null
            ? _ErrorView(message: _error!)
            : _slides == null
                ? const Center(child: CircularProgressIndicator())
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
                              duration: NovaMotion.medium,
                              curve: NovaMotion.emphasized)
                          : null,
                      onNext: _page < _slides!.length - 1
                          ? () => _pages.nextPage(
                              duration: NovaMotion.medium,
                              curve: NovaMotion.emphasized)
                          : null,
                    ),
                  ]),
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
          color: context.nova.surfaceAlt,
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
                            style: TextStyle(color: context.nova.inkLow))
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
    final c = context.nova;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(children: [
          NovaIconButton(
              tooltip: 'Previous slide',
              icon: Icons.arrow_back_rounded,
              onPressed: onPrev),
          Expanded(
            child: Column(children: [
              Text('Slide ${page + 1} of $total',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: total == 0 ? 0 : (page + 1) / total),
                  duration: NovaMotion.medium,
                  curve: NovaMotion.emphasized,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    backgroundColor: c.surfaceAlt,
                  ),
                ),
              ),
            ]),
          ),
          NovaIconButton(
              tooltip: 'Next slide',
              icon: Icons.arrow_forward_rounded,
              onPressed: onNext),
        ]),
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
          Icon(Icons.broken_image_outlined, size: 52, color: context.nova.inkLow),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ),
    );
  }
}
