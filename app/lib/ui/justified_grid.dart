import 'dart:math' as math;

import 'package:flutter/material.dart';

class _GridRow {
  _GridRow(this.start, this.end, this.height, {required this.full});
  final int start;
  final int end;
  final double height;
  final bool full;
}

List<_GridRow> _layout(List<double> aspects, double width, double target, double gap) {
  final rows = <_GridRow>[];
  var start = 0;
  var sum = 0.0;
  for (var i = 0; i < aspects.length; i++) {
    sum += aspects[i].clamp(0.4, 3.0);
    final n = i - start + 1;
    if (sum * target + gap * (n - 1) >= width) {
      rows.add(_GridRow(start, i + 1, (width - gap * (n - 1)) / sum, full: true));
      start = i + 1;
      sum = 0;
    }
  }
  if (start < aspects.length) {
    final n = aspects.length - start;
    rows.add(_GridRow(start, aspects.length, math.min(target, (width - gap * (n - 1)) / sum), full: false));
  }
  return rows;
}

/// "Justified" mreža kao u profesionalnim galerijama: svaka fotografija
/// zadržava svoj oblik, a redovi su poravnati sa obe strane. Kao sliver,
/// lako radi i sa hiljadama fotografija.
class SliverJustifiedGrid extends StatelessWidget {
  const SliverJustifiedGrid({
    super.key,
    required this.aspects,
    required this.itemBuilder,
    this.targetHeight,
    this.gap = 6,
  });

  final List<double> aspects;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double? targetHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final width = constraints.crossAxisExtent;
      final target = targetHeight ?? (width < 480 ? 150.0 : width < 900 ? 200.0 : 250.0);
      final rows = _layout(aspects, width, target, gap);
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, r) {
          final row = rows[r];
          return Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: SizedBox(
              height: row.height,
              child: Row(children: [
                for (var i = row.start; i < row.end; i++) ...[
                  if (i > row.start) SizedBox(width: gap),
                  // Pun red koristi Expanded da zaokruživanje nikad ne napravi prelivanje.
                  if (row.full)
                    Expanded(flex: (aspects[i].clamp(0.4, 3.0) * 1000).round(), child: itemBuilder(context, i))
                  else
                    SizedBox(width: aspects[i].clamp(0.4, 3.0) * row.height, child: itemBuilder(context, i)),
                ],
              ]),
            ),
          );
        },
      );
    });
  }
}
