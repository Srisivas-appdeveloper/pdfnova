import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// The quick note, versioned by its last-update time (ms since epoch).
class QuickNote {
  const QuickNote(this.text, this.updatedAt);
  final String text;
  final int updatedAt;
}

/// Result of a save: what is stored now, and whether a concurrent edit
/// (e.g. from the Home Screen widget) had to be merged in.
class NoteSaveResult {
  const NoteSaveResult(this.note, {this.merged = false});
  final QuickNote note;
  final bool merged;
}

/// Single source of truth for the quick note.
///
/// On Android it lives where the Home Screen widget reads it (the widget's
/// SharedPreferences, via the `pdfnova/notes` channel) so the app and the
/// widget always show the same text. Elsewhere it lives in Hive.
///
/// Saves are compare-and-set: the caller passes the version it edited. If
/// someone else saved in between, both texts are kept (merged) instead of
/// one silently overwriting the other.
class NotesStore {
  NotesStore({NoteBackend? backend, NoteVersionStore? versions})
      : _backend = backend ?? _defaultBackend(),
        _versions = versions ?? HiveNoteVersionStore();

  static final NotesStore instance = NotesStore();

  final NoteBackend _backend;
  final NoteVersionStore _versions;

  /// Earlier versions kept for recovery (newest first).
  static const maxVersions = 10;

  /// While typing, at most one snapshot per this interval.
  static const snapshotEvery = Duration(minutes: 5);

  static NoteBackend _defaultBackend() =>
      Platform.isAndroid ? ChannelNoteBackend() : HiveNoteBackend();

  Future<QuickNote> load() => _backend.read();

  Future<NoteSaveResult> save(String text, {required int baseVersion}) async {
    final current = await _backend.read();
    if (current.updatedAt > baseVersion && current.text != text) {
      // Conflict: keep both texts, and keep the other edit as a version too.
      await _snapshot(current, force: true);
      final merged = mergeNotes(text, current.text);
      final stored = await _backend.write(merged);
      return NoteSaveResult(stored, merged: true);
    }
    if (current.text != text) await _snapshot(current);
    return NoteSaveResult(await _backend.write(text));
  }

  Future<List<QuickNote>> versions() => _versions.read();

  /// Restores an earlier version. The text being replaced is kept as a
  /// version first, so a restore can itself be undone.
  Future<QuickNote> restore(QuickNote version) async {
    final current = await _backend.read();
    await _snapshot(current, force: true);
    return _backend.write(version.text);
  }

  Future<void> _snapshot(QuickNote note, {bool force = false}) async {
    if (note.text.trim().isEmpty) return;
    final list = await _versions.read();
    if (list.isNotEmpty && list.first.text == note.text) return;
    if (!force &&
        list.isNotEmpty &&
        note.updatedAt - list.first.updatedAt < snapshotEvery.inMilliseconds) {
      return;
    }
    await _versions.write([note, ...list].take(maxVersions).toList());
  }

  /// Keeps both versions; never drops text. The other edit is appended
  /// unless it is already contained in this one.
  static String mergeNotes(String mine, String theirs) {
    if (theirs.trim().isEmpty || mine.contains(theirs)) return mine;
    if (mine.trim().isEmpty || theirs.contains(mine)) return theirs;
    return '$mine\n\n— Also written from the widget —\n$theirs';
  }
}

abstract class NoteBackend {
  Future<QuickNote> read();

  /// Stores [text] stamped with now; returns the stored version.
  Future<QuickNote> write(String text);
}

class ChannelNoteBackend implements NoteBackend {
  static const _channel = MethodChannel('pdfnova/notes');

  @override
  Future<QuickNote> read() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('getNote');
    return QuickNote(
        m?['text'] as String? ?? '', (m?['updatedAt'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<QuickNote> write(String text) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _channel.invokeMethod('setNote', {'text': text, 'updatedAt': now});
    return QuickNote(text, now);
  }
}

class HiveNoteBackend implements NoteBackend {
  Box get _box => Hive.box('settings');

  @override
  Future<QuickNote> read() async => QuickNote(
      _box.get('quickNote', defaultValue: '') as String,
      _box.get('quickNoteUpdatedAt', defaultValue: 0) as int);

  @override
  Future<QuickNote> write(String text) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.putAll({'quickNote': text, 'quickNoteUpdatedAt': now});
    return QuickNote(text, now);
  }
}

class MemoryNoteBackend implements NoteBackend {
  QuickNote note = const QuickNote('', 0);
  int _clock = 0;

  @override
  Future<QuickNote> read() async => note;

  @override
  Future<QuickNote> write(String text) async =>
      note = QuickNote(text, note.updatedAt + 1 + _clock++);
}

abstract class NoteVersionStore {
  Future<List<QuickNote>> read();
  Future<void> write(List<QuickNote> versions);
}

class HiveNoteVersionStore implements NoteVersionStore {
  Box get _box => Hive.box('settings');

  @override
  Future<List<QuickNote>> read() async => [
        for (final m
            in (_box.get('quickNoteVersions', defaultValue: const []) as List)
                .whereType<Map>())
          QuickNote(m['text'] as String? ?? '', (m['at'] as num?)?.toInt() ?? 0)
      ];

  @override
  Future<void> write(List<QuickNote> versions) =>
      _box.put('quickNoteVersions', [
        for (final v in versions) {'text': v.text, 'at': v.updatedAt}
      ]);
}

class MemoryNoteVersionStore implements NoteVersionStore {
  List<QuickNote> items = [];
  @override
  Future<List<QuickNote>> read() async => items;
  @override
  Future<void> write(List<QuickNote> versions) async => items = versions;
}
