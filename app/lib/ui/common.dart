import 'package:flutter/material.dart';

import '../api/api.dart';
import 'theme.dart';

const _months = ['januar', 'februar', 'mart', 'april', 'maj', 'jun', 'jul', 'avgust', 'septembar', 'oktobar', 'novembar', 'decembar'];

String formatDate(DateTime d) => '${d.day}. ${_months[d.month - 1]} ${d.year}.';
String formatDateMs(int ms) => formatDate(DateTime.fromMillisecondsSinceEpoch(ms));
String formatShortDate(DateTime d) => '${d.day}.${d.month}.${d.year}.';

String? formatIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  return d == null ? iso : formatDate(d);
}

String formatDateTimeMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${formatShortDate(d)} u $hh:$mm';
}

String timeAgo(int ms) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (diff.inMinutes < 1) return 'upravo sada';
  if (diff.inMinutes < 60) return 'pre ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'pre ${diff.inHours} h';
  if (diff.inDays < 7) return 'pre ${diff.inDays} ${diff.inDays == 1 ? 'dan' : 'dana'}';
  return formatShortDate(DateTime.fromMillisecondsSinceEpoch(ms));
}

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

/// Srpska množina: 1 fotografija, 2 fotografije, 5 fotografija, 21 fotografija.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n $one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n $few';
  return '$n $many';
}

String photosLabel(int n) => plural(n, 'fotografija', 'fotografije', 'fotografija');
String copiesLabel(int n) => plural(n, 'primerak', 'primerka', 'primeraka');

void showMessage(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: error ? const Color(0xFFFFB4AB) : const Color(0xFF8FE3BF)),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      duration: Duration(seconds: error ? 5 : 3),
    ));
}

void showError(BuildContext context, Object e) =>
    showMessage(context, e is ApiException ? e.message : 'Došlo je do greške. Pokušajte ponovo.', error: true);

/// Sve slike se učitavaju kroz aplikaciju (sa našim zaglavljem) i crtaju na
/// canvas — nema <img> elementa, pa ni opcije "Sačuvaj sliku" u pregledaču.
ImageProvider appImage(String url) => NetworkImage(url, headers: const {'X-Fotograf': '1'});

/// Slika sa servera sa nežnim pojavljivanjem i neutralnom pozadinom dok se učitava.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.background = AppColors.sand, this.semanticLabel});

  final String url;
  final BoxFit fit;
  final Color background;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Image(
        image: appImage(url),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        semanticLabel: semanticLabel,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stack) => const Center(
          child: Icon(Icons.image_not_supported_outlined, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}

class Centered extends StatelessWidget {
  const Centered({super.key, required this.child, this.maxWidth = 1200, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: AppColors.sand, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),
            Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ]),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.inkSoft)),
          ],
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Nešto nije u redu',
        message: error is ApiException ? (error as ApiException).message : 'Došlo je do greške. Pokušajte ponovo.',
        action: onRetry == null
            ? null
            : FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Pokušaj ponovo')),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.inkSoft, this.background = AppColors.sand, this.icon});

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}

Pill orderStatusPill(String status) => switch (status) {
      'submitted' => const Pill('Nova', color: AppColors.emeraldDark, background: AppColors.emeraldSoft, icon: Icons.notifications_active_rounded),
      'printing' => const Pill('U štampi', color: AppColors.amber, background: AppColors.amberSoft, icon: Icons.print_rounded),
      'done' => const Pill('Završena', icon: Icons.done_all_rounded),
      _ => const Pill('Bira se...', icon: Icons.more_horiz_rounded),
    };

Pill projectStatusPill(String status) => switch (status) {
      'open' => const Pill('Otvoren za izbor', color: AppColors.emeraldDark, background: AppColors.emeraldSoft, icon: Icons.lock_open_rounded),
      'closed' => const Pill('Samo pregled', color: AppColors.amber, background: AppColors.amberSoft, icon: Icons.visibility_rounded),
      _ => const Pill('Skriven', icon: Icons.visibility_off_rounded),
    };

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Odustani',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: Theme.of(context).textTheme.bodyLarge),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Jednostavno deljenje kontrolera kroz stablo widgeta.
class Scope<T extends Listenable> extends InheritedNotifier<T> {
  const Scope({super.key, required T value, required super.child}) : super(notifier: value);

  static T of<T extends Listenable>(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Scope<T>>();
    assert(s != null, 'Nema Scope<$T> iznad');
    return s!.notifier!;
  }

  static T read<T extends Listenable>(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<Scope<T>>();
    return s!.notifier!;
  }
}

bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < 640;
