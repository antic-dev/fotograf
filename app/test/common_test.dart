import 'package:flutter_test/flutter_test.dart';
import 'package:fotograf/ui/common.dart';

void main() {
  test('srpska množina', () {
    expect(photosLabel(1), '1 fotografija');
    expect(photosLabel(2), '2 fotografije');
    expect(photosLabel(5), '5 fotografija');
    expect(photosLabel(11), '11 fotografija');
    expect(photosLabel(12), '12 fotografija');
    expect(photosLabel(21), '21 fotografija');
    expect(photosLabel(22), '22 fotografije');
    expect(copiesLabel(1), '1 primerak');
    expect(copiesLabel(3), '3 primerka');
    expect(copiesLabel(14), '14 primeraka');
  });

  test('datumi', () {
    expect(formatIsoDate('2026-06-14'), '14. jun 2026.');
    expect(formatIsoDate(null), isNull);
    expect(formatBytes(5 * 1024 * 1024 * 1024 * 1024), '5.0 TB');
  });
}
