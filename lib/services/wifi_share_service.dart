import 'dart:io';

/// Phone→phone sharing with zero internet: a tiny HTTP server on the local
/// network serves one file; the receiver opens the URL (or scans the QR) in
/// any browser. Works on hotspot too.
class WifiShareService {
  WifiShareService._();
  static final WifiShareService instance = WifiShareService._();

  HttpServer? _server;
  String? url;

  Future<String?> start(String filePath) async {
    await stop();
    try {
      final ip = await _localIp();
      if (ip == null) return null; // no LAN interface (only cellular/VPN)

      // Port 8765 may be taken (e.g. a stale server) — walk a small range.
      HttpServer? server;
      var port = 0;
      for (var p = 8765; p <= 8770; p++) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, p);
          port = p;
          break;
        } on SocketException {
          continue; // busy — try the next one
        }
      }
      if (server == null) return null;
      _server = server;

      final rawName = filePath.split('/').last;
      final encodedName = Uri.encodeComponent(rawName);
      server.listen((req) async {
        final file = File(filePath);
        if (!_matchesRequestedFile(req.uri.path, rawName, encodedName) ||
            !file.existsSync()) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final length = await file.length();
        req.response.headers
          ..contentType = ContentType.binary
          ..contentLength = length
          // Plain filename= is NOT percent-decoded by browsers, so a name like
          // "My Invoice.pdf" must go raw in the quoted form; the RFC 5987
          // filename*= form carries the encoded version for stricter clients.
          ..add('Content-Disposition',
              'attachment; filename="$rawName"; filename*=UTF-8\'\'$encodedName');
        try {
          if (req.method != 'HEAD') {
            await req.response.addStream(file.openRead());
          }
        } finally {
          await req.response.close();
        }
      });
      url = 'http://$ip:$port/$encodedName';
      return url;
    } catch (_) {
      await stop();
      return null;
    }
  }

  /// dart:io keeps the request path percent-ENCODED ("/My%20File.pdf"), while
  /// some clients re-encode or send it decoded — accept every spelling of the
  /// same filename, 404 everything else (favicon, scanners, …).
  bool _matchesRequestedFile(
      String requestPath, String rawName, String encodedName) {
    if (requestPath == '/$encodedName' || requestPath == '/$rawName') {
      return true;
    }
    try {
      return Uri.decodeComponent(requestPath) == '/$rawName';
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    url = null;
  }

  /// Picks the LAN-reachable IPv4. The first interface from the OS is often
  /// cellular (rmnet_data/ccmni) or a VPN (tun) whose IP the other phone can
  /// never reach — so WiFi/hotspot/ethernet interfaces win, cellular/VPN are
  /// skipped entirely (returning null shows the "join a WiFi" hint instead).
  Future<String?> _localIp() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLinkLocal: false);

    int score(String name) {
      final n = name.toLowerCase();
      if (n.contains('wlan') ||
          n.contains('wifi') ||
          n.startsWith('ap') ||
          n.startsWith('eth') ||
          n.startsWith('en') || // macOS/iOS-style names
          n.contains('rndis') || // USB tethering
          n.contains('pan')) {
        return 2; // LAN-reachable
      }
      if (n.contains('rmnet') ||
          n.contains('ccmni') ||
          n.contains('pdp') ||
          n.contains('ppp') ||
          n.contains('tun') ||
          n.contains('wg') ||
          n.contains('dummy')) {
        return 0; // cellular / VPN — unreachable from another phone
      }
      return 1; // unknown — usable fallback
    }

    final ranked = interfaces.toList()
      ..sort((a, b) => score(b.name).compareTo(score(a.name)));
    for (final iface in ranked) {
      if (score(iface.name) == 0) continue;
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}
