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
  NotesStore({NoteBackend? backend}) : _backend = backend ?? _defaultBackend();

  static final NotesStore instance = NotesStore();

  final NoteBackend _backend;

  static NoteBackend _defaultBackend() =>
      Platform.isAndroid ? ChannelNoteBackend() : HiveNoteBackend();

  Future<QuickNote> load() => _backend.read();

  Future<NoteSaveResult> save(String text, {required int baseVersion}) async {
    final current = await _backend.read();
    if (current.updatedAt > baseVersion && current.text != text) {
      final merged = mergeNotes(text, current.text);
      final stored = await _backend.write(merged);
      return NoteSaveResult(stored, merged: true);
    }
    return NoteSaveResult(await _backend.write(text));
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
