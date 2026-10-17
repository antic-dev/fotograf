import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'http_util.dart';
import 'routes/admin_routes.dart';
import 'routes/auth_routes.dart';
import 'routes/client_routes.dart';
import 'routes/print_routes.dart';
import 'services.dart';

Handler buildHandler(Services s) {
  final router = Router(notFoundHandler: (Request req) {
    if (req.url.path.startsWith('api/')) return jsonError(ApiError.notFound());
    return _serveWeb(s, req);
  });
  mountAuthRoutes(router, s);
  mountClientRoutes(router, s);
  mountPrintRoutes(router, s);
  mountAdminRoutes(router, s);

  return const Pipeline()
      .addMiddleware(_securityHeaders(s))
      .addMiddleware(_errors())
      .addMiddleware(_csrf(s))
      .addMiddleware(_adminGuard(s))
      .addHandler(router.call);
}

/// Strogi bezbednosni HTTP zaglavlja za svaki odgovor.
Middleware _securityHeaders(Services s) {
  final csp = [
    "default-src 'self'",
    // Flutter (CanvasKit) koristi WebAssembly; Google prijava se učitava sa accounts.google.com
    "script-src 'self' 'wasm-unsafe-eval' https://accounts.google.com/gsi/client",
    "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style",
    "img-src 'self' data: blob:",
    "font-src 'self' data: https://fonts.gstatic.com",
    "connect-src 'self' https://accounts.google.com/gsi/ https://fonts.gstatic.com",
    'frame-src https://accounts.google.com/gsi/',
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    if (s.config.cookieSecure) 'upgrade-insecure-requests',
  ].join('; ');

  final headers = <String, String>{
    'content-security-policy': csp,
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'cross-origin-opener-policy': 'same-origin-allow-popups',
    'cross-origin-resource-policy': 'same-origin',
    'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()',
    'x-robots-tag': 'noindex, nofollow, noarchive',
    if (s.config.cookieSecure) 'strict-transport-security': 'max-age=63072000; includeSubDomains',
  };
  return (inner) => (req) async {
        final res = await inner(req);
        return res.change(headers: headers);
      };
}

Middleware _errors() => (inner) => (req) async {
      try {
        return await inner(req);
      } on ApiError catch (e) {
        return jsonError(e);
      } catch (e, st) {
        stderr.writeln('[${DateTime.now().toIso8601String()}] ${req.method} /${req.url.path}: $e\n$st');
        return jsonError(ApiError(500, 'Došlo je do greške na serveru. Pokušajte ponovo.', code: 'server_error'));
      }
    };

/// Zaštita od CSRF: svaki zahtev koji menja podatke mora doći sa našeg
/// porekla i nositi prilagođeno zaglavlje koje drugi sajtovi ne mogu poslati
/// bez CORS dozvole (a CORS ne dozvoljavamo nikome).
Middleware _csrf(Services s) => (inner) => (req) {
      const safe = {'GET', 'HEAD', 'OPTIONS'};
      if (req.url.path.startsWith('api/') && !safe.contains(req.method)) {
        if (req.headers['x-fotograf'] != '1') throw ApiError.forbidden('Zahtev je odbijen.');
        final origin = req.headers['origin'];
        if (origin != null && origin != s.config.publicOrigin.origin) {
          throw ApiError.forbidden('Zahtev je odbijen.');
        }
        final site = req.headers['sec-fetch-site'];
        if (site != null && site != 'same-origin' && site != 'none') {
          throw ApiError.forbidden('Zahtev je odbijen.');
        }
      }
      if (req.method == 'OPTIONS') return Response(204);
      return inner(req);
    };

Middleware _adminGuard(Services s) => (inner) => (req) {
      final path = req.url.path;
      if (path.startsWith('api/admin/') && path != 'api/admin/drive/callback') {
        s.requireAdmin(req);
      }
      return inner(req);
    };

const _mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.bin': 'application/octet-stream',
  '.frag': 'application/octet-stream',
  '.webmanifest': 'application/manifest+json',
};

Future<Response> _serveWeb(Services s, Request req) async {
  if (req.method != 'GET' && req.method != 'HEAD') return Response(405);
  final root = p.normalize(p.absolute(s.config.webDir));
  String rel;
  try {
    rel = Uri.decodeComponent(req.url.path);
  } on ArgumentError {
    rel = ''; // neispravno kodiran URL → početna stranica
  }
  var file = File(p.normalize(p.join(root, rel)));
  // Sprečava izlazak iz web foldera (path traversal) i skrivene fajlove.
  final insideRoot = p.isWithin(root, file.path);
  final hidden = p.split(rel).any((seg) => seg.startsWith('.'));
  if (!insideRoot || hidden || !file.existsSync()) {
    file = File(p.join(root, 'index.html'));
    if (!file.existsSync()) {
      return Response.notFound('Web aplikacija nije izgrađena. Pokrenite: cd app && flutter build web');
    }
  }
  final ext = p.extension(file.path).toLowerCase();
  final stat = file.statSync();
  final etag = '"${stat.size.toRadixString(36)}-${stat.modified.millisecondsSinceEpoch.toRadixString(36)}"';
  final headers = {
    HttpHeaders.contentTypeHeader: _mime[ext] ?? 'application/octet-stream',
    // Flutter fajlovi nemaju verziju u imenu (main.dart.js...), pa pregledač
    // uvek proverava ETag — posle novog deploy-a niko ne dobija mešavinu verzija.
    // Provera je jeftina (304 bez sadržaja).
    HttpHeaders.cacheControlHeader: 'no-cache',
    HttpHeaders.etagHeader: etag,
  };
  if (req.headers[HttpHeaders.ifNoneMatchHeader] == etag) return Response.notModified(headers: headers);
  return Response.ok(
    req.method == 'HEAD' ? null : file.openRead(),
    headers: {...headers, HttpHeaders.contentLengthHeader: '${stat.size}'},
  );
}
