import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../core/widgets/nova_mark.dart';
import '../../services/storage_service.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final storage = StorageService.instance;
    var i = 0;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: NovaEyebrow(title),
              ),
              child,
            ],
          ).enter(context, index: i++, delayMs: 60),
        );

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            20, 28, 20, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 26),
            child: Text('Settings', style: t.displaySmall).enter(context),
          ),
          section(
            'Appearance',
            NovaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text('Follow your phone, or pick one.', style: t.bodySmall),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: storage.themeMode,
                    builder: (_, mode, __) => NovaSegmented<ThemeMode>(
                      value: mode,
                      onChanged: storage.setThemeMode,
                      options: const [
                        (ThemeMode.system, 'Auto', Icons.brightness_auto_outlined),
                        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<bool>(
                    valueListenable: storage.reduceMotion,
                    builder: (_, on, __) => SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: on,
                      onChanged: storage.setReduceMotion,
                      title: Text('Reduce motion', style: t.titleMedium),
                      subtitle: Text(
                          'Simple fades instead of moving transitions.',
                          style: t.bodySmall),
                    ),
                  ),
                ],
              ),
            ),
          ),
          section(
            'Privacy',
            NovaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    NovaIconTile(
                        icon: Icons.lock_outline_rounded,
                        fg: c.success,
                        bg: c.successSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('Everything runs on this phone',
                          style: t.titleMedium),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  for (final (icon, text) in const [
                    (Icons.cloud_off_outlined,
                        'Your files are never uploaded. Every tool works offline.'),
                    (Icons.folder_outlined,
                        'Results stay in the app until you save them to Download/PDFNova or share them.'),
                    (Icons.wifi_tethering_rounded,
                        'WiFi share only serves the file you pick, on your local network, while the screen is open.'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 18, color: c.inkLow),
                          const SizedBox(width: 12),
                          Expanded(child: Text(text, style: t.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          section(
            'About',
            NovaCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Row(children: [
                    const NovaMark(size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PDF Nova', style: t.headlineSmall),
                          Text('Your private PDF toolkit', style: t.bodySmall),
                        ],
                      ),
                    ),
                  ]),
                ),
                Divider(height: 1, color: c.border),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(Icons.article_outlined, color: c.inkMid),
                  title: const Text('Open-source licences'),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.inkLow),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'PDF Nova',
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: NovaMark(size: 48),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
