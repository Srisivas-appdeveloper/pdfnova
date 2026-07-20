import 'dart:io';
import 'dart:math' as math;
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + the rewarded gate in _withAd
// import '../../services/ad_service.dart';
import '../../services/file_service.dart';

/// Confetti + file card(s). Handles one output (open directly) or many
/// (batch / PDF→images: list + share-all). Save/Share runs through one
/// declared rewarded ad with a guaranteed no-fill fallback.
class SuccessView extends StatefulWidget {
  const SuccessView({super.key, required this.paths});
  final List<String> paths;

  @override
  State<SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<SuccessView> {
  late final ConfettiController _confetti =
      ConfettiController(duration: const Duration(milliseconds: 900));
  // ADS DISABLED FOR RELEASE — re-enable: restore the unlock flag + rewarded gate.
  // bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _withAd(void Function() action) {
    // ADS DISABLED FOR RELEASE — actions run directly. Re-enable: restore below.
    action();
    // if (_unlocked) return action();
    // AdService.instance.showRewardedThen(() {
    //   if (mounted) setState(() => _unlocked = true);
    //   action();
    // });
  }

  String _sizeLabel(String path) {
    final f = File(path);
    final kb = f.existsSync() ? f.lengthSync() / 1024 : 0;
    return kb > 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${kb.toStringAsFixed(0)} KB';
  }

  /// One save path for both buttons: real Downloads/PDFNova via MediaStore,
  /// honest fallbacks, and never a silent failure.
  Future<void> _save(String path) async {
    String message;
    try {
      final where = await FileService.instance.saveToDownloads(path);
      message = where.startsWith('Download/')
          ? 'Saved to $where — find it in your Files app.'
          : 'Saved inside the app folder. Use Share to send it anywhere.';
    } catch (_) {
      message = 'Could not save the file. Try Share instead.';
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.paths.length > 1;
    // ADS DISABLED FOR RELEASE — was: final adReady = AdService.instance.rewardedReady && !_unlocked;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                    gradient: AppColors.aurora, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 46, color: Colors.white),
              )
                  .animate()
                  .scale(
                      begin: const Offset(0, 0),
                      curve: Curves.elasticOut,
                      duration: 700.ms)
                  .then()
                  .shimmer(duration: 600.ms),
              const SizedBox(height: 18),
              Text(many ? '${widget.paths.length} files ready!' : 'Ready!',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.paths.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final path = widget.paths[i];
                    final name = path.split('/').last.toLowerCase();
                    final isImage = name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg');
                    final isText = name.endsWith('.txt');
                    final isPpt = name.endsWith('.pptx');
                    final isDoc = name.endsWith('.docx');

                    final icon = isPpt
                        ? Icons.slideshow_rounded
                        : isDoc
                            ? Icons.description_rounded
                            : isImage
                                ? Icons.image_rounded
                                : isText
                                    ? Icons.notes_rounded
                                    : Icons.picture_as_pdf_rounded;

                    return GlassCard(
                      strong: true,
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      onTap: () =>
                          _withAd(() => openAnyFile(context, path)),
                      child: Row(children: [
                        Icon(icon, color: AppColors.cyan, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.bodyLarge),
                              const SizedBox(height: 2),
                              Text(_sizeLabel(path),
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded, color: AppColors.cyan, size: 22),
                          onPressed: () => _withAd(() => _save(path)),
                        ),
                      ]),
                    )
                        .animate(delay: (60 * i).ms)
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.2);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    // ADS DISABLED — re-enable: restore adReady above and use
                    // label: adReady ? 'Watch ad · Open' : 'Open File',
                    // icon: adReady ? play_circle_outline : open_in_new
                    child: AuroraButton(
                      label: 'Open File',
                      icon: Icons.open_in_new_rounded,
                      onPressed: () => _withAd(() =>
                          openAnyFile(context, widget.paths.first)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassCard(
                      radius: 18,
                      strong: true,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      onTap: () => _withAd(() => _save(widget.paths.first)),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded, color: AppColors.cyan, size: 20),
                          SizedBox(width: 8),
                          Text('Save File',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.3),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _withAd(() => many
                    ? FileService.instance.shareAll(widget.paths)
                    : FileService.instance.share(widget.paths.first)),
                icon: const Icon(Icons.ios_share_rounded,
                    size: 18, color: AppColors.cyan),
                label: Text(many ? 'Share All' : 'Share',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.cyan)),
              ).animate().fadeIn(delay: 450.ms),
            ],
          ),
        ),
        ConfettiWidget(
          confettiController: _confetti,
          blastDirection: math.pi / 2,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.6,
          numberOfParticles: 18,
          maxBlastForce: 24,
          colors: const [AppColors.violet, AppColors.cyan, Colors.white],
        ),
      ],
    );
  }
}
