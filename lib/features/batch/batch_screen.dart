import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../../services/pdf_service.dart';
import '../home/tools.dart';
import '../tool/tool_bloc.dart';
import '../tool/processing_view.dart';
import '../tool/success_view.dart';

enum _BatchOp { compress, protect, watermark, metadata }

/// Batch: pick many PDFs, pick one action, get every output at once.
/// Nobody offers this offline — it's the power-user hook.
class BatchScreen extends StatelessWidget {
  const BatchScreen({super.key, required this.tool});
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
              child: switch (state) {
                ToolProcessing s => ProcessingView(
                    progress: s.progress, label: 'Working through your files'),
                ToolSuccess s => SuccessView(paths: s.paths),
                _ => _BatchFlow(tool: tool),
              },
            ),
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

  bool get _needsParam =>
      _op == _BatchOp.protect || _op == _BatchOp.watermark;

  bool get _ready =>
      _files.length >= 2 && (!_needsParam || _param.text.trim().isNotEmpty);

  void _run() {
    final files = _files.toList();
    final op = _op;
    final param = _param.text.trim();
    context.read<ToolBloc>().add(ToolStarted(widget.tool, () async {
      final pdf = PdfService.instance;
      final out = <String>[];
      for (final f in files) {
        final result = switch (op) {
          _BatchOp.compress => await pdf.compress(f.bytes),
          _BatchOp.protect => await pdf.protect(f.bytes, param),
          _BatchOp.watermark => await pdf.watermark(f.bytes, param),
          _BatchOp.metadata => await pdf.stripMetadata(f.bytes),
        };
        out.addAll(result);
      }
      return out;
    }));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        GlassCard(
          frosted: true,
          strong: true,
          onTap: () async {
            final picked =
                await FileService.instance.pickPdfs(multiple: true);
            if (picked.isNotEmpty) setState(() => _files.addAll(picked));
          },
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            const Icon(Icons.dynamic_feed_rounded,
                color: AppColors.cyan, size: 36),
            const SizedBox(height: 10),
            Text(
                _files.isEmpty
                    ? 'Choose 2 or more PDFs'
                    : '${_files.length} files — tap to add more',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Apply to all', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (op, label) in const [
            (_BatchOp.compress, 'Compress'),
            (_BatchOp.protect, 'Protect'),
            (_BatchOp.watermark, 'Watermark'),
            (_BatchOp.metadata, 'Clean metadata'),
          ])
            GestureDetector(
              onTap: () => setState(() => _op = op),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: _op == op ? AppColors.aurora : null,
                  color: _op == op ? null : AppColors.glassFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text(label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color:
                            _op == op ? Colors.white : AppColors.textMid)),
              ),
            ),
        ]),
        if (_needsParam) ...[
          const SizedBox(height: 16),
          GlassCard(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _param,
              onChanged: (_) => setState(() {}),
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: _op == _BatchOp.protect
                    ? 'Password for all files'
                    : 'Watermark text',
                hintStyle: TextStyle(color: AppColors.textLow),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        AuroraButton(
            label: 'Run batch',
            icon: Icons.bolt_rounded,
            onPressed: _ready ? _run : null),
      ],
    );
  }
}
