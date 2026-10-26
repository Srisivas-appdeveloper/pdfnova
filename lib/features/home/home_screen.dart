import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_background.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../core/widgets/nova_mark.dart';
import 'tools.dart';
import 'widgets/tool_card.dart';

/// Tools tab: artwork header with parallax, a search bar that pins under
/// the status bar, then each tool family as a two-column grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();
  final _offset = ValueNotifier<double>(0);
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _offset.value = _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _offset.dispose();
    _query.dispose();
    super.dispose();
  }

  static bool _available(Tool t) => !t.androidOnly || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final q = _query.text.trim().toLowerCase();
    final total = allTools.where(_available).length;
    final matches = q.isEmpty
        ? const <Tool>[]
        : [
            for (final t in allTools)
              if (_available(t) &&
                  (t.title.toLowerCase().contains(q) ||
                      t.subtitle.toLowerCase().contains(q)))
                t
          ];
    // Cards grow with the system font size instead of clipping text.
    final cardHeight = 104 + 46 * MediaQuery.textScalerOf(context).scale(1);

    final top = MediaQuery.paddingOf(context).top;
    const headerHeight = 286.0;
    // The pinned search bar grows with the system text size.
    final searchExtent =
        _SearchHeader.extentFor(MediaQuery.textScalerOf(context));
    final artHeight = top + headerHeight + searchExtent;

    return Stack(children: [
      // Artwork lives behind the scroll view: it drifts up at half speed
      // (parallax) and stretches when you pull down past the top.
      ValueListenableBuilder<double>(
        valueListenable: _offset,
        builder: (_, o, art) => Positioned(
          top: o > 0 ? -o * 0.5 : 0,
          left: 0,
          right: 0,
          height: artHeight,
          child: Transform.scale(
            scale: o < 0 ? 1 + (-o / artHeight) : 1,
            alignment: Alignment.topCenter,
            child: art,
          ),
        ),
        child: NovaArt(height: artHeight),
      ),
      Padding(
        padding: EdgeInsets.only(top: top),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(height: headerHeight, toolCount: total),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchHeader(
                  extent: searchExtent,
                  canvas: c.canvas,
                  border: c.border,
                  child: NovaField(
                    controller: _query,
                    hint: 'Search $total tools',
                    icon: Icons.search_rounded,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              if (q.isNotEmpty) ...[
                if (matches.isEmpty)
                  SliverToBoxAdapter(child: _NoMatch(query: _query.text.trim()))
                else
                  _grid(matches, cardHeight),
              ] else
                for (final section in toolSections) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
                    sliver: SliverToBoxAdapter(
                      child: NovaEyebrow(
                        section.title,
                        trailing: Text(
                            '${section.tools.where(_available).length}',
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                    ),
                  ),
                  _grid(section.tools.where(_available).toList(), cardHeight),
                ],
              SliverToBoxAdapter(
                  child: SizedBox(
                      height: 32 + MediaQuery.paddingOf(context).bottom)),
            ],
          ),
        ),
      ),
      // Status-bar strip fills with canvas once content scrolls beneath it.
      ValueListenableBuilder<double>(
        valueListenable: _offset,
        builder: (_, o, __) => Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: ColoredBox(
              color: c.canvas.withValues(
                  alpha: ((o - headerHeight + 60) / 60).clamp(0.0, 1.0)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _grid(List<Tool> tools, double height) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: height,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ToolCard(tool: tools[i]).enter(context, index: i),
            childCount: tools.length,
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.height, required this.toolCount});
  final double height;
  final int toolCount;

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    // [height] is a minimum: with large system text or a narrow screen the
    // headline wraps further and the header grows instead of overflowing.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: IntrinsicHeight(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const NovaMark(size: 28),
                const SizedBox(width: 10),
                // Flexible + ellipsis: with very large system text the
                // wordmark and chip share the row instead of overflowing.
                Expanded(
                  child: Text('PDF Nova',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMedium),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: c.success),
                    const SizedBox(width: 5),
                    Text('On-device',
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 1.3),
                        style: t.labelMedium
                            ?.copyWith(color: c.ink, fontSize: 12)),
                  ]),
                ),
              ]).enter(context, delayMs: 150),
              const Spacer(),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Every document,\n'),
                  TextSpan(
                      text: 'handled privately.',
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: c.accent)),
                ]),
                style: t.displaySmall,
              ).enter(context, delayMs: 250),
              const SizedBox(height: 10),
              Text('$toolCount tools. Nothing leaves your phone.',
                      style: t.bodyMedium)
                  .enter(context, delayMs: 330),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search bar that sticks under the status bar; a hairline appears under
/// it once content scrolls beneath.
class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({
    required this.extent,
    required this.child,
    required this.canvas,
    required this.border,
  });

  final Widget child;
  final Color canvas;
  final Color border;

  final double extent;

  /// 80 at normal size; taller for larger system text so the field fits.
  static double extentFor(TextScaler s) =>
      (80 + (s.scale(15.5) - 15.5) * 1.4).clamp(80.0, 140.0);

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // Transparent over the artwork; solid canvas with a hairline once pinned.
    final pinned = overlaps || shrinkOffset > 0;
    return AnimatedContainer(
      duration: NovaMotion.quick,
      decoration: BoxDecoration(
        color: pinned ? canvas : canvas.withValues(alpha: 0),
        border: Border(
            bottom: BorderSide(
                color: pinned ? border : border.withValues(alpha: 0))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) => true;
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Column(children: [
        Icon(Icons.search_off_rounded, size: 40, color: context.nova.inkLow),
        const SizedBox(height: 14),
        Text('No tool matches "$query"',
            style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Try a shorter word, like "merge" or "word".',
            style: t.bodyMedium, textAlign: TextAlign.center),
      ]).enter(context),
    );
  }
}
