import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

final Random _rng = Random.secure();

Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64urlDecode(String s) {
  final padded = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
  return base64Url.decode(padded);
}

/// Nasumičan, kriptografski siguran token (podrazumevano 192 bita).
String randomToken([int bytes = 24]) => b64url(randomBytes(bytes));

/// Kratak nasumičan identifikator za javne ID-jeve (nije pogodljiv, 96 bita).
String randomId() => b64url(randomBytes(12));

String sha256Hex(String input) => c.sha256.convert(utf8.encode(input)).toString();

/// Poređenje u konstantnom vremenu (zaštita od timing napada).
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

/// AES-256-GCM šifrovanje osetljivih vrednosti pre upisa u bazu.
class SecretBox {
  SecretBox(this._key) {
    if (_key.length != 32) throw ArgumentError('Ključ mora imati 32 bajta.');
  }

  final Uint8List _key;

  String encrypt(String plaintext) {
    final nonce = randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));
    final out = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
    return 'v1.${b64url(nonce)}.${b64url(out)}';
  }

  String decrypt(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != 'v1') {
      throw const FormatException('Neispravan šifrovani zapis.');
    }
    final nonce = b64urlDecode(parts[1]);
    final data = b64urlDecode(parts[2]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));
    return utf8.decode(cipher.process(data));
  }
}

/// PKCE (RFC 7636) S256 izazov za dati verifier.
String pkceChallenge(String verifier) => b64url(c.sha256.convert(ascii.encode(verifier)).bytes);
