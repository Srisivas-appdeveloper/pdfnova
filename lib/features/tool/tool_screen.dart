import 'dart:isolate';
import 'dart:typed_data';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + the interstitial call in the listener
// import '../../services/ad_service.dart';
import '../../services/conversion_service.dart';
import '../../services/file_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pdf_service.dart';
import '../home/tools.dart';
import 'processing_view.dart';
import 'success_view.dart';
import 'tool_bloc.dart';
import 'tool_stages.dart';
import 'pick_zone.dart';
import 'tool_header.dart';

/// Generic tool journey — input → processing → success — on one surface.
/// Stages change with a fade-through (old stage fades and shrinks a touch,
/// new one fades in and grows), so the screen never jumps.
class ToolScreen extends StatelessWidget {
  const ToolScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: Scaffold(
        backgroundColor: c.canvas,
        appBar: AppBar(
          // Keep the leading slot the same width in every state.
          leadingWidth: 56,
          leading: BlocBuilder<ToolBloc, ToolState>(
            builder: (context, state) => state is ToolProcessing
                ? const SizedBox(width: 56) // don't abandon mid-write
                : const BackButton(),
          ),
        ),
        body: BlocConsumer<ToolBloc, ToolState>(
          listener: (context, state) {
            if (state is ToolSuccess) {
              // ADS DISABLED FOR RELEASE — re-enable: uncomment the line below.
              // AdService.instance.maybeShowInterstitial();
            }
            if (state is ToolFailure) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(toolSnack(context, state.message));
            }
          },
          // Only rebuild the switcher when the stage changes; progress ticks
          // rebuild the processing view below on their own.
          buildWhen: (a, b) => a.runtimeType != b.runtimeType,
          builder: (context, state) => PopScope(
            // Block the back gesture mid-write: popping here would leave
            // the work running headless and the user never sees the result.
            canPop: state is! ToolProcessing,
            child: PageTransitionSwitcher(
              duration: NovaMotion.page,
              transitionBuilder: (child, a, b) => FadeThroughTransition(
                animation: a,
                secondaryAnimation: b,
                fillColor: c.canvas,
                child: child,
              ),
              child: switch (state) {
                ToolProcessing() => BlocBuilder<ToolBloc, ToolState>(
                    key: const ValueKey('processing'),
                    builder: (context, s) => ProcessingView(
                        progress: s is ToolProcessing ? s.progress : null,
                        stage: s is ToolProcessing
                            ? s.stage
                            : null, // keep the outgoing ring unchanged while it fades
                        label: _processingLabel(tool.id)),
                  ),
                ToolSuccess s => SuccessView(
                    key: const ValueKey('success'),
                    paths: s.paths,
                    notes: s.notes),
                _ => _InputView(key: const ValueKey('input'), tool: tool),
              },
            ),
          ),
        ),
      ),
    );
  }

  static String _processingLabel(ToolId id) => switch (id) {
        ToolId.ocr => 'Reading your pages',
        ToolId.compressTarget => 'Squeezing to size',
        ToolId.pdfToImages => 'Turning pages into pictures',
        ToolId.pdfToWord => 'Building your Word document',
        ToolId.wordToPdf => 'Converting Word to PDF',
        ToolId.pdfToPpt => 'Building your presentation',
        _ => 'Working on it',
      };
}

// ---- Input stage --------------------------------------------------------
class _InputView extends StatefulWidget {
  const _InputView({super.key, required this.tool});
  final Tool tool;

  @override
  State<_InputView> createState() => _InputViewState();
}

/// Print colours for the Stamp tool — fixed, not theme colours, because
/// they end up on paper.
const _stampColors = [
  Color(0xFFD63B2F),
  Color(0xFF17915A),
  Color(0xFF3550E6),
  Color(0xFFB86E00),
];

class _InputViewState extends State<_InputView> {
  final List<PickedPdf> _files = [];
  List<Uint8List> _images = [];
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _textCtrl = TextEditingController(); // watermark / stamp text
  bool _aadhaarMode = true;
  int _targetKb = 500;

  /// Page count of the picked PDF (Split), read off the UI thread;
  /// -1 = password-protected, null = not known yet.
  int? _pageCount;
  Color _stampColor = _stampColors.first;
  PdfToWordMode _wordMode = PdfToWordMode.editable;

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _yearCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _multi =>
      widget.tool.id == ToolId.merge || widget.tool.id == ToolId.imagesToPdf;

  bool get _isDocxPick => widget.tool.id == ToolId.wordToPdf;

  Future<void> _pick() async {
    if (widget.tool.id == ToolId.imagesToPdf) {
      final imgs = await FileService.instance.pickImages();
      // Append so re-picking adds to the selection instead of discarding it.
      if (imgs.isNotEmpty) setState(() => _images = [..._images, ...imgs]);
      return;
    }
    if (_isDocxPick) {
      final picked = await FileService.instance.pickDocx();
      if (picked.isNotEmpty) {
        setState(() => _files
          ..clear()
          ..add(picked.first));
      }
      return;
    }
    final picked = await FileService.instance.pickPdfs(multiple: _multi);
    if (picked.isNotEmpty) {
      setState(() {
        if (_multi) {
          _files.addAll(picked);
        } else {
          _files
            ..clear()
            ..add(picked.first);
        }
        _pageCount = null;
      });
      if (widget.tool.id == ToolId.split) {
        final n = await countPdfPages(picked.first.bytes);
        if (mounted) setState(() => _pageCount = n);
      }
    }
  }

  /// Empty range fields mean exactly what their hints show — page 1 and the
  /// last page — so a picked PDF is ready to split without retyping them.
  int? get _splitFrom => _fromCtrl.text.isEmpty
      ? ((_pageCount ?? 0) > 0 ? 1 : null)
      : int.tryParse(_fromCtrl.text);
  int? get _splitTo => _toCtrl.text.isEmpty
      ? ((_pageCount ?? 0) > 0 ? _pageCount : null)
      : int.tryParse(_toCtrl.text);

  bool get _ready {
    switch (widget.tool.id) {
      case ToolId.merge:
        return _files.length >= 2;
      case ToolId.imagesToPdf:
        return _images.isNotEmpty;
      case ToolId.split:
        return _files.isNotEmpty && _splitFrom != null && _splitTo != null;
      case ToolId.unlock:
        return _files.isNotEmpty &&
            (_aadhaarMode
                ? _nameCtrl.text.trim().length >= 2 &&
                    _yearCtrl.text.trim().length == 4
                : _passwordCtrl.text.isNotEmpty);
      case ToolId.protect:
        return _files.isNotEmpty && _passwordCtrl.text.length >= 4;
      case ToolId.watermark || ToolId.stamp:
        return _files.isNotEmpty && _textCtrl.text.trim().isNotEmpty;
      default:
        return _files.isNotEmpty;
    }
  }

  void _start() {
    FocusScope.of(context).unfocus();
    final pdf = PdfService.instance;
    final bytes = _files.isNotEmpty ? _files.first.bytes : null;
    final Future<List<String>> Function() task = switch (widget.tool.id) {
      ToolId.merge => () => pdf.merge([for (final f in _files) f.bytes]),
      ToolId.split => () =>
          pdf.split(bytes!, _splitFrom!, _splitTo!),
      ToolId.compress => () => pdf.compress(bytes!),
      ToolId.compressTarget => () =>
          pdf.compressToTarget(bytes!, _targetKb * 1024),
      ToolId.protect => () => pdf.protect(bytes!, _passwordCtrl.text),
      ToolId.unlock => () => pdf.unlock(
          bytes!,
          _aadhaarMode
              ? PdfService.aadhaarPassword(_nameCtrl.text, _yearCtrl.text)
              : _passwordCtrl.text),
      ToolId.imagesToPdf => () => pdf.imagesToPdf(_images),
      ToolId.watermark => () => pdf.watermark(bytes!, _textCtrl.text.trim()),
      ToolId.stamp => () =>
          pdf.stamp(bytes!, _textCtrl.text.trim().toUpperCase(), _stampColor),
      ToolId.pageNumbers => () => pdf.pageNumbers(bytes!),
      ToolId.metadata => () => pdf.stripMetadata(bytes!),
      ToolId.pdfToImages => () =>
          pdf.pdfToImages(bytes!, sourceName: _files.first.name),
      ToolId.pdfToText => () => pdf.pdfToText(bytes!),
      ToolId.pdfToWord => () =>
          ConversionService.instance.pdfToWord(bytes!, mode: _wordMode),
      ToolId.wordToPdf => () => ConversionService.instance.wordToPdf(bytes!),
      ToolId.pdfToPpt => () => ConversionService.instance.pdfToPpt(bytes!),
      ToolId.ocr => () => OcrService.instance.ocrPdf(bytes!),
      _ => () async => <String>[],
    };
    context.read<ToolBloc>().add(ToolStarted(widget.tool, task));
  }

  String get _pickTitle {
    final id = widget.tool.id;
    final n = id == ToolId.imagesToPdf ? _images.length : _files.length;
    if (n == 0) {
      return id == ToolId.imagesToPdf
          ? 'Choose photos'
          : _isDocxPick
              ? 'Choose a .docx file'
              : 'Choose a PDF';
    }
    return '$n selected · tap to ${_multi ? 'add more' : 'change'}';
  }

  String get _pickHint => switch (widget.tool.id) {
        ToolId.imagesToPdf => 'JPG or PNG, as many as you like',
        ToolId.merge => 'Pick two or more PDFs',
        ToolId.wordToPdf => 'Word documents (.docx)',
        _ => 'From your phone or Files app',
      };

  @override
  Widget build(BuildContext context) {
    final id = widget.tool.id;
    final c = context.nova;
    final options = <Widget>[
      if (id == ToolId.split) _splitFields(),
      if (id == ToolId.unlock) _unlockFields(),
      if (id == ToolId.protect)
        NovaField(
          controller: _passwordCtrl,
          label: 'New password',
          hint: 'At least 4 characters',
          obscure: true,
          onChanged: (_) => setState(() {}),
        ),
      if (id == ToolId.compressTarget) _targetSize(),
      if (id == ToolId.pdfToWord) ...[
        NovaSegmented<PdfToWordMode>(
          value: _wordMode,
          onChanged: (m) => setState(() => _wordMode = m),
          options: const [
            (PdfToWordMode.editable, 'Editable text', Icons.edit_note_rounded),
            (PdfToWordMode.layout, 'Exact look', Icons.image_outlined),
          ],
        ),
        ToolNote(_wordMode == PdfToWordMode.editable
            ? 'Real paragraphs you can edit, with alignment kept. Pictures and exact layout are not carried over; scanned pages are read with OCR.'
            : 'Every page as a picture: looks identical to the PDF, but the text cannot be edited.'),
      ],
      if (id == ToolId.watermark)
        NovaField(
          controller: _textCtrl,
          label: 'Watermark text',
          hint: 'e.g. CONFIDENTIAL',
          onChanged: (_) => setState(() {}),
        ),
      if (id == ToolId.stamp) _stampFields(),
      if (id == ToolId.ocr)
        const ToolNote(
            'Reads printed English and Hindi text from scanned pages, entirely on this phone. The result is a text file.'),
      if (id == ToolId.compressTarget)
        const ToolNote(
            'To guarantee the size, pages become pictures (like a scan). Great for portal uploads, but text can no longer be selected.'),
    ];

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ToolHeader(tool: widget.tool),
            PickZone(
              icon: id == ToolId.imagesToPdf
                  ? Icons.add_photo_alternate_outlined
                  : Icons.add_rounded,
              title: _pickTitle,
              hint: _pickHint,
              done:
                  (id == ToolId.imagesToPdf ? _images.length : _files.length) >
                      0,
              onTap: _pick,
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
                        icon: _isDocxPick
                            ? Icons.description_outlined
                            : Icons.picture_as_pdf_outlined,
                        fg: _isDocxPick ? c.accent : c.danger,
                        bg: _isDocxPick ? c.accentSoft : c.dangerSoft,
                        size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          Text(f.sizeLabel,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
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
            if (id == ToolId.imagesToPdf && _images.isNotEmpty)
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_images[i],
                          width: 76, height: 96, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          decoration: BoxDecoration(
                              color: c.surface, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(3),
                          child:
                              Icon(Icons.close_rounded, size: 14, color: c.ink),
                        ),
                      ),
                    ),
                  ]).enter(context, index: i),
                ),
              ),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...options.map((w) => w.enter(context, delayMs: 260)),
            ],
          ],
        ),
      ),
      // Primary action stays pinned above the keyboard / nav bar.
      Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: c.canvas,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: NovaButton(
          label: widget.tool.title,
          icon: Icons.arrow_forward_rounded,
          onPressed: _ready ? _start : null,
        ),
      ),
    ]);
  }

  Widget _splitFields() => Column(children: [
        Row(children: [
          Expanded(
            child: NovaField(
              controller: _fromCtrl,
              label: 'From page',
              hint: '1',
              number: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NovaField(
              controller: _toCtrl,
              label: 'To page',
              hint: (_pageCount ?? 0) > 0 ? '$_pageCount' : '',
              number: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        if (_files.isNotEmpty && _pageCount != null)
          ToolNote(
              _pageCount! < 0
                  ? 'This PDF is password-protected. Unlock it first with the Unlock tool.'
                  : 'This PDF has $_pageCount ${_pageCount == 1 ? 'page' : 'pages'}.',
              icon: Icons.description_outlined),
      ]);

  Widget _targetSize() {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final originalKb =
        _files.isNotEmpty ? (_files.first.bytes.length / 1024).round() : 0;
    final reductionPct = originalKb > 0 && _targetKb < originalKb
        ? (((originalKb - _targetKb) / originalKb) * 100).clamp(1, 95).round()
        : 0;
    final targetLabel = _targetKb >= 1024
        ? '${(_targetKb / 1024).toStringAsFixed(1)} MB'
        : '$_targetKb KB';

    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target size', style: t.labelMedium),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: NovaMotion.quick,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                            .animate(a),
                    child: child,
                  ),
                ),
                child: Text(targetLabel,
                    key: ValueKey(targetLabel), style: t.displaySmall),
              ),
              const Spacer(),
              if (reductionPct > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.successSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('~$reductionPct% smaller',
                      style: t.labelMedium
                          ?.copyWith(color: c.success, fontSize: 12)),
                ),
            ],
          ),
          Text(
            _files.isNotEmpty
                ? 'Original ${_files.first.sizeLabel}'
                : 'Choose a file to compare',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          Slider(
            value: _targetKb.toDouble().clamp(50.0, 5000.0),
            min: 50.0,
            max: 5000.0,
            divisions: 99,
            onChanged: (v) => setState(() => _targetKb = v.round()),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (kb, label) in const [
              (100, '100 KB'),
              (200, '200 KB'),
              (500, '500 KB'),
              (1024, '1 MB'),
              (2048, '2 MB'),
              (5000, '5 MB'),
            ])
              NovaChip(
                label: label,
                selected: _targetKb == kb,
                onTap: () => setState(() => _targetKb = kb),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _stampFields() {
    final c = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NovaField(
          controller: _textCtrl,
          label: 'Stamp text',
          hint: 'PAID, APPROVED…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        // One-tap presets — the tool promises PAID · APPROVED · custom.
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final word in const ['PAID', 'APPROVED', 'RECEIVED', 'COPY'])
            NovaChip(
              label: word,
              selected: _textCtrl.text.trim().toUpperCase() == word,
              onTap: () => setState(() => _textCtrl.text = word),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Ink colour', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        Row(children: [
          for (final color in _stampColors)
            GestureDetector(
              onTap: () => setState(() => _stampColor = color),
              child: AnimatedContainer(
                duration: NovaMotion.quick,
                margin: const EdgeInsets.only(right: 12),
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _stampColor == color ? c.ink : Colors.transparent,
                      width: 2),
                ),
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _unlockFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NovaSegmented<bool>(
            value: _aadhaarMode,
            onChanged: (v) => setState(() => _aadhaarMode = v),
            options: const [
              (true, 'Aadhaar', Icons.badge_outlined),
              (false, 'I know the password', null),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: NovaMotion.medium,
            curve: NovaMotion.emphasized,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: NovaMotion.medium,
              child: _aadhaarMode
                  ? Column(
                      key: const ValueKey('aadhaar'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NovaField(
                          controller: _nameCtrl,
                          label: 'Name',
                          hint: 'As printed on your Aadhaar',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        NovaField(
                          controller: _yearCtrl,
                          label: 'Year of birth',
                          hint: 'YYYY',
                          number: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const ToolNote(
                          'Aadhaar PDFs open with the first 4 letters of your name in capitals + your birth year. We build that for you and remove the lock — entirely on this phone.',
                          icon: Icons.key_outlined,
                        ),
                      ],
                    )
                  : NovaField(
                      key: const ValueKey('manual'),
                      controller: _passwordCtrl,
                      label: 'PDF password',
                      hint: 'Password',
                      obscure: true,
                      onChanged: (_) => setState(() {}),
                    ),
            ),
          ),
        ],
      );
}

/// Page count of [bytes] off the UI isolate; -1 if locked or unreadable.
/// Top-level on purpose: a closure created inside an instance method shares
/// its context with the method's other closures (which capture `this`),
/// making it unsendable to an isolate.
Future<int> countPdfPages(Uint8List bytes) => Isolate.run(() {
      try {
        final d = sf.PdfDocument(inputBytes: bytes);
        final c = d.pages.count;
        d.dispose();
        return c;
      } catch (_) {
        return -1;
      }
    });
