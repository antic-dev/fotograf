import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'project_form.dart';
import 'send_to_printer.dart';
import 'upload_picker.dart';
import 'refresh.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AdminRefresh.instance.addListener(_load);
  }

  @override
  void dispose() {
    AdminRefresh.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/api/admin/overview') as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 11) return 'Dobro jutro';
    if (h < 18) return 'Dobar dan';
    return 'Dobro veče';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _data;
    if (d == null) {
      return Scaffold(body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final stats = d['stats'] as Map<String, dynamic>;
    final drive = d['drive'] as Map<String, dynamic>;
    final quota = drive['quota'] as Map<String, dynamic>?;
    final recent = [for (final o in d['recentOrders'] as List) AdminOrder.fromJson(o as Map<String, dynamic>)];
    final phone = isPhone(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, phone ? 20 : 40, 0, 120),
          children: [
            Centered(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_greeting, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                Text(d['studioName'] as String, style: phone ? t.headlineLarge : t.displaySmall),
                const SizedBox(height: 24),
                if (drive['connected'] != true) ...[
                  const DriveConnectBanner(),
                  const SizedBox(height: 20),
                ],
                Wrap(spacing: 12, runSpacing: 12, children: [
                  FilledButton.icon(
                    onPressed: () => pickProjectAndUpload(context),
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Otpremi fotografije'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final p = await showProjectForm(context);
                      if (p != null && context.mounted) context.go('/admin/projekti/${p.id}');
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Novi projekat'),
                  ),
                ]),
                const SizedBox(height: 28),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth > 900 ? 4 : 2;
                  final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    SizedBox(
                      width: w,
                      child: StatCard(
                        label: 'Nove porudžbine',
                        value: '${stats['newOrders']}',
                        icon: Icons.inbox_rounded,
                        highlight: (stats['newOrders'] as int) > 0,
                        onTap: () => context.go('/admin/porudzbine'),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: StatCard(
                        label: 'Klijenti trenutno biraju',
                        value: '${stats['drafts']}',
                        icon: Icons.touch_app_outlined,
                        onTap: () => context.go('/admin/porudzbine?status=draft'),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: StatCard(label: 'Projekti', value: '${stats['projects']}', icon: Icons.photo_library_outlined, onTap: () => context.go('/admin/projekti')),
                    ),
                    SizedBox(width: w, child: StatCard(label: 'Fotografije', value: '${stats['photos']}', icon: Icons.image_outlined)),
                  ]);
                }),
                if (quota != null && quota['limit'] != null) ...[
                  const SizedBox(height: 12),
                  _StorageCard(usage: (quota['usage'] as num?) ?? 0, limit: quota['limit'] as num),
                ],
                const SizedBox(height: 32),
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
                  Text('Nove porudžbine', style: t.headlineSmall),
                  if (recent.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final all = await Api.instance.get('/api/admin/orders?status=submitted') as List;
                        if (!context.mounted) return;
                        final ok = await sendOrdersToPrinter(context, [for (final o in all) (o as Map)['id'] as String]);
                        if (ok) _load();
                      },
                      icon: const Icon(Icons.print_rounded),
                      label: Text(phone ? 'Sve u štampu' : 'Pošalji sve štampariji'),
                    ),
                ]),
                const SizedBox(height: 12),
                if (recent.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(children: [
                        const Icon(Icons.inbox_outlined, color: AppColors.inkFaint, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Još nema novih porudžbina. Kada klijent pošalje izbor, pojaviće se ovde.',
                            style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                          ),
                        ),
                      ]),
                    ),
                  )
                else
                  for (final o in recent) ...[
                    OrderCard(order: o, onTap: () => context.go('/admin/porudzbine/${o.id}')),
                    const SizedBox(height: 10),
                  ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.usage, required this.limit});
  final num usage;
  final num limit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ratio = limit == 0 ? 0.0 : (usage / limit).clamp(0.0, 1.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const Icon(Icons.add_to_drive_rounded, color: AppColors.emerald, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Google Drive', style: t.titleSmall),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ratio, minHeight: 8)),
              const SizedBox(height: 6),
              Text('Iskorišćeno ${formatBytes(usage)} od ${formatBytes(limit)}', style: t.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
