import 'dart:convert';
import 'dart:io';

import 'package:fotograf_server/fotograf_server.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeGoogle google;
  late TestApp app;

  setUpAll(() => google = FakeGoogle());
  setUp(() => app = TestApp.create(google));
  tearDown(() => app.dispose());

  group('bezbednost', () {
    test('admin rute traže prijavu', () async {
      final res = await app.call('GET', '/api/admin/projects');
      expect(res.status, 401);
    });

    test('svaki odgovor ima bezbednosna zaglavlja', () async {
      final res = await app.call('GET', '/api/auth/me');
      expect(res.headers['content-security-policy'], contains("frame-ancestors 'none'"));
      expect(res.headers['x-frame-options'], 'DENY');
      expect(res.headers['referrer-policy'], 'no-referrer');
      expect(res.headers['strict-transport-security'], isNotNull);
    });

    test('POST bez CSRF zaglavlja ili sa tuđeg porekla se odbija', () async {
      await app.loginAsAdmin();
      var res = await app.call('POST', '/api/admin/projects', json: {'title': 'x'}, csrf: false);
      expect(res.status, 403);
      res = await app.call('POST', '/api/admin/projects',
          json: {'title': 'x'}, headers: {'origin': 'https://zlonamerni.sajt'});
      expect(res.status, 403);
    });

    test('samo administratorski nalog može da se prijavi', () async {
      final start = await app.call('GET', '/api/auth/start');
      final token = google.sign(app.idPayload(email: 'neko.drugi@gmail.com', nonce: start.json['nonce'] as String));
      final res = await app.call('POST', '/api/auth/google', json: {'credential': token});
      expect(res.status, 403);
      expect((await app.call('GET', '/api/admin/projects')).status, 401);
    });

    test('prijava odbija token bez ispravnog nonce-a (replay)', () async {
      await app.call('GET', '/api/auth/start');
      final token = google.sign(app.idPayload(email: app.services.config.adminEmail, nonce: 'tudji-nonce'));
      final res = await app.call('POST', '/api/auth/google', json: {'credential': token});
      expect(res.status, 401);
    });

    test('prijava odbija neverifikovan mejl, pogrešan aud, istekao token i lažan potpis', () async {
      Future<int> attempt(Map<String, Object?> Function(String nonce) payload, {bool tamper = false}) async {
        final start = await app.call('GET', '/api/auth/start');
        var token = google.sign(payload(start.json['nonce'] as String));
        if (tamper) {
          final parts = token.split('.');
          final body = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
          body['email'] = app.services.config.adminEmail;
          token = '${parts[0]}.${b64url(utf8.encode(jsonEncode(body)))}.${parts[2]}';
        }
        return (await app.call('POST', '/api/auth/google', json: {'credential': token})).status;
      }

      final admin = app.services.config.adminEmail;
      expect(await attempt((n) => app.idPayload(email: admin, nonce: n, verified: false)), 403);
      expect(await attempt((n) => app.idPayload(email: admin, nonce: n, aud: 'drugi-klijent')), 401);
      expect(await attempt((n) => app.idPayload(email: admin, nonce: n, exp: 1000)), 401);
      expect(await attempt((n) => app.idPayload(email: 'napadac@gmail.com', nonce: n), tamper: true), 401);
    });

    test('odjava poništava sesiju', () async {
      await app.loginAsAdmin();
      expect((await app.call('GET', '/api/auth/me')).status, 200);
      final saved = Map.of(app.cookies);
      await app.call('POST', '/api/auth/logout');
      app.cookies.addAll(saved); // čak i ukradeni kolačić više ne važi
      expect((await app.call('GET', '/api/auth/me')).status, 401);
    });

    test('osetljive vrednosti su šifrovane', () {
      final box = SecretBox(app.services.config.secretKey);
      final enc = box.encrypt('refresh-token');
      expect(enc, isNot(contains('refresh')));
      expect(box.decrypt(enc), 'refresh-token');
      final tampered = '${enc.substring(0, enc.length - 2)}AA';
      expect(() => box.decrypt(tampered), throwsA(anything));
    });
  });

  group('kompletan tok', () {
    test('projekat → otpremanje → izbor klijenta → štamparija', () async {
      await app.loginAsAdmin();

      // 1. Novi projekat
      var res = await app.call('POST', '/api/admin/projects', json: {
        'title': 'Venčanje Ana i Marko',
        'clientName': 'Ana',
        'eventDate': '2026-06-14',
        'maxPhotos': 2,
        'sizes': ['13x18', '20x30'],
        'finishes': ['Sjajni', 'Mat'],
      });
      expect(res.status, 201, reason: res.text);
      final project = res.json as Map<String, dynamic>;
      final projectId = project['id'] as String;
      final shareUrl = project['shareUrl'] as String;
      expect(shareUrl, startsWith('${TestApp.origin}/g/'));
      final token = shareUrl.split('/g/').last;

      // 2. Otpremanje — ne-slike se odbijaju
      res = await app.call('POST', '/api/admin/projects/$projectId/photos?name=virus.jpg', bytes: utf8.encode('<?php echo 1; ?> ... padding'));
      expect(res.status, 415);
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        res = await app.call('POST', '/api/admin/projects/$projectId/photos?name=IMG_000$i.jpg', bytes: testJpeg(w: 900 + i * 10, h: 600));
        expect(res.status, 201, reason: res.text);
        ids.add(res.json['id'] as String);
      }
      expect(app.drive.files, hasLength(3));

      // 3. Klijent bez naloga otvara link
      app.cookies.clear();
      res = await app.call('GET', '/api/s/$token');
      expect(res.status, 200);
      expect(res.json['photos'], hasLength(3));
      expect(res.json['project']['canSelect'], true);
      expect(res.json.toString(), isNot(contains('drive')), reason: 'klijent ne sme videti Drive ID-jeve');

      // Pogrešan link i link drugog projekta ne otvaraju ništa
      expect((await app.call('GET', '/api/s/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).status, 404);
      res = await app.call('GET', '/api/s/$token/photos/${ids[0]}/thumb');
      expect(res.status, 200);
      expect(res.headers['content-type'], 'image/jpeg');
      res = await app.call('GET', '/api/s/$token/photos/${ids[0]}/preview');
      expect(res.status, 200);
      final clientPreview = res.body;

      // Slika se ne može otvoriti direktno u pregledaču niti ugraditi na drugi sajt
      res = await app.call('GET', '/api/s/$token/photos/${ids[0]}/preview', csrf: false);
      expect(res.status, 403);
      res = await app.call('GET', '/api/s/$token/photos/${ids[0]}/preview', headers: {'sec-fetch-dest': 'document'});
      expect(res.status, 403);
      res = await app.call('GET', '/api/s/$token/photos/${ids[0]}/thumb', headers: {'sec-fetch-dest': 'image'});
      expect(res.status, 403);

      // 4. Izbor fotografija (čuva se automatski)
      res = await app.call('PUT', '/api/s/$token/selection/${ids[0]}', json: {});
      expect(res.status, 200, reason: res.text);
      expect(app.cookies.keys.any((k) => k.contains('fv')), isTrue);
      res = await app.call('PUT', '/api/s/$token/selection/${ids[1]}', json: {'quantity': 3, 'size': '20x30', 'finish': 'Mat'});
      expect(res.status, 200);
      res = await app.call('PUT', '/api/s/$token/selection/${ids[2]}', json: {});
      expect(res.status, 409, reason: 'maksimalno 2 fotografije');
      res = await app.call('PUT', '/api/s/$token/selection/${ids[0]}', json: {'size': 'A0'});
      expect(res.status, 400);

      // Drugi posetilac ima svoj, odvojen izbor
      final firstVisitor = Map.of(app.cookies);
      app.cookies.clear();
      res = await app.call('GET', '/api/s/$token');
      expect(res.json['order']['items'], isEmpty);
      app.cookies
        ..clear()
        ..addAll(firstVisitor);

      // 5. Slanje izbora
      res = await app.call('POST', '/api/s/$token/submit', json: {'name': ''});
      expect(res.status, 400);
      res = await app.call('POST', '/api/s/$token/submit', json: {'name': 'Ana Petrović', 'phone': '+381 64 123 4567', 'note': 'Hvala!'});
      expect(res.status, 200, reason: res.text);
      expect(res.json['status'], 'submitted');
      res = await app.call('PUT', '/api/s/$token/selection/${ids[0]}', json: {'quantity': 2});
      expect(res.status, 409, reason: 'poslat izbor je zaključan');
      res = await app.call('POST', '/api/s/$token/reopen');
      expect(res.json['status'], 'draft');
      res = await app.call('POST', '/api/s/$token/submit', json: {'name': 'Ana Petrović'});
      expect(res.json['status'], 'submitted');

      // 6. Administrator vidi porudžbinu
      app.cookies.removeWhere((k, _) => k.contains('fv'));
      await app.loginAsAdmin();
      res = await app.call('GET', '/api/admin/overview');
      expect(res.json['stats']['newOrders'], 1);
      res = await app.call('GET', '/api/admin/orders');
      final orders = res.json as List;
      expect(orders, hasLength(1));
      expect(orders.first['name'], 'Ana Petrović');
      expect(orders.first['copies'], 4);
      final orderId = orders.first['id'] as String;

      // Klijent vidi žig i smanjenu rezoluciju; administrator čistu sliku
      final adminPreview = (await app.call('GET', '/api/admin/photos/${ids[0]}/preview')).body;
      expect(adminPreview, isNot(equals(clientPreview)));
      final decoded = img.decodeJpg(clientPreview)!;
      expect(decoded.width, lessThanOrEqualTo(previewLongEdge));

      // 7. Link za štampariju
      res = await app.call('POST', '/api/admin/print-links', json: {'orderIds': [orderId], 'days': 7});
      expect(res.status, 201, reason: res.text);
      final printUrl = res.json['url'] as String;
      expect(res.json['mail']['body'], contains(printUrl));
      expect(res.json['mail']['body'], contains('20x30 — Mat: 3 kom'));
      final printToken = printUrl.split('/stampa/').last;
      res = await app.call('GET', '/api/admin/orders/$orderId');
      expect(res.json['status'], 'printing');

      // Klijent sada ne može da menja izbor
      app.cookies.addAll(firstVisitor);
      res = await app.call('POST', '/api/s/$token/reopen');
      expect(res.status, 409);

      // 8. Štamparija bez naloga
      app.cookies.clear();
      res = await app.call('GET', '/api/print/$printToken');
      expect(res.status, 200);
      expect(res.json['totalCopies'], 4);
      expect(res.json['groups'], hasLength(2));
      res = await app.call('GET', '/api/print/$printToken/photos/${ids[1]}/original');
      expect(res.status, 200);
      expect(res.headers['content-disposition'], contains('IMG_0001.jpg'));
      res = await app.call('GET', '/api/print/$printToken/photos/${ids[2]}/original');
      expect(res.status, 404, reason: 'fotografija koja nije u porudžbini nije dostupna');

      res = await app.call('GET', '/api/print/$printToken/zip');
      expect(res.status, 200);
      final zipFile = File('${app.tmp.path}/test.zip')..writeAsBytesSync(res.body);
      final check = await Process.run('python3', [
        '-c',
        'import sys,zipfile;z=zipfile.ZipFile(sys.argv[1]);assert z.testzip() is None;print("\\n".join(z.namelist()))',
        zipFile.path,
      ]);
      expect(check.exitCode, 0, reason: check.stderr.toString());
      final names = check.stdout.toString().trim().split('\n');
      expect(names, contains('SPISAK.txt'));
      expect(names, contains('13x18 Sjajni/1x_Ana Petrović_IMG_0000.jpg'));
      expect(names, contains('20x30 Mat/3x_Ana Petrović_IMG_0001.jpg'));

      // 9. Opoziv linka
      await app.loginAsAdmin();
      final links = (await app.call('GET', '/api/admin/print-links')).json as List;
      await app.call('POST', '/api/admin/print-links/${links.first['id']}/revoke');
      app.cookies.clear();
      expect((await app.call('GET', '/api/print/$printToken')).status, 410);

      // 10. Novi link projekta poništava stari
      await app.loginAsAdmin();
      res = await app.call('POST', '/api/admin/projects/$projectId/rotate-link');
      expect(res.json['shareUrl'], isNot(shareUrl));
      expect((await app.call('GET', '/api/s/$token')).status, 404);

      // 11. Skriven projekat nije dostupan ni preko novog linka
      final newToken = (res.json['shareUrl'] as String).split('/g/').last;
      await app.call('PATCH', '/api/admin/projects/$projectId', json: {'status': 'hidden'});
      expect((await app.call('GET', '/api/s/$newToken')).status, 404);

      // 12. Brisanje fotografije ide u Kantu na Drive-u
      res = await app.call('POST', '/api/admin/projects/$projectId/photos/delete', json: {'ids': [ids[2]]});
      expect(res.status, 200);
      expect(app.drive.trashed, hasLength(1));
    });

    test('zatvoren projekat i istekao rok ne dozvoljavaju izbor', () async {
      await app.loginAsAdmin();
      var res = await app.call('POST', '/api/admin/projects', json: {
        'title': 'Krštenje',
        'deadline': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      });
      final id = res.json['id'] as String;
      final token = (res.json['shareUrl'] as String).split('/g/').last;
      res = await app.call('POST', '/api/admin/projects/$id/photos?name=a.jpg', bytes: testJpeg());
      final photoId = res.json['id'];
      res = await app.call('GET', '/api/s/$token');
      expect(res.json['project']['canSelect'], false);
      res = await app.call('PUT', '/api/s/$token/selection/$photoId', json: {});
      expect(res.status, 409);
    });
  });

  group('statički fajlovi', () {
    test('nema izlaska iz web foldera', () async {
      Directory('${app.tmp.path}/web').createSync();
      File('${app.tmp.path}/web/index.html').writeAsStringSync('<html>app</html>');
      File('${app.tmp.path}/tajna.txt').writeAsStringSync('TAJNA');
      for (final path in ['/../tajna.txt', '/%2e%2e/tajna.txt', '/.env', '/g/nesto']) {
        final res = await app.call('GET', path);
        expect(res.text, isNot(contains('TAJNA')), reason: path);
      }
      final res = await app.call('GET', '/g/bilo-sta');
      expect(res.text, contains('app'));
    });
  });

  test('ZIP CRC32', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });
}
