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

/// Stavke za štampu grupisane po klijentu — štamparija pakuje kovertu po osobi.
/// Svaka stavka mora imati: photo_id, filename, quantity, customer, size_bytes.
Map<String, Object?> printSummary(List<Row> items) {
  final customers = <String, Map<String, Object?>>{};
  var totalCopies = 0;
  var totalBytes = 0;
  for (final i in items) {
    final name = (i['customer'] as String? ?? '').trim();
    final c = customers.putIfAbsent(name, () => {'name': name, 'copies': 0, 'items': <Object>[]});
    final q = i['quantity'] as int;
    c['copies'] = (c['copies'] as int) + q;
    (c['items'] as List).add({
      'photoId': i['photo_id'],
      'filename': i['filename'],
      'quantity': q,
      'bytes': i['size_bytes'],
    });
    totalCopies += q;
    totalBytes += (i['size_bytes'] as int?) ?? 0;
  }
  return {
    'customers': customers.values.toList(),
    'totalCopies': totalCopies,
    'photoCount': items.length,
    'totalBytes': totalBytes,
  };
}

String printSummaryText(Map<String, Object?> summary, String printSize) {
  final b = StringBuffer()
    ..writeln('Format: $printSize cm')
    ..writeln('Ukupno: ${summary['totalCopies']} kom (${photosLabel(summary['photoCount'] as int)})');
  final customers = (summary['customers'] as List).cast<Map<String, Object?>>();
  if (customers.length > 1 || (customers.isNotEmpty && (customers.first['name'] as String).isNotEmpty)) {
    b.writeln();
    for (final c in customers) {
      final name = (c['name'] as String).isEmpty ? 'Klijent' : c['name'];
      b.writeln('• $name: ${c['copies']} kom');
    }
  }
  return b.toString();
}

/// ZIP sa ORIGINALIMA (bajt-za-bajt, bez kompresije i smanjivanja).
/// Ime fajla počinje brojem kopija: "2x_DSC_4120.jpg". Ako je u paketu više
/// klijenata, svaki ima svoj folder.
Response zipResponse(Services s, String zipName, List<Row> items, {required String printSize, String? header}) {
  final summary = printSummary(items);
  final customers = (summary['customers'] as List).cast<Map<String, Object?>>();
  final byPhoto = {for (final i in items) i['photo_id'] as String: i['drive_file_id'] as String};
  final perCustomerFolders = customers.length > 1;
  final used = <String>{};
  final entries = <ZipEntry>[];
  final listing = StringBuffer()
    ..writeln(header ?? 'Porudžbina za štampu')
    ..writeln()
    ..write(printSummaryText(summary, printSize))
    ..writeln();
  for (final c in customers) {
    final name = (c['name'] as String).isEmpty ? 'Klijent' : c['name'] as String;
    final folder = perCustomerFolders ? '${safeFilename(name)}/' : '';
    if (perCustomerFolders) listing.writeln('[$name]');
    for (final it in (c['items'] as List).cast<Map<String, Object?>>()) {
      final base = safeFilename('${it['quantity']}x_${it['filename']}');
      var path = '$folder$base';
      var n = 2;
      while (!used.add(path)) {
        path = '$folder${n++}_$base';
      }
      listing.writeln('  ${it['quantity']} kom  ${it['filename']}');
      final driveId = byPhoto[it['photoId']]!;
      entries.add(ZipEntry(path, () async => (await s.drive.download(driveId)).stream));
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

/// Stranica za štampariju (kao WeTransfer, ali bez posrednika): pristup samo
/// preko tajnog, vremenski ograničenog linka koji administrator može opozvati.
/// Originali idu direktno sa servera — administrator ništa ne preuzima.
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
        '''SELECT i.photo_id, i.quantity, i.customer, p.filename, p.drive_file_id, p.mime, p.size_bytes
           FROM print_link_items i JOIN photos p ON p.id = i.photo_id
           WHERE i.print_link_id = ? ORDER BY i.id''',
        [l['id']],
      );

  r.get('/api/print/<token>', (Request req, String token) {
    s.rateLimit(req, 'print-view', 120, const Duration(minutes: 1));
    final l = link(req, token);
    s.db.exec('UPDATE print_links SET access_count = access_count + 1, last_access_at = ? WHERE id = ?', [nowMs(), l['id']]);
    return jsonOk({
      'studioName': s.studioName,
      'label': l['label'],
      'printSize': l['print_size'],
      'createdAt': l['created_at'],
      'expiresAt': l['expires_at'],
      ...printSummary(items(l)),
    });
  });

  Row linkPhoto(Request req, String token, String id) {
    final l = link(req, token);
    final photo = s.db.one(
      'SELECT p.* FROM photos p JOIN print_link_items i ON i.photo_id = p.id WHERE i.print_link_id = ? AND p.id = ?',
      [l['id'], id],
    );
    if (photo == null) throw ApiError.notFound();
    return photo;
  }

  r.get('/api/print/<token>/photos/<id>/thumb', (Request req, String token, String id) async {
    s.rateLimit(req, 'print-media', 3000, const Duration(minutes: 1));
    return serveDerivative(s, req, linkPhoto(req, token, id), MediaKind.thumb, watermark: false);
  });

  r.get('/api/print/<token>/photos/<id>/original', (Request req, String token, String id) async {
    s.rateLimit(req, 'print-download', 600, const Duration(minutes: 1));
    return serveOriginal(s, linkPhoto(req, token, id));
  });

  r.get('/api/print/<token>/zip', (Request req, String token) {
    s.rateLimit(req, 'print-zip', 10, const Duration(minutes: 10));
    final l = link(req, token);
    s.db.audit('print_zip', detail: l['label'] as String, ip: s.ip(req));
    return zipResponse(
      s,
      'stampa-${safeFilename(l['label'] as String)}.zip',
      items(l),
      printSize: l['print_size'] as String,
      header: '${s.studioName} — ${l['label']}',
    );
  });
}
