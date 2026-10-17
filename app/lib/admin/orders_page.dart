import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'send_to_printer.dart';
import 'shell.dart';
import 'widgets.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, this.status, this.projectId});
  final String? status;
  final String? projectId;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

const _filters = [
  ('submitted', 'Nove'),
  ('printing', 'U štampi'),
  ('done', 'Završene'),
  ('draft', 'Biraju se'),
  ('all', 'Sve'),
];

class _OrdersPageState extends State<OrdersPage> {
  late String _status = widget.status ?? 'submitted';
  List<AdminOrder>? _orders;
  Object? _error;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final q = 'status=$_status${widget.projectId == null ? '' : '&projectId=${widget.projectId}'}';
      final list = await Api.instance.get('/api/admin/orders?$q') as List;
      if (!mounted) return;
      setState(() {
        _orders = [for (final o in list) AdminOrder.fromJson(o as Map<String, dynamic>)];
        _selected.retainWhere((id) => _orders!.any((o) => o.id == id));
        // Nove porudžbine su unapred označene — jedan dodir do štamparije.
        if (_status == 'submitted' && _selected.isEmpty) _selected.addAll(_orders!.map((o) => o.id));
      });
      AdminBadges.instance.refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _setStatus(String s) {
    setState(() {
      _status = s;
      _orders = null;
      _selected.clear();
    });
    _load();
  }

  Future<void> _send() async {
    final ok = await sendOrdersToPrinter(context, _selected.toList());
    if (ok) {
      _selected.clear();
      _load();
    }
  }

  bool get _selectable => _status == 'submitted' || _status == 'printing' || _status == 'done' || _status == 'all';

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    final selectable = _selectable && (orders?.isNotEmpty ?? false);
    final chosen = orders?.where((o) => _selected.contains(o.id) && o.status != 'draft').toList() ?? [];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Centered(
              maxWidth: 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PageHeader(
                  title: 'Porudžbine',
                  subtitle: widget.projectId != null ? 'Prikazane su porudžbine jednog projekta.' : 'Izbor fotografija koji su klijenti poslali.',
                  actions: [
                    if (widget.projectId != null)
                      OutlinedButton.icon(onPressed: () => context.go('/admin/porudzbine'), icon: const Icon(Icons.filter_alt_off_outlined), label: const Text('Sve porudžbine')),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (value, label) in _filters) ...[
                      ChoiceChip(label: Text(label), selected: _status == value, onSelected: (_) => _setStatus(value)),
                      const SizedBox(width: 8),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                if (_status == 'draft')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Ovi klijenti su počeli da biraju, ali još nisu poslali izbor.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                    ),
                  ),
                if (selectable)
                  Row(children: [
                    Checkbox(
                      value: _selected.length == orders!.length ? true : (_selected.isEmpty ? false : null),
                      tristate: true,
                      onChanged: (_) => setState(() {
                        if (_selected.length == orders.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(orders.map((o) => o.id));
                        }
                      }),
                    ),
                    Text('Označi sve', style: Theme.of(context).textTheme.bodyMedium),
                  ]),
              ]),
            ),
          ),
          if (orders == null)
            SliverFillRemaining(child: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
          else if (orders.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: switch (_status) {
                  'submitted' => 'Nema novih porudžbina',
                  'printing' => 'Ništa nije u štampi',
                  'draft' => 'Niko trenutno ne bira',
                  _ => 'Nema porudžbina',
                },
                message: _status == 'submitted' ? 'Kada klijent pošalje izbor, pojaviće se ovde.' : null,
              ),
            )
          else
            SliverToBoxAdapter(
              child: Centered(
                maxWidth: 1000,
                child: Column(children: [
                  for (final o in orders) ...[
                    OrderCard(
                      order: o,
                      selected: selectable && o.status != 'draft' ? _selected.contains(o.id) : null,
                      onSelect: (v) => setState(() => v ? _selected.add(o.id) : _selected.remove(o.id)),
                      onTap: () async {
                        await context.push('/admin/porudzbine/${o.id}');
                        _load();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 140),
                ]),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : Material(
              color: AppColors.paper,
              elevation: 12,
              child: SafeArea(
                top: false,
                child: Centered(
                  maxWidth: 1000,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(plural(chosen.length, 'porudžbina', 'porudžbine', 'porudžbina'), style: Theme.of(context).textTheme.titleSmall),
                        Text(copiesLabel(chosen.fold(0, (a, o) => a + o.copies)), style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    FilledButton.icon(onPressed: _send, icon: const Icon(Icons.print_rounded), label: const Text('Pošalji štampariji')),
                  ]),
                ),
              ),
            ),
    );
  }
}
