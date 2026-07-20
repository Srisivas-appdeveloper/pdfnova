# PDF Nova — full offline PDF suite (Flutter)

iLovePDF-class toolkit that runs **100% on-device**. 22 tools, dark glass
UI, crack-reveal transitions, policy-safe AdMob. Nothing is ever uploaded.

## Tools

| Section | Tools |
|---|---|
| Organize | Merge · Split · Pages (reorder/rotate/delete) · Batch |
| Shrink & convert | Compress · Fit to size (200KB/500KB/1MB) · Images→PDF · PDF→Images · PDF→Text |
| Secure | Unlock (Aadhaar + manual) · Protect AES-256 · Watermark · Clean metadata · Vault (biometric) |
| Smart | Scan (ML Kit, Android) · OCR (English + Hindi) · Sign (draw & place) · Fill form |
| More | Page numbers · Stamp · Reader (night mode + read aloud) · WiFi share |

## Setup

```bash
flutter create . --platforms=android,ios --org com.technotackle --project-name pdfnova
flutter pub get
flutter run
```

### Android — required manifest & gradle edits
`android/app/build.gradle`: `minSdkVersion 23`.

`android/app/src/main/AndroidManifest.xml` inside `<application>`:
```xml
<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
  android:value="ca-app-pub-3940256099942544~3347511713"/>
```
Above `<application>` (WiFi share + biometrics):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```
For local_auth, MainActivity must extend `FlutterFragmentActivity`
(change one word in MainActivity.kt).

### iOS — Info.plist
```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
<key>NSFaceIDUsageDescription</key>
<string>Unlock your private PDF vault</string>
```
Scan tool is Android-only (hidden automatically on iOS).

## Architecture

```
lib/
  core/       theme tokens · SlideUpRoute · CrackRevealRoute · glass widgets · liquid progress
  services/   PdfService (Syncfusion) · RasterService (pdfx/PDFium) · OcrService (ML Kit)
              AdService · StorageService (Hive) · FileService · WifiShareService (dart:io HttpServer)
  features/
    home/     sectioned tool grid + recents
    tool/     generic ToolBloc → input / processing / success (multi-file aware)
    organize/ signature/ formfill/ scan/ viewer/ vault/ wifishare/ batch/  (custom flows)
```

- **State:** flutter_bloc — one generic `ToolBloc` runs any task returning
  `List<String>` output paths; simple tools plug into the generic screen,
  complex ones own their flow but reuse the same bloc + views.
- **Storage:** Hive — recents + ad frequency counters.
- **Rendering:** pdfx (PDFium) for thumbnails, previews, PDF→Images,
  fit-to-size and OCR input; Syncfusion for all document surgery.

## Motion system
Splash (elastic mark + light ring, 1.6s, tap-to-skip) → slide-up handover.
Screens enter bottom-up (420ms easeOutQuint) while the page behind recedes
and dims. Tool cards charge up on press (spring scale + aurora border
glow) then fire the cracker: white micro-flash → aurora crack ring →
12 tumbling shards with gravity → circular reveal with an easeOutBack
settle. Banner lives in a fixed-height glass strip so content NEVER jumps
when an ad fills; on no-fill it stays a quiet footer.

## Ads (policy-safe by construction)
Test IDs hardcoded in `ad_service.dart` — swap only at release; never tap
your own live ads. Rewarded gates Save/Share with guaranteed no-fill
fallback; interstitial capped at 1 per 3 ops; banner anchored in its own
strip; no ads in Reader or Vault; processing shows real progress only.

## Honest limits
- PDF↔Word/Excel with layout fidelity is not possible fully offline — say
  so in the store listing instead of shipping a bad version.
- Fit-to-size outputs image-based PDFs (stated in the UI).
- Syncfusion Community License: free under $1M revenue / ≤5 devs — recheck
  before scaling.
