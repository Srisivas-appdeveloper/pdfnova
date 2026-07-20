import 'dart:typed_data';
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

/// Fill form: lists every text field in the PDF's AcroForm, one glass input
/// each, optional flatten so the result can't be edited afterwards.
class FormFillScreen extends StatelessWidget {
  const FormFillScreen({super.key, required this.tool});
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
                ToolProcessing s =>
                  ProcessingView(progress: s.progress, label: 'Filling the form'),
                ToolSuccess s => SuccessView(paths: s.paths),
                _ => _FormFlow(tool: tool),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FormFlow extends StatefulWidget {
  const _FormFlow({required this.tool});
  final Tool tool;

  @override
  State<_FormFlow> createState() => _FormFlowState();
}

class _FormFlowState extends State<_FormFlow> {
  Uint8List? _pdf;
  List<(int, String, String)>? _fields;
  final Map<int, TextEditingController> _controllers = {};
  bool _flatten = true;
  String? _error;

  Future<void> _pick() async {
    final picked = await FileService.instance.pickPdfs();
    if (picked.isEmpty) return;
    final fields = PdfService.instance.listFormFields(picked.first.bytes);
    setState(() {
      _pdf = picked.first.bytes;
      _fields = fields;
      _error = fields.isEmpty
          ? 'This PDF has no fillable form fields. Use the Sign tool to write on flat PDFs.'
          : null;
      for (final (i, _, value) in fields) {
        _controllers[i] = TextEditingController(text: value);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    context.read<ToolBloc>().add(ToolStarted(
          widget.tool,
          () => PdfService.instance.fillForm(
              _pdf!,
              {for (final e in _controllers.entries) e.key: e.value.text},
              _flatten),
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_fields == null || _fields!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GlassCard(
              frosted: true,
              strong: true,
              onTap: _pick,
              padding:
                  const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_note_rounded,
                    color: AppColors.cyan, size: 40),
                const SizedBox(height: 12),
                Text('Choose a form PDF',
                    style: Theme.of(context).textTheme.titleMedium),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        for (final (i, name, _) in _fields!) ...[
          Text(name,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 13)),
          const SizedBox(height: 6),
          GlassCard(
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controllers[i],
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 14),
        ],
        SwitchListTile(
          value: _flatten,
          activeColor: AppColors.violet,
          contentPadding: EdgeInsets.zero,
          title: Text('Lock after filling',
              style: Theme.of(context).textTheme.bodyLarge),
          subtitle: Text('Fields become permanent print, not editable',
              style: Theme.of(context).textTheme.bodyMedium),
          onChanged: (v) => setState(() => _flatten = v),
        ),
        const SizedBox(height: 12),
        AuroraButton(
            label: 'Fill & save', icon: Icons.bolt_rounded, onPressed: _fill),
      ],
    );
  }
}
