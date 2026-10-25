import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/storage_service.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + AdMob meta-data in AndroidManifest.xml
// import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars; each screen sets the icon
  // brightness for its own background.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _registerFontLicenses();
  // Vault AES-GCM uses the platform's native crypto instead of pure Dart.
  FlutterCryptography.enable();
  await StorageService.instance.init();
  // Ads init is fire-and-forget so first frame is never blocked by the SDK.
  // ADS DISABLED FOR RELEASE — re-enable: uncomment the line below.
  // AdService.instance.init();
  runApp(const PdfNovaApp());
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
