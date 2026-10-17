import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import 'crypto_util.dart';

class IdTokenException implements Exception {
  IdTokenException(this.message);
  final String message;
  @override
  String toString() => 'IdTokenException: $message';
}

class GoogleIdentity {
  GoogleIdentity({required this.sub, required this.email, required this.emailVerified, this.name, this.picture, this.nonce});

  final String sub;
  final String email;
  final bool emailVerified;
  final String? name;
  final String? picture;
  final String? nonce;
}

/// Lokalna kriptografska provera Google ID tokena (RS256) uz keširane
/// javne ključeve sa https://www.googleapis.com/oauth2/v3/certs.
class GoogleIdTokenVerifier {
  GoogleIdTokenVerifier({required this.clientId, http.Client? client}) : _http = client ?? http.Client();

  static final _certsUri = Uri.parse('https://www.googleapis.com/oauth2/v3/certs');
  static const _issuers = {'accounts.google.com', 'https://accounts.google.com'};

  final String clientId;
  final http.Client _http;
  Map<String, RSAPublicKey> _keys = {};
  DateTime _keysExpire = DateTime.fromMillisecondsSinceEpoch(0);

  Future<GoogleIdentity> verify(String token) async {
    final parts = token.split('.');
    if (parts.length != 3) throw IdTokenException('Neispravan format tokena.');

    final Map<String, dynamic> header;
    final Map<String, dynamic> payload;
    try {
      header = jsonDecode(utf8.decode(b64urlDecode(parts[0]))) as Map<String, dynamic>;
      payload = jsonDecode(utf8.decode(b64urlDecode(parts[1]))) as Map<String, dynamic>;
    } catch (_) {
      throw IdTokenException('Token se ne može pročitati.');
    }
    if (header['alg'] != 'RS256') throw IdTokenException('Nepodržan algoritam.');
    final kid = header['kid'];
    if (kid is! String) throw IdTokenException('Nedostaje kid.');

    final key = await _key(kid);
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(key));
    final signedData = Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}'));
    final bool valid;
    try {
      valid = signer.verifySignature(signedData, RSASignature(b64urlDecode(parts[2])));
    } catch (_) {
      throw IdTokenException('Potpis nije ispravan.');
    }
    if (!valid) throw IdTokenException('Potpis nije ispravan.');

    if (!_issuers.contains(payload['iss'])) throw IdTokenException('Pogrešan izdavalac.');
    final aud = payload['aud'];
    if (aud != clientId) throw IdTokenException('Token nije namenjen ovoj aplikaciji.');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exp = payload['exp'];
    final iat = payload['iat'];
    if (exp is! int || exp < now - 30) throw IdTokenException('Token je istekao.');
    if (iat is! int || iat > now + 300) throw IdTokenException('Neispravno vreme izdavanja.');

    final email = payload['email'];
    final sub = payload['sub'];
    if (email is! String || sub is! String) throw IdTokenException('Nedostaje email.');
    final verified = payload['email_verified'] == true || payload['email_verified'] == 'true';

    return GoogleIdentity(
      sub: sub,
      email: email.toLowerCase(),
      emailVerified: verified,
      name: payload['name'] as String?,
      picture: payload['picture'] as String?,
      nonce: payload['nonce'] as String?,
    );
  }

  Future<RSAPublicKey> _key(String kid) async {
    if (DateTime.now().isAfter(_keysExpire) || !_keys.containsKey(kid)) {
      await _refresh();
    }
    final k = _keys[kid];
    if (k == null) throw IdTokenException('Nepoznat ključ.');
    return k;
  }

  Future<void> _refresh() async {
    final res = await _http.get(_certsUri);
    if (res.statusCode != 200) throw IdTokenException('Google ključevi nisu dostupni.');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final keys = <String, RSAPublicKey>{};
    for (final k in (body['keys'] as List).cast<Map<String, dynamic>>()) {
      if (k['kty'] != 'RSA') continue;
      keys[k['kid'] as String] = RSAPublicKey(
        _bigInt(b64urlDecode(k['n'] as String)),
        _bigInt(b64urlDecode(k['e'] as String)),
      );
    }
    _keys = keys;
    var maxAge = 3600;
    final cc = res.headers['cache-control'];
    final m = cc == null ? null : RegExp(r'max-age=(\d+)').firstMatch(cc);
    if (m != null) maxAge = int.parse(m.group(1)!);
    _keysExpire = DateTime.now().add(Duration(seconds: maxAge));
  }

  static BigInt _bigInt(Uint8List bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }
}
