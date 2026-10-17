import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';
import 'send_to_printer.dart';
import 'widgets.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  AdminOrder? _o;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/api/admin/orders/${widget.orderId}');
      if (mounted) setState(() => _o = AdminOrder.fromJson(d as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await Api.instance.patch('/api/admin/orders/${widget.orderId}', {'status': status});
      await _load();
      if (mounted) showMessage(context, 'Status je promenjen.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Obrisati porudžbinu?', message: 'Izbor ovog klijenta biće trajno obrisan.', confirmLabel: 'Obriši', danger: true);
    if (!ok) return;
    try {
      await Api.instance.delete('/api/admin/orders/${widget.orderId}');
      if (mounted) context.canPop() ? context.pop() : context.go('/admin/porudzbine');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/admin/porudzbine');

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null) {
      return Scaffold(appBar: AppBar(), body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final t = Theme.of(context).textTheme;
    final phone = isPhone(context);
    final groups = <String, int>{};
    for (final i in o.items) {
      groups['${i.size} · ${i.finish}'] = (groups['${i.size} · ${i.finish}'] ?? 0) + i.quantity;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'delete' ? _delete() : _setStatus(v),
            itemBuilder: (_) => [
              if (o.status != 'submitted') const PopupMenuItem(value: 'submitted', child: Text('Vrati u „Nove”')),
              if (o.status != 'done') const PopupMenuItem(value: 'done', child: Text('Označi kao završenu')),
              if (o.status != 'draft') const PopupMenuItem(value: 'draft', child: Text('Dozvoli klijentu izmene')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Obriši porudžbinu', style: TextStyle(color: AppColors.danger))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 140), children: [
        Centered(
          maxWidth: 1100,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, children: [orderStatusPill(o.status)]),
            const SizedBox(height: 10),
            Text(o.displayName, style: phone ? t.headlineLarge : t.displaySmall),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => context.go('/admin/projekti/${o.projectId}'),
              child: Text(o.projectTitle, style: t.titleMedium?.copyWith(color: AppColors.emerald, fontWeight: FontWeight.w500)),
            ),
            if (o.submittedAt != null) Text('Poslato ${formatDateTimeMs(o.submittedAt!)}', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (o.status == 'submitted' || o.status == 'printing')
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await sendOrdersToPrinter(context, [o.id], label: '${o.projectTitle} — ${o.displayName}');
                    if (ok) _load();
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Pošalji štampariji'),
                ),
              if (o.status == 'printing')
                OutlinedButton.icon(onPressed: () => _setStatus('done'), icon: const Icon(Icons.done_all_rounded), label: const Text('Završeno')),
              if (o.phone.isNotEmpty)
                OutlinedButton.icon(onPressed: () => navigateTo('tel:${o.phone.replaceAll(' ', '')}'), icon: const Icon(Icons.call_rounded), label: Text(o.phone)),
              OutlinedButton.icon(onPressed: () => download('/api/admin/orders/${o.id}/zip'), icon: const Icon(Icons.folder_zip_outlined), label: const Text('Preuzmi originale')),
            ]),
            const SizedBox(height: 20),
            if (o.note.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(18), border: const Border(left: BorderSide(color: AppColors.gold, width: 4))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Poruka klijenta', style: t.titleSmall?.copyWith(color: AppColors.gold)),
                  const SizedBox(height: 6),
                  SelectableText(o.note, style: t.bodyLarge),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: AppColors.emeraldSoft, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${photosLabel(o.photoCount)} · ${copiesLabel(o.copies)}', style: t.titleLarge?.copyWith(color: AppColors.emeraldDark)),
                const SizedBox(height: 6),
                for (final e in groups.entries) Text('${e.key}:  ${e.value} kom', style: t.bodyLarge?.copyWith(color: AppColors.emeraldDark)),
              ]),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 900 ? 5 : (c.maxWidth > 600 ? 4 : 2);
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(spacing: 10, runSpacing: 14, children: [
                for (final i in o.items)
                  SizedBox(
                    width: w,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(fit: StackFit.expand, children: [
                            NetImage(adminThumb(i.photoId)),
                            Positioned(left: 8, top: 8, child: Pill('${i.quantity}×', color: Colors.white, background: AppColors.ink.withValues(alpha: 0.85))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${i.size} · ${i.finish}', style: t.titleSmall),
                      Text(i.filename, style: t.bodySmall, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
              ]);
            }),
          ]),
        ),
      ]),
    );
  }
}
