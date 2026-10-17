import 'dart:convert';
import 'dart:typed_data';

/// Jedan fajl u ZIP arhivi; sadržaj se otvara tek kada dođe na red, tako da
/// server nikada ne drži celu arhivu u memoriji.
class ZipEntry {
  ZipEntry(this.name, this.open);

  final String name;
  final Future<Stream<List<int>>> Function() open;
}

/// Strimuje ZIP (bez kompresije — JPEG je već kompresovan) uz ZIP64 podršku
/// za arhive veće od 4 GB.
Stream<List<int>> zipStream(List<ZipEntry> entries, {DateTime? time}) async* {
  final t = time ?? DateTime.now();
  final dosTime = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  final dosDate = ((t.year - 1980).clamp(0, 127) << 9) | (t.month << 5) | t.day;
  const flags = 0x0808; // bit 3: data descriptor, bit 11: UTF-8 imena
  const max32 = 0xFFFFFFFF;

  final central = <Uint8List>[];
  var offset = 0;

  for (final e in entries) {
    final name = utf8.encode(e.name);
    final local = _Buf()
      ..u32(0x04034b50)
      ..u16(20)
      ..u16(flags)
      ..u16(0)
      ..u16(dosTime)
      ..u16(dosDate)
      ..u32(0)
      ..u32(0)
      ..u32(0)
      ..u16(name.length)
      ..u16(0)
      ..bytes(name);
    final header = local.done();
    final headerOffset = offset;
    yield header;
    offset += header.length;

    var crc = 0xFFFFFFFF;
    var size = 0;
    final stream = await e.open();
    await for (final chunk in stream) {
      crc = _crcUpdate(crc, chunk);
      size += chunk.length;
      yield chunk;
    }
    crc ^= 0xFFFFFFFF;
    offset += size;
    if (size >= max32) throw StateError('Pojedinačan fajl veći od 4 GB nije podržan.');

    final desc = (_Buf()
          ..u32(0x08074b50)
          ..u32(crc)
          ..u32(size)
          ..u32(size))
        .done();
    yield desc;
    offset += desc.length;

    final needs64 = headerOffset >= max32;
    final extra = needs64 ? ((_Buf()..u16(0x0001)..u16(8)..u64(headerOffset)).done()) : Uint8List(0);
    central.add((_Buf()
          ..u32(0x02014b50)
          ..u16(needs64 ? 45 : 20)
          ..u16(needs64 ? 45 : 20)
          ..u16(flags)
          ..u16(0)
          ..u16(dosTime)
          ..u16(dosDate)
          ..u32(crc)
          ..u32(size)
          ..u32(size)
          ..u16(name.length)
          ..u16(extra.length)
          ..u16(0)
          ..u16(0)
          ..u16(0)
          ..u32(0)
          ..u32(needs64 ? max32 : headerOffset)
          ..bytes(name)
          ..bytes(extra))
        .done());
  }

  final cdOffset = offset;
  var cdSize = 0;
  for (final c in central) {
    yield c;
    cdSize += c.length;
  }
  final zip64 = cdOffset >= max32 || cdSize >= max32 || entries.length >= 0xFFFF;
  if (zip64) {
    final eocd64Offset = cdOffset + cdSize;
    yield (_Buf()
          ..u32(0x06064b50)
          ..u64(44)
          ..u16(45)
          ..u16(45)
          ..u32(0)
          ..u32(0)
          ..u64(entries.length)
          ..u64(entries.length)
          ..u64(cdSize)
          ..u64(cdOffset))
        .done();
    yield (_Buf()
          ..u32(0x07064b50)
          ..u32(0)
          ..u64(eocd64Offset)
          ..u32(1))
        .done();
  }
  yield (_Buf()
        ..u32(0x06054b50)
        ..u16(0)
        ..u16(0)
        ..u16(zip64 ? 0xFFFF : entries.length)
        ..u16(zip64 ? 0xFFFF : entries.length)
        ..u32(zip64 ? max32 : cdSize)
        ..u32(zip64 ? max32 : cdOffset)
        ..u16(0))
      .done();
}

class _Buf {
  final _b = BytesBuilder();
  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u64(int v) {
    u32(v & 0xFFFFFFFF);
    u32((v ~/ 0x100000000) & 0xFFFFFFFF);
  }

  void bytes(List<int> v) => _b.add(v);
  Uint8List done() => _b.takeBytes();
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crcUpdate(int crc, List<int> data) {
  var c = crc;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c;
}

/// CRC32 (koristi se i u testovima).
int crc32(List<int> data) => _crcUpdate(0xFFFFFFFF, data) ^ 0xFFFFFFFF;
