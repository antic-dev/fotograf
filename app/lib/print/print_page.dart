import 'package:flutter/material.dart';

import '../api/api.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';

/// Stranica za štampariju — radi kao WeTransfer: jedno dugme preuzima sve
/// originale u punoj rezoluciji. Bez naloga; tajni link ističe i može se opozvati.
class PrintPage extends StatefulWidget {
  const PrintPage({super.key, required this.token});
  final String token;

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _downloading = false;

  String get _base => '/api/print/${widget.token}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await Api.instance.get(_base) as Map<String, dynamic>;
      setState(() => _data = d);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  void _downloadAll() {
    download('$_base/zip');
    setState(() => _downloading = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = _error;
    if (e != null) {
      final gone = e is ApiException && (e.status == 410 || e.status == 404);
      return Scaffold(
        body: EmptyState(
          icon: gone ? Icons.link_off_rounded : Icons.cloud_off_rounded,
          title: gone ? 'Link više ne važi' : 'Nema veze',
          message: gone ? e.message : 'Proverite internet vezu.',
          action: gone ? null : FilledButton(onPressed: _load, child: const Text('Pokušaj ponovo')),
        ),
      );
    }
    final d = _data;
    if (d == null) return const Scaffold(body: LoadingView(label: 'Učitavam porudžbinu...'));

    final customers = (d['customers'] as List).cast<Map<String, dynamic>>();
    final size = (d['printSize'] as String).replaceAll('x', '×');
    final expires = DateTime.fromMillisecondsSinceEpoch(d['expiresAt'] as int);
    final daysLeft = expires.difference(DateTime.now()).inDays;
    final phone = isPhone(context);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: AppColors.ink,
            child: SafeArea(
              bottom: false,
              child: Centered(
                maxWidth: 1100,
                padding: EdgeInsets.fromLTRB(20, phone ? 28 : 48, 20, phone ? 28 : 48),
                child: Column(children: [
                  Text((d['studioName'] as String).toUpperCase(), style: t.labelLarge?.copyWith(color: AppColors.gold, letterSpacing: 3, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text('Porudžbina za štampu', style: t.bodyLarge?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    d['label'] as String,
                    textAlign: TextAlign.center,
                    style: (phone ? t.headlineLarge : t.displaySmall)?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 28),
                  // Kartica u stilu WeTransfer-a
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(color: AppColors.emeraldSoft, shape: BoxShape.circle),
                            child: Icon(_downloading ? Icons.downloading_rounded : Icons.download_rounded, color: AppColors.emerald, size: 36),
                          ),
                          const SizedBox(height: 16),
                          Text('${d['totalCopies']} kom · $size cm', style: t.headlineMedium?.copyWith(fontFamily: bodyFont, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            '${photosLabel(d['photoCount'] as int)} · ${formatBytes(d['totalBytes'] as int)}',
                            style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            daysLeft <= 0 ? 'Link ističe danas' : 'Link ističe za ${plural(daysLeft, 'dan', 'dana', 'dana')} (${formatDate(expires)})',
                            style: t.bodyMedium?.copyWith(color: daysLeft <= 2 ? AppColors.danger : AppColors.inkFaint),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _downloadAll,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(_downloading ? 'Preuzimanje je počelo' : 'Preuzmi sve (ZIP)'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Originali u punoj rezoluciji. Ime fajla počinje brojem kopija (npr. „2x_IMG_0001.jpg”)'
                            '${customers.length > 1 ? ', a svaki klijent ima svoj folder' : ''}. Spisak je u SPISAK.txt.',
                            textAlign: TextAlign.center,
                            style: t.bodySmall,
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        for (final c in customers) ...[
          SliverToBoxAdapter(
            child: Centered(
              maxWidth: 1100,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              child: Row(children: [
                Expanded(
                  child: Text(
                    (c['name'] as String).isEmpty ? 'Fotografije' : c['name'] as String,
                    style: t.headlineSmall,
                  ),
                ),
                Pill('${c['copies']} kom', color: AppColors.emeraldDark, background: AppColors.emeraldSoft),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Centered(
              maxWidth: 1100,
              padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 20),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final it in (c['items'] as List).cast<Map<String, dynamic>>())
                  _PrintTile(base: _base, item: it, size: phone ? (MediaQuery.sizeOf(context).width - 34) / 2 : 160),
              ]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 60)),
      ]),
    );
  }
}

class _PrintTile extends StatelessWidget {
  const _PrintTile({required this.base, required this.item, required this.size});
  final String base;
  final Map<String, dynamic> item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final id = item['photoId'] as String;
    return SizedBox(
      width: size,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(fit: StackFit.expand, children: [
              NetImage('$base/photos/$id/thumb'),
              Positioned(
                left: 8,
                top: 8,
                child: Pill('${item['quantity']}×', color: Colors.white, background: AppColors.ink.withValues(alpha: 0.85)),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: IconButton.filled(
                  tooltip: 'Preuzmi original',
                  style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                  onPressed: () => download('$base/photos/$id/original'),
                  icon: const Icon(Icons.download_rounded),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text(item['filename'] as String, style: t.bodySmall, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
