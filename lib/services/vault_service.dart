import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Encrypted private vault.
///
/// Design (see docs/SECURITY.md):
/// - AES-256-GCM (authenticated) from package:cryptography — native on
///   Android/iOS via cryptography_flutter, pure Dart in tests.
/// - One random 256-bit key per install, kept in platform secure storage
///   (Android Keystore-wrapped / iOS Keychain, this device only). The key is
///   NOT bound to biometrics, so enrolling a new fingerprint never makes the
///   vault unreadable; biometrics gate the UI.
/// - Each document is two blobs: `<id>.nvd` (content) and `<id>.nvm`
///   (metadata JSON: name, size, date, SHA-256). Blob layout is
///   `PNV1 | nonce(12) | ciphertext | tag(16)`, with `PNV1|kind|id` as
///   associated data so blobs can't be swapped between entries.
/// - Writes go to `.tmp` then rename, so a crash never leaves a half file
///   in place of a good one.
class VaultService {
  VaultService({
    Future<Directory> Function()? vaultDir,
    Future<Directory> Function()? tempDir,
    VaultKeyStore? keyStore,
  })  : _vaultDir = vaultDir ?? _defaultVaultDir,
        _tempDir = tempDir ?? _defaultTempDir,
        _keys = keyStore ?? SecureVaultKeyStore();

  static final VaultService instance = VaultService();

  static final _magic = utf8.encode('PNV1');
  static const _dataExt = '.nvd';
  static const _metaExt = '.nvm';
  static final _cipher = AesGcm.with256bits();

  final Future<Directory> Function() _vaultDir;
  final Future<Directory> Function() _tempDir;
  final VaultKeyStore _keys;
  SecretKey? _key;

  static Future<Directory> _defaultVaultDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/PDFNovaVault')..createSync(recursive: true);
  }

  static Future<Directory> _defaultTempDir() async {
    final dir = await getTemporaryDirectory();
    return Directory('${dir.path}/vault_open')..createSync(recursive: true);
  }

  // ---- Key ---------------------------------------------------------------

  Future<SecretKey> _secretKey() async {
    if (_key != null) return _key!;
    final stored = await _keys.read();
    if (stored != null) return _key = SecretKey(stored);
    // No key. Only create one if there is nothing encrypted to orphan —
    // otherwise a fresh key would make existing files permanently unreadable.
    final dir = await _vaultDir();
    final hasEncrypted = dir
        .listSync()
        .any((f) => f.path.endsWith(_dataExt) || f.path.endsWith(_metaExt));
    if (hasEncrypted) throw const VaultKeyMissingException();
    final fresh = await _cipher.newSecretKey();
    final bytes = Uint8List.fromList(await fresh.extractBytes());
    await _keys.write(bytes);
    return _key = fresh;
  }

  /// Forget the in-memory key (e.g. when the vault screen locks).
  void lock() => _key = null;

  // ---- Blob crypto -------------------------------------------------------

  List<int> _aad(String kind, String id) =>
      [..._magic, ...utf8.encode('|$kind|$id')];

  Future<Uint8List> _seal(List<int> plain, String kind, String id) async {
    final box = await _cipher.encrypt(plain,
        secretKey: await _secretKey(), aad: _aad(kind, id));
    return Uint8List.fromList(
        [..._magic, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> _open(Uint8List blob, String kind, String id) async {
    const n = 12, t = 16;
    if (blob.length < 4 + n + t || !_sameBytes(blob.sublist(0, 4), _magic)) {
      throw const VaultCorruptException('Not a PDF Nova vault file');
    }
    final box = SecretBox(blob.sublist(4 + n, blob.length - t),
        nonce: blob.sublist(4, 4 + n), mac: Mac(blob.sublist(blob.length - t)));
    try {
      return Uint8List.fromList(await _cipher.decrypt(box,
          secretKey: await _secretKey(), aad: _aad(kind, id)));
    } on SecretBoxAuthenticationError {
      throw const VaultCorruptException(
          'This file was changed or damaged and cannot be decrypted');
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<void> _atomicWrite(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _sha256(List<int> bytes) async =>
      base64Encode((await Sha256().hash(bytes)).bytes);

  // ---- Public API --------------------------------------------------------

  Future<List<VaultEntry>> list() async {
    final dir = await _vaultDir();
    final entries = <VaultEntry>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith(_metaExt)) continue;
      final id = f.uri.pathSegments.last.replaceAll(_metaExt, '');
      try {
        final meta = jsonDecode(
            utf8.decode(await _open(await f.readAsBytes(), 'meta', id))) as Map;
        entries.add(VaultEntry(
          id: id,
          name: meta['name'] as String,
          size: meta['size'] as int,
          addedAt: DateTime.parse(meta['addedAt'] as String),
          sha256: meta['sha256'] as String,
        ));
      } on VaultKeyMissingException {
        rethrow;
      } catch (_) {
        entries.add(VaultEntry.damaged(id));
      }
    }
    entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return entries;
  }

  Future<VaultEntry> add(String name, List<int> bytes) async {
    final dir = await _vaultDir();
    final id = _newId();
    final entry = VaultEntry(
      id: id,
      name: name,
      size: bytes.length,
      addedAt: DateTime.now(),
      sha256: await _sha256(bytes),
    );
    await _atomicWrite(
        File('${dir.path}/$id$_dataExt'), await _seal(bytes, 'data', id));
    await _atomicWrite(
        File('${dir.path}/$id$_metaExt'),
        await _seal(
            utf8.encode(jsonEncode({
              'name': entry.name,
              'size': entry.size,
              'addedAt': entry.addedAt.toIso8601String(),
              'sha256': entry.sha256,
            })),
            'meta',
            id));
    return entry;
  }

  /// Decrypts and integrity-checks a document.
  Future<Uint8List> read(VaultEntry e) async {
    final dir = await _vaultDir();
    final plain = await _open(
        await File('${dir.path}/${e.id}$_dataExt').readAsBytes(), 'data', e.id);
    if (await _sha256(plain) != e.sha256) {
      throw const VaultCorruptException('Checksum mismatch');
    }
    return plain;
  }

  /// Writes a decrypted copy into app-private temp storage so another app
  /// can display it. Call [purgeTemp] when the vault locks.
  Future<File> exportToTemp(VaultEntry e) async {
    final dir = Directory('${(await _tempDir()).path}/${e.id}')
      ..createSync(recursive: true);
    final safe = e.name.replaceAll(RegExp(r'[\\/]'), '_');
    final out = File('${dir.path}/$safe');
    await out.writeAsBytes(await read(e), flush: true);
    return out;
  }

  Future<void> purgeTemp() async {
    final dir = await _tempDir();
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        try {
          f.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> delete(VaultEntry e) async {
    final dir = await _vaultDir();
    for (final ext in [_metaExt, _dataExt]) {
      final f = File('${dir.path}/${e.id}$ext');
      if (f.existsSync()) await f.delete();
    }
  }

  /// Plain files left by the pre-encryption vault (anything that is not a
  /// vault blob or temp file).
  Future<List<File>> legacyFiles() async {
    final dir = await _vaultDir();
    return dir.listSync().whereType<File>().where((f) {
      final p = f.path;
      final name = f.uri.pathSegments.last;
      return !p.endsWith(_dataExt) &&
          !p.endsWith(_metaExt) &&
          !p.endsWith('.tmp') &&
          !name.startsWith('.');
    }).toList();
  }

  /// Encrypts each legacy file, then decrypts the new copy and compares
  /// checksums. Only a verified file has its plain original removed; any
  /// failure leaves the original untouched and is reported.
  Future<VaultMigrationReport> migrateLegacy() async {
    final report = VaultMigrationReport();
    for (final f in await legacyFiles()) {
      final name = f.uri.pathSegments.last;
      VaultEntry? entry;
      try {
        final bytes = await f.readAsBytes();
        entry = await add(name, bytes);
        final back = await read(entry);
        if (await _sha256(back) != await _sha256(bytes)) {
          throw const VaultCorruptException('Verification failed');
        }
        await f.delete();
        report.migrated.add(name);
      } catch (e) {
        if (entry != null) {
          try {
            await delete(entry);
          } catch (_) {}
        }
        report.failed[name] = e.toString();
      }
    }
    return report;
  }
}

class VaultEntry {
  VaultEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.addedAt,
    required this.sha256,
  }) : damaged = false;

  VaultEntry.damaged(this.id)
      : name = 'Damaged file',
        size = 0,
        addedAt = DateTime.fromMillisecondsSinceEpoch(0),
        sha256 = '',
        damaged = true;

  final String id;
  final String name;
  final int size;
  final DateTime addedAt;
  final String sha256;
  final bool damaged;
}

class VaultMigrationReport {
  final migrated = <String>[];
  final failed = <String, String>{};
}

class VaultCorruptException implements Exception {
  const VaultCorruptException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VaultKeyMissingException implements Exception {
  const VaultKeyMissingException();
  @override
  String toString() =>
      'The vault key is missing on this device, so existing vault files cannot be opened. They have not been deleted.';
}

/// Where the vault key lives. Swappable for tests.
abstract class VaultKeyStore {
  Future<Uint8List?> read();
  Future<void> write(Uint8List key);
}

class SecureVaultKeyStore implements VaultKeyStore {
  static const _name = 'pdfnova.vault.key.v1';
  final _storage = const FlutterSecureStorage(
    // Keystore-wrapped, not biometric-bound (see class doc above).
    aOptions: AndroidOptions(),
    // Never leaves this device (no iCloud Keychain sync, no restore elsewhere).
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<Uint8List?> read() async {
    final v = await _storage.read(key: _name);
    return v == null ? null : base64Decode(v);
  }

  @override
  Future<void> write(Uint8List key) =>
      _storage.write(key: _name, value: base64Encode(key));
}

class MemoryVaultKeyStore implements VaultKeyStore {
  Uint8List? key;
  @override
  Future<Uint8List?> read() async => key;
  @override
  Future<void> write(Uint8List k) async => key = k;
}
