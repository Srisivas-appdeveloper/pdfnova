import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfnova/services/wifi_share_service.dart';
import '../helpers.dart';

void main() {
  test('serves exactly the shared PDF, typed as PDF; nothing else', () async {
    final dir = Directory.systemTemp.createTempSync('wifishare_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pdf = File('${dir.path}/My Lease.pdf')
      ..writeAsBytesSync(samplePdf(2));

    final url = await WifiShareService.instance.start(pdf.path);
    if (url == null) {
      markTestSkipped('no LAN interface on this machine');
      return;
    }
    addTearDown(WifiShareService.instance.stop);
    final port = Uri.parse(url).port;
    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> get(String path) async =>
        (await client.get('127.0.0.1', port, path)).close();

    final ok = await get('/${Uri.encodeComponent('My Lease.pdf')}');
    expect(ok.statusCode, 200);
    expect(ok.headers.contentType?.mimeType, 'application/pdf');
    final body = await ok.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(body, pdf.readAsBytesSync());

    for (final other in ['/', '/other.pdf', '/../../etc/hosts']) {
      final r = await get(other);
      await r.drain<void>();
      expect(r.statusCode, 404, reason: other);
    }
  });
}
