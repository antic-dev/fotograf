import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'send_to_printer.dart';
import 'widgets.dart';

class PrintLinksPage extends StatefulWidget {
  const PrintLinksPage({super.key});

  @override
  State<PrintLinksPage> createState() => _PrintLinksPageState();
}

class _PrintLinksPageState extends State<PrintLinksPage> {
  List<PrintLink>? _links;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.instance.get('/api/admin/print-links') as List;
      if (mounted) setState(() => _links = [for (final l in list) PrintLink.fromJson(l as Map<String, dynamic>)]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _revoke(PrintLink l) async {
    final ok = await confirm(context, title: 'Opozvati link?', message: 'Štamparija više neće moći da otvori ovaj link.', confirmLabel: 'Opozovi', danger: true);
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/print-links/${l.id}/revoke');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final links = _links;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 140), children: [
          Centered(
            maxWidth: 1000,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const PageHeader(
                title: 'Štamparija',
                subtitle: 'Linkovi koje ste poslali štampariji. Originali se preuzimaju direktno sa servera, u punoj rezoluciji.',
              ),
              if (links == null)
                Padding(padding: const EdgeInsets.only(top: 60), child: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
              else if (links.isEmpty)
                const EmptyState(
                  icon: Icons.print_outlined,
                  title: 'Još niste ništa poslali',
                  message: 'U „Porudžbine” označite porudžbine i pritisnite „Pošalji štampariji”.',
                )
              else
                for (final l in links) ...[
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => showPrintLinkSheet(context, l),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: l.active ? AppColors.emeraldSoft : AppColors.sand, shape: BoxShape.circle),
                            child: Icon(Icons.print_rounded, color: l.active ? AppColors.emerald : AppColors.inkFaint),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.label, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                '${photosLabel(l.photoCount)} · ${copiesLabel(l.copies)} · ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(l.createdAt))}',
                                style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                              ),
                              const SizedBox(height: 6),
                              Wrap(spacing: 8, runSpacing: 6, children: [
                                if (l.revoked)
                                  const Pill('Opozvan', icon: Icons.block_rounded)
                                else if (l.expired)
                                  const Pill('Istekao', icon: Icons.timer_off_outlined)
                                else
                                  Pill('Važi do ${formatShortDate(DateTime.fromMillisecondsSinceEpoch(l.expiresAt))}', color: AppColors.emeraldDark, background: AppColors.emeraldSoft, icon: Icons.check_rounded),
                                Pill(l.accessCount == 0 ? 'Još nije otvoren' : 'Otvoren ${l.accessCount}×', icon: Icons.visibility_outlined),
                                if (l.sentTo.isNotEmpty) Pill('Poslato: ${l.sentTo}', icon: Icons.mail_outline_rounded),
                              ]),
                            ]),
                          ),
                          if (l.active)
                            IconButton(tooltip: 'Opozovi', onPressed: () => _revoke(l), icon: const Icon(Icons.block_rounded, color: AppColors.inkFaint)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ]),
          ),
        ]),
      ),
    );
  }
}
