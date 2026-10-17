import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../ui/theme.dart';
import 'auth.dart';
import 'uploads.dart';

/// Broj novih porudžbina za značku u meniju.
class AdminBadges extends ChangeNotifier {
  AdminBadges._();
  static final AdminBadges instance = AdminBadges._();

  int newOrders = 0;

  Future<void> refresh() async {
    try {
      final list = await Api.instance.get('/api/admin/orders?status=submitted') as List;
      if (list.length != newOrders) {
        newOrders = list.length;
        notifyListeners();
      }
    } catch (_) {}
  }
}

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('/admin', 'Pregled', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Dest('/admin/projekti', 'Projekti', Icons.photo_library_outlined, Icons.photo_library_rounded),
  _Dest('/admin/porudzbine', 'Porudžbine', Icons.inbox_outlined, Icons.inbox_rounded),
  _Dest('/admin/stampa', 'Štamparija', Icons.print_outlined, Icons.print_rounded),
  _Dest('/admin/podesavanja', 'Podešavanja', Icons.tune_outlined, Icons.tune_rounded),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AdminBadges.instance.refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => AdminBadges.instance.refresh());
  }

  @override
  void didUpdateWidget(AdminShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) AdminBadges.instance.refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _index {
    for (var i = _dests.length - 1; i >= 0; i--) {
      if (widget.location == _dests[i].path || (i > 0 && widget.location.startsWith('${_dests[i].path}/'))) return i;
    }
    return 0;
  }

  Widget _icon(int i, bool selected) {
    final d = _dests[i];
    final icon = Icon(selected ? d.selectedIcon : d.icon);
    if (d.path != '/admin/porudzbine') return icon;
    return ListenableBuilder(
      listenable: AdminBadges.instance,
      builder: (context, _) {
        final n = AdminBadges.instance.newOrders;
        return Badge(isLabelVisible: n > 0, label: Text('$n'), backgroundColor: AppColors.danger, child: icon);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final t = Theme.of(context).textTheme;
    final index = _index;

    final content = Stack(children: [
      Positioned.fill(child: widget.child),
      Positioned(
        right: wide ? 24 : 12,
        left: wide ? null : 12,
        bottom: wide ? 24 : 12,
        child: const Align(alignment: Alignment.bottomRight, child: UploadPanel()),
      ),
    ]);

    if (!wide) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => context.go(_dests[i].path),
          destinations: [
            for (var i = 0; i < _dests.length; i++)
              NavigationDestination(icon: _icon(i, false), selectedIcon: _icon(i, true), label: _dests[i].label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(children: [
        NavigationRail(
          extended: MediaQuery.sizeOf(context).width >= 1200,
          minExtendedWidth: 232,
          selectedIndex: index,
          onDestinationSelected: (i) => context.go(_dests[i].path),
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 28),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 22),
              ),
              if (MediaQuery.sizeOf(context).width >= 1200) ...[
                const SizedBox(width: 12),
                ListenableBuilder(
                  listenable: AdminAuth.instance,
                  builder: (context, _) => ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      AdminAuth.instance.studioName.isEmpty ? 'Fotograf' : AdminAuth.instance.studioName,
                      style: t.titleLarge?.copyWith(fontFamily: displayFont),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ]),
          ),
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: IconButton(
                  tooltip: 'Odjava',
                  onPressed: () async {
                    await AdminAuth.instance.logout();
                    if (context.mounted) context.go('/admin/prijava');
                  },
                  icon: const Icon(Icons.logout_rounded),
                ),
              ),
            ),
          ),
          destinations: [
            for (var i = 0; i < _dests.length; i++)
              NavigationRailDestination(icon: _icon(i, false), selectedIcon: _icon(i, true), label: Text(_dests[i].label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ]),
    );
  }
}
