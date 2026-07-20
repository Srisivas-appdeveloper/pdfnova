import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/glass_button.dart';
import '../../core/widgets/gradient_background.dart';
import '../../services/file_service.dart';
import '../home/tools.dart';

/// Vault: biometric-gated private folder inside app storage. Files are
/// copied here and can only be listed after fingerprint / face / device-PIN
/// unlock. (App-private storage means other apps can't browse it.)
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _auth = LocalAuthentication();
  bool _unlocked = false;
  List<FileSystemEntity> _files = [];

  Future<Directory> _vaultDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/PDFNovaVault')..createSync(recursive: true);
  }

  Future<void> _unlock() async {
    // Check if the device has biometric hardware and enrolled credentials.
    final canCheck = await _auth.canCheckBiometrics;
    final isDeviceSupported = await _auth.isDeviceSupported();

    if (!canCheck && !isDeviceSupported) {
      // No biometrics at all — device PIN/pattern fallback is still valid.
      // local_auth will use device credentials automatically.
    }

    bool ok = false;
    try {
      ok = await _auth.authenticate(
        localizedReason: 'Unlock your private PDF vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow device PIN as fallback
        ),
      );
    } on Exception catch (e) {
      // SECURITY: never unlock on error. If nothing is enrolled (no
      // fingerprint AND no device PIN), the vault stays locked and the
      // user is told how to fix it — opening without auth would make the
      // lock meaningless.
      if (!mounted) return;
      final msg = e.toString();
      final notEnrolled =
          msg.contains('NotEnrolled') || msg.contains('notEnrolled');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notEnrolled
              ? 'No fingerprint or screen lock is set up on this device. Set one up in Settings to use the Vault.'
              : 'Could not verify your identity. Please try again.'),
        ),
      );
      return;
    }

    if (!ok || !mounted) return;
    final dir = await _vaultDir();
    setState(() {
      _unlocked = true;
      _files = dir.listSync().whereType<File>().toList();
    });
  }

  Future<void> _addFile() async {
    final picked = await FileService.instance.pickPdfs();
    if (picked.isEmpty) return;
    final dir = await _vaultDir();
    final dest = File('${dir.path}/${picked.first.name}');
    await dest.writeAsBytes(picked.first.bytes, flush: true);
    setState(() => _files = dir.listSync().whereType<File>().toList());
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.tool.title)),
        body: !_unlocked
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                          gradient: AppColors.aurora, shape: BoxShape.circle),
                      child: const Icon(Icons.fingerprint_rounded,
                          size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text('Your private files',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('Locked behind your fingerprint or face.',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    AuroraButton(
                        label: 'Unlock',
                        icon: Icons.lock_open_rounded,
                        expanded: false,
                        onPressed: _unlock),
                  ]),
                ),
              )
            : Column(children: [
                Expanded(
                  child: _files.isEmpty
                      ? Center(
                          child: Text('Vault is empty — add a PDF below.',
                              style: Theme.of(context).textTheme.bodyMedium))
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: _files.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final f = _files[i];
                            return GlassCard(
                              radius: 18,
                              onTap: () => FileService.instance.open(f.path),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(children: [
                                const Icon(Icons.picture_as_pdf_rounded,
                                    color: AppColors.cyan),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(f.path.split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: AppColors.danger, size: 20),
                                  onPressed: () async {
                                    await File(f.path).delete();
                                    final dir = await _vaultDir();
                                    setState(() => _files = dir
                                        .listSync()
                                        .whereType<File>()
                                        .toList());
                                  },
                                ),
                              ]),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: AuroraButton(
                      label: 'Add PDF to vault',
                      icon: Icons.add_rounded,
                      onPressed: _addFile),
                ),
              ]),
      ),
    );
  }
}
