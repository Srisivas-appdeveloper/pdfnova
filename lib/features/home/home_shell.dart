import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../services/shortcut_service.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + the strip under the tab content
// import '../../core/widgets/ad_banner.dart';
import '../files/files_tab.dart';
import '../settings/settings_tab.dart';
import 'home_screen.dart';
import 'tool_router.dart';
import 'tools.dart';

/// App frame: three tabs (Tools · Files · Settings) under one tab bar.
///
/// Changing tab uses a shared-axis slide that follows direction — moving
/// right slides content left and vice versa — so the tabs feel like a row
/// of pages rather than a stack of cards.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    ShortcutService.instance.listenToolLaunch((id) {
      if (mounted) _openToolByName(id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = await ShortcutService.instance.getInitialShortcut();
      if (id != null && mounted) _openToolByName(id);
    });
  }

  void _openToolByName(String name) {
    final tool = allTools.firstWhere(
      (t) => t.id.name.toLowerCase() == name.toLowerCase(),
      orElse: () => allTools.first,
    );
    openToolRoute(context, tool);
  }

  void _select(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _reverse = i < _tab;
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final reduced = NovaMotion.reduced(context);
    final page = switch (_tab) {
      0 => const HomeScreen(key: PageStorageKey('tools')),
      1 => FilesTab(
          key: const PageStorageKey('files'),
          onBrowseTools: () => _select(0)),
      _ => const SettingsTab(key: PageStorageKey('settings')),
    };
    return PopScope(
      // Back on a secondary tab returns to Tools before leaving the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: PageTransitionSwitcher(
          duration: reduced ? NovaMotion.quick : NovaMotion.page,
          reverse: _reverse,
          transitionBuilder: (child, primary, secondary) => reduced
              ? FadeTransition(opacity: primary, child: child)
              : SharedAxisTransition(
                  animation: primary,
                  secondaryAnimation: secondary,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: c.canvas,
                  child: child,
                ),
          child: KeyedSubtree(key: ValueKey(_tab), child: page),
        ),
        bottomNavigationBar: _NovaTabBar(index: _tab, onSelect: _select),
      ),
    );
  }
}

class _NovaTabBar extends StatelessWidget {
  const _NovaTabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Tools'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Files'),
    (Icons.tune_outlined, Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / _items.length;
            return Stack(children: [
              // Sliding pill behind the active item.
              AnimatedPositioned(
                duration: NovaMotion.page,
                curve: NovaMotion.emphasized,
                left: w * index + (w - 92) / 2,
                top: 10,
                width: 92,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Row(children: [
                for (final (i, (outline, filled, label)) in _items.indexed)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: i == index ? 1.0 : 0.92,
                              duration: NovaMotion.medium,
                              curve: Curves.easeOutBack,
                              child: AnimatedSwitcher(
                                duration: NovaMotion.quick,
                                child: Icon(
                                  i == index ? filled : outline,
                                  key: ValueKey(i == index),
                                  size: 22,
                                  color: i == index ? c.accent : c.inkLow,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedDefaultTextStyle(
                              duration: NovaMotion.quick,
                              style: t.labelSmall!.copyWith(
                                letterSpacing: 0.2,
                                fontSize: 11.5,
                                color: i == index ? c.accent : c.inkLow,
                              ),
                              child: Text(label),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}
