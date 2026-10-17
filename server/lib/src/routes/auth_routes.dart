import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../crypto_util.dart';
import '../google_id_token.dart';
import '../http_util.dart';
import '../services.dart';

/// Prijava administratora preko "Sign in with Google" (Google Identity Services).
/// Klijenti se ne prijavljuju — oni koriste tajni link projekta.
void mountAuthRoutes(Router r, Services s) {
  // Jednokratni nonce vezan za pregledač — sprečava ponovnu upotrebu
  // (replay) ukradenog Google ID tokena.
  r.get('/api/auth/start', (Request req) {
    s.rateLimit(req, 'auth-start', 60, const Duration(minutes: 1));
    final nonce = randomToken(24);
    return jsonOk(
      {'clientId': s.config.googleClientId, 'nonce': nonce},
      headers: {
        HttpHeaders.setCookieHeader: buildCookie(
          s.nonceCookie,
          sha256Hex(nonce),
          secure: s.config.cookieSecure,
          maxAge: const Duration(minutes: 15),
        ),
      },
    );
  });

  r.post('/api/auth/google', (Request req) async {
    s.rateLimit(req, 'auth-login', 10, const Duration(minutes: 5));
    final body = await readJson(req, maxBytes: 8192);
    final credential = str(body, 'credential', max: 4096, required: true)!;

    final GoogleIdentity id;
    try {
      id = await s.idVerifier.verify(credential);
    } on IdTokenException {
      s.db.audit('login_failed', detail: 'neispravan token', ip: s.ip(req));
      throw ApiError.unauthorized('Prijava nije uspela. Pokušajte ponovo.');
    }

    final expectedNonce = parseCookies(req)[s.nonceCookie];
    if (expectedNonce == null || id.nonce == null || !constantTimeEquals(expectedNonce, sha256Hex(id.nonce!))) {
      s.db.audit('login_failed', detail: 'nonce', ip: s.ip(req));
      throw ApiError.unauthorized('Prijava je istekla. Osvežite stranicu i pokušajte ponovo.');
    }

    if (!id.emailVerified || id.email != s.config.adminEmail) {
      s.db.audit('login_denied', detail: id.email, ip: s.ip(req));
      throw ApiError.forbidden('Nalog ${id.email} nema pristup administraciji.');
    }

    final token = s.createAdminSession(req);
    s.db.audit('login', detail: id.email, ip: s.ip(req));
    return Response(
      200,
      body: '{"ok":true}',
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.cacheControlHeader: 'no-store',
        HttpHeaders.setCookieHeader: [
          s.adminCookieHeader(token),
          clearCookie(s.nonceCookie, secure: s.config.cookieSecure),
        ],
      },
    );
  });

  r.post('/api/auth/logout', (Request req) {
    s.destroyAdminSession(req);
    return jsonOk({'ok': true}, headers: {
      HttpHeaders.setCookieHeader: clearCookie(s.adminCookie, secure: s.config.cookieSecure),
    });
  });

  r.get('/api/auth/me', (Request req) {
    if (!s.isAdmin(req)) throw ApiError.unauthorized();
    return jsonOk({'admin': true, 'email': s.config.adminEmail, 'studioName': s.studioName});
  });
}
