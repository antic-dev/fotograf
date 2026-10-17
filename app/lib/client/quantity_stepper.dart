import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Veliki − / + za broj primeraka — lako se pogađa prstom.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.dark = false});

  final int value;
  final ValueChanged<int>? onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = dark ? Colors.white : AppColors.ink;
    final border = dark ? Colors.white38 : AppColors.line;
    Widget button(IconData icon, int next, String tooltip) => IconButton.outlined(
          tooltip: tooltip,
          onPressed: onChanged == null || next < 1 || next > 99 ? null : () => onChanged!(next),
          iconSize: 26,
          color: fg,
          style: IconButton.styleFrom(
            foregroundColor: fg,
            minimumSize: const Size(52, 52),
            side: BorderSide(color: border, width: 1.5),
            disabledForegroundColor: fg.withValues(alpha: 0.3),
          ),
          icon: Icon(icon),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.remove_rounded, value - 1, 'Manje'),
      SizedBox(
        width: 56,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
          child: Text(
            '$value',
            key: ValueKey(value),
            textAlign: TextAlign.center,
            style: t.headlineSmall?.copyWith(fontFamily: bodyFont, fontWeight: FontWeight.w800, color: fg),
          ),
        ),
      ),
      button(Icons.add_rounded, value + 1, 'Više'),
    ]);
  }
}
