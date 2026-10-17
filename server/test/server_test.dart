import 'dart:convert';
import 'dart:io';

import 'package:fotograf_server/fotograf_server.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeGoogle google;
  late TestApp app;

  setUpAll(() => google = FakeGoogle());
  setUp(() async => app = await TestApp.create(google));
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

    test('prijava: pogrešna lozinka ili mejl se odbijaju, ispravni prolaze', () async {
      final email = TestApp.adminEmail;
      expect((await app.login(email, 'pogresna-lozinka')).status, 401);
      expect((await app.login('napadac@gmail.com', TestApp.adminPassword)).status, 401);
      expect((await app.call('GET', '/api/auth/me')).status, 401);
      final ok = await app.login(email.toUpperCase(), TestApp.adminPassword);
      expect(ok.status, 200, reason: 'mejl nije osetljiv na velika slova');
      final me = await app.call('GET', '/api/auth/me');
      expect(me.json['admin'], isTrue);
      expect(me.text, isNot(contains(email)), reason: 'mejl administratora se nikad ne šalje pregledaču');
      for (final path in ['/api/admin/settings', '/api/admin/overview']) {
        expect((await app.call('GET', path)).text, isNot(contains(email)), reason: path);
      }
      final cookie = app.cookies.entries.firstWhere((e) => e.key.contains('fa'));
      expect(cookie.value.length, greaterThan(40));
    });

    test('posle 5 pogrešnih lozinki prijava se privremeno zaključava', () async {
      final email = TestApp.adminEmail;
      for (var i = 0; i < 5; i++) {
        expect((await app.login(email, 'pogresno-$i')).status, 401);
      }
      final locked = await app.login(email, TestApp.adminPassword);
      expect(locked.status, 429);
      expect(locked.json['code'], 'locked');
      // Kada zaključavanje istekne, ispravna lozinka ponovo radi.
      app.services.db.setSetting('login_locked_until', '0');
      expect((await app.login(email, TestApp.adminPassword)).status, 200);
    });

    test('lozinka se čuva samo kao jak heš', () async {
      final stored = app.services.db.setting('admin_password_hash')!;
      expect(stored, startsWith('pbkdf2-sha256\$310000\$'));
      expect(stored, isNot(contains(TestApp.adminPassword)));
      final dbFile = app.services.db.query('SELECT value FROM settings').map((r) => r['value']).join(' ');
      expect(dbFile, isNot(contains(TestApp.adminPassword)));
    });

    test('promena lozinke iz podešavanja', () async {
      await app.loginAsAdmin();
      var res = await app.call('POST', '/api/admin/password', json: {'current': 'netacno', 'next': 'NovaLozinka-123'});
      expect(res.status, 400);
      res = await app.call('POST', '/api/admin/password', json: {'current': TestApp.adminPassword, 'next': 'kratka'});
      expect(res.status, 400);
      res = await app.call(
        'POST',
        '/api/admin/password',
        json: {'current': TestApp.adminPassword, 'next': 'NovaLozinka-123'},
      );
      expect(res.status, 200, reason: res.text);
      expect((await app.call('GET', '/api/auth/me')).status, 200, reason: 'ova sesija ostaje prijavljena');
      app.cookies.clear();
      expect((await app.login(TestApp.adminEmail, TestApp.adminPassword)).status, 401);
      expect((await app.login(TestApp.adminEmail, 'NovaLozinka-123')).status, 200);
    });

    test('bez ADMIN_EMAIL u bazi prijava nije moguća', () async {
      app.services.db.setSetting('admin_email', null);
      final res = await app.login(TestApp.adminEmail, TestApp.adminPassword);
      expect(res.status, 503);
      expect(res.json['code'], 'no_account');
    });

    test('promena ADMIN_PASSWORD na serveru resetuje lozinku', () async {
      await app.services.setAdminPassword('Zaboravljena-123');
      app.services.db.setSetting('admin_password_env_fp', 'stara-vrednost');
      await app.services.initAdminAccount();
      expect((await app.login(TestApp.adminEmail, TestApp.adminPassword)).status, 200);
    });

    test('Google ID token se proverava kriptografski (povezivanje Drive-a)', () async {
      final v = GoogleIdTokenVerifier(clientId: TestApp.clientId, client: google.client());
      final email = TestApp.adminEmail;
      final id = await v.verify(google.sign(app.idPayload(email: email)));
      expect(id.email, email);
      expect(id.emailVerified, isTrue);
      await expectLater(
        v.verify(google.sign(app.idPayload(email: email, aud: 'drugi'))),
        throwsA(isA<IdTokenException>()),
      );
      await expectLater(
        v.verify(google.sign(app.idPayload(email: email, exp: 1000))),
        throwsA(isA<IdTokenException>()),
      );
      final parts = google.sign(app.idPayload(email: 'x@gmail.com')).split('.');
      final forged = '${parts[0]}.${b64url(utf8.encode(jsonEncode(app.idPayload(email: email))))}.${parts[2]}';
      await expectLater(v.verify(forged), throwsA(isA<IdTokenException>()));
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
      res = await app.call('PUT', '/api/s/$token/selection/${ids[1]}', json: {'quantity': 3});
      expect(res.status, 200);
      res = await app.call('PUT', '/api/s/$token/selection/${ids[2]}', json: {});
      expect(res.status, 409, reason: 'maksimalno 2 fotografije');
      res = await app.call('PUT', '/api/s/$token/selection/${ids[0]}', json: {'quantity': 0});
      expect(res.status, 400, reason: 'količina mora biti 1-99');
      res = await app.call('GET', '/api/s/$token');
      expect(res.json['project']['printSize'], '13x18');
      expect((res.json['order']['items'] as List).map((i) => i['quantity']), [1, 3]);

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
      expect(res.json['mail']['body'], contains('Format: 13x18 cm'));
      expect(res.json['mail']['body'], contains('Ukupno: 4 kom'));
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
      expect(res.json['printSize'], '13x18');
      expect(res.json['photoCount'], 2);
      expect(res.json['totalBytes'], greaterThan(0));
      expect(res.json['customers'], hasLength(1));
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
      expect(names, contains('1x_IMG_0000.jpg'));
      expect(names, contains('3x_IMG_0001.jpg'));

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

  group('otpornost', () {
    test('uklanjanje bez postojećeg izbora ne pravi praznu porudžbinu', () async {
      await app.loginAsAdmin();
      var res = await app.call('POST', '/api/admin/projects', json: {'title': 'Test'});
      final id = res.json['id'] as String;
      final token = (res.json['shareUrl'] as String).split('/g/').last;
      res = await app.call('POST', '/api/admin/projects/$id/photos?name=a.jpg', bytes: testJpeg());
      final photoId = res.json['id'];
      app.cookies.clear();
      res = await app.call('DELETE', '/api/s/$token/selection/$photoId');
      expect(res.status, 200);
      expect(app.cookies.keys.where((k) => k.contains('fv')), isEmpty);
      expect(app.services.db.scalar('SELECT COUNT(*) FROM orders'), 0);
      expect(app.services.db.scalar('SELECT COUNT(*) FROM visitors'), 0);
    });

    test('otpremanje bez povezanog Drive-a daje jasnu poruku', () async {
      await app.loginAsAdmin();
      final res0 = await app.call('POST', '/api/admin/projects', json: {'title': 'Bez Drive-a'});
      app.drive.isConnected = false;
      final res = await app.call('POST', '/api/admin/projects/${res0.json['id']}/photos?name=a.jpg', bytes: testJpeg());
      expect(res.status, 503);
      expect(res.json['code'], 'drive_not_connected');
    });

    test('Google greške se pretvaraju u razumljive poruke', () {
      final full = DriveStore.driveError(gdrive.DetailedApiRequestError(403, "The user's Drive storage quota has been exceeded."));
      expect(full.status, 507);
      expect(full.message, contains('pun'));
      final disabled = DriveStore.driveError(gdrive.DetailedApiRequestError(403, 'Drive API has not been used in project'));
      expect(disabled.code, 'drive_api_disabled');
      expect(DriveStore.driveError(gdrive.DetailedApiRequestError(500, 'x')).status, 502);
    });

    test('keš se čisti kada pređe granicu, a brisanje fotografija je u jednom prolazu', () async {
      final cache = app.services.cache;
      for (var i = 0; i < 10; i++) {
        File('${cache.dir}/p${i}_t_clean.jpg').writeAsBytesSync(List.filled(1000, 1));
      }
      await cache.trim(5000);
      final left = Directory(cache.dir).listSync().length;
      expect(left, lessThanOrEqualTo(4));
      cache.deletePhotos(['p9', 'p8', 'p7', 'p6', 'p5', 'p4', 'p3', 'p2', 'p1', 'p0']);
      expect(Directory(cache.dir).listSync(), isEmpty);
    });

    test('web fajlovi se uvek proveravaju (nema mešanja verzija posle deploy-a)', () async {
      Directory('${app.tmp.path}/web').createSync();
      File('${app.tmp.path}/web/index.html').writeAsStringSync('<html>app</html>');
      File('${app.tmp.path}/web/main.dart.js').writeAsStringSync('// js');
      final res = await app.call('GET', '/main.dart.js');
      expect(res.headers['cache-control'], 'no-cache');
    });
  });

  test('ADMIN_PASSWORD_B64 prenosi i specijalne znakove', () {
    final dir = Directory.systemTemp.createTempSync('fotograf-cfg');
    addTearDown(() => dir.deleteSync(recursive: true));
    const pw =
        r'a$b#c"d'
        "'"
        r'e \ š';
    final c = Config.fromEnvironment({'DATA_DIR': dir.path, 'ADMIN_PASSWORD_B64': base64.encode(utf8.encode(pw))});
    expect(c.adminPassword, pw);
    expect(
      () => Config.fromEnvironment({'DATA_DIR': dir.path, 'ADMIN_PASSWORD': 'kratka'}),
      throwsA(isA<StateError>()),
    );
  });

  test('ZIP CRC32', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });
}
