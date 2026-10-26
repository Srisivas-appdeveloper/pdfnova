import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../home/tools.dart';
import '../tool/pick_zone.dart';
import '../../services/tool_errors.dart';
import '../tool/tool_bloc.dart';
import '../tool/tool_header.dart';
import '../tool/tool_stages.dart';

enum _BatchOp { compress, protect, watermark, metadata }

/// Renames a batch output after the file it came from, e.g.
/// `watermarked_1792….pdf` → `Annual_Report_watermarked.pdf`, so results
/// can be told apart. Never overwrites: adds _2, _3… on a clash, and keeps
/// the original name if renaming isn't possible.
Future<String> _nameAfterSource(String path, String sourceName) async {
  final outName = path.split('/').last;
  final op = outName.contains('_')
      ? outName.substring(0, outName.lastIndexOf('_'))
      : 'output';
  final dot = sourceName.lastIndexOf('.');
  final base = '${dot > 0 ? sourceName.substring(0, dot) : sourceName}_$op';
  for (var n = 1; n < 50; n++) {
    try {
      return await FileService.instance
          .renameOutput(path, n == 1 ? base : '${base}_$n');
    } on FileSystemException {
      continue; // name taken — try the next suffix
    } catch (_) {
      return path;
    }
  }
  return path;
}

/// Runs [op] on every file, reporting real per-file progress. One failing
/// file does not cost the others: successes are returned, failures are
/// named in the result notes, and only an all-failed run is an error.
Future<List<String>> runBatch(List<PickedPdf> files,
    Future<List<String>> Function(Uint8List bytes) op) async {
  final out = <String>[];
  final failed = <String>[];
  for (final (i, f) in files.indexed) {
    ToolProgress.report(i / files.length,
        stage: 'File ${i + 1} of ${files.length}');
    try {
      for (final path in await op(f.bytes)) {
        out.add(await _nameAfterSource(path, f.name));
      }
    } catch (e) {
      failed.add('${f.name} (${describeToolError(e)})');
    }
  }
  ToolProgress.report(1, stage: 'Done');
  if (out.isEmpty) {
    throw UserFacingError(
        'None of the ${files.length} files could be processed. ${failed.first}');
  }
  if (failed.isNotEmpty) {
    ToolNotes.add(
        '${out.length} of ${files.length} files done. Not processed: ${failed.join('; ')}');
  }
  return out;
}

/// Batch: pick many PDFs, pick one action, get every output at once.
/// Nobody offers this offline — it's the power-user hook.
class BatchScreen extends StatelessWidget {
  const BatchScreen({super.key, required this.tool});
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
                  .showSnackBar(toolSnack(context, state.message));
            }
          },
          builder: (context, state) => ToolStages(
            state: state,
            processingLabel: 'Working through your files',
            input: _BatchFlow(tool: tool),
          ),
        ),
      ),
    );
  }
}

class _BatchFlow extends StatefulWidget {
  const _BatchFlow({required this.tool});
  final Tool tool;

  @override
  State<_BatchFlow> createState() => _BatchFlowState();
}

class _BatchFlowState extends State<_BatchFlow> {
  final List<PickedPdf> _files = [];
  _BatchOp _op = _BatchOp.compress;
  final _param = TextEditingController(); // password or watermark text

  @override
  void dispose() {
    _param.dispose();
    super.dispose();
  }

  bool get _needsParam => _op == _BatchOp.protect || _op == _BatchOp.watermark;

  bool get _ready =>
      _files.length >= 2 && (!_needsParam || _param.text.trim().isNotEmpty);

  void _run() {
    final files = _files.toList();
    final op = _op;
    final param = _param.text.trim();
    context.read<ToolBloc>().add(ToolStarted(
        widget.tool,
        () => runBatch(files, (bytes) {
              final pdf = PdfService.instance;
              return switch (op) {
                _BatchOp.compress => pdf.compress(bytes),
                _BatchOp.protect => pdf.protect(bytes, param),
                _BatchOp.watermark => pdf.watermark(bytes, param),
                _BatchOp.metadata => pdf.stripMetadata(bytes),
              };
            })));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          physics: const BouncingScrollPhysics(),
          children: [
            ToolHeader(tool: widget.tool),
            PickZone(
              icon: Icons.dynamic_feed_rounded,
              title: _files.isEmpty
                  ? 'Choose 2 or more PDFs'
                  : '${_files.length} files · tap to add more',
              hint: 'Every file gets the same treatment',
              done: _files.length >= 2,
              onTap: () async {
                final picked =
                    await FileService.instance.pickPdfs(multiple: true);
                if (picked.isNotEmpty) setState(() => _files.addAll(picked));
              },
            ).enter(context, delayMs: 200),
            const SizedBox(height: 12),
            for (final (i, f) in _files.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NovaCard(
                  radius: 16,
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(children: [
                    NovaIconTile(
                        icon: Icons.picture_as_pdf_outlined,
                        fg: c.danger,
                        bg: c.dangerSoft,
                        size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('${f.name} · ${f.sizeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon:
                          Icon(Icons.close_rounded, size: 18, color: c.inkLow),
                      onPressed: () => setState(() => _files.removeAt(i)),
                    ),
                  ]),
                ).enter(context),
              ),
            const SizedBox(height: 14),
            Text('Apply to all', style: t.labelMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (op, label, icon) in const [
                (_BatchOp.compress, 'Compress', Icons.compress_rounded),
                (_BatchOp.protect, 'Protect', Icons.shield_outlined),
                (
                  _BatchOp.watermark,
                  'Watermark',
                  Icons.branding_watermark_outlined
                ),
                (
                  _BatchOp.metadata,
                  'Clean metadata',
                  Icons.cleaning_services_outlined
                ),
              ])
                NovaChip(
                  label: label,
                  icon: icon,
                  selected: _op == op,
                  onTap: () => setState(() {
                    // Watermark text must never silently become a password.
                    if (op != _op) _param.clear();
                    _op = op;
                  }),
                ),
            ]),
            if (_needsParam) ...[
              const SizedBox(height: 16),
              NovaField(
                key: ValueKey(_op),
                controller: _param,
                // Appears below the chips — focusing it scrolls it into view
                // and opens the keyboard, instead of a silently disabled Run.
                autofocus: true,
                label: _op == _BatchOp.protect ? 'Password' : 'Watermark text',
                hint: _op == _BatchOp.protect
                    ? 'Password for all files'
                    : 'e.g. CONFIDENTIAL',
                obscure: _op == _BatchOp.protect,
                onChanged: (_) => setState(() {}),
              ).enter(context),
            ],
          ],
        ),
      ),
      ToolActionBar(
        child: NovaButton(
            label: _files.length >= 2
                ? 'Run on ${_files.length} files'
                : 'Run batch',
            icon: Icons.arrow_forward_rounded,
            onPressed: _ready ? _run : null),
      ),
    ]);
  }
}
