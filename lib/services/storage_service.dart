import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'document_index.dart';

/// Hive-backed local storage. Two boxes:
///  - settings: counters used for ad frequency capping, appearance prefs
///  - recents:  output history — the single source of truth for files the
///              app has generated (shown in the Files tab)
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  late Box _settings;
  late Box _recents;

  /// [hivePath] lets tests use a temp directory instead of the app's.
  Future<void> init({String? hivePath}) async {
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _settings = await Hive.openBox('settings');
    _recents = await Hive.openBox('recents');
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == _settings.get('themeMode'),
      orElse: () => ThemeMode.system,
    );
    reduceMotion.value = _settings.get('reduceMotion', defaultValue: false);
    contentIndexing.value =
        _settings.get('contentIndexing', defaultValue: false);
    await _upgradeRecents();
  }

  // ---- Appearance ------------------------------------------------------
  /// Listened to by the app root; changing it re-themes the whole app.
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  final reduceMotion = ValueNotifier<bool>(false);

  /// Opt-in local content search (see DocumentIndex). Off by default.
  final contentIndexing = ValueNotifier<bool>(false);

  /// Turning it off deletes all indexed text; turning it on indexes the
  /// current output history. Returns how many documents were indexed.
  Future<int> setContentIndexing(bool on) async {
    contentIndexing.value = on;
    await _settings.put('contentIndexing', on);
    if (!on) {
      await DocumentIndex.instance.clear();
      return 0;
    }
    return (await DocumentIndex.instance.sync(history.map((r) => r.path)))
        .indexed;
  }

  /// Index side-effects never break the history operation itself.
  Future<void> _index(Future<void> Function(DocumentIndex i) f) async {
    if (!contentIndexing.value) return;
    try {
      await f(DocumentIndex.instance);
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    return _settings.put('themeMode', mode.name);
  }

  Future<void> setReduceMotion(bool on) {
    reduceMotion.value = on;
    return _settings.put('reduceMotion', on);
  }

  // ---- Ad frequency capping -------------------------------------------
  int get completedOps => _settings.get('completedOps', defaultValue: 0);
  Future<void> incrementOps() =>
      _settings.put('completedOps', completedOps + 1);

  /// Interstitial allowed at most once per 3 completed operations.
  /// The op-count that last triggered an ad is remembered, so repeated
  /// calls while the counter sits at 3/6/9… don't fire back-to-back ads.
  bool get interstitialDue =>
      completedOps > 0 &&
      completedOps % 3 == 0 &&
      _settings.get('lastInterstitialAt', defaultValue: -1) != completedOps;

  Future<void> markInterstitialShown() =>
      _settings.put('lastInterstitialAt', completedOps);

  // ---- Output history (Files tab) ---------------------------------------
  /// Most entries kept. Older ones drop off the history only — the files
  /// themselves are never deleted by this cap.
  static const historyLimit = 200;
  static const _schema = 2;

  List<OutputRecord> get history {
    final raw = _recents.get('list', defaultValue: <dynamic>[]) as List;
    return [
      for (final e in raw.whereType<Map>())
        if (OutputRecord.tryParse(e) case final r?) r
    ];
  }

  /// Back-compat view used by older call sites.
  List<Map<String, dynamic>> get recents =>
      [for (final r in history) r.toMap()];

  Future<void> _save(List<OutputRecord> list) => _recents
      .put('list', [for (final r in list.take(historyLimit)) r.toMap()]);

  /// v1 entries had only path/tool/time and at most 20 rows. Fill in size
  /// and job id where the file still exists; never drops entries.
  Future<void> _upgradeRecents() async {
    if ((_settings.get('recentsSchema', defaultValue: 1) as int) >= _schema) {
      return;
    }
    await _save([for (final r in history) r.withMeasuredSize()]);
    await _settings.put('recentsSchema', _schema);
  }

  /// Records every output of one operation (multi-output tools such as
  /// PDF → Images share a [OutputRecord.job] id).
  Future<void> addOutputs(List<String> paths, String tool) async {
    final job = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    final fresh = [
      for (final p in paths)
        OutputRecord(path: p, tool: tool, time: now, job: job)
            .withMeasuredSize()
    ];
    await _save([...fresh, ...history.where((r) => !paths.contains(r.path))]);
    await _index((i) async {
      for (final p in paths) {
        await i.indexFile(p);
      }
    });
  }

  Future<void> addRecent(String path, String tool) => addOutputs([path], tool);

  Future<void> removeRecent(String path) => removeRecents({path});

  /// Removing history also removes that file's indexed text.
  Future<void> removeRecents(Set<String> paths) async {
    await _save(history.where((r) => !paths.contains(r.path)).toList());
    await _index((i) async {
      for (final p in paths) {
        await i.remove(p);
      }
    });
  }

  Future<void> renameRecent(String from, String to) async {
    await _save(
        [for (final r in history) r.path == from ? r.copyWith(path: to) : r]);
    await _index((i) async {
      await i.remove(from);
      await i.indexFile(to);
    });
  }

  /// Drops history rows whose file no longer exists. Returns how many.
  Future<int> pruneMissing() async {
    final all = history;
    final kept = all.where((r) => File(r.path).existsSync()).toList();
    await _save(kept);
    await _index((i) async {
      for (final r in all.where((r) => !kept.contains(r))) {
        await i.remove(r.path);
      }
    });
    return all.length - kept.length;
  }
}

/// One generated file in the output history.
class OutputRecord {
  const OutputRecord({
    required this.path,
    required this.tool,
    required this.time,
    this.bytes,
    this.job,
  });

  final String path;
  final String tool;
  final DateTime time;

  /// Size when recorded (null for legacy rows whose file was gone).
  final int? bytes;

  /// Groups outputs produced by the same run.
  final String? job;

  String get name => path.split('/').last;
  String get extension {
    final n = name.toLowerCase();
    final dot = n.lastIndexOf('.');
    return dot < 0 ? '' : n.substring(dot + 1);
  }

  bool get exists => File(path).existsSync();

  /// Size on disk right now, falling back to the recorded size.
  int? get currentBytes => exists ? File(path).lengthSync() : bytes;

  static OutputRecord? tryParse(Map raw) {
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    return OutputRecord(
      path: path,
      tool: raw['tool'] is String ? raw['tool'] as String : 'Other',
      time: DateTime.tryParse('${raw['time']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      bytes: raw['bytes'] is int ? raw['bytes'] as int : null,
      job: raw['job'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'path': path,
        'tool': tool,
        'time': time.toIso8601String(),
        if (bytes != null) 'bytes': bytes,
        if (job != null) 'job': job,
      };

  OutputRecord copyWith({String? path}) => OutputRecord(
      path: path ?? this.path, tool: tool, time: time, bytes: bytes, job: job);

  OutputRecord withMeasuredSize() => exists
      ? OutputRecord(
          path: path,
          tool: tool,
          time: time,
          bytes: File(path).lengthSync(),
          job: job)
      : this;
}
