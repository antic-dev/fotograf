import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/google_sign_in.dart';
import 'auth.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key, this.next});
  final String? next;

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  late Future<Map<String, dynamic>> _start;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = _fetchStart();
  }

  Future<Map<String, dynamic>> _fetchStart() async => await Api.instance.get('/api/auth/start') as Map<String, dynamic>;

  Future<void> _onCredential(String credential) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuth.instance.loginWithGoogle(credential);
      if (!mounted) return;
      final next = widget.next;
      context.go(next != null && next.startsWith('/admin') && !next.startsWith('//') ? next : '/admin');
    } catch (e) {
      setState(() {
        _error = e is ApiException ? e.message : 'Prijava nije uspela.';
        _busy = false;
        _start = _fetchStart(); // novi nonce za sledeći pokušaj
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Text('Prijava za fotografa', style: t.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Pristup ima samo administratorski Google nalog.',
                      style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_busy)
                      const LoadingView(label: 'Prijavljujem...')
                    else
                      FutureBuilder<Map<String, dynamic>>(
                        future: _start,
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return ErrorView(error: snap.error!, onRetry: () => setState(() => _start = _fetchStart()));
                          }
                          if (!snap.hasData) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
                          return GoogleSignInButton(
                            key: ValueKey(snap.data!['nonce']),
                            clientId: snap.data!['clientId'] as String,
                            nonce: snap.data!['nonce'] as String,
                            onCredential: _onCredential,
                          );
                        },
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: t.bodyMedium?.copyWith(color: AppColors.danger))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.inkFaint),
                      const SizedBox(width: 6),
                      Text('Zaštićena veza · sesija ističe automatski', style: t.bodySmall?.copyWith(color: AppColors.inkFaint)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
