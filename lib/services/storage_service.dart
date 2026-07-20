import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed local storage. Two boxes:
///  - settings: counters used for ad frequency capping, prefs
///  - recents:  last 20 output files for the home screen "Recent" rail
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  late Box _settings;
  late Box _recents;

  Future<void> init() async {
    await Hive.initFlutter();
    _settings = await Hive.openBox('settings');
    _recents = await Hive.openBox('recents');
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

  // ---- Recent files ----------------------------------------------------
  List<Map<String, dynamic>> get recents {
    final raw = _recents.get('list', defaultValue: <dynamic>[]) as List;
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> addRecent(String path, String tool) async {
    final list = recents.toList()
      ..insert(0, {
        'path': path,
        'tool': tool,
        'time': DateTime.now().toIso8601String(),
      });
    await _recents.put('list', list.take(20).toList());
  }
}
