import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/file_open.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../services/file_service.dart';
import '../files/file_row.dart';
// ADS DISABLED FOR RELEASE — re-enable: import ad_service.dart and route the
// actions in _withAd through AdService.instance.showRewardedThen.

/// Result screen: a check mark that draws itself inside an expanding ring,
/// then the output file card(s) and actions. One output → Open / Save /
/// Share; many (batch, PDF → images) → a list with Share all.
class SuccessView extends StatelessWidget {
  const SuccessView({super.key, required this.paths});
  final List<String> paths;

  void _withAd(void Function() action) => action();

  Future<void> _save(BuildContext context, String path) async {
    String message;
    try {
      final where = await FileService.instance.saveToDownloads(path);
      message = where.startsWith('Download/')
          ? 'Saved to $where — find it in your Files app.'
          : 'Saved inside the app folder. Use Share to send it anywhere.';
    } catch (_) {
      message = 'Could not save the file. Try Share instead.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final many = paths.length > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const _DoneMark(),
          const SizedBox(height: 22),
          Text(many ? '${paths.length} files ready' : 'Done.',
                  style: t.displaySmall)
              .enter(context, delayMs: 350),
          const SizedBox(height: 6),
          Text('Saved privately in the app. Save or share it below.',
                  style: t.bodyMedium, textAlign: TextAlign.center)
              .enter(context, delayMs: 420),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: paths.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final path = paths[i];
                final (icon, (fg, bg)) = fileLook(context, path);
                return NovaCard(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  onTap: () => _withAd(() => openAnyFile(context, path)),
                  child: Row(children: [
                    NovaIconTile(icon: icon, fg: fg, bg: bg, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall),
                          const SizedBox(height: 3),
                          Text(fileSize(path), style: t.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Save to Downloads',
                      icon: Icon(Icons.download_rounded, color: c.accent),
                      onPressed: () => _withAd(() => _save(context, path)),
                    ),
                  ]),
                ).enter(context, index: i, delayMs: 480);
              },
            ),
          ),
          const SizedBox(height: 14),
          Column(children: [
            NovaButton(
              label: many ? 'Open first file' : 'Open',
              icon: Icons.open_in_new_rounded,
              onPressed: () =>
                  _withAd(() => openAnyFile(context, paths.first)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: NovaButton.secondary(
                  label: 'Save',
                  icon: Icons.download_rounded,
                  onPressed: () =>
                      _withAd(() => _save(context, paths.first)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NovaButton.secondary(
                  label: many ? 'Share all' : 'Share',
                  icon: Icons.ios_share_rounded,
                  onPressed: () => _withAd(() => many
                      ? FileService.instance.shareAll(paths)
                      : FileService.instance.share(paths.first)),
                ),
              ),
            ]),
          ]).enter(context, delayMs: 560),
        ],
      ),
    );
  }
}

/// Ring scales open with a soft pulse, then the tick draws on.
class _DoneMark extends StatefulWidget {
  const _DoneMark();

  @override
  State<_DoneMark> createState() => _DoneMarkState();
}

class _DoneMarkState extends State<_DoneMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    NovaMotion.reduced(context) ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final ring = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
    final tick = CurvedAnimation(
        parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic));
    final pulse = CurvedAnimation(
        parent: _c, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    return SizedBox.square(
      dimension: 112,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          // Fading pulse ring.
          Opacity(
            opacity: (1 - pulse.value) * 0.6,
            child: Container(
              width: 84 + 28 * pulse.value,
              height: 84 + 28 * pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.success, width: 1.5),
              ),
            ),
          ),
          Transform.scale(
            scale: ring.value,
            child: Container(
              width: 84,
              height: 84,
              decoration:
                  BoxDecoration(color: c.successSoft, shape: BoxShape.circle),
              child: CustomPaint(painter: _TickPainter(tick.value, c.success)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.3, s.height * 0.52)
      ..lineTo(s.width * 0.45, s.height * 0.66)
      ..lineTo(s.width * 0.71, s.height * 0.38);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final ui.PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t || old.color != color;
}
