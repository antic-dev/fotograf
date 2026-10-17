import 'package:flutter/material.dart';

import '../api/api.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';

/// Stranica za štampariju. Bez naloga — samo tajni link koji ističe.
/// Sve se preuzima u punoj, originalnoj rezoluciji direktno sa servera.
class PrintPage extends StatefulWidget {
  const PrintPage({super.key, required this.token});
  final String token;

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  Map<String, dynamic>? _data;
  Object? _error;

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_error != null) {
      final e = _error;
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
    final groups = (d['groups'] as List).cast<Map<String, dynamic>>();
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
                padding: EdgeInsets.fromLTRB(20, phone ? 28 : 48, 20, phone ? 28 : 44),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((d['studioName'] as String).toUpperCase(), style: t.labelLarge?.copyWith(color: AppColors.gold, letterSpacing: 3, fontSize: 13)),
                  const SizedBox(height: 10),
                  Text('Porudžbina za štampu', style: t.bodyLarge?.copyWith(color: Colors.white70)),
                  Text(d['label'] as String, style: (phone ? t.headlineLarge : t.displaySmall)?.copyWith(color: Colors.white)),
                  const SizedBox(height: 20),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final g in groups)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                        child: Text('${g['size']} · ${g['finish']}:  ${g['copies']} kom',
                            style: t.titleMedium?.copyWith(color: Colors.white)),
                      ),
                  ]),
                  const SizedBox(height: 24),
                  Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton.icon(
                      onPressed: () => download('$_base/zip'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink, minimumSize: const Size(260, 60)),
                      icon: const Icon(Icons.download_rounded),
                      label: Text('Preuzmi sve (ZIP) · ${d['totalCopies']} kom'),
                    ),
                    Text(
                      'Originali u punoj rezoluciji, raspoređeni po veličini.\nLink važi do ${formatDateMs(d['expiresAt'] as int)}',
                      style: t.bodyMedium?.copyWith(color: Colors.white60),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        for (final g in groups) ...[
          SliverToBoxAdapter(
            child: Centered(
              maxWidth: 1100,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              child: Row(children: [
                Expanded(child: Text('${g['size']} cm · ${g['finish']}', style: t.headlineSmall)),
                Pill('${g['copies']} kom', color: AppColors.emeraldDark, background: AppColors.emeraldSoft),
              ]),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 20),
            sliver: SliverToBoxAdapter(
              child: Centered(
                maxWidth: 1100,
                padding: EdgeInsets.zero,
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final it in (g['items'] as List).cast<Map<String, dynamic>>())
                    _PrintTile(base: _base, item: it, size: phone ? (MediaQuery.sizeOf(context).width - 34) / 2 : 160),
                ]),
              ),
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
                child: Pill('${item['quantity']}×', color: Colors.white, background: AppColors.ink.withValues(alpha: 0.8)),
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
        if ((item['customer'] as String? ?? '').isNotEmpty)
          Text(item['customer'] as String, style: t.bodySmall?.copyWith(color: AppColors.inkFaint), overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
