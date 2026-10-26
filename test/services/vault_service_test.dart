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
  group('hardening', () {
    test('truncated ciphertext is rejected', () async {
      final e = await vault.add('t.pdf', doc);
      final f = File('${vaultDir.path}/${e.id}.nvd');
      final b = f.readAsBytesSync();
      f.writeAsBytesSync(b.sublist(0, b.length - 40));
      await expectLater(vault.read(e), throwsA(isA<VaultCorruptException>()));
      f.writeAsBytesSync(b.sublist(0, 10)); // shorter than header + tag
      await expectLater(vault.read(e), throwsA(isA<VaultCorruptException>()));
    });

    test('interrupted migration resumes without duplicating', () async {
      vaultDir.createSync(recursive: true);
      final legacy = File('${vaultDir.path}/old.pdf')..writeAsBytesSync(doc);
      // Simulate a crash after the encrypted copy was written but before
      // the plain original was removed.
      await vault.add('old.pdf', doc);
      expect(legacy.existsSync(), isTrue);

      final report = await vault.migrateLegacy();
      expect(report.migrated, ['old.pdf']);
      expect(legacy.existsSync(), isFalse);
      final list = await vault.list();
      expect(list, hasLength(1), reason: 'no duplicate entry');
      expect(await vault.read(list.single), doc);
    });

    test('a same-named but different legacy file is not merged away', () async {
      vaultDir.createSync(recursive: true);
      await vault.add('old.pdf', samplePdf(1, label: 'version A'));
      File('${vaultDir.path}/old.pdf').writeAsBytesSync(doc);
      await vault.migrateLegacy();
      expect(await vault.list(), hasLength(2));
    });

    test('crash leftovers are cleaned, complete entries and legacy kept',
        () async {
      final keep = await vault.add('keep.pdf', doc);
      File('${vaultDir.path}/abc.nvd.tmp').writeAsBytesSync([1, 2, 3]);
      File('${vaultDir.path}/orphan.nvd').writeAsBytesSync([4, 5, 6]);
      final legacy = File('${vaultDir.path}/legacy.pdf')..writeAsBytesSync(doc);
      expect(await vault.cleanupIncomplete(), 2);
      expect(File('${vaultDir.path}/orphan.nvd').existsSync(), isFalse);
      expect(legacy.existsSync(), isTrue);
      expect(await vault.read((await vault.list()).single), doc);
      expect((await vault.list()).single.id, keep.id);
    });

    test('a failed write (e.g. disk full) leaves nothing behind', () async {
      await vault.add('first.pdf', doc); // creates the key
      final before = vaultDir.listSync().length;
      Process.runSync('chmod', ['555', vaultDir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', vaultDir.path]));
      await expectLater(vault.add('second.pdf', doc), throwsA(anything));
      Process.runSync('chmod', ['755', vaultDir.path]);
      expect(vaultDir.listSync(), hasLength(before));
    });

    test('unreadable legacy file fails migration and is kept', () async {
      vaultDir.createSync(recursive: true);
      final f = File('${vaultDir.path}/locked.pdf')..writeAsBytesSync(doc);
      Process.runSync('chmod', ['000', f.path]);
      addTearDown(() => Process.runSync('chmod', ['644', f.path]));
      final r = await vault.migrateLegacy();
      expect(r.failed.keys, ['locked.pdf']);
      Process.runSync('chmod', ['644', f.path]);
      expect(f.readAsBytesSync(), doc);
      expect(await vault.list(), isEmpty);
    });

    test('key-store read failure never creates a replacement key', () async {
      await vault.add('x.pdf', doc);
      final throwing = VaultService(
        vaultDir: () async => vaultDir,
        tempDir: () async => tempDir,
        keyStore: _ThrowingReadKeyStore(),
      );
      await expectLater(
          throwing.list(), throwsA(isA<VaultKeyUnavailableException>()));
      // still unreadable only through that store; original key untouched
      expect(await vault.list(), hasLength(1));
    });

    test('a malformed stored key is rejected, not used', () async {
      keys.key = Uint8List(7);
      await expectLater(make().add('x.pdf', doc),
          throwsA(isA<VaultKeyUnavailableException>()));
    });

    test('concurrent first use creates exactly one key', () async {
      final v = make();
      await Future.wait([v.add('a.pdf', doc), v.add('b.pdf', doc)]);
      final list = await make().list(); // fresh instance, stored key
      expect(list, hasLength(2));
      for (final e in list) {
        expect(await make().read(e), doc);
      }
    });
  });
}

class _FailingKeyStore implements VaultKeyStore {
  @override
  Future<Uint8List?> read() async => null;
  @override
  Future<void> write(Uint8List key) async =>
      throw const FileSystemException('secure storage unavailable');
}

class _ThrowingReadKeyStore implements VaultKeyStore {
  @override
  Future<Uint8List?> read() async => throw Exception('KeyStore invalidated');
  @override
  Future<void> write(Uint8List key) async =>
      fail('must never write a replacement key');
}
