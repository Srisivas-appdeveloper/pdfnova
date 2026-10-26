import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/nova_button.dart';
import '../../core/widgets/nova_card.dart';
import '../../core/widgets/nova_controls.dart';
import '../../core/widgets/nova_entrance.dart';
import '../../core/widgets/nova_dialog.dart';
import '../../services/file_service.dart';
import '../../services/secure_window.dart';
import '../../services/vault_service.dart';
import '../files/file_row.dart';
import '../tool/tool_header.dart';
import '../tool/tool_stages.dart';
import '../home/tools.dart';
import '../viewer/viewer_screen.dart';

/// Vault: biometric-gated, AES-256-GCM encrypted private folder (see
/// VaultService). Files are encrypted on the way in, decrypted only into
/// app-private temp storage to view, and wiped from there on lock.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.tool});
  final Tool tool;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  final _vault = VaultService.instance;
  bool _unlocked = false;
  bool _busy = false;
  List<VaultEntry> _entries = [];
  int _legacyCount = 0;
  String? _error;
  // True while we sent the user to the system file picker ourselves. That
  // pause is ours: it must not re-lock the vault mid-pick.
  bool _ownPause = false;
  DateTime? _pausedAt;

  /// Even after the vault's own hand-off to the picker, coming back
  /// after longer than this requires authenticating again.
  static const relockAfter = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecureWindow.set(true);
    // Decrypted copies from an earlier session must not linger.
    _vault.purgeTemp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecureWindow.set(false);
    _lock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Policy (docs/SECURITY.md): leaving the app re-locks the vault, except
    // for the vault's own hand-off to the file picker — and even that
    // re-lock if the user is away longer than [relockAfter].
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      if (_unlocked && !_ownPause) {
        _closeViewer();
        setState(_lock);
      }
    }
    if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      _ownPause = false;
      _pausedAt = null;
      if (_unlocked && away > relockAfter) {
        _closeViewer();
        setState(_lock);
      }
    }
  }

  void _lock() {
    _unlocked = false;
    _entries = [];
    _vault.lock();
    _vault.purgeTemp();
  }

  Future<void> _unlock() async {
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
      _snack(notEnrolled
          ? 'No fingerprint or screen lock is set up on this device. Set one up in Settings to use the Vault.'
          : 'Could not verify your identity. Please try again.');
      return;
    }
    if (!ok || !mounted) return;
    setState(() => _unlocked = true);
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      final entries = await _vault.list();
      final legacy = await _vault.legacyFiles();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _legacyCount = legacy.length;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addFile() async {
    _ownPause = true;
    final picked = await FileService.instance.pickPdfs();
    _ownPause = false;
    if (picked.isEmpty) return;
    await _run(() async {
      await _vault.add(picked.first.name, picked.first.bytes);
      _snack(
          'Encrypted and added to the vault. Your original file was not changed.');
    });
  }

  /// Opens in the app's own Reader. Handing the decrypted copy to another
  /// app let it cache the file and screenshot it, outside the vault's
  /// re-lock; here screenshots stay blocked and the copy is deleted when
  /// the Reader closes (or the vault locks).
  Future<void> _open(VaultEntry e) => _run(() async {
        final file = await _vault.exportToTemp(e);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ViewerScreen(
              tool: allTools.firstWhere((t) => t.id == ToolId.viewer),
              initialPath: file.path),
        ));
        try {
          file.parent.deleteSync(recursive: true);
        } catch (_) {}
      });

  /// Closes a Reader showing a vault file, so locking hides it too.
  void _closeViewer() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
  }

  Future<void> _delete(VaultEntry e) async {
    final ok = await _confirm(
      title: 'Delete from vault?',
      body: '"${e.name}" will be permanently removed from the vault.',
      action: 'Delete',
    );
    if (ok == true) await _run(() => _vault.delete(e));
  }

  Future<void> _migrate() async {
    final ok = await _confirm(
      title: 'Encrypt older files?',
      body:
          '$_legacyCount ${_legacyCount == 1 ? 'file was' : 'files were'} added before the vault used encryption. '
          'Each one is encrypted, decrypted again and compared. Only after that check passes is the unencrypted copy removed. '
          'If anything fails, the original stays exactly as it is.',
      action: 'Encrypt now',
      destructive: false,
    );
    if (ok != true) return;
    await _run(() async {
      final r = await _vault.migrateLegacy();
      _snack(r.failed.isEmpty
          ? 'Encrypted ${r.migrated.length} ${r.migrated.length == 1 ? 'file' : 'files'}.'
          : 'Encrypted ${r.migrated.length}; ${r.failed.length} could not be encrypted and were left unchanged.');
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = true,
  }) =>
      showNovaDialog<bool>(
        context: context,
        builder: (d) {
          final t = Theme.of(d).textTheme;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.headlineSmall),
                  const SizedBox(height: 8),
                  Text(body, style: t.bodyMedium),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: NovaButton.secondary(
                          label: 'Cancel',
                          onPressed: () => Navigator.pop(d, false)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NovaButton(
                          label: action,
                          color: destructive ? d.nova.danger : null,
                          onPressed: () => Navigator.pop(d, true)),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );

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
              onPressed: () => setState(_lock),
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
              duration: NovaMotion.ambient,
              curve: Curves.easeOut)
          .fadeOut(duration: NovaMotion.ambient);
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
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
        child: Row(children: [
          Text('Vault', style: t.headlineLarge),
          const SizedBox(width: 10),
          Icon(Icons.lock_open_rounded, size: 20, color: c.success),
          const Spacer(),
          Text('${_entries.length} ${_entries.length == 1 ? 'file' : 'files'}',
              style: t.bodyMedium),
        ]).enter(context),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
        child: Row(children: [
          Icon(Icons.enhanced_encryption_outlined, size: 15, color: c.inkLow),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                'AES-256 encrypted on this phone. Re-locks when you leave.',
                style: t.bodySmall),
          ),
        ]),
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (_legacyCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: NovaCard(
            color: c.accentSoft,
            borderColor: Colors.transparent,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.shield_outlined, color: c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    '$_legacyCount older ${_legacyCount == 1 ? 'file is' : 'files are'} not encrypted yet.',
                    style: t.titleSmall),
              ),
              TextButton(
                  onPressed: _busy ? null : _migrate,
                  child: const Text('Encrypt')),
            ]),
          ).enter(context),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: ToolNote(_error!, icon: Icons.error_outline_rounded),
        ),
      Expanded(
        child: _entries.isEmpty
            ? Center(
                child: Text(
                    _legacyCount > 0
                        ? 'Encrypt your older files to see them here.'
                        : 'The vault is empty — add a PDF below.',
                    style: t.bodyMedium))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final e = _entries[i];
                  return NovaCard(
                    radius: 18,
                    onTap: e.damaged || _busy ? null : () => _open(e),
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                    child: Row(children: [
                      NovaIconTile(
                          icon: e.damaged
                              ? Icons.report_gmailerrorred_rounded
                              : Icons.picture_as_pdf_outlined,
                          fg: c.danger,
                          bg: c.dangerSoft,
                          size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleSmall),
                            Text(
                                e.damaged
                                    ? 'Cannot be decrypted — kept, not deleted'
                                    : formatBytes(e.size),
                                style: t.bodySmall?.copyWith(
                                    color: e.damaged ? c.danger : null)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: c.danger, size: 20),
                        onPressed: _busy ? null : () => _delete(e),
                      ),
                    ]),
                  ).enter(context, index: i);
                },
              ),
      ),
      ToolActionBar(
        child: NovaButton(
            label: 'Add PDF to vault',
            icon: Icons.add_rounded,
            onPressed: _busy ? null : _addFile),
      ),
    ]);
  }
}
