import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../tool/tool_header.dart';
import '../../services/file_service.dart';
import '../../services/wifi_share_service.dart';
import '../home/tools.dart';

/// WiFi share: serve one file over the local network; the other phone scans
/// the QR (or types the URL) in any browser. Works over hotspot with zero
/// internet — pure dart:io HttpServer.
class WifiShareScreen extends StatefulWidget {
  const WifiShareScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<WifiShareScreen> createState() => _WifiShareScreenState();
}

class _WifiShareScreenState extends State<WifiShareScreen> {
  String? _url;
  String? _fileName;

  @override
  void dispose() {
    WifiShareService.instance.stop();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final picked = await FileService.instance.pickPdfs();
      if (picked.isEmpty) return;
      // Write picked bytes to a temp-served copy via vault-adjacent temp file.
      final path = await FileService.instance.persistTemp(picked.first);
      final url = await WifiShareService.instance.start(path);
      if (!mounted) return;
      if (url == null) {
        // No LAN interface (only cellular/VPN), or no free port — say so
        // instead of silently sitting on the picker.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not start sharing. Join a WiFi network or hotspot, then try again.')));
        return;
      }
      setState(() {
        _url = url;
        _fileName = picked.first.name;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Something went wrong while sharing. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(),
      body: AnimatedSwitcher(
        duration: NovaMotion.page,
        switchInCurve: NovaMotion.emphasized,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
        ),
        child: _url == null
            ? ListView(
                key: const ValueKey('idle'),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  ToolHeader(tool: widget.tool),
                  for (final (i, (icon, text)) in const [
                    (Icons.wifi_rounded,
                        'Both phones on the same WiFi or hotspot — no internet needed.'),
                    (Icons.qr_code_2_rounded,
                        'The other phone scans the code with its camera, or types the link in any browser.'),
                    (Icons.timer_outlined,
                        'Sharing stops when you tap Stop or leave this screen.'),
                  ].indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NovaCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          NovaIconTile(icon: icon, size: 40),
                          const SizedBox(width: 14),
                          Expanded(child: Text(text, style: t.bodyMedium)),
                        ]),
                      ).enter(context, index: i, delayMs: 200),
                    ),
                  const SizedBox(height: 14),
                  NovaButton(
                      label: 'Choose file & start',
                      icon: Icons.upload_file_rounded,
                      onPressed: _start),
                ],
              )
            : ListView(
                key: const ValueKey('live'),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: c.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text('Sharing now', style: t.titleMedium),
                  ]),
                  const SizedBox(height: 16),
                  NovaCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white, // QR needs a light ground
                            borderRadius: BorderRadius.circular(18)),
                        child: QrImageView(data: _url!, size: 210),
                      ),
                      const SizedBox(height: 18),
                      Text(_fileName ?? '',
                          textAlign: TextAlign.center,
                          style: t.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(_url!,
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: c.accent)),
                    ]),
                  ).enter(context),
                  const SizedBox(height: 16),
                  NovaButton.secondary(
                    label: 'Stop sharing',
                    icon: Icons.stop_circle_outlined,
                    color: c.danger,
                    onPressed: () async {
                      await WifiShareService.instance.stop();
                      setState(() => _url = null);
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
