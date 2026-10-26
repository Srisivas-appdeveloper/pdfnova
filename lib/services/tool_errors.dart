import 'dart:io';

/// An error whose message is written for the user and can be shown as-is
/// (invalid input, unsupported file, verification failure…).
class UserFacingError implements Exception {
  const UserFacingError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Writes [bytes] to [path] without ever leaving a half-written file there:
/// the data goes to `<path>.part` first and is renamed only once complete.
/// On failure the partial file is removed and the error rethrown.
Future<void> writeAtomic(String path, List<int> bytes) async {
  final part = File('$path.part');
  try {
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(path);
  } catch (_) {
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// Turns any failure from a tool run into a calm, specific message.
/// Never includes file contents, paths or stack traces.
String describeToolError(Object err, {bool isUnlockTool = false}) {
  if (err is UserFacingError) return err.message;
  if (err is FileSystemException &&
      (err.osError?.errorCode == 28 ||
          (err.osError?.message.toLowerCase().contains('no space') ?? false))) {
    return 'Your phone is out of storage space. Free some space and try again — nothing was saved.';
  }
  final text = err.toString().toLowerCase();
  if (text.contains('password') || text.contains('encrypted')) {
    return isUnlockTool
        ? 'That password did not open this PDF. Check the name spelling and year, then try again.'
        : 'This PDF is password-protected. Unlock it first with the Unlock tool, then try again.';
  }
  if (text.contains('notext')) return 'No readable text was found in this PDF.';
  return 'Something went wrong while processing. The file may be damaged — try another copy.';
}
