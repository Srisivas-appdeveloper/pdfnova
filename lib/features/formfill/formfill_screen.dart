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
import '../tool/tool_bloc.dart';
import '../tool/tool_header.dart';
import '../tool/tool_stages.dart';

/// Fill form: lists every text field in the PDF's AcroForm, one input
/// each, optional flatten so the result can't be edited afterwards.
class FormFillScreen extends StatelessWidget {
  const FormFillScreen({super.key, required this.tool});
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
            processingLabel: 'Filling the form',
            input: _FormFlow(tool: tool),
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
    final t = Theme.of(context).textTheme;
    final hasFields = _fields != null && _fields!.isNotEmpty;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ToolHeader(tool: widget.tool),
            PickZone(
              icon: Icons.edit_note_rounded,
              title: hasFields
                  ? '${_fields!.length} fields found · tap to change'
                  : 'Choose a form PDF',
              hint: 'PDFs with fillable fields (AcroForm)',
              done: hasFields,
              onTap: _pick,
            ).enter(context, delayMs: 200),
            if (_error != null)
              ToolNote(_error!, icon: Icons.error_outline_rounded),
            if (hasFields) ...[
              const SizedBox(height: 22),
              for (final (n, (i, name, _)) in _fields!.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: NovaField(
                    controller: _controllers[i]!,
                    label: name,
                    hint: 'Type here',
                  ).enter(context, index: n),
                ),
              NovaCard(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: SwitchListTile.adaptive(
                  value: _flatten,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Lock after filling', style: t.titleMedium),
                  subtitle: Text('Fields become permanent print, not editable',
                      style: t.bodySmall),
                  onChanged: (v) => setState(() => _flatten = v),
                ),
              ),
            ],
          ],
        ),
      ),
      if (hasFields)
        ToolActionBar(
          child: NovaButton(
              label: 'Fill & save',
              icon: Icons.arrow_forward_rounded,
              onPressed: _fill),
        ),
    ]);
  }
}
