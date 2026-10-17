import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code});

  final int status;
  final String message;
  final String? code;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Klijent za naš server. Aplikacija i API su na istom domenu, pa pregledač
/// sam šalje HttpOnly kolačiće; JavaScript ih nikada ne vidi.
class Api {
  Api._();

  static final Api instance = Api._();
  final http.Client _client = http.Client();

  /// Poziva se kada server javi da je administratorska sesija istekla.
  void Function()? onUnauthorized;

  static const _headers = {'X-Fotograf': '1'};

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body ?? const {});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body ?? const {});
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.base.resolve(path))..headers.addAll(_headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req));
    } catch (_) {
      throw ApiException(0, 'Nema internet veze. Proverite vezu i pokušajte ponovo.', code: 'offline');
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final message = data is Map && data['error'] is String ? data['error'] as String : 'Nešto nije u redu (${res.statusCode}).';
    final err = ApiException(res.statusCode, message, code: data is Map ? data['code'] as String? : null);
    if (err.isUnauthorized && path.startsWith('/api/admin/')) onUnauthorized?.call();
    throw err;
  }
}
