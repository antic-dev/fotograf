import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../http_util.dart';
import '../passwords.dart';
import '../services.dart';

/// Prijava administratora mejlom i lozinkom.
/// Klijenti se ne prijavljuju — oni koriste tajni link projekta.
void mountAuthRoutes(Router r, Services s) {
  // Provera lozinke je namerno spora (~1 s); ograničavamo broj istovremenih
  // provera da napadač ne bi zaobišao zaključavanje paralelnim zahtevima.
  var inFlight = 0;

  r.post('/api/auth/login', (Request req) async {
    s.rateLimit(req, 'auth-login', 10, const Duration(minutes: 15));
    final body = await readJson(req, maxBytes: 4096);
    final email = (str(body, 'email', max: 200) ?? '').toLowerCase();
    final password = str(body, 'password', max: 200) ?? '';

    final adminEmail = s.adminEmail;
    if (adminEmail == null || !s.adminAccountSet) {
      throw ApiError(503, 'Prijava još nije podešena na serveru (ADMIN_EMAIL i ADMIN_PASSWORD).', code: 'no_account');
    }
    final lock = s.loginLockRemaining;
    if (lock > Duration.zero) {
      final min = (lock.inSeconds / 60).ceil();
      throw ApiError(429, 'Previše pogrešnih pokušaja. Pokušajte ponovo za $min min.', code: 'locked');
    }
    if (inFlight >= 2) throw ApiError.tooMany();

    inFlight++;
    final bool ok;
    try {
      // Lozinka se proverava i kad je mejl pogrešan — isto trajanje odgovora,
      // pa se ne može otkriti koji mejl je administratorski.
      final valid = await verifyPassword(password, s.db.setting('admin_password_hash')!);
      ok = valid && email == adminEmail;
    } finally {
      inFlight--;
    }

    if (!ok) {
      s.recordLoginFailure();
      s.db.audit('login_failed', ip: s.ip(req));
      throw ApiError.unauthorized('Pogrešan mejl ili lozinka.');
    }
    s.recordLoginSuccess();
    final token = s.createAdminSession(req);
    s.db.audit('login', ip: s.ip(req));
    return jsonOk({'ok': true}, headers: {HttpHeaders.setCookieHeader: s.adminCookieHeader(token)});
  });

  r.post('/api/auth/logout', (Request req) {
    s.destroyAdminSession(req);
    return jsonOk({'ok': true}, headers: {
      HttpHeaders.setCookieHeader: clearCookie(s.adminCookie, secure: s.config.cookieSecure),
    });
  });

  r.get('/api/auth/me', (Request req) {
    if (!s.isAdmin(req)) throw ApiError.unauthorized();
    return jsonOk({'admin': true, 'studioName': s.studioName});
  });

  // Promena lozinke iz Podešavanja (traži trenutnu lozinku).
  r.post('/api/admin/password', (Request req) async {
    s.rateLimit(req, 'auth-change', 10, const Duration(minutes: 15));
    final body = await readJson(req, maxBytes: 4096);
    final current = str(body, 'current', max: 200) ?? '';
    final next = str(body, 'next', max: 200) ?? '';
    if (!await verifyPassword(current, s.db.setting('admin_password_hash') ?? '')) {
      throw ApiError.badRequest('Trenutna lozinka nije tačna.');
    }
    if (next.length < 10) throw ApiError.badRequest('Nova lozinka mora imati bar 10 znakova.');
    if (next.toLowerCase().contains((s.adminEmail ?? '').split('@').first)) {
      throw ApiError.badRequest('Lozinka ne sme da sadrži vaš mejl.');
    }
    await s.setAdminPassword(next);
    // Sve druge sesije se gase; ova ostaje prijavljena sa novim kolačićem.
    s.db.exec('DELETE FROM admin_sessions');
    final token = s.createAdminSession(req);
    s.db.audit('password_changed', ip: s.ip(req));
    return jsonOk({'ok': true}, headers: {HttpHeaders.setCookieHeader: s.adminCookieHeader(token)});
  });
}
