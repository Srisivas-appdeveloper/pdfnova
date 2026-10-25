import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
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

  Future<void> _delete(FileSystemEntity f) async {
    await File(f.path).delete();
    final dir = await _vaultDir();
    setState(() => _files = dir.listSync().whereType<File>().toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nova;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        actions: [
          if (_unlocked)
            NovaIconButton(
              tooltip: 'Lock',
              icon: Icons.lock_outline_rounded,
              onPressed: () => setState(() {
                _unlocked = false;
                _files = [];
              }),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: AnimatedSwitcher(
        duration: NovaMotion.page,
        switchInCurve: NovaMotion.emphasized,
        switchOutCurve: NovaMotion.accelerate,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
        ),
        child: _unlocked ? _openView(context) : _lockedView(context),
      ),
    );
  }

  Widget _lockedView(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    final reduced = NovaMotion.reduced(context);
    Widget ring = Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.success.withValues(alpha: 0.35)),
      ),
    );
    if (!reduced) {
      ring = ring
          .animate(onPlay: (a) => a.repeat())
          .scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.25, 1.25),
              duration: 1800.ms,
              curve: Curves.easeOut)
          .fadeOut(duration: 1800.ms);
    }
    return Center(
      key: const ValueKey('locked'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox.square(
            dimension: 160,
            child: Stack(alignment: Alignment.center, children: [
              ring,
              GestureDetector(
                onTap: _unlock,
                child: NovaIconTile(
                  icon: Icons.fingerprint_rounded,
                  fg: c.success,
                  bg: c.successSoft,
                  size: 96,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Private vault', style: t.headlineLarge),
          const SizedBox(height: 6),
          Text('Locked behind your fingerprint, face or screen lock.',
              style: t.bodyMedium, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          NovaButton(
              label: 'Unlock',
              icon: Icons.lock_open_rounded,
              expanded: false,
              onPressed: _unlock),
        ]).enter(context, delayMs: 120),
      ),
    );
  }

  Widget _openView(BuildContext context) {
    final c = context.nova;
    final t = Theme.of(context).textTheme;
    return Column(key: const ValueKey('open'), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Row(children: [
          Text('Vault', style: t.headlineLarge),
          const SizedBox(width: 10),
          Icon(Icons.lock_open_rounded, size: 20, color: c.success),
          const Spacer(),
          Text('${_files.length} ${_files.length == 1 ? 'file' : 'files'}',
              style: t.bodyMedium),
        ]).enter(context),
      ),
      Expanded(
        child: _files.isEmpty
            ? Center(
                child: Text('The vault is empty — add a PDF below.',
                    style: t.bodyMedium))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final f = _files[i];
                  return NovaCard(
                    radius: 18,
                    onTap: () => FileService.instance.open(f.path),
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                    child: Row(children: [
                      NovaIconTile(
                          icon: Icons.picture_as_pdf_outlined,
                          fg: c.danger,
                          bg: c.dangerSoft,
                          size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Text(f.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall)),
                      IconButton(
                        tooltip: 'Delete',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: c.danger, size: 20),
                        onPressed: () => _delete(f),
                      ),
                    ]),
                  ).enter(context, index: i);
                },
              ),
      ),
      Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: c.canvas,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: NovaButton(
            label: 'Add PDF to vault',
            icon: Icons.add_rounded,
            onPressed: _addFile),
      ),
    ]);
  }
}
