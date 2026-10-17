import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import 'db.dart';
import 'http_util.dart';
import 'images.dart';
import 'services.dart';

enum MediaKind { thumb, preview }

/// Zajednička logika za isporuku sličica i pregleda (iz keša, uz pravljenje
/// iz originala sa Drive-a kada je potrebno).
Future<Response> serveDerivative(
  Services s,
  Request req,
  Row photo,
  MediaKind kind, {
  required bool watermark,
}) async {
  final photoId = photo['id'] as String;
  final driveId = photo['drive_file_id'] as String;
  final String path;
  final Future<Uint8List> Function() create;
  final text = watermark ? s.watermarkText : null;
  if (kind == MediaKind.thumb) {
    path = s.cache.thumbPath(photoId, text);
    create = () async => renderThumb(await s.drive.downloadBytes(driveId), watermark: text);
  } else {
    path = s.cache.previewPath(photoId, text);
    create = () async => renderPreview(await s.drive.downloadBytes(driveId), watermark: text);
  }
  final File file;
  try {
    file = await s.cache.getOrCreate(path, create);
  } on ApiError {
    rethrow;
  } catch (e) {
    throw imageError(e);
  }
  final res = await serveFile(req, file, 'image/jpeg', cache: 'private, max-age=604800, immutable');
  return res.change(headers: {'content-disposition': 'inline; filename="pregled.jpg"'});
}

/// Slike za klijente se isporučuju samo aplikaciji (XHR sa našim zaglavljem),
/// a ne kada neko otvori adresu slike direktno u pregledaču ili je ugradi
/// na drugi sajt. Ovo ne zamenjuje žig, ali uklanja "Otvori sliku u novoj
/// kartici → Sačuvaj".
void requireAppImageRequest(Request req) {
  final dest = req.headers['sec-fetch-dest'];
  if (req.headers['x-fotograf'] != '1' || (dest != null && dest != 'empty')) {
    throw ApiError.forbidden('Fotografije se mogu pogledati samo u galeriji.');
  }
}

Future<Response> serveFile(Request req, File file, String type, {required String cache}) async {
  final stat = await file.stat();
  final etag = '"${stat.size.toRadixString(36)}-${stat.modified.millisecondsSinceEpoch.toRadixString(36)}"';
  final headers = {
    HttpHeaders.contentTypeHeader: type,
    HttpHeaders.cacheControlHeader: cache,
    HttpHeaders.etagHeader: etag,
  };
  if (req.headers[HttpHeaders.ifNoneMatchHeader] == etag) {
    return Response.notModified(headers: headers);
  }
  return Response.ok(
    req.method == 'HEAD' ? null : file.openRead(),
    headers: {...headers, HttpHeaders.contentLengthHeader: '${stat.size}'},
  );
}

/// Strimuje original sa Drive-a kao preuzimanje.
Future<Response> serveOriginal(Services s, Row photo) async {
  final media = await s.drive.download(photo['drive_file_id'] as String);
  return Response.ok(
    media.stream,
    headers: {
      HttpHeaders.contentTypeHeader: photo['mime'] as String,
      if (media.length != null) HttpHeaders.contentLengthHeader: '${media.length}',
      'content-disposition': contentDisposition(photo['filename'] as String),
      HttpHeaders.cacheControlHeader: 'private, no-store',
    },
  );
}
