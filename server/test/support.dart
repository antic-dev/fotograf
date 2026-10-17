import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fotograf_server/fotograf_server.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:pointycastle/export.dart';
import 'package:shelf/shelf.dart';

/// Drive u memoriji — testovi ne smeju dirati pravi Google nalog.
class FakeDrive extends DriveStore {
  FakeDrive({required super.config, required super.db, required super.box});

  final Map<String, Uint8List> files = {};
  final Set<String> trashed = {};
  final Map<String, String> folders = {};

  bool isConnected = true;

  @override
  bool get connected => isConnected;

  @override
  Future<String> ensureProjectFolder(String projectId) async {
    final existing = db.scalar('SELECT drive_folder_id FROM projects WHERE id = ?', [projectId]) as String?;
    if (existing != null) return existing;
    final id = 'folder-${folders.length}';
    folders[id] = projectId;
    db.exec('UPDATE projects SET drive_folder_id = ? WHERE id = ?', [id, projectId]);
    return id;
  }

  @override
  Future<void> renameFolder(String folderId, String name) async {}

  @override
  Future<String> upload({required String folderId, required String filename, required String mime, required Uint8List bytes}) async {
    final id = 'file-${files.length}';
    files[id] = bytes;
    return id;
  }

  @override
  Future<drive.Media> download(String fileId) async {
    final b = files[fileId]!;
    return drive.Media(Stream.value(b), b.length);
  }

  @override
  Future<void> trash(String fileId) async => trashed.add(fileId);

  @override
  Future<Map<String, Object?>> quota() async => {'limit': 5 * 1024 * 1024 * 1024 * 1024, 'usage': 1024, 'email': 'x'};
}

/// Lažni Google: pravi RSA ključ i potpisuje ID tokene kao Google.
class FakeGoogle {
  FakeGoogle() {
    final gen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _random(),
      ));
    final pair = gen.generateKeyPair();
    publicKey = pair.publicKey;
    privateKey = pair.privateKey;
  }

  late final RSAPublicKey publicKey;
  late final RSAPrivateKey privateKey;
  static const kid = 'test-key';

  static SecureRandom _random() {
    final r = FortunaRandom();
    final rng = Random.secure();
    r.seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)))));
    return r;
  }

  http.Client client() => MockClient((req) async {
        if (req.url.toString() == 'https://www.googleapis.com/oauth2/v3/certs') {
          return http.Response(
            jsonEncode({
              'keys': [
                {'kty': 'RSA', 'kid': kid, 'alg': 'RS256', 'n': b64url(_bytes(publicKey.modulus!)), 'e': b64url(_bytes(publicKey.publicExponent!))},
              ],
            }),
            200,
            headers: {'cache-control': 'public, max-age=3600'},
          );
        }
        return http.Response('not found', 404);
      });

  String sign(Map<String, Object?> payload, {String? keyId}) {
    final header = b64url(utf8.encode(jsonEncode({'alg': 'RS256', 'kid': keyId ?? kid, 'typ': 'JWT'})));
    final body = b64url(utf8.encode(jsonEncode(payload)));
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sig = signer.generateSignature(Uint8List.fromList(ascii.encode('$header.$body')));
    return '$header.$body.${b64url(sig.bytes)}';
  }

  static Uint8List _bytes(BigInt n) {
    final hex = n.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList([for (var i = 0; i < padded.length; i += 2) int.parse(padded.substring(i, i + 2), radix: 16)]);
  }
}

class TestApp {
  TestApp._(this.services, this.handler, this.drive, this.google, this.tmp);

  final Services services;
  final Handler handler;
  final FakeDrive drive;
  final FakeGoogle google;
  final Directory tmp;

  static const origin = 'https://foto.test';
  static const clientId = 'test-client.apps.googleusercontent.com';

  static const adminEmail = 'fotograf@example.com';
  static const adminPassword = 'Tajna-Lozinka-2026';

  static Future<TestApp> create(FakeGoogle google) async {
    final tmp = Directory.systemTemp.createTempSync('fotograf-test');
    final config = Config.fromEnvironment({
      'APP_SECRET': base64.encode(List.filled(32, 7)),
      'ADMIN_EMAIL': adminEmail,
      'ADMIN_PASSWORD': adminPassword,
      'PUBLIC_URL': origin,
      'GOOGLE_CLIENT_ID': clientId,
      'GOOGLE_CLIENT_SECRET': 'secret',
      'DATA_DIR': tmp.path,
      'WEB_DIR': '${tmp.path}/web',
    });
    final db = Db.memory();
    final box = SecretBox(config.secretKey);
    final drive = FakeDrive(config: config, db: db, box: box);
    final services = Services(
      config: config,
      db: db,
      drive: drive,
      cache: MediaCache(tmp.path),
      idVerifier: GoogleIdTokenVerifier(clientId: clientId, client: google.client()),
      mailer: Mailer(config),
    );
    await services.initAdminAccount();
    return TestApp._(services, buildHandler(services), drive, google, tmp);
  }

  void dispose() {
    services.db.close();
    tmp.deleteSync(recursive: true);
  }

  /// Simulira pregledač: pamti kolačiće.
  final Map<String, String> cookies = {};

  Future<TestResponse> call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    Map<String, String>? headers,
    bool csrf = true,
    bool withCookies = true,
  }) async {
    final h = <String, String>{
      if (csrf) 'x-fotograf': '1',
      if (csrf && method != 'GET') 'origin': origin,
      if (json != null) 'content-type': 'application/json',
      if (withCookies && cookies.isNotEmpty) 'cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      ...?headers,
    };
    final req = Request(
      method,
      Uri.parse('$origin$path'),
      headers: h,
      body: json != null ? jsonEncode(json) : bytes,
    );
    final res = await handler(req);
    final body = await res.read().fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c)).then((b) => b.takeBytes());
    for (final c in res.headersAll['set-cookie'] ?? const <String>[]) {
      final kv = c.split(';').first;
      final i = kv.indexOf('=');
      final name = kv.substring(0, i);
      final value = kv.substring(i + 1);
      if (value.isEmpty || c.contains('Max-Age=0')) {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
    return TestResponse(res.statusCode, res.headers, body);
  }

  Future<void> loginAsAdmin() async {
    final res = await login(adminEmail, adminPassword);
    if (res.status != 200) throw StateError('Admin login nije uspeo: ${res.text}');
  }

  Future<TestResponse> login(String email, String password) =>
      call('POST', '/api/auth/login', json: {'email': email, 'password': password});

  Map<String, Object?> idPayload({required String email, String? nonce, bool verified = true, String? aud, int? exp}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'iss': 'https://accounts.google.com',
      'aud': aud ?? clientId,
      'sub': '1234567890',
      'email': email,
      'email_verified': verified,
      'iat': now,
      'exp': exp ?? now + 3600,
      'nonce': ?nonce,
    };
  }
}

class TestResponse {
  TestResponse(this.status, this.headers, this.body);

  final int status;
  final Map<String, String> headers;
  final Uint8List body;

  String get text => utf8.decode(body, allowMalformed: true);
  dynamic get json => jsonDecode(text);
}

Uint8List testJpeg({int w = 1200, int h = 800}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 128);
    }
  }
  return img.encodeJpg(image, quality: 85);
}
