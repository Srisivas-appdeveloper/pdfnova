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
