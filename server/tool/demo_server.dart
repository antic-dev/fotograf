// Demo server — pokreće celu aplikaciju BEZ Google naloga, sa izmišljenim
// fotografijama u memoriji. Služi samo za isprobavanje izgleda i toka.
//
//   cd server && dart run tool/demo_server.dart
//
// Zatim otvorite adrese koje se ispišu u konzoli. NIKADA ne koristiti u produkciji.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fotograf_server/fotograf_server.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:image/image.dart' as img;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class MemoryDrive extends DriveStore {
  MemoryDrive({required super.config, required super.db, required super.box});

  final Map<String, Uint8List> files = {};

  @override
  bool get connected => true;

  @override
  Future<String> ensureProjectFolder(String projectId) async => 'demo-folder-$projectId';

  @override
  Future<void> renameFolder(String folderId, String name) async {}

  @override
  Future<String> upload({required String folderId, required String filename, required String mime, required Uint8List bytes}) async {
    final id = 'demo-${files.length}';
    files[id] = bytes;
    return id;
  }

  @override
  Future<drive.Media> download(String fileId) async => drive.Media(Stream.value(files[fileId]!), files[fileId]!.length);

  @override
  Future<void> trash(String fileId) async {}

  @override
  Future<Map<String, Object?>> quota() async => {'limit': 5 * 1024 * 1024 * 1024 * 1024, 'usage': 812 * 1024 * 1024 * 1024};
}

/// "Fotografija" pejzaža: nebo, sunce i slojevi brda.
Uint8List fakePhoto(Random r, int w, int h) {
  final palettes = [
    [0xFF2E3B55, 0xFFF4A261, 0xFFE76F51, 0xFF264653], // zalazak
    [0xFF8EC5FC, 0xFFE0C3FC, 0xFF6A8D73, 0xFF2D4739], // jutro
    [0xFF0F2027, 0xFF2C5364, 0xFF203A43, 0xFF0B1A1F], // noć
    [0xFFFFD3A5, 0xFFFD6585, 0xFF9B5DE5, 0xFF3D2C5E], // ljubičasto
    [0xFFA1C4FD, 0xFFC2E9FB, 0xFF7FA37F, 0xFF4A6B4A], // proleće
  ];
  final p = palettes[r.nextInt(palettes.length)];
  Color c(int v) => Color(v);
  final top = c(p[0]), bottom = c(p[1]), hill1 = c(p[2]), hill2 = c(p[3]);
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final col = Color.lerp(top, bottom, t);
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, col.r, col.g, col.b);
    }
  }
  final sx = (w * (0.2 + r.nextDouble() * 0.6)).round(), sy = (h * (0.25 + r.nextDouble() * 0.2)).round();
  img.fillCircle(image, x: sx, y: sy, radius: (min(w, h) * 0.09).round(), color: img.ColorRgba8(255, 244, 214, 230));
  for (var layer = 0; layer < 3; layer++) {
    final base = h * (0.55 + layer * 0.13);
    final col = Color.lerp(hill1, hill2, layer / 2);
    final f1 = 1.5 + r.nextDouble() * 3, f2 = 4 + r.nextDouble() * 6, ph = r.nextDouble() * 6;
    for (var x = 0; x < w; x++) {
      final yy = base + sin(x / w * f1 * pi + ph) * h * 0.06 + sin(x / w * f2 * pi) * h * 0.015;
      for (var y = yy.round().clamp(0, h); y < h; y++) {
        image.setPixelRgb(x, y, col.r, col.g, col.b);
      }
    }
  }
  return img.encodeJpg(image, quality: 88);
}

class Color {
  const Color(int v)
      : r = (v >> 16) & 0xFF,
        g = (v >> 8) & 0xFF,
        b = v & 0xFF;
  const Color.rgb(this.r, this.g, this.b);
  final int r, g, b;
  static Color lerp(Color a, Color b, double t) =>
      Color.rgb((a.r + (b.r - a.r) * t).round(), (a.g + (b.g - a.g) * t).round(), (a.b + (b.b - a.b) * t).round());
}

const demoEmail = 'demo@fotograf.local';
const demoPassword = 'demo-lozinka';

Future<void> main(List<String> args) async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final tmp = Directory.systemTemp.createTempSync('fotograf-demo');
  final config = Config.fromEnvironment({
    'APP_SECRET': base64.encode(List.filled(32, 1)),
    'ADMIN_EMAIL': demoEmail,
    'ADMIN_PASSWORD': demoPassword,
    'PUBLIC_URL': 'http://localhost:$port',
    'GOOGLE_CLIENT_ID': 'demo.apps.googleusercontent.com',
    'GOOGLE_CLIENT_SECRET': 'demo',
    'DATA_DIR': tmp.path,
    'WEB_DIR': Platform.environment['WEB_DIR'] ?? '../app/build/web',
    'COOKIE_SECURE': 'false',
    'PORT': '$port',
  });
  final db = Db.open(tmp.path);
  final box = SecretBox(config.secretKey);
  final store = MemoryDrive(config: config, db: db, box: box);
  final s = Services(
    config: config,
    db: db,
    drive: store,
    cache: MediaCache(tmp.path),
    idVerifier: GoogleIdTokenVerifier(clientId: config.googleClientId),
    mailer: Mailer(config),
  );
  await s.initAdminAccount();
  final app = buildHandler(s);

  // --- Seed podaci preko pravog API-ja ---
  final adminToken = randomToken(32);
  db.exec('INSERT INTO admin_sessions(token_hash, created_at, expires_at, last_seen_at) VALUES(?, ?, ?, ?)', [
    sha256Hex(adminToken),
    DateTime.now().millisecondsSinceEpoch,
    DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
  ]);
  final origin = config.publicUrl;
  Future<dynamic> call(String method, String path, {Object? json, List<int>? bytes, String? cookie}) async {
    final res = await app(Request(method, Uri.parse('$origin$path'),
        headers: {
          'x-fotograf': '1',
          'origin': origin,
          if (json != null) 'content-type': 'application/json',
          'cookie': cookie ?? 'fa=$adminToken',
        },
        body: json != null ? jsonEncode(json) : bytes));
    final text = await res.readAsString();
    if (res.statusCode >= 300) throw StateError('$method $path → ${res.statusCode}: $text');
    return text.isEmpty ? null : jsonDecode(text);
  }

  db.setSetting('studio_name', 'Studio Svetlost');
  db.setSetting('printer_email', 'stamparija@example.com');
  final r = Random(7);
  final shapes = [(1500, 1000), (1000, 1500), (1500, 1000), (1200, 1200), (1500, 1000), (1000, 1500)];

  stdout.writeln('Pravim demo fotografije...');
  final wedding = await call('POST', '/api/admin/projects', json: {
    'title': 'Venčanje Ana i Marko',
    'clientName': 'Ana i Marko',
    'eventDate': '2026-09-12',
    'message': 'Hvala vam što ste nas pustili u vaš poseban dan! Izaberite omiljene fotografije za štampu.',
    'maxPhotos': 30,
  }) as Map;
  for (var i = 0; i < 24; i++) {
    final (w, h) = shapes[i % shapes.length];
    await call('POST', '/api/admin/projects/${wedding['id']}/photos?name=DSC_${(4120 + i).toString().padLeft(4, '0')}.jpg', bytes: fakePhoto(r, w, h));
  }
  final baptism = await call('POST', '/api/admin/projects', json: {'title': 'Krštenje male Mile', 'eventDate': '2026-10-04'}) as Map;
  for (var i = 0; i < 9; i++) {
    final (w, h) = shapes[(i + 1) % shapes.length];
    await call('POST', '/api/admin/projects/${baptism['id']}/photos?name=IMG_${(870 + i)}.jpg', bytes: fakePhoto(r, w, h));
  }

  // Jedan klijent je već poslao izbor
  final token = (wedding['shareUrl'] as String).split('/g/').last;
  final photos = ((await call('GET', '/api/admin/projects/${wedding['id']}')) as Map)['photos'] as List;
  var visitor = '';
  for (final i in [0, 3, 5, 8]) {
    final res = await app(Request('PUT', Uri.parse('$origin/api/s/$token/selection/${photos[i]['id']}'),
        headers: {'x-fotograf': '1', 'origin': origin, 'content-type': 'application/json', if (visitor.isNotEmpty) 'cookie': visitor},
        body: jsonEncode({'quantity': i == 3 ? 2 : 1})));
    final set = res.headers['set-cookie'];
    if (set != null) visitor = set.split(';').first;
  }
  await call('POST', '/api/s/$token/submit', json: {'name': 'Jelena Marković', 'phone': '064 123 4567', 'note': 'Može li ova sa tortom malo veća? Hvala!'}, cookie: visitor);

  // Demo prijava: postavlja administratorski kolačić (POSTOJI SAMO U DEMO SERVERU).
  Handler withDemoLogin(Handler inner) => (req) {
        if (req.url.path == 'demo-login') {
          return Response.found('/admin', headers: {'set-cookie': 'fa=$adminToken; Path=/; HttpOnly; SameSite=Strict'});
        }
        return inner(req);
      };

  await io.serve(withDemoLogin(app), 'localhost', port);
  stdout
    ..writeln('')
    ..writeln('Demo radi!')
    ..writeln('  Klijent:        $origin/g/$token')
    ..writeln('  Administrator:  $origin/admin')
    ..writeln('     mejl:    $demoEmail')
    ..writeln('     lozinka: $demoPassword')
    ..writeln('');
}
