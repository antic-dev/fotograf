import 'dart:io';

import 'package:shelf/shelf.dart';

import 'config.dart';
import 'crypto_util.dart';
import 'db.dart';
import 'drive.dart';
import 'google_id_token.dart';
import 'http_util.dart';
import 'images.dart';
import 'mailer.dart';
import 'rate_limit.dart';

const adminSessionAbsolute = Duration(hours: 12);
const adminSessionIdle = Duration(hours: 4);
const visitorCookieAge = Duration(days: 400);

/// Svi klijenti dobijaju isti format; menja se samo broj primeraka.
const defaultPrintSize = '13x18';

/// Svi deljeni servisi aplikacije na jednom mestu.
class Services {
  Services({
    required this.config,
    required this.db,
    required this.drive,
    required this.cache,
    required this.idVerifier,
    required this.mailer,
  })  : box = SecretBox(config.secretKey),
        limiter = RateLimiter();

  final Config config;
  final Db db;
  final DriveStore drive;
  final MediaCache cache;
  final GoogleIdTokenVerifier idVerifier;
  final Mailer mailer;
  final SecretBox box;
  final RateLimiter limiter;

  /// Privremena stanja OAuth povezivanja Drive-a: state -> PKCE verifier.
  final Map<String, ({String verifier, int expires})> oauthPending = {};

  String get adminCookie => cookieName('fa', config.cookieSecure);
  String get visitorCookie => cookieName('fv', config.cookieSecure);
  String get nonceCookie => cookieName('fn', config.cookieSecure);
  String get oauthCookie => cookieName('fo', config.cookieSecure);

  String ip(Request req) => clientIp(req, trustProxy: config.trustProxy);

  void rateLimit(Request req, String bucket, int max, Duration window) {
    if (!limiter.allow('$bucket:${ip(req)}', max, window)) throw ApiError.tooMany();
  }

  // ---------------------------------------------------------------------------
  // Podešavanja
  // ---------------------------------------------------------------------------

  String get studioName => db.setting('studio_name') ?? 'Fotograf';
  /// Žig se UVEK stavlja na slike koje vide klijenti.
  String get watermarkText {
    final t = (db.setting('watermark_text') ?? '').trim();
    return t.isNotEmpty ? t : studioName;
  }
  String get printerEmail => db.setting('printer_email') ?? '';

  /// Format štampe (npr. "13x18") — isti za sve fotografije i sve klijente.
  String get printSize {
    final v = (db.setting('print_size') ?? '').trim();
    return v.isEmpty ? defaultPrintSize : v;
  }

  // ---------------------------------------------------------------------------
  // Administratorska sesija
  // ---------------------------------------------------------------------------

  String createAdminSession(Request req) {
    final token = randomToken(32);
    final now = nowMs();
    db.exec(
      'INSERT INTO admin_sessions(token_hash, created_at, expires_at, last_seen_at, ip, user_agent) VALUES(?, ?, ?, ?, ?, ?)',
      [
        sha256Hex(token),
        now,
        now + adminSessionAbsolute.inMilliseconds,
        now,
        ip(req),
        (req.headers[HttpHeaders.userAgentHeader] ?? '').characters200,
      ],
    );
    db.exec('DELETE FROM admin_sessions WHERE expires_at < ? OR last_seen_at < ?',
        [now, now - adminSessionIdle.inMilliseconds]);
    return token;
  }

  bool isAdmin(Request req) {
    final token = parseCookies(req)[adminCookie];
    if (token == null || token.length > 100) return false;
    final hash = sha256Hex(token);
    final row = db.one('SELECT expires_at, last_seen_at FROM admin_sessions WHERE token_hash = ?', [hash]);
    if (row == null) return false;
    final now = nowMs();
    if ((row['expires_at'] as int) < now || (row['last_seen_at'] as int) < now - adminSessionIdle.inMilliseconds) {
      db.exec('DELETE FROM admin_sessions WHERE token_hash = ?', [hash]);
      return false;
    }
    if (now - (row['last_seen_at'] as int) > 60000) {
      db.exec('UPDATE admin_sessions SET last_seen_at = ? WHERE token_hash = ?', [now, hash]);
    }
    return true;
  }

  void requireAdmin(Request req) {
    if (!isAdmin(req)) throw ApiError.unauthorized('Sesija je istekla. Prijavite se ponovo.');
  }

  void destroyAdminSession(Request req) {
    final token = parseCookies(req)[adminCookie];
    if (token != null) db.exec('DELETE FROM admin_sessions WHERE token_hash = ?', [sha256Hex(token)]);
  }

  String adminCookieHeader(String token) =>
      buildCookie(adminCookie, token, secure: config.cookieSecure, maxAge: adminSessionAbsolute);

  // ---------------------------------------------------------------------------
  // Posetioci (klijenti bez naloga)
  // ---------------------------------------------------------------------------

  /// Vraća ID posetioca iz kolačića, ili null.
  String? visitorId(Request req) {
    final token = parseCookies(req)[visitorCookie];
    if (token == null || token.length > 100) return null;
    final row = db.one('SELECT id, last_seen_at FROM visitors WHERE token_hash = ?', [sha256Hex(token)]);
    if (row == null) return null;
    final now = nowMs();
    if (now - (row['last_seen_at'] as int) > 3600000) {
      db.exec('UPDATE visitors SET last_seen_at = ? WHERE id = ?', [now, row['id']]);
    }
    return row['id'] as String;
  }

  /// Pravi novog posetioca; vraća ID i Set-Cookie zaglavlje.
  ({String id, String cookie}) createVisitor() {
    final token = randomToken(32);
    final id = randomId();
    final now = nowMs();
    db.exec('INSERT INTO visitors(id, token_hash, created_at, last_seen_at) VALUES(?, ?, ?, ?)',
        [id, sha256Hex(token), now, now]);
    return (
      id: id,
      cookie: buildCookie(visitorCookie, token, secure: config.cookieSecure, maxAge: visitorCookieAge, sameSite: 'Lax'),
    );
  }

  // ---------------------------------------------------------------------------
  // Linkovi
  // ---------------------------------------------------------------------------

  String shareUrl(String token) => '${config.publicUrl}/g/$token';
  String printUrl(String token) => '${config.publicUrl}/stampa/$token';

  String? decryptOrNull(String? enc) {
    if (enc == null) return null;
    try {
      return box.decrypt(enc);
    } catch (_) {
      return null;
    }
  }
}

extension on String {
  String get characters200 => length > 200 ? substring(0, 200) : this;
}
