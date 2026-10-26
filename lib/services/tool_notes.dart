import 'dart:async';

/// Lets a service attach a caveat to the result of the tool run it is part
/// of, without changing every task's return type. Notes travel in a Zone,
/// so they only reach the run that produced them (and are dropped when
/// code runs outside a tool run, e.g. in tests or on another isolate).
abstract final class ToolNotes {
  static const _key = #pdfNovaToolNotes;

  static void add(String note) {
    final sink = Zone.current[_key];
    if (sink is List<String> && !sink.contains(note)) sink.add(note);
  }

  static Future<T> collect<T>(List<String> into, Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: into});
}

/// Real progress from inside a tool run. Tools that can measure progress
/// (e.g. per file or per page) call [report]; everything else shows an
/// indeterminate indicator instead of an invented percentage.
abstract final class ToolProgress {
  static const _key = #pdfNovaToolProgress;

  /// [fraction] in 0–1 (null = still working, amount unknown); [stage] is a
  /// short human label such as "File 2 of 5".
  static void report(double? fraction, {String? stage}) {
    final sink = Zone.current[_key];
    if (sink is void Function(double?, String?)) {
      sink(fraction?.clamp(0.0, 1.0), stage);
    }
  }

  static Future<T> track<T>(
          void Function(double? fraction, String? stage) onProgress,
          Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: onProgress});
}
