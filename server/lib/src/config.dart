import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Najmanja dozvoljena dužina administratorske lozinke.
const minPasswordLength = 8;

class Config {
  Config({
    required this.publicUrl,
    required this.port,
    required this.host,
    required this.dataDir,
    required this.webDir,
    required this.secretKey,
    required this.cookieSecure,
    required this.trustProxy,
    required this.maxUploadBytes,
    this.adminEmail,
    this.adminPassword,
    this.driveEmail,
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.cacheMaxBytes = 10 * 1024 * 1024 * 1024,
    this.smtpHost,
    this.smtpPort = 587,
    this.smtpUser,
    this.smtpPassword,
    this.smtpFrom,
  });

  /// Mejl jedinog administratora (ADMIN_EMAIL). Kao i lozinka, upisuje se u
  /// bazu pri pokretanju, pa kasnije može da se izostavi. Nigde se ne prikazuje.
  final String? adminEmail;

  /// Početna lozinka administratora (ADMIN_PASSWORD). Čuva se samo kao jak
  /// heš u bazi; promena ove vrednosti resetuje lozinku.
  final String? adminPassword;

  /// Opciono: jedini Google nalog čiji Drive sme da se poveže (DRIVE_EMAIL).
  /// Bez njega se koristi nalog koji administrator izabere pri povezivanju.
  final String? driveEmail;

  /// Google OAuth podaci — potrebni SAMO za povezivanje Google Drive-a.
  final String googleClientId;
  final String googleClientSecret;

  /// Javni URL aplikacije bez završne kose crte, npr. https://foto.mojsajt.rs
  final String publicUrl;
  final int port;
  final String host;
  final String dataDir;
  final String webDir;

  /// 32 bajta tajnog ključa za AES-256-GCM šifrovanje osetljivih podataka u
  /// bazi (Google refresh token, linkovi).
  final Uint8List secretKey;
  final bool cookieSecure;
  final bool trustProxy;
  final int maxUploadBytes;

  /// Najveća veličina keša sličica i pregleda na disku servera.
  final int cacheMaxBytes;

  final String? smtpHost;
  final int smtpPort;
  final String? smtpUser;
  final String? smtpPassword;
  final String? smtpFrom;

  bool get smtpEnabled =>
      (smtpHost ?? '').isNotEmpty && (smtpUser ?? '').isNotEmpty && (smtpPassword ?? '').isNotEmpty;

  bool get googleConfigured => googleClientId.isNotEmpty && googleClientSecret.isNotEmpty;

  String get driveRedirectUri => '$publicUrl/api/admin/drive/callback';

  Uri get publicOrigin => Uri.parse(publicUrl);

  static Config fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String? opt(String key) {
      final v = e[key]?.trim() ?? '';
      return v.isEmpty ? null : v;
    }

    final port = int.parse(opt('PORT') ?? '8080');
    final dataDir = opt('DATA_DIR') ?? 'data';

    // Bez PUBLIC_URL aplikacija radi lokalno na ovom računaru.
    var publicUrl = opt('PUBLIC_URL') ?? 'http://localhost:$port';
    while (publicUrl.endsWith('/')) {
      publicUrl = publicUrl.substring(0, publicUrl.length - 1);
    }
    final local = publicUrl.startsWith('http://localhost') || publicUrl.startsWith('http://127.0.0.1');
    final cookieSecure =
        (opt('COOKIE_SECURE') ?? (publicUrl.startsWith('https://') ? 'true' : 'false')).toLowerCase() != 'false';
    if (!publicUrl.startsWith('https://') && !local) {
      throw StateError('PUBLIC_URL mora koristiti https:// (npr. https://foto.mojsajt.rs).');
    }

    // ADMIN_PASSWORD_B64 koristi automatsko postavljanje (deploy.yml), da
    // specijalni znakovi u lozinki ($, #, navodnici) ne smetaju .env fajlu.
    final b64 = opt('ADMIN_PASSWORD_B64');
    String? adminPassword;
    if (b64 != null) {
      try {
        adminPassword = utf8.decode(base64.decode(b64));
      } on FormatException {
        throw StateError('ADMIN_PASSWORD_B64 nije ispravan base64.');
      }
    } else {
      adminPassword = opt('ADMIN_PASSWORD');
    }
    if (adminPassword != null && adminPassword.length < minPasswordLength) {
      throw StateError('ADMIN_PASSWORD mora imati bar $minPasswordLength znakova.');
    }

    final adminEmail = opt('ADMIN_EMAIL')?.toLowerCase();
    if (adminEmail != null && !RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(adminEmail)) {
      throw StateError('ADMIN_EMAIL nije ispravan mejl.');
    }
    return Config(
      adminEmail: adminEmail,
      adminPassword: adminPassword,
      driveEmail: opt('DRIVE_EMAIL')?.toLowerCase(),
      googleClientId: opt('GOOGLE_CLIENT_ID') ?? '',
      googleClientSecret: opt('GOOGLE_CLIENT_SECRET') ?? '',
      publicUrl: publicUrl,
      port: port,
      host: opt('HOST') ?? '0.0.0.0',
      dataDir: dataDir,
      webDir: opt('WEB_DIR') ?? '../app/build/web',
      secretKey: _secretKey(opt('APP_SECRET'), dataDir),
      cookieSecure: cookieSecure,
      trustProxy: (opt('TRUST_PROXY') ?? 'false').toLowerCase() == 'true',
      maxUploadBytes: int.parse(opt('MAX_UPLOAD_MB') ?? '80') * 1024 * 1024,
      cacheMaxBytes: (double.parse(opt('CACHE_MAX_GB') ?? '10') * 1024 * 1024 * 1024).round(),
      smtpHost: opt('SMTP_HOST'),
      smtpPort: int.tryParse(opt('SMTP_PORT') ?? '') ?? 587,
      smtpUser: opt('SMTP_USER'),
      smtpPassword: opt('SMTP_PASSWORD'),
      smtpFrom: opt('SMTP_FROM'),
    );
  }

  /// APP_SECRET iz okruženja, ili ključ koji se jednom napravi i čuva u
  /// fajlu `app_secret` u folderu sa podacima.
  static Uint8List _secretKey(String? fromEnv, String dataDir) {
    if (fromEnv != null) {
      final k = base64.decode(fromEnv);
      if (k.length != 32) throw StateError('APP_SECRET mora biti 32 bajta u base64 formatu (openssl rand -base64 32).');
      return Uint8List.fromList(k);
    }
    Directory(dataDir).createSync(recursive: true);
    final f = File(p.join(dataDir, 'app_secret'));
    if (f.existsSync()) {
      final k = base64.decode(f.readAsStringSync().trim());
      if (k.length == 32) return Uint8List.fromList(k);
      throw StateError('Fajl ${f.path} je oštećen.');
    }
    final rng = Random.secure();
    final k = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    f.writeAsStringSync(base64.encode(k));
    if (!Platform.isWindows) Process.runSync('chmod', ['600', f.path]);
    return k;
  }
}
