import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/services/vault_service.dart';
import '../helpers.dart';

void main() {
  late Directory root, vaultDir, tempDir;
  late MemoryVaultKeyStore keys;
  late VaultService vault;

  VaultService make() => VaultService(
        vaultDir: () async => vaultDir..createSync(recursive: true),
        tempDir: () async => tempDir..createSync(recursive: true),
        keyStore: keys,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('vault_test_');
    vaultDir = Directory('${root.path}/vault');
    tempDir = Directory('${root.path}/tmp');
    keys = MemoryVaultKeyStore();
    vault = make();
  });
  tearDown(() => root.deleteSync(recursive: true));

  final doc = samplePdf(2, label: 'secret salary');

  test('round-trips a document and lists it by name', () async {
    final e = await vault.add('Payslip March.pdf', doc);
    final list = await vault.list();
    expect(list.single.name, 'Payslip March.pdf');
    expect(list.single.size, doc.length);
    expect(await vault.read(list.single), doc);
    expect(e.id, list.single.id);
  });

  test('nothing readable is stored on disk', () async {
    await vault.add('Aadhaar.pdf', doc);
    for (final f in vaultDir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      expect(String.fromCharCodes(bytes).contains('%PDF'), isFalse);
      expect(String.fromCharCodes(bytes).contains('Aadhaar'), isFalse,
          reason: 'file names must be encrypted too');
      expect(f.path.contains('Aadhaar'), isFalse);
    }
  });

  test('two encryptions of the same file differ (random nonces)', () async {
    await vault.add('a.pdf', doc);
    await vault.add('b.pdf', doc);
    final data = vaultDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.nvd'))
        .map((f) => f.readAsBytesSync())
        .toList();
    expect(data, hasLength(2));
    expect(data[0], isNot(equals(data[1])));
  });

  test('a tampered file is detected, not decrypted', () async {
    final e = await vault.add('x.pdf', doc);
    final f = File('${vaultDir.path}/${e.id}.nvd');
    final bytes = f.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0x01;
    f.writeAsBytesSync(bytes);
    await expectLater(vault.read(e), throwsA(isA<VaultCorruptException>()));
  });

  test('swapping blobs between entries is rejected (bound by AAD)', () async {
    final a = await vault.add('a.pdf', doc);
    final b = await vault.add('b.pdf', samplePdf(1, label: 'other'));
    File('${vaultDir.path}/${b.id}.nvd')
        .copySync('${vaultDir.path}/${a.id}.nvd');
    await expectLater(vault.read(a), throwsA(isA<VaultCorruptException>()));
  });

  test('a different key cannot read the vault', () async {
    final e = await vault.add('x.pdf', doc);
    keys.key = Uint8List(32); // wrong key
    final other = make();
    await expectLater(other.read(e), throwsA(isA<VaultCorruptException>()));
    // listing shows the entry as damaged instead of crashing or deleting
    final list = await other.list();
    expect(list.single.damaged, isTrue);
    expect(vaultDir.listSync(), isNotEmpty);
  });

  test('missing key with existing files: refuses to create a new key',
      () async {
    await vault.add('x.pdf', doc);
    keys.key = null;
    final fresh = make();
    await expectLater(fresh.list(), throwsA(isA<VaultKeyMissingException>()));
    expect(keys.key, isNull, reason: 'must not orphan files with a new key');
    expect(vaultDir.listSync().whereType<File>(), hasLength(2));
  });

  test('migrates legacy plain files: verified, then original removed',
      () async {
    vaultDir.createSync(recursive: true);
    File('${vaultDir.path}/old statement.pdf').writeAsBytesSync(doc);
    expect((await vault.legacyFiles()), hasLength(1));

    final report = await vault.migrateLegacy();
    expect(report.migrated, ['old statement.pdf']);
    expect(report.failed, isEmpty);
    expect(File('${vaultDir.path}/old statement.pdf').existsSync(), isFalse);
    final e = (await vault.list()).single;
    expect(e.name, 'old statement.pdf');
    expect(await vault.read(e), doc);
  });

  test('a failed migration leaves the original untouched', () async {
    vaultDir.createSync(recursive: true);
    final legacy = File('${vaultDir.path}/keep me.pdf')..writeAsBytesSync(doc);
    final broken = VaultService(
      vaultDir: () async => vaultDir,
      tempDir: () async => tempDir,
      keyStore: _FailingKeyStore(),
    );
    final report = await broken.migrateLegacy();
    expect(report.migrated, isEmpty);
    expect(report.failed.keys, ['keep me.pdf']);
    expect(legacy.readAsBytesSync(), doc);
  });

  test('temp copies are written privately and purged', () async {
    final e = await vault.add('view.pdf', doc);
    final f = await vault.exportToTemp(e);
    expect(f.readAsBytesSync(), doc);
    expect(f.path.startsWith(tempDir.path), isTrue);
    await vault.purgeTemp();
    expect(f.existsSync(), isFalse);
  });

  test('delete removes both blobs', () async {
    final e = await vault.add('gone.pdf', doc);
    await vault.delete(e);
    expect(await vault.list(), isEmpty);
    expect(vaultDir.listSync().whereType<File>(), isEmpty);
  });
}

class _FailingKeyStore implements VaultKeyStore {
  @override
  Future<Uint8List?> read() async => null;
  @override
  Future<void> write(Uint8List key) async =>
      throw const FileSystemException('secure storage unavailable');
}
