import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/storage_service.dart';
// ADS DISABLED FOR RELEASE — re-enable: uncomment below + AdMob meta-data in AndroidManifest.xml
// import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF0B0E1A),
  ));
  await StorageService.instance.init();
  // Ads init is fire-and-forget so first frame is never blocked by the SDK.
  // ADS DISABLED FOR RELEASE — re-enable: uncomment the line below.
  // AdService.instance.init();
  runApp(const PdfNovaApp());
}
