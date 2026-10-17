import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Greška koja se bezbedno prikazuje klijentu (bez internih detalja).
class ApiError implements Exception {
  ApiError(this.status, this.message, {this.code});

  final int status;
  final String message;
  final String? code;

  static ApiError badRequest(String m) => ApiError(400, m, code: 'bad_request');
  static ApiError unauthorized([String m = 'Potrebna je prijava.']) => ApiError(401, m, code: 'unauthorized');
  static ApiError forbidden([String m = 'Nemate pristup.']) => ApiError(403, m, code: 'forbidden');
  static ApiError notFound([String m = 'Nije pronađeno.']) => ApiError(404, m, code: 'not_found');
  static ApiError conflict(String m) => ApiError(409, m, code: 'conflict');
  static ApiError tooMany() =>
      ApiError(429, 'Previše zahteva. Sačekajte malo pa pokušajte ponovo.', code: 'rate_limited');

  @override
  String toString() => 'ApiError($status, $message)';
}

const _jsonHeaders = {
  HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
  HttpHeaders.cacheControlHeader: 'no-store',
};

Response jsonOk(Object? body, {int status = 200, Map<String, Object>? headers}) =>
    Response(status, body: jsonEncode(body), headers: {..._jsonHeaders, ...?headers});

Response jsonError(ApiError e) => Response(
      e.status,
      body: jsonEncode({'error': e.message, 'code': e.code}),
      headers: _jsonHeaders,
    );

Future<Uint8List> readBodyBytes(Request req, int maxBytes) async {
  final declared = req.contentLength;
  if (declared != null && declared > maxBytes) {
    throw ApiError(413, 'Fajl je prevelik.', code: 'too_large');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in req.read()) {
    builder.add(chunk);
    if (builder.length > maxBytes) {
      throw ApiError(413, 'Fajl je prevelik.', code: 'too_large');
    }
  }
  return builder.takeBytes();
}

Future<Map<String, dynamic>> readJson(Request req, {int maxBytes = 64 * 1024}) async {
  final type = req.headers[HttpHeaders.contentTypeHeader] ?? '';
  if (!type.toLowerCase().startsWith('application/json')) {
    throw ApiError(415, 'Očekivan je JSON.', code: 'unsupported_media_type');
  }
  final bytes = await readBodyBytes(req, maxBytes);
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  throw ApiError.badRequest('Neispravan zahtev.');
}

Map<String, String> parseCookies(Request req) {
  final header = req.headers[HttpHeaders.cookieHeader];
  final out = <String, String>{};
  if (header == null) return out;
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
  }
  return out;
}

String buildCookie(
  String name,
  String value, {
  required bool secure,
  Duration? maxAge,
  String sameSite = 'Strict',
  String path = '/',
}) {
  final b = StringBuffer('$name=$value; Path=$path; HttpOnly; SameSite=$sameSite');
  if (secure) b.write('; Secure');
  if (maxAge != null) b.write('; Max-Age=${maxAge.inSeconds}');
  return b.toString();
}

String clearCookie(String name, {required bool secure, String sameSite = 'Strict'}) =>
    buildCookie(name, '', secure: secure, maxAge: Duration.zero, sameSite: sameSite);

/// Cookie prefiks `__Host-` garantuje Secure, Path=/ i bez Domain atributa.
/// Na lokalnom http razvoju se koristi obično ime.
String cookieName(String base, bool secure) => secure ? '__Host-$base' : base;

String clientIp(Request req, {required bool trustProxy}) {
  if (trustProxy) {
    final fwd = req.headers['x-forwarded-for'];
    if (fwd != null && fwd.isNotEmpty) {
      // Poslednja adresa je ona koju je dodao naš (pouzdani) reverse proxy.
      final parts = fwd.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
  }
  final info = req.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Bezbedno ime fajla za Content-Disposition i ZIP.
String safeFilename(String name) {
  var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  if (n.isEmpty) n = 'fotografija.jpg';
  if (n.length > 150) n = n.substring(n.length - 150);
  return n;
}

String contentDisposition(String filename, {bool attachment = true}) {
  final safe = safeFilename(filename);
  final ascii = safe.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '_');
  final encoded = Uri.encodeComponent(safe);
  return "${attachment ? 'attachment' : 'inline'}; filename=\"$ascii\"; filename*=UTF-8''$encoded";
}

String? str(Map<String, dynamic> m, String key, {int max = 500, bool required = false}) {
  final v = m[key];
  if (v == null || (v is String && v.trim().isEmpty)) {
    if (required) throw ApiError.badRequest('Polje "$key" je obavezno.');
    return null;
  }
  if (v is! String) throw ApiError.badRequest('Polje "$key" mora biti tekst.');
  final t = v.trim();
  if (t.length > max) throw ApiError.badRequest('Polje "$key" je predugačko.');
  return t;
}

int? intField(Map<String, dynamic> m, String key, {int min = 0, int max = 1 << 31}) {
  final v = m[key];
  if (v == null) return null;
  if (v is! int) throw ApiError.badRequest('Polje "$key" mora biti broj.');
  if (v < min || v > max) throw ApiError.badRequest('Polje "$key" nije u dozvoljenom opsegu.');
  return v;
}

bool? boolField(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! bool) throw ApiError.badRequest('Polje "$key" mora biti da/ne.');
  return v;
}

List<String>? stringList(Map<String, dynamic> m, String key, {int maxItems = 20, int maxLen = 40}) {
  final v = m[key];
  if (v == null) return null;
  if (v is! List) throw ApiError.badRequest('Polje "$key" mora biti lista.');
  final out = <String>[];
  for (final x in v) {
    if (x is! String) throw ApiError.badRequest('Polje "$key" mora sadržati tekst.');
    final t = x.trim();
    if (t.isEmpty) continue;
    if (t.length > maxLen) throw ApiError.badRequest('Vrednost u "$key" je predugačka.');
    if (!out.contains(t)) out.add(t);
  }
  if (out.length > maxItems) throw ApiError.badRequest('Previše vrednosti u "$key".');
  return out;
}
