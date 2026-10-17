import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'crypto_util.dart';

/// PBKDF2-HMAC-SHA256 sa nasumičnom solju. Broj iteracija je zapisan u hešu,
/// pa se kasnije može povećati bez gubitka postojećih lozinki.
const passwordIterations = 310000;

Uint8List _derive(String password, Uint8List salt, int iterations) {
  final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return d.process(Uint8List.fromList(utf8.encode(password)));
}

/// Pravi heš lozinke (traje ~1 s, u zasebnom izolatu da server ne stane).
Future<String> hashPassword(String password, {int iterations = passwordIterations}) async {
  final salt = randomBytes(16);
  final hash = await Isolate.run(() => _derive(password, salt, iterations));
  return 'pbkdf2-sha256\$$iterations\$${b64url(salt)}\$${b64url(hash)}';
}

/// Proverava lozinku u konstantnom vremenu.
Future<bool> verifyPassword(String password, String stored) async {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1000) return false;
  final salt = b64urlDecode(parts[2]);
  final expected = b64urlDecode(parts[3]);
  final actual = await Isolate.run(() => _derive(password, salt, iterations));
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}

/// Otisak lozinke iz okruženja (HMAC tajnim ključem) — da server prepozna
/// kada je ADMIN_PASSWORD promenjen, bez čuvanja same lozinke.
String envPasswordFingerprint(String password, Uint8List secretKey) {
  final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(secretKey));
  return b64url(mac.process(Uint8List.fromList(utf8.encode('admin-password:$password'))));
}
