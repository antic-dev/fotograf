import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../crypto_util.dart';
import '../db.dart';
import '../drive.dart';
import '../http_util.dart';
import '../images.dart';
import '../media.dart';
import '../services.dart';
import 'print_routes.dart';

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Administratorske rute. Middleware u app.dart garantuje da je svaki zahtev
/// na /api/admin/* od prijavljenog administratora (osim Google povratnog poziva).
void mountAdminRoutes(Router r, Services s) {
  final db = s.db;

  // ---------------------------------------------------------------------------
  // Pomoćne funkcije
  // ---------------------------------------------------------------------------

  Row projectRow(String id) {
    final p = db.one('SELECT * FROM projects WHERE id = ?', [id]);
    if (p == null) throw ApiError.notFound('Projekat ne postoji.');
    return p;
  }

  Map<String, Object?> projectJson(Row p) {
    final id = p['id'];
    final folder = p['drive_folder_id'] as String?;
    return {
      'id': id,
      'title': p['title'],
      'clientName': p['client_name'],
      'eventDate': p['event_date'],
      'message': p['message'],
      'status': p['status'],
      'maxPhotos': p['max_photos'],
      'deadline': p['deadline'],
      'coverPhotoId': p['cover_photo_id'],
      'driveFolderUrl': folder == null ? null : 'https://drive.google.com/drive/folders/$folder',
      'shareUrl': s.shareUrl(s.decryptOrNull(p['share_token_enc'] as String) ?? ''),
      'createdAt': p['created_at'],
      'updatedAt': p['updated_at'],
      'photoCount': db.scalar('SELECT COUNT(*) FROM photos WHERE project_id = ?', [id]),
      'newOrders': db.scalar("SELECT COUNT(*) FROM orders WHERE project_id = ? AND status = 'submitted'", [id]),
      'totalOrders': db.scalar("SELECT COUNT(*) FROM orders WHERE project_id = ? AND status != 'draft'", [id]),
      'activeDrafts': db.scalar(
        "SELECT COUNT(*) FROM orders o WHERE o.project_id = ? AND o.status = 'draft' AND EXISTS(SELECT 1 FROM order_items WHERE order_id = o.id)",
        [id],
      ),
    };
  }

  Map<String, Object?> photoJson(Row ph) => {
        'id': ph['id'],
        'name': ph['filename'],
        'w': ph['width'],
        'h': ph['height'],
        'size': ph['size_bytes'],
        'takenAt': ph['taken_at'],
        'selectedBy': db.scalar(
          "SELECT COUNT(*) FROM order_items i JOIN orders o ON o.id = i.order_id WHERE i.photo_id = ? AND o.status != 'draft'",
          [ph['id']],
        ),
      };

  Map<String, Object?> orderSummary(Row o) {
    final agg = db.one(
      'SELECT COUNT(*) AS n, COALESCE(SUM(quantity), 0) AS copies FROM order_items WHERE order_id = ?',
      [o['id']],
    )!;
    final preview = db.query('SELECT photo_id FROM order_items WHERE order_id = ? ORDER BY created_at LIMIT 4', [o['id']]);
    return {
      'id': o['id'],
      'projectId': o['project_id'],
      'projectTitle': o['project_title'],
      'status': o['status'],
      'name': o['name'],
      'phone': o['phone'],
      'note': o['note'],
      'createdAt': o['created_at'],
      'updatedAt': o['updated_at'],
      'submittedAt': o['submitted_at'],
      'photoCount': agg['n'],
      'copies': agg['copies'],
      'previewPhotoIds': [for (final p in preview) p['photo_id']],
    };
  }

  void applyProjectFields(Map<String, dynamic> b, Map<String, Object?> out, {required bool creating}) {
    final title = str(b, 'title', max: 120, required: creating);
    if (title != null) out['title'] = title;
    if (b.containsKey('clientName')) out['client_name'] = str(b, 'clientName', max: 120) ?? '';
    if (b.containsKey('message')) out['message'] = str(b, 'message', max: 2000) ?? '';
    if (b.containsKey('eventDate')) {
      final d = str(b, 'eventDate', max: 10);
      if (d != null && !_datePattern.hasMatch(d)) throw ApiError.badRequest('Datum nije ispravan.');
      out['event_date'] = d;
    }
    if (b.containsKey('status')) {
      final st = str(b, 'status', max: 10, required: true);
      if (!const ['open', 'closed', 'hidden'].contains(st)) throw ApiError.badRequest('Nepoznat status.');
      out['status'] = st;
    }
    if (b.containsKey('maxPhotos')) out['max_photos'] = intField(b, 'maxPhotos', min: 1, max: 100000);
    if (b.containsKey('deadline')) out['deadline'] = intField(b, 'deadline', min: 0, max: 1 << 50);
  }

  /// Premešta u Kantu na Drive-u "koliko može": i ako Drive trenutno ne
  /// odgovara, brisanje iz aplikacije uspeva (fajl tada ostaje na Drive-u).
  Future<void> trashQuietly(String driveId) async {
    try {
      await s.drive.trash(driveId);
    } catch (e) {
      stderr.writeln('Drive trash nije uspeo za $driveId: $e');
    }
  }

  Future<void> deletePhotos(Row project, List<String> ids) async {
    final deleted = <String>[];
    for (final id in ids) {
      final ph = db.one('SELECT * FROM photos WHERE id = ? AND project_id = ?', [id, project['id']]);
      if (ph == null) continue;
      await trashQuietly(ph['drive_file_id'] as String);
      db.exec('DELETE FROM photos WHERE id = ?', [id]);
      deleted.add(id);
    }
    s.cache.deletePhotos(deleted);
    final cover = db.scalar('SELECT cover_photo_id FROM projects WHERE id = ?', [project['id']]);
    if (cover != null && ids.contains(cover)) {
      final next = db.scalar('SELECT id FROM photos WHERE project_id = ? ORDER BY sort_index LIMIT 1', [project['id']]);
      db.exec('UPDATE projects SET cover_photo_id = ? WHERE id = ?', [next, project['id']]);
    }
    db.exec('UPDATE projects SET updated_at = ? WHERE id = ?', [nowMs(), project['id']]);
  }

  // ---------------------------------------------------------------------------
  // Pregled i podešavanja
  // ---------------------------------------------------------------------------

  r.get('/api/admin/overview', (Request req) async {
    Map<String, Object?>? quota;
    if (s.drive.connected) {
      try {
        quota = await s.drive.quota();
      } catch (_) {}
    }
    final recent = db.query(
      "SELECT o.*, p.title AS project_title FROM orders o JOIN projects p ON p.id = o.project_id WHERE o.status = 'submitted' ORDER BY o.submitted_at DESC LIMIT 6",
    );
    return jsonOk({
      'studioName': s.studioName,
      'drive': {'connected': s.drive.connected, 'quota': quota},
      'stats': {
        'projects': db.scalar('SELECT COUNT(*) FROM projects'),
        'photos': db.scalar('SELECT COUNT(*) FROM photos'),
        'newOrders': db.scalar("SELECT COUNT(*) FROM orders WHERE status = 'submitted'"),
        'printing': db.scalar("SELECT COUNT(*) FROM orders WHERE status = 'printing'"),
        'drafts': db.scalar(
          "SELECT COUNT(*) FROM orders o WHERE o.status = 'draft' AND EXISTS(SELECT 1 FROM order_items WHERE order_id = o.id)",
        ),
      },
      'recentOrders': [for (final o in recent) orderSummary(o)],
    });
  });

  r.get('/api/admin/settings', (Request req) {
    return jsonOk({
      'studioName': s.studioName,
      'watermarkText': s.watermarkText,
      'printerEmail': s.printerEmail,
      'printSize': s.printSize,
      'smtpEnabled': s.mailer.enabled,
      'drive': {'connected': s.drive.connected, 'configured': s.config.googleConfigured},
      'activeSessions': db.scalar('SELECT COUNT(*) FROM admin_sessions WHERE expires_at > ?', [nowMs()]),
    });
  });

  r.put('/api/admin/settings', (Request req) async {
    final b = await readJson(req);
    if (b.containsKey('studioName')) {
      db.setSetting('studio_name', str(b, 'studioName', max: 80, required: true));
    }
    if (b.containsKey('watermarkText')) {
      final before = s.watermarkText;
      db.setSetting('watermark_text', str(b, 'watermarkText', max: 40) ?? '');
      if (before != s.watermarkText) {
        // Slike sa starim žigom više nisu potrebne; nove se prave po potrebi.
        for (final f in Directory(s.cache.dir).listSync()) {
          if (!f.path.contains('_clean')) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
    }
    if (b.containsKey('printerEmail')) {
      final e = str(b, 'printerEmail', max: 200) ?? '';
      if (e.isNotEmpty && !_emailPattern.hasMatch(e)) throw ApiError.badRequest('Mejl štamparije nije ispravan.');
      db.setSetting('printer_email', e);
    }
    if (b.containsKey('printSize')) {
      final size = str(b, 'printSize', max: 20) ?? '';
      if (size.isNotEmpty && !RegExp(r'^\d{1,3}\s*[xX×]\s*\d{1,3}$').hasMatch(size)) {
        throw ApiError.badRequest('Format štampe upišite kao npr. 13x18.');
      }
      db.setSetting('print_size', size.replaceAll(RegExp(r'\s'), '').replaceAll(RegExp('[X×]'), 'x'));
    }
    db.audit('settings_updated', ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/sessions/revoke-all', (Request req) {
    db.exec('DELETE FROM admin_sessions');
    db.audit('sessions_revoked', ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.get('/api/admin/audit', (Request req) {
    final rows = db.query('SELECT ts, action, detail, ip FROM audit ORDER BY id DESC LIMIT 200');
    return jsonOk(rows);
  });

  // ---------------------------------------------------------------------------
  // Google Drive povezivanje
  // ---------------------------------------------------------------------------

  r.get('/api/admin/drive/connect', (Request req) {
    if (!s.config.googleConfigured) {
      return Response.found(
        '/admin/podesavanja?drive=greska&poruka=${Uri.encodeQueryComponent('Google podaci nisu podešeni na serveru (GOOGLE_CLIENT_ID i GOOGLE_CLIENT_SECRET). Vidi README.')}',
      );
    }
    final now = nowMs();
    s.oauthPending.removeWhere((_, v) => v.expires < now);
    final state = randomToken(24);
    final verifier = randomToken(48);
    s.oauthPending[state] = (verifier: verifier, expires: now + 10 * 60 * 1000);
    return Response.found(
      s.drive.authorizationUrl(state: state, codeVerifier: verifier).toString(),
      headers: {
        // Lax: kolačić mora da preživi povratak sa accounts.google.com
        HttpHeaders.setCookieHeader: buildCookie(
          s.oauthCookie,
          sha256Hex(state),
          secure: s.config.cookieSecure,
          maxAge: const Duration(minutes: 10),
          sameSite: 'Lax',
        ),
        HttpHeaders.cacheControlHeader: 'no-store',
      },
    );
  });

  r.get('/api/admin/drive/callback', (Request req) async {
    s.rateLimit(req, 'drive-callback', 10, const Duration(minutes: 10));
    final q = req.url.queryParameters;
    final state = q['state'] ?? '';
    final cookie = parseCookies(req)[s.oauthCookie];
    final pending = s.oauthPending.remove(state);
    String target;
    if (q['error'] != null) {
      target = '/admin/podesavanja?drive=otkazano';
    } else if (pending == null ||
        pending.expires < nowMs() ||
        cookie == null ||
        !constantTimeEquals(cookie, sha256Hex(state))) {
      target = '/admin/podesavanja?drive=greska';
    } else {
      try {
        await s.drive.completeAuthorization(code: q['code'] ?? '', codeVerifier: pending.verifier, verifier: s.idVerifier);
        await s.drive.rootFolderId();
        db.audit('drive_connected', ip: s.ip(req));
        target = '/admin/podesavanja?drive=povezan';
      } on ApiError catch (e) {
        db.audit('drive_connect_failed', detail: e.message, ip: s.ip(req));
        target = '/admin/podesavanja?drive=greska&poruka=${Uri.encodeQueryComponent(e.message)}';
      } catch (e) {
        db.audit('drive_connect_failed', detail: '$e', ip: s.ip(req));
        target = '/admin/podesavanja?drive=greska';
      }
    }
    return Response.found(target, headers: {
      HttpHeaders.setCookieHeader: clearCookie(s.oauthCookie, secure: s.config.cookieSecure, sameSite: 'Lax'),
      HttpHeaders.cacheControlHeader: 'no-store',
    });
  });

  r.post('/api/admin/drive/disconnect', (Request req) async {
    await s.drive.disconnect();
    db.audit('drive_disconnected', ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  // ---------------------------------------------------------------------------
  // Projekti
  // ---------------------------------------------------------------------------

  r.get('/api/admin/projects', (Request req) {
    final rows = db.query('SELECT * FROM projects ORDER BY COALESCE(event_date, \'\') DESC, created_at DESC');
    return jsonOk([for (final p in rows) projectJson(p)]);
  });

  r.post('/api/admin/projects', (Request req) async {
    final b = await readJson(req);
    final fields = <String, Object?>{};
    applyProjectFields(b, fields, creating: true);
    final id = randomId();
    final token = randomToken(24);
    final now = nowMs();
    fields.addAll({
      'id': id,
      'share_token_hash': sha256Hex(token),
      'share_token_enc': s.box.encrypt(token),
      'created_at': now,
      'updated_at': now,
    });
    final cols = fields.keys.toList();
    db.exec(
      'INSERT INTO projects(${cols.join(', ')}) VALUES(${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) fields[c]],
    );
    db.audit('project_created', detail: fields['title'] as String, ip: s.ip(req));
    if (s.drive.connected) {
      try {
        await s.drive.ensureProjectFolder(id);
      } catch (_) {
        // Folder će biti napravljen pri prvom otpremanju.
      }
    }
    return jsonOk(projectJson(projectRow(id)), status: 201);
  });

  r.get('/api/admin/projects/<id>', (Request req, String id) {
    final p = projectRow(id);
    final photos = db.query('SELECT * FROM photos WHERE project_id = ? ORDER BY sort_index, created_at', [id]);
    return jsonOk({...projectJson(p), 'photos': [for (final ph in photos) photoJson(ph)]});
  });

  r.patch('/api/admin/projects/<id>', (Request req, String id) async {
    final before = projectRow(id);
    final b = await readJson(req);
    final fields = <String, Object?>{};
    applyProjectFields(b, fields, creating: false);
    if (fields.isEmpty) return jsonOk(projectJson(before));
    fields['updated_at'] = nowMs();
    final cols = fields.keys.toList();
    db.exec(
      'UPDATE projects SET ${cols.map((c) => '$c = ?').join(', ')} WHERE id = ?',
      [for (final c in cols) fields[c], id],
    );
    final after = projectRow(id);
    final folder = after['drive_folder_id'] as String?;
    if (folder != null && (before['title'] != after['title'] || before['event_date'] != after['event_date'])) {
      try {
        await s.drive.renameFolder(folder, DriveStore.folderName(after['title'] as String, after['event_date'] as String?));
      } catch (_) {}
    }
    db.audit('project_updated', detail: after['title'] as String, ip: s.ip(req));
    return jsonOk(projectJson(after));
  });

  r.delete('/api/admin/projects/<id>', (Request req, String id) async {
    final p = projectRow(id);
    final folder = p['drive_folder_id'] as String?;
    if (folder != null && s.drive.connected) await trashQuietly(folder);
    final photoIds = db.query('SELECT id FROM photos WHERE project_id = ?', [id]).map((r) => r['id'] as String).toList();
    db.exec('DELETE FROM projects WHERE id = ?', [id]);
    s.cache.deletePhotos(photoIds);
    db.audit('project_deleted', detail: p['title'] as String, ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/projects/<id>/rotate-link', (Request req, String id) {
    final p = projectRow(id);
    final token = randomToken(24);
    db.exec(
      'UPDATE projects SET share_token_hash = ?, share_token_enc = ?, updated_at = ? WHERE id = ?',
      [sha256Hex(token), s.box.encrypt(token), nowMs(), id],
    );
    db.audit('project_link_rotated', detail: p['title'] as String, ip: s.ip(req));
    return jsonOk(projectJson(projectRow(id)));
  });

  // ---------------------------------------------------------------------------
  // Fotografije
  // ---------------------------------------------------------------------------

  r.post('/api/admin/projects/<id>/photos', (Request req, String id) async {
    projectRow(id);
    final rawName = req.url.queryParameters['name'] ?? 'fotografija.jpg';
    final filename = safeFilename(rawName);
    final bytes = await readBodyBytes(req, s.config.maxUploadBytes);
    final mime = sniffImageMime(bytes);
    if (mime == null) throw ApiError(415, '"$filename" nije slika.', code: 'bad_image');
    if (mime == 'image/heic') {
      throw ApiError(415, '"$filename" je HEIC. Izvezite ga kao JPEG pa otpremite ponovo.', code: 'bad_image');
    }

    // Pre teške obrade: bez povezanog Drive-a nema gde da se sačuva original.
    if (!s.drive.connected) throw DriveNotConnected();

    final ProcessedImage processed;
    try {
      processed = await processUpload(bytes, watermark: s.watermarkText);
    } catch (e) {
      throw imageError(e);
    }

    final folder = await s.drive.ensureProjectFolder(id);
    final driveId = await s.drive.upload(folderId: folder, filename: filename, mime: mime, bytes: bytes);

    final photoId = randomId();
    final now = nowMs();
    db.tx(() {
      final next = (db.scalar('SELECT COALESCE(MAX(sort_index), -1) + 1 FROM photos WHERE project_id = ?', [id]) as int);
      db.exec(
        '''INSERT INTO photos(id, project_id, filename, drive_file_id, mime, size_bytes, width, height, taken_at, sort_index, created_at)
           VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [photoId, id, filename, driveId, mime, bytes.length, processed.width, processed.height, processed.takenAt, next, now],
      );
      db.exec('UPDATE projects SET cover_photo_id = COALESCE(cover_photo_id, ?), updated_at = ? WHERE id = ?', [photoId, now, id]);
    });
    await s.cache.store(s.cache.thumbPath(photoId, s.watermarkText), processed.thumb);
    await s.cache.store(s.cache.thumbPath(photoId, null), processed.thumbClean);
    await s.cache.store(s.cache.previewPath(photoId, s.watermarkText), processed.preview);
    return jsonOk(photoJson(db.one('SELECT * FROM photos WHERE id = ?', [photoId])!), status: 201);
  });

  r.post('/api/admin/projects/<id>/photos/delete', (Request req, String id) async {
    final p = projectRow(id);
    final b = await readJson(req);
    final ids = stringList(b, 'ids', maxItems: 5000, maxLen: 40) ?? const [];
    await deletePhotos(p, ids);
    db.audit('photos_deleted', detail: '${p['title']} · ${photosLabel(ids.length)}', ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/projects/<id>/photos/order', (Request req, String id) async {
    projectRow(id);
    final b = await readJson(req, maxBytes: 512 * 1024);
    final ids = stringList(b, 'ids', maxItems: 20000, maxLen: 40) ?? const [];
    db.tx(() {
      for (var i = 0; i < ids.length; i++) {
        db.exec('UPDATE photos SET sort_index = ? WHERE id = ? AND project_id = ?', [i, ids[i], id]);
      }
    });
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/projects/<id>/photos/sort', (Request req, String id) async {
    projectRow(id);
    final b = await readJson(req);
    final by = str(b, 'by', max: 10) ?? 'taken';
    final order = by == 'name' ? 'filename COLLATE NOCASE' : 'COALESCE(taken_at, created_at), filename';
    final rows = db.query('SELECT id FROM photos WHERE project_id = ? ORDER BY $order', [id]);
    db.tx(() {
      for (var i = 0; i < rows.length; i++) {
        db.exec('UPDATE photos SET sort_index = ? WHERE id = ?', [i, rows[i]['id']]);
      }
    });
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/projects/<id>/cover', (Request req, String id) async {
    projectRow(id);
    final b = await readJson(req);
    final photoId = str(b, 'photoId', max: 40, required: true);
    final ok = db.one('SELECT id FROM photos WHERE id = ? AND project_id = ?', [photoId, id]);
    if (ok == null) throw ApiError.notFound('Fotografija ne postoji.');
    db.exec('UPDATE projects SET cover_photo_id = ?, updated_at = ? WHERE id = ?', [photoId, nowMs(), id]);
    return jsonOk({'ok': true});
  });

  Row photoRow(String id) {
    final ph = db.one('SELECT * FROM photos WHERE id = ?', [id]);
    if (ph == null) throw ApiError.notFound();
    return ph;
  }

  r.get('/api/admin/photos/<id>/thumb', (Request req, String id) => serveDerivative(s, req, photoRow(id), MediaKind.thumb, watermark: false));
  r.get('/api/admin/photos/<id>/preview', (Request req, String id) => serveDerivative(s, req, photoRow(id), MediaKind.preview, watermark: false));
  r.get('/api/admin/photos/<id>/original', (Request req, String id) => serveOriginal(s, photoRow(id)));

  // ---------------------------------------------------------------------------
  // Porudžbine
  // ---------------------------------------------------------------------------

  r.get('/api/admin/orders', (Request req) {
    final q = req.url.queryParameters;
    final status = q['status'] ?? 'active';
    final where = <String>[];
    final params = <Object?>[];
    switch (status) {
      case 'active':
        where.add("o.status IN ('submitted', 'printing')");
      case 'draft':
        where.add("o.status = 'draft' AND EXISTS(SELECT 1 FROM order_items WHERE order_id = o.id)");
      case 'submitted' || 'printing' || 'done':
        where.add('o.status = ?');
        params.add(status);
      default:
        where.add("o.status != 'draft'");
    }
    if (q['projectId'] != null) {
      where.add('o.project_id = ?');
      params.add(q['projectId']);
    }
    final rows = db.query(
      'SELECT o.*, p.title AS project_title FROM orders o JOIN projects p ON p.id = o.project_id '
      'WHERE ${where.join(' AND ')} ORDER BY COALESCE(o.submitted_at, o.updated_at) DESC LIMIT 500',
      params,
    );
    return jsonOk([for (final o in rows) orderSummary(o)]);
  });

  Row orderRow(String id) {
    final o = db.one('SELECT o.*, p.title AS project_title FROM orders o JOIN projects p ON p.id = o.project_id WHERE o.id = ?', [id]);
    if (o == null) throw ApiError.notFound('Porudžbina ne postoji.');
    return o;
  }

  List<Row> orderItems(String orderId) => db.query(
        '''SELECT i.photo_id, i.quantity, p.filename, p.width, p.height, p.drive_file_id, p.mime, p.size_bytes
           FROM order_items i JOIN photos p ON p.id = i.photo_id
           WHERE i.order_id = ? ORDER BY p.sort_index''',
        [orderId],
      );

  r.get('/api/admin/orders/<id>', (Request req, String id) {
    final o = orderRow(id);
    return jsonOk({
      ...orderSummary(o),
      'items': [
        for (final i in orderItems(id))
          {
            'photoId': i['photo_id'],
            'filename': i['filename'],
            'quantity': i['quantity'],
            'w': i['width'],
            'h': i['height'],
          },
      ],
    });
  });

  r.patch('/api/admin/orders/<id>', (Request req, String id) async {
    final o = orderRow(id);
    final b = await readJson(req);
    final status = str(b, 'status', max: 12, required: true);
    if (!const ['draft', 'submitted', 'printing', 'done'].contains(status)) throw ApiError.badRequest('Nepoznat status.');
    db.exec('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?', [status, nowMs(), id]);
    db.audit('order_status', detail: '${o['name']} → $status', ip: s.ip(req));
    return jsonOk(orderSummary(orderRow(id)));
  });

  r.delete('/api/admin/orders/<id>', (Request req, String id) {
    final o = orderRow(id);
    db.exec('DELETE FROM orders WHERE id = ?', [id]);
    db.audit('order_deleted', detail: '${o['name']} · ${o['project_title']}', ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.get('/api/admin/orders/<id>/zip', (Request req, String id) {
    final o = orderRow(id);
    final customer = (o['name'] as String).isEmpty ? 'klijent' : o['name'] as String;
    final items = [
      for (final i in orderItems(id)) {...i, 'customer': customer},
    ];
    return zipResponse(s, '${safeFilename('${o['project_title']} - $customer')}.zip', items,
        printSize: s.printSize, header: '${o['project_title']} — $customer');
  });

  // ---------------------------------------------------------------------------
  // Linkovi za štampariju
  // ---------------------------------------------------------------------------

  Map<String, Object?> printLinkJson(Row l) {
    final agg = db.one(
      'SELECT COUNT(*) AS n, COALESCE(SUM(quantity), 0) AS copies FROM print_link_items WHERE print_link_id = ?',
      [l['id']],
    )!;
    final now = nowMs();
    return {
      'id': l['id'],
      'label': l['label'],
      'url': s.printUrl(s.decryptOrNull(l['token_enc'] as String) ?? ''),
      'createdAt': l['created_at'],
      'expiresAt': l['expires_at'],
      'revoked': l['revoked'] == 1,
      'expired': (l['expires_at'] as int) < now,
      'accessCount': l['access_count'],
      'lastAccessAt': l['last_access_at'],
      'sentTo': l['sent_to'],
      'photoCount': agg['n'],
      'copies': agg['copies'],
      'printSize': l['print_size'],
    };
  }

  Map<String, String> mailFor(Row l) {
    final items = db.query(
      'SELECT i.*, p.filename, p.size_bytes FROM print_link_items i JOIN photos p ON p.id = i.photo_id WHERE i.print_link_id = ?',
      [l['id']],
    );
    final stats = printSummary(items);
    final summary = printSummaryText(stats, l['print_size'] as String);
    final url = s.printUrl(s.decryptOrNull(l['token_enc'] as String) ?? '');
    final exp = DateTime.fromMillisecondsSinceEpoch(l['expires_at'] as int);
    final date = '${exp.day}.${exp.month}.${exp.year}.';
    return {
      'to': s.printerEmail,
      'subject': 'Porudžbina za štampu — ${l['label']}',
      'body': 'Pozdrav,\n\n'
          'šaljem novu porudžbinu za štampu: ${l['label']}\n\n'
          '$summary\n'
          'Sve fotografije u punoj rezoluciji (${formatSize(stats['totalBytes'] as int)}) preuzimate jednim klikom ovde:\n'
          '$url\n\n'
          'Link važi do $date\n\n'
          'Hvala!\n${s.studioName}',
    };
  }

  r.get('/api/admin/print-links', (Request req) {
    final rows = db.query('SELECT * FROM print_links ORDER BY created_at DESC LIMIT 300');
    return jsonOk([for (final l in rows) {...printLinkJson(l), 'mail': mailFor(l)}]);
  });

  r.post('/api/admin/print-links', (Request req) async {
    final b = await readJson(req);
    final orderIds = stringList(b, 'orderIds', maxItems: 500, maxLen: 40) ?? const [];
    if (orderIds.isEmpty) throw ApiError.badRequest('Izaberite bar jednu porudžbinu.');
    final days = intField(b, 'days', min: 1, max: 90) ?? 30;
    final orders = [for (final id in orderIds) orderRow(id)];
    for (final o in orders) {
      if (o['status'] == 'draft') throw ApiError.badRequest('Porudžbina "${o['name']}" još nije poslata.');
    }
    final projects = orders.map((o) => o['project_title'] as String).toSet();
    final now = DateTime.now();
    final label = str(b, 'label', max: 120) ??
        (projects.length == 1 ? projects.first : 'Porudžbina ${now.day}.${now.month}.${now.year}.');

    final token = randomToken(24);
    final id = randomId();
    db.tx(() {
      db.exec(
        'INSERT INTO print_links(id, token_hash, token_enc, label, print_size, created_at, expires_at) VALUES(?, ?, ?, ?, ?, ?, ?)',
        [id, sha256Hex(token), s.box.encrypt(token), label, s.printSize, now.millisecondsSinceEpoch, now.add(Duration(days: days)).millisecondsSinceEpoch],
      );
      for (final o in orders) {
        db.exec('INSERT INTO print_link_orders(print_link_id, order_id) VALUES(?, ?)', [id, o['id']]);
        db.exec(
          'INSERT INTO print_link_items(print_link_id, photo_id, quantity, customer) '
          'SELECT ?, photo_id, quantity, ? FROM order_items WHERE order_id = ?',
          [id, o['name'], o['id']],
        );
        if (o['status'] == 'submitted') {
          db.exec("UPDATE orders SET status = 'printing', updated_at = ? WHERE id = ?", [now.millisecondsSinceEpoch, o['id']]);
        }
      }
    });
    db.audit('print_link_created', detail: label, ip: s.ip(req));
    final l = db.one('SELECT * FROM print_links WHERE id = ?', [id])!;
    return jsonOk({...printLinkJson(l), 'mail': mailFor(l)}, status: 201);
  });

  r.post('/api/admin/print-links/<id>/revoke', (Request req, String id) {
    final n = db.exec('UPDATE print_links SET revoked = 1 WHERE id = ?', [id]);
    if (n == 0) throw ApiError.notFound();
    db.audit('print_link_revoked', detail: id, ip: s.ip(req));
    return jsonOk({'ok': true});
  });

  r.delete('/api/admin/print-links/<id>', (Request req, String id) {
    db.exec('DELETE FROM print_links WHERE id = ?', [id]);
    return jsonOk({'ok': true});
  });

  r.post('/api/admin/print-links/<id>/send', (Request req, String id) async {
    final l = db.one('SELECT * FROM print_links WHERE id = ?', [id]);
    if (l == null) throw ApiError.notFound();
    final b = await readJson(req);
    final to = str(b, 'to', max: 200) ?? s.printerEmail;
    if (!_emailPattern.hasMatch(to)) throw ApiError.badRequest('Unesite ispravan mejl štamparije.');
    final mail = mailFor(l);
    await s.mailer.send(to: to, subject: mail['subject']!, text: mail['body']!);
    db.exec('UPDATE print_links SET sent_to = ? WHERE id = ?', [to, id]);
    db.audit('print_link_sent', detail: '${l['label']} → $to', ip: s.ip(req));
    return jsonOk({'ok': true});
  });
}
