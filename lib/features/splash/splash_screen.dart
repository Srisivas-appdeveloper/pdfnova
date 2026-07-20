import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/routes/slide_up_route.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/gradient_background.dart';
import '../home/home_screen.dart';

/// Opening moment: aurora blobs breathe in, the mark scales up with an
/// elastic pop, the wordmark slides up from below, a light ring expands —
/// then the whole thing hands over to Home with the slide-up transition.
/// Total 1.6s; tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), _go);
  }

  void _go() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context)
        .pushReplacement(SlideUpRoute(page: const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _go,
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(alignment: Alignment.center, children: [
                  // Expanding light ring behind the mark
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.cyan.withOpacity(0.5), width: 1.5),
                    ),
                  )
                      .animate()
                      .scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1.6, 1.6),
                          duration: 900.ms,
                          curve: Curves.easeOutCubic)
                      .fadeOut(duration: 900.ms),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: AppColors.aurora,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.violet.withOpacity(0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 44),
                  )
                      .animate()
                      .scale(
                          begin: const Offset(0, 0),
                          duration: 700.ms,
                          curve: Curves.elasticOut)
                      .then(delay: 100.ms)
                      .shimmer(duration: 500.ms),
                ]),
                const SizedBox(height: 26),
                ShaderMask(
                  shaderCallback: (r) => AppColors.aurora.createShader(r),
                  child: Text('PDF Nova',
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(fontSize: 36, color: Colors.white)),
                )
                    .animate(delay: 350.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.4, curve: Curves.easeOutCubic),
                const SizedBox(height: 8),
                Text('Your PDFs. Your phone. Nothing uploaded.',
                        style: Theme.of(context).textTheme.bodyMedium)
                    .animate(delay: 550.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.5, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
