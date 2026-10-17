import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../crypto_util.dart';
import '../db.dart';
import '../http_util.dart';
import '../media.dart';
import '../services.dart';

final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{20,64}$');

/// Rute za klijente. Pristup ima ISKLJUČIVO onaj ko zna tajni link projekta
/// (192-bitni nasumični token). Token jednog projekta ne otvara nijedan drugi.
void mountClientRoutes(Router r, Services s) {
  Row project(Request req, String token) {
    if (!_tokenPattern.hasMatch(token)) {
      s.rateLimit(req, 'share-miss', 30, const Duration(minutes: 10));
      throw ApiError.notFound('Link nije ispravan ili je istekao.');
    }
    final row = s.db.one(
      "SELECT * FROM projects WHERE share_token_hash = ? AND status != 'hidden'",
      [sha256Hex(token)],
    );
    if (row == null) {
      s.rateLimit(req, 'share-miss', 30, const Duration(minutes: 10));
      throw ApiError.notFound('Link nije ispravan ili je istekao.');
    }
    return row;
  }

  bool canSelect(Row p) {
    if (p['status'] != 'open') return false;
    final deadline = p['deadline'] as int?;
    return deadline == null || nowMs() <= deadline;
  }

  Row? orderFor(Row p, String? visitorId) => visitorId == null
      ? null
      : s.db.one('SELECT * FROM orders WHERE project_id = ? AND visitor_id = ?', [p['id'], visitorId]);

  Map<String, Object?> orderJson(Row? o) {
    if (o == null) return {'status': 'draft', 'name': '', 'phone': '', 'note': '', 'items': []};
    final items = s.db.query(
      'SELECT photo_id, quantity FROM order_items WHERE order_id = ? ORDER BY created_at',
      [o['id']],
    );
    return {
      'status': o['status'],
      'name': o['name'],
      'phone': o['phone'],
      'note': o['note'],
      'submittedAt': o['submitted_at'],
      'items': [
        for (final i in items)
          {'photoId': i['photo_id'], 'quantity': i['quantity']},
      ],
    };
  }

  Response withVisitorCookie(Response res, String? cookie) =>
      cookie == null ? res : res.change(headers: {HttpHeaders.setCookieHeader: cookie});

  /// Vraća porudžbinu u izradi; pravi posetioca i porudžbinu ako ne postoje.
  ({Row order, String? cookie}) editableOrder(Request req, Row p) {
    if (!canSelect(p)) throw ApiError.conflict('Izbor fotografija za ovaj projekat je zatvoren.');
    var visitor = s.visitorId(req);
    String? cookie;
    if (visitor == null) {
      // Gosti na istom WiFi-ju dele IP adresu — limit je velikodušan.
      s.rateLimit(req, 'visitor-new', 300, const Duration(hours: 1));
      final v = s.createVisitor();
      visitor = v.id;
      cookie = v.cookie;
    }
    var order = orderFor(p, visitor);
    if (order == null) {
      final now = nowMs();
      final id = randomId();
      s.db.exec(
        'INSERT INTO orders(id, project_id, visitor_id, status, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?)',
        [id, p['id'], visitor, 'draft', now, now],
      );
      order = s.db.one('SELECT * FROM orders WHERE id = ?', [id])!;
    }
    if (order['status'] != 'draft') {
      throw ApiError.conflict('Vaš izbor je već poslat. Pritisnite "Izmeni izbor" da biste ga menjali.');
    }
    return (order: order, cookie: cookie);
  }

  r.get('/api/s/<token>', (Request req, String token) {
    s.rateLimit(req, 'share-view', 600, const Duration(minutes: 1));
    final p = project(req, token);
    final photos = s.db.query(
      'SELECT id, filename, width, height FROM photos WHERE project_id = ? ORDER BY sort_index, created_at',
      [p['id']],
    );
    final order = orderFor(p, s.visitorId(req));
    return jsonOk({
      'studioName': s.studioName,
      'project': {
        'title': p['title'],
        'clientName': p['client_name'],
        'eventDate': p['event_date'],
        'message': p['message'],
        'status': p['status'],
        'canSelect': canSelect(p),
        'maxPhotos': p['max_photos'],
        'deadline': p['deadline'],
        'printSize': s.printSize,
        'coverPhotoId': p['cover_photo_id'],
      },
      'photos': [
        for (final ph in photos) {'id': ph['id'], 'name': ph['filename'], 'w': ph['width'], 'h': ph['height']},
      ],
      'order': orderJson(order),
    });
  });

  Future<Response> media(Request req, String token, String photoId, MediaKind kind) async {
    s.rateLimit(req, 'share-media', 12000, const Duration(minutes: 1));
    requireAppImageRequest(req);
    final p = project(req, token);
    final photo = s.db.one('SELECT * FROM photos WHERE id = ? AND project_id = ?', [photoId, p['id']]);
    if (photo == null) throw ApiError.notFound();
    // Klijenti uvek dobijaju sliku sa žigom i u smanjenoj rezoluciji.
    return serveDerivative(s, req, photo, kind, watermark: true);
  }

  r.get('/api/s/<token>/photos/<id>/thumb', (Request req, String token, String id) => media(req, token, id, MediaKind.thumb));
  r.get('/api/s/<token>/photos/<id>/preview', (Request req, String token, String id) => media(req, token, id, MediaKind.preview));

  r.put('/api/s/<token>/selection/<photoId>', (Request req, String token, String photoId) async {
    s.rateLimit(req, 'share-write', 2000, const Duration(minutes: 1));
    final p = project(req, token);
    final body = await readJson(req);
    final photo = s.db.one('SELECT id FROM photos WHERE id = ? AND project_id = ?', [photoId, p['id']]);
    if (photo == null) throw ApiError.notFound('Fotografija ne postoji.');

    // Format je fiksan za sve; klijent bira samo broj primeraka.
    final quantity = intField(body, 'quantity', min: 1, max: 99);

    final (:order, :cookie) = editableOrder(req, p);
    s.db.tx(() {
      final existing = s.db.one('SELECT * FROM order_items WHERE order_id = ? AND photo_id = ?', [order['id'], photoId]);
      if (existing == null) {
        final max = p['max_photos'] as int?;
        final count = s.db.scalar('SELECT COUNT(*) FROM order_items WHERE order_id = ?', [order['id']]) as int;
        if (max != null && count >= max) {
          throw ApiError.conflict('Možete izabrati najviše $max fotografija.');
        }
        s.db.exec(
          'INSERT INTO order_items(order_id, photo_id, quantity, created_at) VALUES(?, ?, ?, ?)',
          [order['id'], photoId, quantity ?? 1, nowMs()],
        );
      } else if (quantity != null) {
        s.db.exec('UPDATE order_items SET quantity = ? WHERE order_id = ? AND photo_id = ?', [quantity, order['id'], photoId]);
      }
      s.db.exec('UPDATE orders SET updated_at = ? WHERE id = ?', [nowMs(), order['id']]);
    });
    return withVisitorCookie(jsonOk(orderJson(s.db.one('SELECT * FROM orders WHERE id = ?', [order['id']]))), cookie);
  });

  r.delete('/api/s/<token>/selection/<photoId>', (Request req, String token, String photoId) {
    s.rateLimit(req, 'share-write', 2000, const Duration(minutes: 1));
    final p = project(req, token);
    // Bez postojeće porudžbine nema šta da se ukloni — ne pravimo praznu.
    if (orderFor(p, s.visitorId(req)) == null) return jsonOk(orderJson(null));
    final (:order, :cookie) = editableOrder(req, p);
    s.db.exec('DELETE FROM order_items WHERE order_id = ? AND photo_id = ?', [order['id'], photoId]);
    s.db.exec('UPDATE orders SET updated_at = ? WHERE id = ?', [nowMs(), order['id']]);
    return withVisitorCookie(jsonOk(orderJson(s.db.one('SELECT * FROM orders WHERE id = ?', [order['id']]))), cookie);
  });

  r.post('/api/s/<token>/submit', (Request req, String token) async {
    s.rateLimit(req, 'share-submit', 120, const Duration(minutes: 10));
    final p = project(req, token);
    final body = await readJson(req);
    final name = str(body, 'name', max: 80, required: true)!;
    final phone = str(body, 'phone', max: 40) ?? '';
    final note = str(body, 'note', max: 2000) ?? '';
    if (phone.isNotEmpty && !RegExp(r'^[0-9+()/ .-]{5,40}$').hasMatch(phone)) {
      throw ApiError.badRequest('Broj telefona nije ispravan.');
    }
    final (:order, :cookie) = editableOrder(req, p);
    final count = s.db.scalar('SELECT COUNT(*) FROM order_items WHERE order_id = ?', [order['id']]) as int;
    if (count == 0) throw ApiError.badRequest('Niste izabrali nijednu fotografiju.');
    final now = nowMs();
    s.db.exec(
      "UPDATE orders SET status = 'submitted', name = ?, phone = ?, note = ?, submitted_at = ?, updated_at = ? WHERE id = ?",
      [name, phone, note, now, now, order['id']],
    );
    s.db.audit('order_submitted', detail: '${p['title']} · $name · ${photosLabel(count)}', ip: s.ip(req));
    return withVisitorCookie(jsonOk(orderJson(s.db.one('SELECT * FROM orders WHERE id = ?', [order['id']]))), cookie);
  });

  r.post('/api/s/<token>/reopen', (Request req, String token) {
    s.rateLimit(req, 'share-write', 2000, const Duration(minutes: 1));
    final p = project(req, token);
    if (!canSelect(p)) throw ApiError.conflict('Izbor fotografija za ovaj projekat je zatvoren.');
    final order = orderFor(p, s.visitorId(req));
    if (order == null) throw ApiError.notFound();
    if (order['status'] == 'submitted') {
      s.db.exec("UPDATE orders SET status = 'draft', updated_at = ? WHERE id = ?", [nowMs(), order['id']]);
    } else if (order['status'] != 'draft') {
      throw ApiError.conflict('Fotograf je već poslao vaše fotografije na štampu, pa izbor više ne može da se menja.');
    }
    return jsonOk(orderJson(s.db.one('SELECT * FROM orders WHERE id = ?', [order['id']])));
  });
}
