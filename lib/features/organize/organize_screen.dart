import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../../services/raster_service.dart';
import '../home/tools.dart';
import '../tool/tool_bloc.dart';
import '../tool/processing_view.dart';
import '../tool/success_view.dart';

/// Pages tool: long-press-drag to reorder, tap rotate, swipe-style delete.
/// Thumbnails render once via PDFium then the list is pure state.
class OrganizeScreen extends StatelessWidget {
  const OrganizeScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(tool.title)),
          body: BlocConsumer<ToolBloc, ToolState>(
            listener: (context, state) {
              if (state is ToolFailure) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
            builder: (context, state) => PopScope(
              canPop: state is! ToolProcessing,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: switch (state) {
                  ToolProcessing s => ProcessingView(
                      key: const ValueKey('p'),
                      progress: s.progress,
                      label: 'Rebuilding your PDF'),
                  ToolSuccess s =>
                    SuccessView(key: const ValueKey('s'), paths: s.paths),
                  _ => _Editor(key: const ValueKey('e'), tool: tool),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageItem {
  _PageItem(this.sourceIndex, this.thumb);
  final int sourceIndex;
  final Uint8List thumb;
  int quarterTurns = 0;
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.tool});
  final Tool tool;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  Uint8List? _pdf;
  List<_PageItem>? _pages;
  bool _loading = false;

  Future<void> _pick() async {
    final picked = await FileService.instance.pickPdfs();
    if (picked.isEmpty) return;
    setState(() => _loading = true);
    final bytes = picked.first.bytes;
    try {
      final thumbs = await RasterService.instance.renderAll(bytes, scale: 0.7);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _pages = [for (final (i, t) in thumbs.indexed) _PageItem(i, t)];
        _loading = false;
      });
    } catch (_) {
      // Render failed (corrupted/encrypted PDF) — stop the spinner and say so
      // instead of hanging on a bare CircularProgressIndicator forever.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not read this PDF — it may be corrupted or password-protected.')));
    }
  }

  void _apply() {
    final pages = _pages!;
    context.read<ToolBloc>().add(ToolStarted(
          widget.tool,
          () => PdfService.instance.organize(
            _pdf!,
            [for (final p in pages) p.sourceIndex],
            {for (final p in pages) p.sourceIndex: p.quarterTurns},
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pages == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: GlassCard(
            frosted: true,
            strong: true,
            onTap: _pick,
            padding:
                const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    gradient: AppColors.aurora,
                    borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.grid_view_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              Text('Choose PDF',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Then drag to reorder, tap to rotate',
                  style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ).animate().fadeIn().slideY(begin: 0.15),
        ),
      );
    }
    return Column(children: [
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          itemCount: _pages!.length,
          proxyDecorator: (child, _, anim) => AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Transform.scale(scale: 1.04, child: child),
          ),
          onReorder: (from, to) => setState(() {
            if (to > from) to--;
            final item = _pages!.removeAt(from);
            _pages!.insert(to, item);
          }),
          itemBuilder: (context, i) {
            final p = _pages![i];
            return Padding(
              key: ValueKey(p.sourceIndex),
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                radius: 18,
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RotatedBox(
                      quarterTurns: p.quarterTurns,
                      child: Image.memory(p.thumb,
                          width: 54, height: 74, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Text('Page ${p.sourceIndex + 1}',
                          style: Theme.of(context).textTheme.bodyLarge)),
                  IconButton(
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded,
                        color: AppColors.cyan, size: 22),
                    onPressed: () =>
                        setState(() => p.quarterTurns = (p.quarterTurns + 1) % 4),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger, size: 22),
                    onPressed: () => setState(() => _pages!.removeAt(i)),
                  ),
                  Icon(Icons.drag_handle_rounded, color: AppColors.textLow),
                ]),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: AuroraButton(
          label: 'Apply changes',
          icon: Icons.bolt_rounded,
          onPressed: (_pages?.isEmpty != false) ? null : _apply,
        ),
      ),
    ]);
  }
}
