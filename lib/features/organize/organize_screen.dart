import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../../services/raster_service.dart';
import '../home/tools.dart';
import '../tool/pick_zone.dart';
import '../tool/tool_bloc.dart';
import '../tool/tool_header.dart';
import '../tool/tool_stages.dart';

/// Pages tool: long-press-drag to reorder, tap rotate, tap delete.
/// Thumbnails render once via PDFium then the list is pure state.
class OrganizeScreen extends StatelessWidget {
  const OrganizeScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: Scaffold(
        backgroundColor: context.nova.canvas,
        appBar: AppBar(),
        body: BlocConsumer<ToolBloc, ToolState>(
          listener: (context, state) {
            if (state is ToolFailure) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) => ToolStages(
            state: state,
            processingLabel: 'Rebuilding your PDF',
            input: _Editor(tool: tool),
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
  const _Editor({required this.tool});
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
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    if (_pages == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          ToolHeader(tool: widget.tool),
          PickZone(
            icon: Icons.grid_view_rounded,
            title: _loading ? 'Reading pages…' : 'Choose a PDF',
            hint: 'Then drag to reorder, tap to rotate or delete',
            onTap: _loading ? null : _pick,
          ).enter(context, delayMs: 200),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Row(children: [
          Text('${_pages!.length} pages', style: t.headlineMedium),
          const Spacer(),
          Text('Hold & drag to reorder', style: t.bodySmall),
        ]).enter(context),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          itemCount: _pages!.length,
          proxyDecorator: (child, _, anim) => AnimatedBuilder(
            animation: anim,
            builder: (_, __) => Transform.scale(
              scale: 1 + 0.04 * Curves.easeOut.transform(anim.value),
              child: Material(
                color: Colors.transparent,
                elevation: 8 * anim.value,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(18),
                child: child,
              ),
            ),
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
              padding: const EdgeInsets.only(bottom: 10),
              child: NovaCard(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                child: Row(children: [
                  Container(
                    width: 64,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedRotation(
                      turns: p.quarterTurns / 4,
                      duration: NovaMotion.medium,
                      curve: NovaMotion.emphasized,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(p.thumb,
                            width: 50, height: 66, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Page ${p.sourceIndex + 1}', style: t.titleSmall),
                        if (p.quarterTurns % 4 != 0)
                          Text('Rotated ${(p.quarterTurns % 4) * 90}°',
                              style: t.bodySmall?.copyWith(color: c.accent)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rotate',
                    icon: Icon(Icons.rotate_90_degrees_cw_outlined,
                        color: c.inkMid, size: 22),
                    onPressed: () => setState(() => p.quarterTurns++),
                  ),
                  IconButton(
                    tooltip: 'Delete page',
                    icon: Icon(Icons.delete_outline_rounded,
                        color: c.danger, size: 22),
                    onPressed: () => setState(() => _pages!.removeAt(i)),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator_rounded, color: c.inkLow),
                    ),
                  ),
                ]),
              ).enter(context, index: i),
            );
          },
        ),
      ),
      ToolActionBar(
        child: NovaButton(
          label: 'Apply changes',
          icon: Icons.arrow_forward_rounded,
          onPressed: (_pages?.isEmpty != false) ? null : _apply,
        ),
      ),
    ]);
  }
}
