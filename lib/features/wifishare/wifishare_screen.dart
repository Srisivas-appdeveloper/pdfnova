import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
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
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.tool.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _url == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_tethering_rounded,
                        size: 52, color: AppColors.cyan),
                    const SizedBox(height: 16),
                    Text('Share without internet',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Both phones on the same WiFi or hotspot. Pick a file, the other phone scans the code in its camera or browser.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    AuroraButton(
                        label: 'Choose file & start',
                        icon: Icons.upload_file_rounded,
                        expanded: false,
                        onPressed: _start),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    GlassCard(
                      strong: true,
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16)),
                          child: QrImageView(data: _url!, size: 200),
                        ),
                        const SizedBox(height: 14),
                        Text(_fileName ?? '',
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 6),
                        SelectableText(_url!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.cyan)),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () async {
                        await WifiShareService.instance.stop();
                        setState(() => _url = null);
                      },
                      child: const Text('Stop sharing',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
