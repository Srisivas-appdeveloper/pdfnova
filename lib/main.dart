import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/storage_service.dart';
import 'services/vault_service.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + AdMob meta-data in AndroidManifest.xml
// import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars; each screen sets the icon
  // brightness for its own background.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _registerFontLicenses();
  await StorageService.instance.init();
  // Decrypted vault viewing copies must not survive a killed process.
  VaultService.instance.purgeTemp();
  // Ads init is fire-and-forget so first frame is never blocked by the SDK.
  // ADS DISABLED FOR RELEASE — re-enable: uncomment the line below.
  // AdService.instance.init();
  runApp(const PdfNovaApp());
  _releaseLaunchScreen();
}

/// Android 12+ keeps its launch screen up until this reports that Flutter's
/// first frame — the same mark, same place — is on screen, so the handover
/// can't blink. Waits one extra frame for the surface to be composited.
void _releaseLaunchScreen() {
  if (!Platform.isAndroid) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await WidgetsBinding.instance.endOfFrame;
    try {
      await const MethodChannel('pdfnova/window')
          .invokeMethod('firstFrameShown');
    } catch (_) {
      // The native side falls back to a timeout.
    }
  });
}

/// Bundled fonts are SIL OFL — their licences ship in the app's licence page.
void _registerFontLicenses() {
  for (final (family, file) in const [
    ('Inter', 'assets/fonts/OFL-Inter.txt'),
    ('Instrument Serif', 'assets/fonts/OFL-InstrumentSerif.txt'),
    ('Noto Sans', 'assets/fonts/OFL-NotoSans.txt'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
          [family], await rootBundle.loadString(file));
    });
  }
}
