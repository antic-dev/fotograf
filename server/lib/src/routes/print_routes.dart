import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../crypto_util.dart';
import '../db.dart';
import '../http_util.dart';
import '../media.dart';
import '../services.dart';
import '../zip_stream.dart';

final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{20,64}$');

/// Grupisane stavke za štampu: veličina + papir -> stavke.
List<Map<String, Object?>> groupPrintItems(List<Row> items) {
  final groups = <String, Map<String, Object?>>{};
  for (final i in items) {
    final key = '${i['size']}|${i['finish']}';
    final g = groups.putIfAbsent(key, () => {'size': i['size'], 'finish': i['finish'], 'copies': 0, 'items': <Object>[]});
    g['copies'] = (g['copies'] as int) + (i['quantity'] as int);
    (g['items'] as List).add({
      'photoId': i['photo_id'],
      'filename': i['filename'],
      'quantity': i['quantity'],
      'customer': i['customer'],
    });
  }
  final list = groups.values.toList()
    ..sort((a, b) => _sizeKey(a['size'] as String).compareTo(_sizeKey(b['size'] as String)));
  return list;
}

int _sizeKey(String size) {
  final m = RegExp(r'(\d+)\D+(\d+)').firstMatch(size);
  return m == null ? 1 << 30 : int.parse(m[1]!) * int.parse(m[2]!);
}

String printSummaryText(List<Map<String, Object?>> groups) {
  final b = StringBuffer();
  var total = 0;
  for (final g in groups) {
    b.writeln('• ${g['size']} — ${g['finish']}: ${g['copies']} kom');
    total += g['copies'] as int;
  }
  b.writeln('Ukupno: $total kom');
  return b.toString();
}

/// ZIP sa originalima, raspoređenim u foldere po veličini i papiru.
/// Ime fajla počinje brojem kopija: "2x_Ana_IMG_0001.jpg".
Response zipResponse(Services s, String zipName, List<Row> items, {String? header}) {
  final groups = groupPrintItems(items);
  final used = <String>{};
  final entries = <ZipEntry>[];
  final listing = StringBuffer()
    ..writeln(header ?? 'Porudžbina za štampu')
    ..writeln()
    ..write(printSummaryText(groups))
    ..writeln();
  for (final g in groups) {
    final folder = safeFilename('${g['size']} ${g['finish']}');
    listing.writeln('[$folder]');
    for (final it in (g['items'] as List).cast<Map<String, Object?>>()) {
      final customer = (it['customer'] as String? ?? '').trim();
      final base = safeFilename('${it['quantity']}x_${customer.isEmpty ? '' : '${customer}_'}${it['filename']}');
      var name = '$folder/$base';
      var n = 2;
      while (!used.add(name)) {
        name = '$folder/${n++}_$base';
      }
      listing.writeln('  ${it['quantity']} kom  ${it['filename']}${customer.isEmpty ? '' : '  ($customer)'}');
      final row = items.firstWhere((x) => x['photo_id'] == it['photoId']);
      entries.add(ZipEntry(name, () async => (await s.drive.download(row['drive_file_id'] as String)).stream));
    }
  }
  entries.insert(0, ZipEntry('SPISAK.txt', () async => Stream.value(utf8.encode(listing.toString()))));
  return Response.ok(
    zipStream(entries),
    headers: {
      HttpHeaders.contentTypeHeader: 'application/zip',
      'content-disposition': contentDisposition(zipName),
      HttpHeaders.cacheControlHeader: 'private, no-store',
    },
  );
}

/// Stranica za štampariju: pristup samo preko tajnog, vremenski ograničenog
/// linka koji administrator može opozvati u svakom trenutku.
void mountPrintRoutes(Router r, Services s) {
  Row link(Request req, String token) {
    if (!_tokenPattern.hasMatch(token)) {
      s.rateLimit(req, 'print-miss', 30, const Duration(minutes: 10));
      throw ApiError.notFound('Link nije ispravan.');
    }
    final row = s.db.one('SELECT * FROM print_links WHERE token_hash = ?', [sha256Hex(token)]);
    if (row == null) {
      s.rateLimit(req, 'print-miss', 30, const Duration(minutes: 10));
      throw ApiError.notFound('Link nije ispravan.');
    }
    if (row['revoked'] == 1) throw ApiError(410, 'Ovaj link je opozvan.', code: 'revoked');
    if ((row['expires_at'] as int) < nowMs()) throw ApiError(410, 'Ovaj link je istekao.', code: 'expired');
    return row;
  }

  List<Row> items(Row l) => s.db.query(
        '''SELECT i.photo_id, i.quantity, i.size, i.finish, i.customer, p.filename, p.drive_file_id, p.mime
           FROM print_link_items i JOIN photos p ON p.id = i.photo_id
           WHERE i.print_link_id = ? ORDER BY i.id''',
        [l['id']],
      );

  r.get('/api/print/<token>', (Request req, String token) {
    s.rateLimit(req, 'print-view', 120, const Duration(minutes: 1));
    final l = link(req, token);
    s.db.exec('UPDATE print_links SET access_count = access_count + 1, last_access_at = ? WHERE id = ?', [nowMs(), l['id']]);
    final its = items(l);
    return jsonOk({
      'studioName': s.studioName,
      'label': l['label'],
      'createdAt': l['created_at'],
      'expiresAt': l['expires_at'],
      'groups': groupPrintItems(its),
      'totalCopies': its.fold<int>(0, (a, b) => a + (b['quantity'] as int)),
    });
  });

  r.get('/api/print/<token>/photos/<id>/thumb', (Request req, String token, String id) async {
    s.rateLimit(req, 'print-media', 1500, const Duration(minutes: 1));
    final l = link(req, token);
    final photo = s.db.one(
      'SELECT p.* FROM photos p JOIN print_link_items i ON i.photo_id = p.id WHERE i.print_link_id = ? AND p.id = ?',
      [l['id'], id],
    );
    if (photo == null) throw ApiError.notFound();
    return serveDerivative(s, req, photo, MediaKind.thumb, watermark: false);
  });

  r.get('/api/print/<token>/photos/<id>/original', (Request req, String token, String id) async {
    s.rateLimit(req, 'print-download', 600, const Duration(minutes: 1));
    final l = link(req, token);
    final photo = s.db.one(
      'SELECT p.* FROM photos p JOIN print_link_items i ON i.photo_id = p.id WHERE i.print_link_id = ? AND p.id = ?',
      [l['id'], id],
    );
    if (photo == null) throw ApiError.notFound();
    return serveOriginal(s, photo);
  });

  r.get('/api/print/<token>/zip', (Request req, String token) {
    s.rateLimit(req, 'print-zip', 10, const Duration(minutes: 10));
    final l = link(req, token);
    s.db.audit('print_zip', detail: l['label'] as String, ip: s.ip(req));
    return zipResponse(s, 'stampa-${safeFilename(l['label'] as String)}.zip', items(l), header: '${s.studioName} — ${l['label']}');
  });
}
