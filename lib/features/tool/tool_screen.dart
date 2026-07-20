import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
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

/// Generic tool journey — input → processing → success — one surface,
/// crossfaded. Custom-flow tools (organize, sign, forms…) have their own
/// screens; everything else lives here.
class ToolScreen extends StatelessWidget {
  const ToolScreen({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ToolBloc(),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(tool.title),
            // Keep the leading slot the same width in every state — an empty
            // slot made the title jump to the corner when processing started.
            leadingWidth: 56,
            leading: BlocBuilder<ToolBloc, ToolState>(
              builder: (context, state) => state is ToolProcessing
                  ? const SizedBox(width: 56) // don't abandon mid-write
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
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
                    .showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
            builder: (context, state) {
              // Block the system back gesture mid-write: popping here would
              // leave the work running headless and the user never sees the
              // result. The AppBar back button is already hidden in this state.
              return PopScope(
                canPop: state is! ToolProcessing,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                              .animate(anim),
                      child: child,
                    ),
                  ),
                  child: switch (state) {
                    ToolProcessing s => ProcessingView(
                        key: const ValueKey('processing'),
                        progress: s.progress,
                        label: _processingLabel(tool.id)),
                    ToolSuccess s => SuccessView(
                        key: const ValueKey('success'), paths: s.paths),
                    _ => _InputView(key: const ValueKey('input'), tool: tool),
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _processingLabel(ToolId id) => switch (id) {
        ToolId.ocr         => 'Reading your pages',
        ToolId.compressTarget => 'Squeezing to size',
        ToolId.pdfToImages => 'Turning pages into pictures',
        ToolId.pdfToWord   => 'Building your Word document',
        ToolId.wordToPdf   => 'Converting Word to PDF',
        ToolId.pdfToPpt    => 'Building your presentation',
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
  Color _stampColor = AppColors.danger;

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
      if (picked.isNotEmpty) setState(() { _files ..clear() ..add(picked.first); });
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
      });
    }
  }

  bool get _ready {
    switch (widget.tool.id) {
      case ToolId.merge:
        return _files.length >= 2;
      case ToolId.imagesToPdf:
        return _images.isNotEmpty;
      case ToolId.split:
        return _files.isNotEmpty &&
            int.tryParse(_fromCtrl.text) != null &&
            int.tryParse(_toCtrl.text) != null;
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
    final pdf = PdfService.instance;
    final bytes = _files.isNotEmpty ? _files.first.bytes : null;
    final Future<List<String>> Function() task = switch (widget.tool.id) {
      ToolId.merge => () => pdf.merge([for (final f in _files) f.bytes]),
      ToolId.split => () => pdf.split(
          bytes!, int.parse(_fromCtrl.text), int.parse(_toCtrl.text)),
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
      ToolId.pdfToImages => () => pdf.pdfToImages(bytes!),
      ToolId.pdfToText  => () => pdf.pdfToText(bytes!),
      ToolId.pdfToWord  => () => ConversionService.instance.pdfToWord(bytes!),
      ToolId.wordToPdf  => () => ConversionService.instance.wordToPdf(bytes!),
      ToolId.pdfToPpt   => () => ConversionService.instance.pdfToPpt(bytes!),
      ToolId.ocr        => () => OcrService.instance.ocrPdf(bytes!),
      _                 => () async => <String>[],
    };
    context.read<ToolBloc>().add(ToolStarted(widget.tool, task));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.tool.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _PickZone(
          tool: widget.tool,
          fileCount: id == ToolId.imagesToPdf ? _images.length : _files.length,
          onPick: _pick,
          isDocx: _isDocxPick,
        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.15),
        const SizedBox(height: 16),
        for (final (i, f) in _files.indexed)
          GlassCard(
            radius: 18,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded,
                    color: AppColors.cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('${f.name}  ·  ${f.sizeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textLow),
                  onPressed: () => setState(() => _files.removeAt(i)),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 250.ms)
              .slideX(begin: 0.1, curve: Curves.easeOutCubic),
        if (id == ToolId.imagesToPdf && _images.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_images[i],
                        width: 72, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (id == ToolId.split) _splitFields(),
        if (id == ToolId.unlock) _unlockFields(),
        if (id == ToolId.protect)
          _textField(_passwordCtrl, 'New password (min 4 characters)',
              obscure: true),
        if (id == ToolId.compressTarget) _targetSlider(),
        if (id == ToolId.watermark)
          _textField(_textCtrl, 'Watermark text (e.g. CONFIDENTIAL)'),
        if (id == ToolId.stamp) _stampFields(),
        if (id == ToolId.ocr)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Reads printed text from scanned pages — English and Hindi — fully on this phone. Output is a text file.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12.5),
            ),
          ),
        if (id == ToolId.compressTarget)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Guaranteed-size mode converts pages to pictures (like a scan) — perfect for portal uploads, but text can no longer be selected.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 24),
        AuroraButton(
          label: widget.tool.title,
          icon: Icons.bolt_rounded,
          onPressed: _ready ? _start : null,
        ),
      ],
    );
  }

  Widget _splitFields() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(child: _textField(_fromCtrl, 'From page', number: true)),
          const SizedBox(width: 12),
          Expanded(child: _textField(_toCtrl, 'To page', number: true)),
        ]),
      );

  Widget _targetSlider() {
    final originalKb = _files.isNotEmpty ? (_files.first.bytes.length / 1024).round() : 2048;
    final reductionPct = originalKb > 0 && _targetKb < originalKb
        ? (((originalKb - _targetKb) / originalKb) * 100).clamp(1, 95).round()
        : 0;
    final targetLabel = _targetKb >= 1024
        ? '${(_targetKb / 1024).toStringAsFixed(1)} MB'
        : '$_targetKb KB';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassCard(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Target File Size',
                    style: Theme.of(context).textTheme.titleMedium),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: AppColors.aurora,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(targetLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  _files.isNotEmpty
                      ? 'Original: ${_files.first.sizeLabel}'
                      : 'Select a file to compare',
                  style: TextStyle(color: AppColors.textLow, fontSize: 12.5),
                ),
                if (reductionPct > 0) ...[
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.success.withOpacity(0.5)),
                    ),
                    child: Text('~$reductionPct% smaller',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.cyan,
                inactiveTrackColor: AppColors.glassBorder,
                thumbColor: Colors.white,
                overlayColor: AppColors.cyan.withOpacity(0.2),
                trackHeight: 6,
              ),
              child: Slider(
                value: _targetKb.toDouble().clamp(50.0, 5000.0),
                min: 50.0,
                max: 5000.0,
                divisions: 99,
                onChanged: (v) => setState(() => _targetKb = v.round()),
              ),
            ),
            const SizedBox(height: 8),
            Text('Quick Presets',
                style: TextStyle(color: AppColors.textLow, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (kb, label) in const [
                (100, '100 KB'),
                (200, '200 KB'),
                (500, '500 KB'),
                (1024, '1 MB'),
                (2048, '2 MB'),
                (5000, '5 MB'),
              ])
                GestureDetector(
                  onTap: () => setState(() => _targetKb = kb),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: _targetKb == kb ? AppColors.aurora : null,
                      color: _targetKb == kb ? null : AppColors.glassFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: _targetKb == kb
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _targetKb == kb
                                ? Colors.white
                                : AppColors.textMid)),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stampFields() => Column(children: [
        _textField(_textCtrl, 'Stamp text (PAID, APPROVED…)'),
        const SizedBox(height: 12),
        Row(children: [
          for (final c in const [
            AppColors.danger,
            AppColors.success,
            AppColors.violet,
            AppColors.cyan
          ])
            GestureDetector(
              onTap: () => setState(() => _stampColor = c),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _stampColor == c
                          ? Colors.white
                          : Colors.transparent,
                      width: 2.5),
                ),
              ),
            ),
        ]),
      ]);

  Widget _unlockFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          GlassCard(
            radius: 18,
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              _modeChip('Aadhaar', _aadhaarMode,
                  () => setState(() => _aadhaarMode = true)),
              _modeChip('I know the password', !_aadhaarMode,
                  () => setState(() => _aadhaarMode = false)),
            ]),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _aadhaarMode
                ? Column(
                    key: const ValueKey('aadhaar'),
                    children: [
                      _textField(_nameCtrl, 'Name (as on Aadhaar)'),
                      const SizedBox(height: 12),
                      _textField(_yearCtrl, 'Year of birth (YYYY)',
                          number: true),
                      const SizedBox(height: 10),
                      Text(
                        'Aadhaar PDFs open with the first 4 letters of your name in capitals + your birth year. We build that for you and remove the lock — entirely on this phone.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 12.5),
                      ),
                    ],
                  )
                : _textField(_passwordCtrl, 'PDF password',
                    key: const ValueKey('manual'), obscure: true),
          ),
        ],
      );

  Widget _modeChip(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: active ? AppColors.aurora : null,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    color: active ? Colors.white : AppColors.textMid)),
          ),
        ),
      );

  Widget _textField(TextEditingController ctrl, String hint,
          {bool number = false, bool obscure = false, Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GlassCard(
          key: key,
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            onChanged: (_) => setState(() {}),
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AppColors.textLow),
              border: InputBorder.none,
            ),
          ),
        ),
      );
}

class _PickZone extends StatelessWidget {
  const _PickZone(
      {required this.tool, required this.fileCount, required this.onPick,
       this.isDocx = false});
  final Tool tool;
  final int fileCount;
  final VoidCallback onPick;
  final bool isDocx;

  @override
  Widget build(BuildContext context) {
    final isImages = tool.id == ToolId.imagesToPdf;
    final emptyLabel = isImages
        ? 'Choose photos'
        : isDocx
            ? 'Choose .docx file'
            : 'Choose PDF';
    return GlassCard(
      frosted: true,
      strong: true,
      onTap: onPick,
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.aurora,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
              isImages ? Icons.add_photo_alternate_rounded : Icons.add_rounded,
              size: 32,
              color: Colors.white),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.06, 1.06),
                duration: 1400.ms,
                curve: Curves.easeInOut),
        const SizedBox(height: 16),
        Text(
          fileCount == 0
              ? emptyLabel
              : '$fileCount selected — tap to add more',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(tool.subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}
