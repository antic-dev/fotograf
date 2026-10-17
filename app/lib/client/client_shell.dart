import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'client_controller.dart';

/// Učitava projekat po tajnom linku i deli stanje između galerije,
/// uvećanog prikaza i stranice sa izborom.
class ClientShell extends StatefulWidget {
  const ClientShell({super.key, required this.token, required this.child});

  final String token;
  final Widget child;

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  late ClientController _c;

  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _c = ClientController(widget.token)
      ..onSyncError = (msg) {
        if (mounted) showMessage(context, msg, error: true);
      }
      ..load();
  }

  @override
  void didUpdateWidget(ClientShell old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token) {
      _c.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (_c.loading && _c.project == null) {
          return const Scaffold(body: LoadingView(label: 'Učitavam fotografije...'));
        }
        if (_c.project == null) {
          final e = _c.error;
          final notFound = e is ApiException && e.status == 404;
          return Scaffold(
            body: EmptyState(
              icon: notFound ? Icons.link_off_rounded : Icons.cloud_off_rounded,
              title: notFound ? 'Link ne radi' : 'Nema veze',
              message: notFound
                  ? 'Ovaj link nije ispravan ili ga je fotograf isključio. Javite se fotografu da vam pošalje novi link.'
                  : 'Proverite da li ste povezani na internet, pa pokušajte ponovo.',
              action: notFound
                  ? null
                  : FilledButton.icon(onPressed: _c.load, icon: const Icon(Icons.refresh_rounded), label: const Text('Pokušaj ponovo')),
            ),
          );
        }
        return Scope<ClientController>(value: _c, child: widget.child);
      },
    );
  }
}

/// Početna stranica — namerno ne otkriva ništa o projektima.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 28),
                Text('Vaše fotografije', style: t.displaySmall, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                Text(
                  'Za pregled i izbor fotografija otvorite link koji ste dobili od fotografa (porukom ili mejlom).',
                  style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                TextButton(
                  onPressed: () => context.go('/admin'),
                  child: Text('Prijava za fotografa', style: t.bodyMedium?.copyWith(color: AppColors.inkFaint)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
