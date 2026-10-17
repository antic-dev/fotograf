import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'crypto_util.dart';
import 'http_util.dart';

const thumbLongEdge = 560;

/// Pregled za klijente je namerno male rezolucije: dovoljno za biranje na
/// ekranu, ali nedovoljno za kvalitetnu štampu (13x18 cm traži ~2100 px).
const previewLongEdge = 1280;
const _maxPixels = 150 * 1000 * 1000;

/// Prepoznaje format po "magičnim" bajtovima — nikad ne verujemo ekstenziji
/// ili Content-Type zaglavlju koje šalje pregledač.
String? sniffImageMime(Uint8List b) {
  if (b.length < 12) return null;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  if ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) || (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A)) {
    return 'image/tiff';
  }
  // HEIC/HEIF (ftypheic, ftypmif1...) — prepoznajemo da bismo dali jasnu poruku.
  if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return 'image/heic';
  return null;
}

class ProcessedImage {
  ProcessedImage({
    required this.width,
    required this.height,
    required this.takenAt,
    required this.thumb,
    required this.thumbClean,
    required this.preview,
  });

  final int width;
  final int height;
  final int? takenAt;

  /// Sličica sa žigom (za klijente).
  final Uint8List thumb;

  /// Sličica bez žiga (samo za administratora i štampariju).
  final Uint8List thumbClean;

  /// Pregled sa žigom (za klijente).
  final Uint8List preview;
}

class _Job {
  _Job(this.bytes, this.watermark);
  final Uint8List bytes;
  final String? watermark;
}

/// Najviše dve obrade istovremeno: velika fotografija zauzme stotine MB
/// memorije dok se obrađuje, pa ovo čuva mali server od nestanka memorije.
final _slots = _Semaphore(2);

/// Teška obrada se radi u zasebnom izolatu da server ostane brz.
Future<ProcessedImage> processUpload(Uint8List bytes, {required String watermark}) {
  final job = _Job(bytes, watermark);
  return _slots.run(() => Isolate.run(() => _process(job)));
}

Future<Uint8List> renderPreview(Uint8List original, {String? watermark}) {
  final job = _Job(original, watermark);
  return _slots.run(() => Isolate.run(() {
        final image = _decode(job.bytes);
        return _encodePreview(image, job.watermark);
      }));
}

Future<Uint8List> renderThumb(Uint8List original, {String? watermark}) {
  final job = _Job(original, watermark);
  return _slots.run(() => Isolate.run(() {
        final image = _decode(job.bytes);
        return _encodeThumb(image, job.watermark);
      }));
}

class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= _max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(); // mesto prelazi direktno sledećem
      } else {
        _running--;
      }
    }
  }
}

img.Image _decode(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) throw const FormatException('Nepoznat format slike.');
  final info = decoder.startDecode(bytes);
  if (info == null) throw const FormatException('Slika je oštećena.');
  if (info.width * info.height > _maxPixels) {
    throw const FormatException('Slika ima previše piksela.');
  }
  final image = decoder.decode(bytes);
  if (image == null) throw const FormatException('Slika je oštećena.');
  return img.bakeOrientation(image);
}

ProcessedImage _process(_Job job) {
  final image = _decode(job.bytes);
  int? takenAt;
  try {
    final raw = image.exif.exifIfd['DateTimeOriginal']?.toString() ?? image.exif.imageIfd['DateTime']?.toString();
    if (raw != null) {
      final m = RegExp(r'(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(raw);
      if (m != null) {
        takenAt = DateTime(
          int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
          int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!),
        ).millisecondsSinceEpoch;
      }
    }
  } catch (_) {}
  return ProcessedImage(
    width: image.width,
    height: image.height,
    takenAt: takenAt,
    thumb: _encodeThumb(image, job.watermark),
    thumbClean: _encodeThumb(image, null),
    preview: _encodePreview(image, job.watermark),
  );
}

img.Image _fit(img.Image image, int longEdge) {
  if (image.width <= longEdge && image.height <= longEdge) return image.clone();
  return image.width >= image.height
      ? img.copyResize(image, width: longEdge, interpolation: img.Interpolation.average)
      : img.copyResize(image, height: longEdge, interpolation: img.Interpolation.average);
}

Uint8List _encodeThumb(img.Image image, String? watermark) {
  final t = _fit(image, thumbLongEdge);
  t.exif = img.ExifData(); // uklanja metapodatke (GPS, aparat...)
  if (watermark != null) applyWatermark(t, watermark, small: true);
  return img.encodeJpg(t, quality: watermark == null ? 80 : 76);
}

Uint8List _encodePreview(img.Image image, String? watermark) {
  final pv = _fit(image, previewLongEdge);
  pv.exif = img.ExifData();
  if (watermark != null) applyWatermark(pv, watermark, small: false);
  return img.encodeJpg(pv, quality: watermark == null ? 85 : 80);
}

String _asciiLabel(String text) {
  const map = {'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'dj', 'Č': 'C', 'Ć': 'C', 'Š': 'S', 'Ž': 'Z', 'Đ': 'Dj'};
  final ascii = text.split('').map((ch) => map[ch] ?? ch).join().replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  final label = ascii.isEmpty ? 'PREGLED' : ascii;
  return label.length > 32 ? label.substring(0, 32) : label;
}

/// Dijagonalni žig koji pokriva CELU fotografiju u gustoj mreži, na
/// nasumičnim pozicijama za svaku sliku.
///
/// Zašto ovako: AI alati lako uklanjaju jedan logo u uglu, ali ne i providnu
/// mrežu teksta preko celog kadra (lica, haljina, pozadina...). Providnost je
/// podešena tako da se fotografija jasno vidi pri biranju.
void applyWatermark(img.Image image, String text, {required bool small, int? seed}) {
  final font = small ? img.arial24 : img.arial48;
  final label = _asciiLabel(text);
  final rnd = Random(seed);

  // 1. Tekst se crta na zaseban "stencil" i rotira za -30°.
  var textWidth = 0;
  for (final c in label.codeUnits) {
    textWidth += font.characters[c]?.xAdvance ?? font.base ~/ 2;
  }
  final pad = font.lineHeight ~/ 2;
  final stencil = img.Image(width: textWidth + pad * 2, height: font.lineHeight + pad * 2);
  img.drawString(stencil, label, font: font, x: pad, y: pad, color: img.ColorRgb8(255, 255, 255));
  final rotated = img.copyRotate(stencil, angle: -30, interpolation: img.Interpolation.linear);
  final sw = rotated.width, sh = rotated.height;
  final stamp = Uint8List(sw * sh);
  for (final px in rotated) {
    stamp[px.y * sw + px.x] = px.r.toInt();
  }

  // 2. Maska pokrivenosti za celu sliku (popločavanje sa pomakom).
  final w = image.width, h = image.height;
  final mask = Uint8List(w * h);
  final stepX = (textWidth * 0.92).round() + (small ? 30 : 70);
  final stepY = (sh * 0.62).round() + (small ? 14 : 34);
  final offX = rnd.nextInt(stepX), offY = rnd.nextInt(stepY);
  var row = 0;
  for (var ty = -sh + offY; ty < h; ty += stepY, row++) {
    final shift = row.isOdd ? stepX ~/ 2 : 0;
    for (var tx = -sw + offX + shift; tx < w; tx += stepX) {
      for (var sy = 0; sy < sh; sy++) {
        final y = ty + sy;
        if (y < 0 || y >= h) continue;
        final srcRow = sy * sw, dstRow = y * w;
        for (var sx = 0; sx < sw; sx++) {
          final v = stamp[srcRow + sx];
          if (v == 0) continue;
          final x = tx + sx;
          if (x < 0 || x >= w) continue;
          if (v > mask[dstRow + x]) mask[dstRow + x] = v;
        }
      }
    }
  }

  // 3. Svetao tekst sa tamnom senkom — vidljiv i na svetlim i na tamnim delovima.
  final d = small ? 1 : 2;
  const light = 0.34, dark = 0.22;
  for (final px in image) {
    final x = px.x, y = px.y;
    final cov = mask[y * w + x] / 255.0;
    final sx = x - d, sy = y - d;
    final shadow = (sx >= 0 && sy >= 0) ? mask[sy * w + sx] / 255.0 : 0.0;
    if (cov == 0 && shadow == 0) continue;
    var r = px.r.toDouble(), g = px.g.toDouble(), b = px.b.toDouble();
    final k = 1 - dark * shadow * (1 - cov);
    r *= k;
    g *= k;
    b *= k;
    final a = light * cov;
    px
      ..r = r + (255 - r) * a
      ..g = g + (255 - g) * a
      ..b = b + (255 - b) * a;
  }
}

/// Keš izvedenih slika (sličice i pregledi) na disku servera. Originali su
/// uvek samo na Google Drive-u; keš se može obrisati i biće ponovo napravljen.
class MediaCache {
  MediaCache(String dataDir) : dir = p.join(dataDir, 'cache') {
    Directory(dir).createSync(recursive: true);
  }

  final String dir;
  final Map<String, Future<File>> _inflight = {};

  static String watermarkKey(String? text) =>
      (text == null || text.trim().isEmpty) ? 'clean' : sha256Hex(text.trim()).substring(0, 10);

  String thumbPath(String photoId, String? watermark) =>
      p.join(dir, '${photoId}_t_${watermarkKey(watermark)}.jpg');
  String previewPath(String photoId, String? watermark) =>
      p.join(dir, '${photoId}_p_${watermarkKey(watermark)}.jpg');

  Future<void> store(String path, Uint8List bytes) async {
    final tmp = File('$path.${randomId()}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  /// Vraća fajl iz keša, a ako ne postoji pravi ga (samo jednom, čak i kada
  /// stigne više istovremenih zahteva).
  Future<File> getOrCreate(String path, Future<Uint8List> Function() create) {
    final f = File(path);
    if (f.existsSync()) return Future.value(f);
    return _inflight.putIfAbsent(path, () async {
      try {
        final bytes = await create();
        await store(path, bytes);
        return f;
      } finally {
        unawaited(Future(() => _inflight.remove(path)));
      }
    });
  }

  /// Briše sve izvedene slike za date fotografije (jedan prolaz kroz folder).
  void deletePhotos(Iterable<String> photoIds) {
    final ids = photoIds.toSet();
    if (ids.isEmpty) return;
    for (final e in Directory(dir).listSync()) {
      final name = p.basename(e.path);
      final i = name.indexOf('_');
      if (i > 0 && ids.contains(name.substring(0, i))) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Drži keš ispod [maxBytes]: briše najduže nekorišćene fajlove.
  /// Originali su na Drive-u, pa se obrisano po potrebi ponovo napravi.
  Future<void> trim(int maxBytes) async {
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final e in Directory(dir).list()) {
      if (e is! File) continue;
      final st = await e.stat();
      files.add((e, st));
      total += st.size;
    }
    if (total <= maxBytes) return;
    DateTime last((File, FileStat) f) => f.$2.accessed.isAfter(f.$2.modified) ? f.$2.accessed : f.$2.modified;
    files.sort((a, b) => last(a).compareTo(last(b)));
    final target = (maxBytes * 0.8).round();
    for (final (f, st) in files) {
      if (total <= target) break;
      try {
        await f.delete();
        total -= st.size;
      } catch (_) {}
    }
  }
}

ApiError imageError(Object e) {
  if (e is FormatException) return ApiError(422, e.message, code: 'bad_image');
  return ApiError(422, 'Slika se ne može obraditi.', code: 'bad_image');
}
