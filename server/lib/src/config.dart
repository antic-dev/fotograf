import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Jedini administrator aplikacije. Svi ostali posetioci su klijenti koji
/// pristupaju isključivo preko tajnog linka projekta.
const defaultAdminEmail = 'minehost43@gmail.com';

class Config {
  Config({
    required this.adminEmail,
    required this.driveEmail,
    required this.googleClientId,
    required this.googleClientSecret,
    required this.publicUrl,
    required this.port,
    required this.host,
    required this.dataDir,
    required this.webDir,
    required this.secretKey,
    required this.cookieSecure,
    required this.trustProxy,
    required this.maxUploadBytes,
    this.smtpHost,
    this.smtpPort = 587,
    this.smtpUser,
    this.smtpPassword,
    this.smtpFrom,
  });

  final String adminEmail;

  /// Google nalog čiji se Drive koristi za skladište (podrazumevano isti kao
  /// administratorski). Korisno ako je veliki prostor na drugom nalogu.
  final String driveEmail;
  final String googleClientId;
  final String googleClientSecret;

  /// Javni URL aplikacije bez završne kose crte, npr. https://foto.mojsajt.rs
  final String publicUrl;
  final int port;
  final String host;
  final String dataDir;
  final String webDir;

  /// 32 bajta tajnog ključa (APP_SECRET, base64) za AES-256-GCM šifrovanje
  /// osetljivih podataka u bazi (Google refresh token, linkovi).
  final Uint8List secretKey;
  final bool cookieSecure;
  final bool trustProxy;
  final int maxUploadBytes;

  final String? smtpHost;
  final int smtpPort;
  final String? smtpUser;
  final String? smtpPassword;
  final String? smtpFrom;

  bool get smtpEnabled =>
      (smtpHost ?? '').isNotEmpty && (smtpUser ?? '').isNotEmpty && (smtpPassword ?? '').isNotEmpty;

  String get driveRedirectUri => '$publicUrl/api/admin/drive/callback';

  Uri get publicOrigin => Uri.parse(publicUrl);

  static Config fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String req(String key) {
      final v = e[key]?.trim() ?? '';
      if (v.isEmpty) {
        throw StateError('Nedostaje obavezna promenljiva okruženja $key (pogledaj .env.example).');
      }
      return v;
    }

    final secret = base64.decode(req('APP_SECRET'));
    if (secret.length != 32) {
      throw StateError('APP_SECRET mora biti 32 bajta u base64 formatu (openssl rand -base64 32).');
    }
    var publicUrl = req('PUBLIC_URL');
    while (publicUrl.endsWith('/')) {
      publicUrl = publicUrl.substring(0, publicUrl.length - 1);
    }
    final cookieSecure = (e['COOKIE_SECURE'] ?? 'true').toLowerCase() != 'false';
    if (cookieSecure && !publicUrl.startsWith('https://') && !publicUrl.startsWith('http://localhost')) {
      throw StateError('PUBLIC_URL mora koristiti https:// u produkciji.');
    }

    final adminEmail = (e['ADMIN_EMAIL'] ?? defaultAdminEmail).trim().toLowerCase();
    final driveEmail = (e['DRIVE_EMAIL'] ?? '').trim().toLowerCase();
    return Config(
      adminEmail: adminEmail,
      driveEmail: driveEmail.isEmpty ? adminEmail : driveEmail,
      googleClientId: req('GOOGLE_CLIENT_ID'),
      googleClientSecret: req('GOOGLE_CLIENT_SECRET'),
      publicUrl: publicUrl,
      port: int.parse(e['PORT'] ?? '8080'),
      host: e['HOST'] ?? '0.0.0.0',
      dataDir: e['DATA_DIR'] ?? 'data',
      webDir: e['WEB_DIR'] ?? '../app/build/web',
      secretKey: Uint8List.fromList(secret),
      cookieSecure: cookieSecure,
      trustProxy: (e['TRUST_PROXY'] ?? 'false').toLowerCase() == 'true',
      maxUploadBytes: int.parse(e['MAX_UPLOAD_MB'] ?? '80') * 1024 * 1024,
      smtpHost: e['SMTP_HOST'],
      smtpPort: int.tryParse(e['SMTP_PORT'] ?? '') ?? 587,
      smtpUser: e['SMTP_USER'],
      smtpPassword: e['SMTP_PASSWORD'],
      smtpFrom: e['SMTP_FROM'],
    );
  }
}
