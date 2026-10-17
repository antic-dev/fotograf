import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../ui/theme.dart';
import 'auth.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key, this.next});
  final String? next;

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuth.instance.login(_email.text, _password.text);
      // Pregledač nudi da zapamti lozinku.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      final next = widget.next;
      context.go(next != null && next.startsWith('/admin') && !next.startsWith('//') ? next : '/admin');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Prijava nije uspela. Pokušajte ponovo.';
        _busy = false;
        _password.clear();
      });
      _passwordFocus.requestFocus();
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
                  child: AutofillGroup(
                    child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 34),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Prijava za fotografa', style: t.headlineMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Mejl', prefixIcon: Icon(Icons.alternate_email_rounded)),
                          validator: (v) => (v == null || !v.contains('@')) ? 'Upišite mejl' : null,
                          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          obscureText: !_show,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Lozinka',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _show ? 'Sakrij lozinku' : 'Prikaži lozinku',
                              onPressed: () => setState(() => _show = !_show),
                              icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Upišite lozinku' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
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
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Text('Prijavi se'),
                        ),
                        const SizedBox(height: 24),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.inkFaint),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Zaštićena prijava · sesija ističe automatski',
                              style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
