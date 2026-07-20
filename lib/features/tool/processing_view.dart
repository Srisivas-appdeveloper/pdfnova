import 'package:flutter/material.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + banner creation in initState + ad card in build
// import 'package:google_mobile_ads/google_mobile_ads.dart';
// import '../../core/widgets/glass_card.dart'; // only used by the ad card
import '../../core/widgets/liquid_progress.dart';
// import '../../services/ad_service.dart';

/// Shown while the real work runs: liquid ring + a native-style ad slot
/// below in a glass card, clearly labelled. The wait is genuine — the ad
/// simply keeps the screen earning while Syncfusion crunches.
class ProcessingView extends StatefulWidget {
  const ProcessingView({super.key, required this.progress, required this.label});
  final double progress;
  final String label;

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView> {
  // ADS DISABLED FOR RELEASE — re-enable: restore banner fields + initState + dispose below.
  // BannerAd? _ad;
  // bool _loaded = false;
  //
  // @override
  // void initState() {
  //   super.initState();
  //   _ad = AdService.instance
  //       .createBanner(onLoaded: (_) => setState(() => _loaded = true));
  // }
  //
  // @override
  // void dispose() {
  //   _ad?.dispose();
  //   super.dispose();
  // }

  @override
  Widget build(BuildContext context) {
    // NOTE: no entrance .animate() here — the bloc re-emits progress every
    // 90ms and flutter_animate replays on each rebuild, which made the whole
    // screen flicker/jump during conversion. The AnimatedSwitcher in
    // ToolScreen already handles the one-time entrance.
    //
    // Rigid centering: a fixed-width content box inside Center — the ring and
    // texts share one axis and sit at the exact screen centre on every
    // device, no matter what constraints the parent passes down.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LiquidProgress(progress: widget.progress),
              const SizedBox(height: 28),
              Text(widget.label,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Processing on your phone — nothing leaves it.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
          // ADS DISABLED FOR RELEASE — re-enable: restore the ad card below.
          // const Spacer(),
          // if (_loaded && _ad != null)
          //   GlassCard(
          //     padding: const EdgeInsets.all(10),
          //     radius: 18,
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.start,
          //       children: [
          //         Text('Ad',
          //             style: Theme.of(context)
          //                 .textTheme
          //                 .bodyMedium
          //                 ?.copyWith(fontSize: 10, letterSpacing: 1)),
          //         const SizedBox(height: 6),
          //         SizedBox(
          //           width: _ad!.size.width.toDouble(),
          //           height: _ad!.size.height.toDouble(),
          //           child: AdWidget(ad: _ad!),
          //         ),
          //       ],
          //     ),
          //   ).animate().fadeIn(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
